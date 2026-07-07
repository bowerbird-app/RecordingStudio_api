# frozen_string_literal: true

class CreateAdminSections < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_sections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :admin_sections, :key, unique: true
  end
end