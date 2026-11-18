# frozen_string_literal: true

class DropAccessRecordingIdFromApiClientsAndCredentials < ActiveRecord::Migration[8.1]
  def up
    drop_access_recording_id(
      :recording_studio_api_api_clients,
      "index_recording_studio_api_api_clients_on_access_recording_id"
    )
    drop_access_recording_id(
      :recording_studio_api_api_credentials,
      "idx_on_access_recording_id_103368144f",
      "index_recording_studio_api_credentials_on_active_access"
    )
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def drop_access_recording_id(table_name, *index_names)
    return unless column_exists?(table_name, :access_recording_id)

    index_names.each do |index_name|
      remove_index table_name, name: index_name if index_exists?(table_name, name: index_name)
    end
    remove_column table_name, :access_recording_id
  end
end
