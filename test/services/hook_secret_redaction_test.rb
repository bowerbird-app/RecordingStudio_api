# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class HookSecretRedactionTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :admin)
    Current.actor = @user
  end

  teardown do
    clear_service_hooks
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "service hooks never receive issued secrets and the caller still does" do
    seen = capture_service_hooks do
      @provision = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_point_recording: access_point_recording_for(@access_recording),
        manager_actor: access_manager_for(@access_recording),
        role: @access_recording.recordable.role,
        name: "Hook client"
      )
    end

    assert @provision.success?, @provision.error
    token = @provision.value.fetch(:token)
    credential = @provision.value.fetch(:credential)
    assert_secret_stays_with_caller(token, credential)
    assert_hooks_hide(seen, token)

    seen = capture_service_hooks do
      @issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "client_credentials",
        client_id: credential.oauth_client_id,
        client_secret: token
      )
    end

    assert @issued.success?, @issued.error
    access_token = @issued.value.fetch(:access_token)
    assert_match(/\Arsapi_at_/, access_token)
    assert_hooks_hide(seen, access_token)
    assert_hooks_hide(seen, token)

    seen = capture_service_hooks do
      @rotated = RecordingStudioApi::Services::RotateApiCredential.call(
        api_client: @provision.value.fetch(:api_client),
        actor: @user
      )
    end

    assert @rotated.success?, @rotated.error
    rotated_token = @rotated.value.fetch(:token)
    assert_instance_of RecordingStudioApi::ApiCredential, @rotated.value.fetch(:credential)
    assert_hooks_hide(seen, rotated_token)

    seen = capture_service_hooks do
      @test_credential = RecordingStudioApi::Services::IssueTestCredential.call(
        api: :public,
        actor: @user,
        access_point_recording: @root_recording,
        role: :view,
        name: "Hook test credential"
      )
    end

    assert @test_credential.success?, @test_credential.error
    test_token = @test_credential.value.fetch(:token)
    test_access_token = @test_credential.value.fetch(:access_token)
    assert_instance_of RecordingStudioApi::ApiCredential, @test_credential.value.fetch(:credential)
    assert_hooks_hide(seen, test_token)
    assert_hooks_hide(seen, test_access_token)
  end

  test "around hooks see the service class without the presented secret" do
    client_secret = "presented-client-secret"
    subject = nil
    around_value = nil

    capture_service_hooks do
      RecordingStudio.configuration.hooks.around_service do |hook_subject, block|
        subject = hook_subject
        around_value = block.call
        around_value
      end

      @issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "client_credentials",
        client_id: "missing-client",
        client_secret: client_secret,
        params: {
          "grant_type" => "authorization_code",
          "client_secret" => client_secret,
          "code" => "presented-code",
          "redirect_uri" => "https://app.example/callback",
          "note" => "drop-this"
        }
      )
    end

    assert @issued.failure?
    assert subject.is_a?(RecordingStudioApi::Services::IssueOauthAccessToken)
    assert subject.kind_of?(RecordingStudioApi::Services::IssueOauthAccessToken) # rubocop:disable Style/ClassCheck
    assert_not subject.instance_variable_defined?(:@client_secret)
    kept = subject.instance_variable_get(:@params)
    assert_equal "authorization_code", kept.fetch("grant_type")
    assert_equal "https://app.example/callback", kept.fetch("redirect_uri")
    assert_equal %w[grant_type redirect_uri], kept.keys
    assert_hooks_hide([[:around, subject, around_value, subject]], client_secret)
    assert_hooks_hide([[:around, subject, around_value, subject]], "presented-code")
  end

  test "a delegated grant refresh token stays with the caller and out of the hooks" do
    access_token = "rsapi_at_delegated"
    refresh_token = "rsapi_rt_delegated"
    RecordingStudioApi.register_oauth_grant("refresh_token", handler: lambda { |**|
      RecordingStudio::Services::BaseService::Result.new(
        success: true,
        value: {
          access_token: access_token,
          refresh_token: refresh_token,
          token_type: "Bearer",
          expires_in: 3600
        },
        error: nil,
        errors: []
      )
    })

    seen = capture_service_hooks do
      @issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "refresh_token",
        client_id: "delegated-client",
        client_secret: "delegated-secret",
        params: {
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token,
          "code" => "presented-code",
          "code_verifier" => "presented-verifier",
          "id_token" => "presented-id-token"
        }
      )
    end

    assert @issued.success?, @issued.error
    assert_equal access_token, @issued.value.fetch(:access_token)
    assert_equal refresh_token, @issued.value.fetch(:refresh_token)
    assert_hooks_hide(seen, access_token)
    assert_hooks_hide(seen, refresh_token)
    assert_hooks_hide(seen, "presented-code")
    assert_hooks_hide(seen, "presented-verifier")
    assert_hooks_hide(seen, "presented-id-token")

    after = seen.find { |event, service_class,| event == :after && service_class == RecordingStudioApi::Services::IssueOauthAccessToken }
    assert_nil after[2].value.fetch(:access_token)
    assert_nil after[2].value.fetch(:refresh_token)
    assert_equal "Bearer", after[2].value.fetch(:token_type)
    subject = seen.find { |event,| event == :around }.last
    assert_equal({ "grant_type" => "refresh_token" }, subject.instance_variable_get(:@params))
  end

  test "hook results redact structs data and request parameters" do
    pair = Data.define(:access_token, :token_type).new(access_token: "data-access", token_type: "Bearer")
    legacy = Struct.new(:refresh_token, :expires_in).new("struct-refresh", 60)
    request = ActionController::Parameters.new("id_token" => "param-id-token", "token_type" => "Bearer")
    probe = Class.new(RecordingStudio::Services::BaseService) do
      include RecordingStudioApi::Services::RedactsHookSecrets

      def initialize(value)
        @value = value
      end

      def perform
        success(@value)
      end
    end

    seen = capture_service_hooks do
      @shaped = probe.call({ pair: pair, legacy: legacy, request: request })
    end

    assert_equal "data-access", @shaped.value.fetch(:pair).access_token
    assert_equal "struct-refresh", @shaped.value.fetch(:legacy).refresh_token
    assert_equal "param-id-token", @shaped.value.fetch(:request)["id_token"]
    after = seen.find { |event,| event == :after }
    value = after[2].value
    assert_nil value.fetch(:pair).fetch(:access_token)
    assert_equal "Bearer", value.fetch(:pair).fetch(:token_type)
    assert_nil value.fetch(:legacy).fetch(:refresh_token)
    assert_equal 60, value.fetch(:legacy).fetch(:expires_in)
    assert_nil value.fetch(:request).fetch("id_token")
    assert_equal "Bearer", value.fetch(:request).fetch("token_type")
    %w[data-access struct-refresh param-id-token].each do |secret|
      seen.each do |event, service_class, payload,|
        assert_not hook_text(payload).include?(secret), "#{event} on #{service_class} saw a secret"
      end
    end
  end

  test "pagination hooks do not receive the pagination token" do
    token = "signed-pagination-token"
    seen = capture_service_hooks do
      @page = RecordingStudioApi::Services::PaginateResourceCollection.call(
        relation: RecordingStudioApi::ApiClient.none,
        resource: "api_clients",
        recordable_type: "RecordingStudioApi::ApiClient",
        limit: 1,
        pagination_token: token,
        sort: "created_at",
        order: "desc",
        scope_key: "client-1"
      )
    end

    subjects = seen.select { |event,| event == :around }.map(&:last)
    assert_predicate subjects, :any?
    subjects.each do |subject|
      assert_not subject.instance_variable_defined?(:@pagination_token)
    end
    seen.each do |event, service_class, payload,|
      assert_not hook_text(payload).include?(token), "#{event} on #{service_class} saw the pagination token"
    end
  end

  test "revoke and bearer hooks omit the plaintext token and client secret" do
    token = "rsapi_at_hook_secret"
    client_secret = "hook-client-secret"
    header = "Bearer #{token}"
    seen = capture_service_hooks do
      @revoked = RecordingStudioApi::Services::RevokeOauthAccessToken.call(
        token: token,
        client_id: "missing-client",
        client_secret: client_secret
      )
      @bearer = RecordingStudioApi::Services::AuthenticateBearerToken.call(authorization_header: header)
    end

    assert @revoked.failure?
    assert @bearer.failure?
    assert_hooks_hide(seen, token)
    assert_hooks_hide(seen, client_secret)
    assert_hooks_hide(seen, header)

    subjects = seen.select { |event,| event == :around }.map(&:last)
    assert(subjects.any?(RecordingStudioApi::Services::RevokeOauthAccessToken))
    assert(subjects.any?(RecordingStudioApi::Services::AuthenticateBearerToken))
    subjects.each do |subject|
      assert_not subject.instance_variable_defined?(:@token)
      assert_not subject.instance_variable_defined?(:@client_secret)
      assert_not subject.instance_variable_defined?(:@authorization_header)
    end
  end

  private

  def capture_service_hooks
    hooks = RecordingStudio.configuration.hooks
    clear_service_hooks
    seen = []
    hooks.before_service { |service_class, args| seen << [:before, service_class, args, nil] }
    hooks.after_service { |service_class, result| seen << [:after, service_class, result, nil] }
    hooks.around_service do |subject, block|
      view = block.call
      seen << [:around, subject.class, view, subject]
      view
    end
    yield
    seen
  ensure
    clear_service_hooks
  end

  def clear_service_hooks
    hooks = RecordingStudio.configuration.hooks
    hooks.clear(:before_service)
    hooks.clear(:after_service)
    hooks.clear(:around_service)
  end

  def assert_secret_stays_with_caller(token, credential)
    assert token.present?
    assert_instance_of RecordingStudioApi::ApiCredential, credential
  end

  def assert_hooks_hide(seen, secret)
    assert secret.present?
    seen.each do |event, service_class, payload, subject|
      assert_not hook_text(payload).include?(secret), "#{event} on #{service_class} saw a secret"
      assert_not hook_text(subject).include?(secret), "#{event} subject on #{service_class} saw a secret" if subject
      assert_no_credential(payload)
      assert_no_credential(subject) if subject
    end
  end

  def assert_no_credential(object)
    @visit_ids = {}.compare_by_identity
    visit(object) do |item|
      assert_not item.is_a?(RecordingStudioApi::ApiCredential)
      next unless item.is_a?(RecordingStudioApi::AuthenticatedClient)

      assert_nil item.credential
    end
  end

  def hook_text(object)
    @visit_ids = {}.compare_by_identity
    chunks = []
    visit(object) { |item| chunks << item if item.is_a?(String) }
    chunks.join("\n")
  end

  def visit(object, &block)
    return if object.nil? || seen_visit?(object)

    yield object
    case object
    when Hash
      object.each_value { |value| visit(value, &block) }
    when Array
      object.each { |value| visit(value, &block) }
    when RecordingStudio::Services::BaseService::Result
      visit(object.value, &block)
      visit(object.error, &block)
      visit(object.errors, &block)
    else
      return if defined?(ActiveRecord::Base) && object.is_a?(ActiveRecord::Base)

      object.instance_variables.each do |name|
        visit(object.instance_variable_get(name), &block)
      end
    end
  end

  def seen_visit?(object)
    @visit_ids ||= {}.compare_by_identity
    return true if @visit_ids[object]

    @visit_ids[object] = true
    false
  end
end
