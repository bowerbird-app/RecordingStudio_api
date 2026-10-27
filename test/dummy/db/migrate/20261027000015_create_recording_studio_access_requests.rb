# frozen_string_literal: true

# This migration comes from recording_studio_accessible (originally 20261016000015)
class CreateRecordingStudioAccessRequests < ActiveRecord::Migration[8.1]
  def change
    create_requests_table
    add_index :recording_studio_access_requests, %i[actor_type actor_id],
              name: "index_recording_studio_access_requests_on_actor"
    add_status_and_message_guards
    add_note_and_action_guards
  end

  private

  def create_requests_table
    create_table :recording_studio_access_requests, id: :uuid do |table|
      request_columns(table)
    end
  end

  def request_columns(table)
    table.string :actor_type, null: false
    table.uuid :actor_id, null: false
    table.string :role, null: false
    table.string :action
    table.text :message
    table.string :status, null: false, default: "pending"
    table.uuid :access_recording_id
    table.text :review_note
    table.datetime :created_at, null: false
  end

  def add_status_and_message_guards
    add_check_constraint :recording_studio_access_requests,
                         "status IN ('pending', 'approved', 'denied')",
                         name: "recording_studio_access_requests_status"
    add_check_constraint :recording_studio_access_requests,
                         "message IS NULL OR char_length(message) <= 2000",
                         name: "recording_studio_access_requests_message_length"
  end

  def add_note_and_action_guards
    add_check_constraint :recording_studio_access_requests,
                         "review_note IS NULL OR char_length(review_note) <= 2000",
                         name: "recording_studio_access_requests_note_length"
    add_check_constraint :recording_studio_access_requests,
                         "action IS NULL OR char_length(action) <= 120",
                         name: "recording_studio_access_requests_action_length"
  end
end
