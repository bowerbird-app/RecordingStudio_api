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

  test "listed counts match the credentials screen and ignore other APIs and inactive keys" do
    configure_dummy_operations_api!
    user = User.create!(email: "health-count-#{SecureRandom.hex(4)}@example.com") do |record|
      record.password = "HealthWidgetsPassword!2026"
      record.password_confirmation = "HealthWidgetsPassword!2026"
    end
    _root, access_recording = create_access_recording_for(
      user: user,
      workspace_name: "Health count workspace",
      role: :admin
    )
    _admin_root, admin_root_recording = create_admin_root_recording(name: "Health count admin")
    admin_access = create_access_recording(parent_recording: admin_root_recording, user: user, role: :admin)
    RecordingStudioApi::Admin::ApiAuthorization.recording_for(
      api: :operations,
      root_recording: admin_root_recording,
      create: true
    )

    listed_expiring = provision_api_client_for(access_recording: access_recording, name: "Listed expiring")
    listed_stale = provision_api_client_for(access_recording: access_recording, name: "Listed stale")
    inactive_expiring = provision_api_client_for(access_recording: access_recording, name: "Inactive expiring")
    inactive_stale = provision_api_client_for(access_recording: access_recording, name: "Inactive stale")
    other_expiring = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: admin_root_recording,
      access_recording: admin_access,
      manager_actor: user,
      role: :admin,
      name: "Other API expiring",
      api: :operations
    )
    other_stale = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: admin_root_recording,
      access_recording: admin_access,
      manager_actor: user,
      role: :admin,
      name: "Other API stale",
      api: :operations
    )

    assert other_expiring.success?, other_expiring.error
    assert other_stale.success?, other_stale.error

    freeze_time do
      listed_expiring.fetch(:credential).update_columns(expires_at: 10.days.from_now, last_used_at: 1.day.ago)
      listed_stale.fetch(:credential).update_columns(last_used_at: 120.days.ago, expires_at: nil, created_at: 120.days.ago)
      inactive_expiring.fetch(:credential).update_columns(
        expires_at: 10.days.from_now,
        last_used_at: 1.day.ago,
        revoked_at: Time.current
      )
      inactive_stale.fetch(:credential).update_columns(
        last_used_at: 120.days.ago,
        expires_at: nil,
        created_at: 120.days.ago,
        revoked_at: Time.current
      )
      other_expiring.value.fetch(:credential).update_columns(expires_at: 10.days.from_now, last_used_at: 1.day.ago)
      other_stale.value.fetch(:credential).update_columns(last_used_at: 120.days.ago, expires_at: nil, created_at: 120.days.ago)

      RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.clear_cache!
      context = Struct.new(:params).new({})

      listed_expiring_rows = RecordingStudioApi::Admin::ApiKeyHealthWidgets.listed_rows(context, "expiring_soon")
      listed_stale_rows = RecordingStudioApi::Admin::ApiKeyHealthWidgets.listed_rows(context, "stale")
      screen_rows = RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call(api: :public)
      screen_expiring = RecordingStudioApi::Admin::ApiKeyHealthWidgets.filter_rows(
        RecordingStudioApi::Admin::ApiKeyHealthWidgets.apply_status(screen_rows, "active"),
        "expiring_soon"
      )
      screen_stale = RecordingStudioApi::Admin::ApiKeyHealthWidgets.filter_rows(
        RecordingStudioApi::Admin::ApiKeyHealthWidgets.apply_status(screen_rows, "active"),
        "stale"
      )
      listed_expiring_names = listed_expiring_rows.map { |row| row.api_client.name }
      listed_stale_names = listed_stale_rows.map { |row| row.api_client.name }
      excluded_names = ["Inactive expiring", "Inactive stale", "Other API expiring", "Other API stale"]

      assert_includes listed_expiring_names, "Listed expiring"
      assert_includes listed_stale_names, "Listed stale"
      excluded_names.each do |name|
        assert_not_includes listed_expiring_names, name
        assert_not_includes listed_stale_names, name
      end
      assert_equal screen_expiring.map(&:id).sort, listed_expiring_rows.map(&:id).sort
      assert_equal screen_stale.map(&:id).sort, listed_stale_rows.map(&:id).sort
      assert_equal screen_expiring.size, RecordingStudioApi::Admin::ApiKeyHealthWidgets.listed_count(context, "expiring_soon")
      assert_equal screen_stale.size, RecordingStudioApi::Admin::ApiKeyHealthWidgets.listed_count(context, "stale")

      site_expiring = RecordingStudioApi::Metrics::EXPIRING_SOON.call(RecordingStudioApi::ApiCredential.all).count
      site_stale = RecordingStudioApi::Metrics::STALE.call(RecordingStudioApi::ApiCredential.all).count
      assert_operator site_expiring, :>, listed_expiring_rows.size
      assert_operator site_stale, :>, listed_stale_rows.size
    end
  end
end
