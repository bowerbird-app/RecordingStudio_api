# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "test_helper"
require_relative "dummy/config/environment"
require_relative "support/api_dummy_helpers"

class AccessPolicyTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  test "denies every permission without an access recording" do
    policy = RecordingStudioApi::AccessPolicy.new(access_recording: nil)

    refute policy.can_read?
    refute policy.can_write?
    refute policy.can_admin?
  end

  test "denies every permission for a non-access recordable" do
    workspace = Workspace.create!(name: "Not an access")
    recording = RecordingStudio::Recording.create!(recordable: workspace)
    policy = RecordingStudioApi::AccessPolicy.new(access_recording: recording)

    refute policy.can_read?
    refute policy.can_write?
    refute policy.can_admin?
  end

  { view: [true, false, false], edit: [true, true, false], admin: [true, true, true] }.each do |role, expected_permissions|
    test "#{role} access has the expected permissions" do
      user = create_user(email: "access-policy-#{role}@example.com")
      _root_recording, access_recording = create_access_recording_for(user: user, role: role)

      policy = RecordingStudioApi::AccessPolicy.new(access_recording: access_recording)

      assert_equal expected_permissions[0], policy.can_read?
      assert_equal expected_permissions[1], policy.can_write?
      assert_equal expected_permissions[2], policy.can_admin?
    end
  end
end