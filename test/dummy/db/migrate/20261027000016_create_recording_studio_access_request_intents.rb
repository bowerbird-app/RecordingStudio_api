# frozen_string_literal: true

# This migration comes from recording_studio_accessible (originally 20261016000016)
class CreateRecordingStudioAccessRequestIntents < ActiveRecord::Migration[8.1]
  def change
    create_intents_table
    add_index :recording_studio_access_request_intents, :recording_id
    add_intent_guards
  end

  private

  def create_intents_table
    create_table :recording_studio_access_request_intents, id: :uuid do |table|
      intent_columns(table)
    end
  end

  def intent_columns(table)
    table.uuid :recording_id, null: false
    table.uuid :user_id, null: false
    table.uuid :otp_challenge_id, null: false
    table.string :email, null: false
    table.string :role
    table.string :action
    table.datetime :expires_at, null: false
    table.datetime :fulfilled_at
    table.datetime :created_at, null: false
  end

  def add_intent_guards
    add_check_constraint :recording_studio_access_request_intents,
                         "char_length(email) <= 255",
                         name: "recording_studio_access_request_intents_email_length"
    add_check_constraint :recording_studio_access_request_intents,
                         "action IS NULL OR char_length(action) <= 120",
                         name: "recording_studio_access_request_intents_action_length"
  end
end
