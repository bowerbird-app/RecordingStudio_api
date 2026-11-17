# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"
require "recording_studio_api/test_helpers"

class ApiV1BillingDenialTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers
  include RecordingStudioApi::TestHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Billing token")
    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[bill])
  end

  teardown do
    RecordingStudio.unregister_gate("billing.api", "paywall") if RecordingStudio.gate_registered?("billing.api")
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a gate denial with a known code returns 402 and only the allowlisted fields" do
    RecordingStudio.register_gate("billing.api", "paywall") do
      RecordingStudio::GateDecision.deny(
        code: :plan_limit_reached,
        reason: "internal plan row 9191",
        redirect_to: "https://billing.example/pay",
        details: {
          message: "Plan limit reached",
          feature: "exports",
          limit: 3,
          fix_path: "https://billing.example/pay",
          fixable_by: "owner",
          price_cents: 9191,
          stripe_customer_id: "cus_secret"
        }
      )
    end
    register_bill_action do |context|
      RecordingStudio.check_gate("billing.api", actor: context.api_client, recording: context.recording)
    end

    post bill_path(@page_recording), headers: authorization_headers

    assert_billing_denial(
      :plan_limit_reached,
      details: { message: "Plan limit reached", feature: "exports", limit: 3, fixable_by: "owner" }
    )
    refute response.parsed_body.dig("error", "details").key?("fix_path")
    refute_includes response.body, "https://billing.example"
    refute_includes response.body, "9191"
    refute_includes response.body, "cus_secret"
    refute_includes response.body, "internal plan"
  end

  test "a raised denial returns 402 from the marker, not from code or details methods" do
    register_bill_action { raise ApiV1BillingDenialTest::SeatLimit }

    post bill_path(@page_recording), headers: authorization_headers

    assert_billing_denial(
      :seat_limit_reached,
      details: {
        message: "No seats left",
        feature: "seats",
        limit: 5,
        fix_path: "/settings/seats",
        fixable_by: "owner"
      }
    )
    refute_includes response.body, "card_declined"
    refute_includes response.body, "sub_secret"
  end

  test "a stripe-like error with code is not a 402" do
    register_bill_action { raise ApiV1BillingDenialTest::StripeLike, "card was declined" }

    error = assert_raises(ApiV1BillingDenialTest::StripeLike) do
      post bill_path(@page_recording), headers: authorization_headers
    end

    assert_equal "card_declined", error.code
    assert_equal "card was declined", error.message
  end

  test "an unknown denial code keeps the forbidden response" do
    register_bill_action { raise ApiV1BillingDenialTest::UnknownCode }

    post bill_path(@page_recording), headers: authorization_headers

    assert_response :forbidden
    body = response.parsed_body
    assert_equal "forbidden", body.dig("error", "code")
    assert_equal "API access grant is not authorized for this capability", body.dig("error", "message")
    refute_includes response.body, "invoice_past_due"
    refute_includes response.body, "9191"
    refute_includes response.body, "Pay the invoice"
  end

  test "a denial without a code keeps invalid_input" do
    register_bill_action { raise ApiV1BillingDenialTest::AbsentCode }

    post bill_path(@page_recording), headers: authorization_headers

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "invalid_input", body.dig("error", "code")
    assert_equal "Name is blank", body.dig("error", "message")
    assert_equal [{ "attribute" => "name", "message" => "is blank" }], body.dig("error", "details")
    refute_includes response.body, "hidden billing"
    refute_includes response.body, "9191"
  end

  test "a caller without access gets 403 or 404 and never sees the billing denial" do
    calls = 0
    register_bill_action do
      calls += 1
      RecordingStudio::GateDecision.deny(
        code: :paywall_locked,
        details: { message: "Secret upgrade", feature: "exports", price_cents: 9191 }
      )
    end
    view_user = create_user(email: "billing-view-#{SecureRandom.hex(4)}@example.com")
    view_root, view_access = create_access_recording_for(user: view_user, role: :view)
    view_page = create_page_recording(root_recording: view_root)
    view_token = issue_oauth_access_token_for(access_recording: view_access, name: "View billing token")

    post bill_path(view_page), headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal 0, calls
    assert_equal "forbidden", response.parsed_body.dig("error", "code")
    refute_includes response.body, "Secret upgrade"
    refute_includes response.body, "paywall_locked"
    refute_includes response.body, "exports"
    refute_includes response.body, "9191"

    post bill_path(SecureRandom.uuid), headers: authorization_headers

    assert_response :not_found
    assert_equal 0, calls
    refute_includes response.body, "paywall_locked"
    refute_includes response.body, "Secret upgrade"
  end

  private

  def register_bill_action(&handler)
    RecordingStudioApi.register_capability_action(
      :bill,
      capability: :echoable,
      http_verb: :post,
      required_role: :edit,
      handler: handler
    )
  end

  def bill_path(recording)
    id = recording.respond_to?(:id) ? recording.id : recording
    "/recording_studio_api/api/v1/pages/#{id}/actions/bill"
  end

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  class SeatLimit < StandardError
    include RecordingStudio::Denial

    def initialize
      super("blocked")
      denial(
        code: :seat_limit_reached,
        details: {
          message: "No seats left",
          feature: "seats",
          limit: 5,
          fix_path: "/settings/seats",
          fixable_by: "owner",
          stripe_subscription_id: "sub_secret"
        }
      )
    end

    def code
      "card_declined"
    end

    def details
      { "stripe_subscription_id" => "sub_secret" }
    end
  end

  class StripeLike < StandardError
    def code
      "card_declined"
    end
  end

  class UnknownCode < RecordingStudioApi::AuthorizationError
    include RecordingStudio::Denial

    def initialize
      super("API access grant is not authorized for this capability")
      denial(code: :invoice_past_due, details: { message: "Pay the invoice", feature: "invoices", price_cents: 9191 })
    end
  end

  class AbsentCode < RecordingStudioApi::InvalidActionInputError
    include RecordingStudio::Denial

    def initialize
      super("Name is blank", details: [{ attribute: "name", message: "is blank" }])
      denial(code: nil, details: { message: "hidden billing", price_cents: 9191 })
    end
  end
end
