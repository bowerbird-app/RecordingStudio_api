# frozen_string_literal: true

module RecordingStudioApi
  class ApiClient < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_api_clients"

    recording_studio_recordable(
      label: "API Client",
      plural_label: "API Clients",
      root: false,
      allowed_parent_types: ["RecordingStudio::Access"]
    )

    belongs_to :access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false,
               optional: true

    has_many :credentials,
             class_name: "RecordingStudioApi::ApiCredential",
             dependent: :destroy,
             inverse_of: :api_client

    validates :name, presence: true
    validates :api_key, presence: true, inclusion: { in: ->(_) { RecordingStudioApi.configuration.api_names } }
    validate :access_recording_must_reference_access
    validate :api_key_must_not_change, on: :update

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: access_recording_id
      )
    end

    def root_recording
      recording&.root_recording || access_recording&.root_recording
    end

    def access
      access_recording&.recordable
    end

    def readonly?
      false
    end

    private

    def access_recording_must_reference_access
      return if access_recording.blank?
      return if access_recording.recordable_type == "RecordingStudio::Access"

      errors.add(:access_recording, "must point to a RecordingStudio::Access recording")
    end

    def api_key_must_not_change
      errors.add(:api_key, "cannot be changed") if will_save_change_to_api_key?
    end
  end
end
