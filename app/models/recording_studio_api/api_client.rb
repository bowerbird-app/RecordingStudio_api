# frozen_string_literal: true

require "recording_studio_trashable"

module RecordingStudioApi
  class ApiClient < ApplicationRecord
    include RecordingStudio::Recordable
    include RecordingStudio::Capabilities::Trashable.to

    self.table_name = "recording_studio_api_api_clients"

    recording_studio_recordable(
      label: "API Client",
      plural_label: "API Clients",
      root: false,
      allowed_parent_types: ["RecordingStudio::Access"]
    )

    belongs_to :owner, polymorphic: true, optional: true

    has_many :credentials,
             class_name: "RecordingStudioApi::ApiCredential",
             dependent: :destroy,
             inverse_of: :api_client

    validates :name, presence: true
    validates :api_key, presence: true, inclusion: { in: ->(_) { RecordingStudioApi.configuration.api_names } }
    validate :api_key_must_not_change, on: :update

    scope :under_access_recordings, lambda { |access_recordings_or_ids|
      client_ids = RecordingStudio::Recording.unscoped.where(
        recordable_type: name,
        parent_recording_id: access_parent_ids(access_recordings_or_ids)
      ).select(:recordable_id)
      where(id: client_ids)
    }

    def self.access_parent_ids(access_recordings_or_ids)
      if access_recordings_or_ids.is_a?(ActiveRecord::Relation)
        access_recordings_or_ids.reselect(:id)
      else
        Array(access_recordings_or_ids).filter_map { |record| record.respond_to?(:id) ? record.id : record }
      end
    end

    def self.access_recordings
      parent_ids = RecordingStudio::Recording.unscoped
                                             .where(recordable_type: name)
                                             .where.not(parent_recording_id: nil)
                                             .select(:parent_recording_id)
      RecordingStudio::Recording.unscoped.where(id: parent_ids, recordable_type: "RecordingStudio::Access")
    end

    def self.preload_recordings(clients)
      clients = Array(clients).compact
      return clients if clients.empty?

      recordings = RecordingStudio::Recording.unscoped
                                             .includes(
                                               :root_recording,
                                               parent_recording: [
                                                 :recordable,
                                                 :root_recording,
                                                 { parent_recording: [:recordable, :parent_recording] }
                                               ]
                                             )
                                             .where(recordable_type: name, recordable_id: clients.map(&:id))
                                             .to_a
      by_recordable_id = recordings.index_by { |recording| recording.recordable_id.to_s }
      clients.each do |client|
        recording = by_recordable_id[client.id.to_s]
        client.recording = recording if recording
      end
      clients
    end

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(recordable: self)
    end

    attr_writer :recording

    def access_recording
      parent = recording&.parent_recording
      parent if parent&.recordable_type == "RecordingStudio::Access"
    end

    def root_recording
      recording&.root_recording || access_recording&.root_recording
    end

    def access
      access_recording&.recordable
    end

    def reload(*)
      remove_instance_variable(:@recording) if instance_variable_defined?(:@recording)
      super
    end

    def readonly?
      false
    end

    private

    def api_key_must_not_change
      errors.add(:api_key, "cannot be changed") if will_save_change_to_api_key?
    end
  end
end
