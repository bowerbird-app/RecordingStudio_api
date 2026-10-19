# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"
require "rails/test_help"

class ApiKeyHealthWidgetsTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.clear_cache!
  end

  test "health filter keeps matching credential rows and leaves blank health unchanged" do
    user = User.create!(email: "health-widgets-#{SecureRandom.hex(4)}@example.com") do |record|
      record.password = "HealthWidgetsPassword!2026"
      record.password_confirmation = "HealthWidgetsPassword!2026"
    end
    _root, access_recording = create_access_recording_for(
      user: user,
      workspace_name: "Health filter workspace",
      role: :admin
    )
    expiring = provision_api_client_for(access_recording: access_recording, name: "Expiring row")
    stale = provision_api_client_for(access_recording: access_recording, name: "Stale row")
    healthy = provision_api_client_for(access_recording: access_recording, name: "Healthy row")

    freeze_time do
      expiring.fetch(:credential).update_columns(expires_at: 10.days.from_now, last_used_at: 1.day.ago)
      stale.fetch(:credential).update_columns(last_used_at: 120.days.ago, expires_at: nil, created_at: 120.days.ago)
      healthy.fetch(:credential).update_columns(expires_at: 60.days.from_now, last_used_at: 1.day.ago)

      rows = RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call.select do |row|
        ["Expiring row", "Stale row", "Healthy row"].include?(row.api_client.name)
      end
      names = ->(filtered) { filtered.map { |row| row.api_client.name } }

      assert_equal ["Expiring row", "Healthy row", "Stale row"], names.call(rows).sort
      assert_equal names.call(rows), names.call(RecordingStudioApi::Admin::ApiKeyHealthWidgets.filter_rows(rows, ""))
      assert_equal ["Expiring row"], names.call(RecordingStudioApi::Admin::ApiKeyHealthWidgets.filter_rows(rows, "expiring_soon"))
      assert_equal ["Stale row"], names.call(RecordingStudioApi::Admin::ApiKeyHealthWidgets.filter_rows(rows, "stale"))
    end
  end
end
