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
        params: { "client_secret" => client_secret, "code" => "leave-this" }
      )
    end

    assert @issued.failure?
    assert subject.is_a?(RecordingStudioApi::Services::IssueOauthAccessToken)
    assert subject.kind_of?(RecordingStudioApi::Services::IssueOauthAccessToken) # rubocop:disable Style/ClassCheck
    assert_not subject.instance_variable_defined?(:@client_secret)
    assert_nil subject.instance_variable_get(:@params).fetch("client_secret")
    assert_equal "leave-this", subject.instance_variable_get(:@params).fetch("code")
    assert_hooks_hide([[:around, subject, around_value, subject]], client_secret)
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
