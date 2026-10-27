# frozen_string_literal: true

# This migration comes from recording_studio_accessible (originally 20261016000027)
class AddSubmittedNameToRecordingStudioAccessRequestIntents < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_access_request_intents, :submitted_name, :string
    add_name_length_guard
  end

  private

  def add_name_length_guard
    add_check_constraint :recording_studio_access_request_intents,
                         "submitted_name IS NULL OR char_length(submitted_name) <= 120",
                         name: "recording_studio_access_request_intents_name_length"
  end
end
