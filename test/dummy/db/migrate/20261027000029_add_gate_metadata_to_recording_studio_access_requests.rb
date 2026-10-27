# frozen_string_literal: true

# This migration comes from recording_studio_accessible (originally 20261016000029)
class AddGateMetadataToRecordingStudioAccessRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_access_requests, :gate_metadata, :jsonb, null: false, default: {}
  end
end
