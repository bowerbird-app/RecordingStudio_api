# frozen_string_literal: true

# This migration comes from recording_studio_accessible (originally 20261016000028)
class AllowBlankRoleOnRecordingStudioAccessRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :recording_studio_access_requests, :role, true
  end
end
