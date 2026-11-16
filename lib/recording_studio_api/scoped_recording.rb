# frozen_string_literal: true

module RecordingStudioApi
  class ScopedRecording
    def self.find!(access_grant:, id:, recordable_type:, include_trashed: false, missing: "Resource was not found in this API scope", type_mismatch: nil)
      recording = access_grant.accessible_recordings(include_trashed: include_trashed).find_by(id: id)
      raise NotFoundError, missing if recording.nil?

      expected = recordable_type.to_s
      return recording if recording.recordable_type == expected

      raise NotFoundError, (type_mismatch || "Resource type does not match #{expected}")
    end
  end
end
