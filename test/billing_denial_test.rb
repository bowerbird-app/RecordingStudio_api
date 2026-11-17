# frozen_string_literal: true

require_relative "support/api_dummy_helpers"
require "recording_studio_api/test_helpers"
require "stringio"
require "logger"

class BillingDenialTest < ActiveSupport::TestCase
  include ApiDummyHelpers
  include RecordingStudioApi::TestHelpers

  setup do
    reset_recording_studio_api_configuration!
  end

  teardown do
    reset_recording_studio_api_configuration!
  end

  test "builtin codes are registered and map to 402" do
    assert_equal %i[paywall_locked plan_limit_reached meter_limit_reached seat_limit_reached],
                 RecordingStudioApi.configuration.billing_codes.codes

    RecordingStudioApi::BillingCodes::BUILTIN.each do |code|
      payload = RecordingStudioApi::BillingDenial.interpret(
        RecordingStudio::GateDecision.deny(code: code, details: { feature: code.to_s })
      )
      assert_equal code.to_s, payload.fetch(:code)
      assert_equal :payment_required, payload.fetch(:status)
      assert_equal({ feature: code.to_s }, payload.fetch(:details))
    end
  end

  test "a host can register another billing code" do
    RecordingStudioApi.configuration.register_billing_code("storage_limit_reached")
    RecordingStudioApi.configuration.register_billing_code(:storage_limit_reached)

    assert RecordingStudioApi.configuration.billing_code?(:storage_limit_reached)
    assert_includes RecordingStudioApi.configuration.to_h.fetch(:billing_codes), :storage_limit_reached
    payload = RecordingStudioApi::BillingDenial.interpret(
      RecordingStudio::GateDecision.deny(code: :storage_limit_reached, details: { limit: 10 })
    )
    assert_equal "storage_limit_reached", payload.fetch(:code)
    assert_equal({ limit: 10 }, payload.fetch(:details))
  end

  test "public details keep a relative fix path and drop everything else" do
    payload = RecordingStudioApi::BillingDenial.interpret(
      RecordingStudio::GateDecision.deny(
        code: :paywall_locked,
        reason: "plan price 9191",
        details: {
          message: "Exports are locked",
          feature: "exports",
          limit: 3,
          fix_path: "/settings/plan",
          fixable_by: "owner",
          price_cents: 9191,
          stripe_customer_id: "cus_secret"
        }
      )
    )

    assert_equal(
      {
        message: "Exports are locked",
        feature: "exports",
        limit: 3,
        fix_path: "/settings/plan",
        fixable_by: "owner"
      },
      payload.fetch(:details)
    )
    assert_equal "Exports are locked", payload.fetch(:message)
  end

  test "a non-relative fix path is dropped" do
    [
      "https://billing.example/pay",
      "//billing.example/pay",
      "billing/upgrade",
      "http://billing.example",
      "/\\evil",
      "/%2f%2fevil.com",
      "/%5cevil"
    ].each do |fix_path|
      payload = RecordingStudioApi::BillingDenial.interpret(
        RecordingStudio::GateDecision.deny(
          code: :meter_limit_reached,
          details: { feature: "meters", fix_path: fix_path, price_cents: 9191 }
        )
      )
      assert_equal({ feature: "meters" }, payload.fetch(:details), fix_path)
      refute_includes payload.fetch(:details).values.join, "9191"
    end
  end

  test "a safe relative fix path is kept" do
    payload = RecordingStudioApi::BillingDenial.interpret(
      RecordingStudio::GateDecision.deny(
        code: :paywall_locked,
        details: { fix_path: "/settings/plan?seat=1&from=api" }
      )
    )
    assert_equal({ fix_path: "/settings/plan?seat=1&from=api" }, payload.fetch(:details))
  end

  test "copied text is a capped string and limit is an integer" do
    payload = RecordingStudioApi::BillingDenial.interpret(
      RecordingStudio::GateDecision.deny(
        code: :plan_limit_reached,
        details: {
          message: "m" * 600,
          feature: :"#{'f' * 150}",
          fixable_by: :owner,
          limit: 3
        }
      )
    )

    assert_equal "m" * 500, payload.dig(:details, :message)
    assert_equal "m" * 500, payload.fetch(:message)
    assert_equal "f" * 100, payload.dig(:details, :feature)
    assert_equal "owner", payload.dig(:details, :fixable_by)
    assert_equal 3, payload.dig(:details, :limit)
  end

  test "stripe ids and non-integer limits are dropped" do
    payload = RecordingStudioApi::BillingDenial.interpret(
      RecordingStudio::GateDecision.deny(
        code: :seat_limit_reached,
        details: {
          message: "See cus_abc",
          feature: "price_123",
          fixable_by: "acct_123",
          limit: "3",
          fix_path: "/settings/cus_abc"
        }
      )
    )
    assert_equal({}, payload.fetch(:details))
    assert_equal "Payment required", payload.fetch(:message)

    float_limit = RecordingStudioApi::BillingDenial.interpret(
      RecordingStudio::GateDecision.deny(
        code: :meter_limit_reached,
        details: { feature: "exports", limit: 3.5 }
      )
    )
    assert_equal({ feature: "exports" }, float_limit.fetch(:details))
  end

  test "an allowed decision and a denial without a code are not billing responses" do
    assert_nil RecordingStudioApi::BillingDenial.interpret(RecordingStudio::GateDecision.allow)
    assert_nil RecordingStudioApi::BillingDenial.interpret(RecordingStudio::GateDecision.deny(reason: "no"))
    assert_nil RecordingStudioApi::BillingDenial.interpret(BillingDenialTest::StripeLike.new)
  end

  test "a raised denial uses the marker fields when the error also defines code and details" do
    payload = RecordingStudioApi::BillingDenial.interpret(BillingDenialTest::SeatLimit.new)
    assert_equal "seat_limit_reached", payload.fetch(:code)
    assert_equal "/settings/seats", payload.dig(:details, :fix_path)
    refute payload.fetch(:details).key?(:stripe_subscription_id)
  end

  test "development warns for an unknown code without the details" do
    decision = RecordingStudio::GateDecision.deny(
      code: :invoice_past_due,
      details: { message: "secret invoice", price_cents: 9191 }
    )
    io = StringIO.new

    Rails.stub(:logger, Logger.new(io)) do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
        assert_nil RecordingStudioApi::BillingDenial.interpret(decision)
      end
    end

    assert_includes io.string, "invoice_past_due"
    refute_includes io.string, "9191"
    refute_includes io.string, "secret invoice"
  end

  test "test runs do not warn for an unknown code" do
    io = StringIO.new
    decision = RecordingStudio::GateDecision.deny(code: :invoice_past_due, details: { price_cents: 9191 })

    Rails.stub(:logger, Logger.new(io)) do
      assert_nil RecordingStudioApi::BillingDenial.interpret(decision)
    end

    assert_empty io.string
  end

  test "assert_billing_denial fails for a code that is not registered" do
    http = Struct.new(:status, :body).new(402, { error: { code: "nope", message: "x" } }.to_json)
    error = assert_raises(Minitest::Assertion) do
      assert_billing_denial(:nope, response: http)
    end
    assert_includes error.message, "not a registered billing code"
  end

  test "assert_billing_denial fails when the body leaks a field" do
    body = {
      error: {
        code: "paywall_locked",
        message: "Locked",
        details: { message: "Locked", feature: "exports", price_cents: 9191 }
      }
    }
    http = Struct.new(:status, :body).new(402, body.to_json)
    error = assert_raises(Minitest::Assertion) do
      assert_billing_denial(:paywall_locked, response: http)
    end
    assert_includes error.message, "leaked"
  end

  class StripeLike < StandardError
    def initialize
      super("card was declined")
    end

    def code
      "card_declined"
    end
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
end
