# frozen_string_literal: true

class CreateRecordingStudioAdminAdmins < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_admin_admins, id: :uuid do |t|
      t.string :name, null: false
      t.string :key

      t.timestamps
    end

    add_index :recording_studio_admin_admins, :key, unique: true
  end
end
