# frozen_string_literal: true

module RecordingStudioApi
  class ScopedRecording
    def self.find!(access_grant:, id:, recordable_type:, include_trashed: false, missing: "Resource was not found in this API scope", type_mismatch: nil)
      recording = access_grant.accessible_recordings(include_trashed: include_trashed).find_by(id: id)
      raise NotFoundError, missing if recording.nil?

      expected = recordable_type.to_s
      return recording if recording.recordable_type == expected

      raise NotFoundError, (type_mismatch || type_mismatch_message(expected, recording, api: api_for(access_grant)))
    end

    def self.api_for(access_grant)
      access_grant.api_client&.api_key.presence || :public
    end
    private_class_method :api_for

    def self.public_recordable_name(type, api:)
      RecordingStudioApi.recordable_registration_for(type, api: api)&.public_name || type.to_s
    end
    private_class_method :public_recordable_name

    def self.type_mismatch_message(expected, recording, api:)
      expected_name = public_recordable_name(expected, api: api)
      actual_name = public_recordable_name(recording.recordable_type, api: api)
      "Expected a #{expected_name}, but this id is a #{actual_name}. Pass the id of a #{expected_name} recording (the id returned when that resource was created or looked up)."
    end
    private_class_method :type_mismatch_message
  end
end
