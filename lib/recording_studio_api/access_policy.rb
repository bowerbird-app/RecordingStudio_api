# frozen_string_literal: true

module RecordingStudioApi
  class AccessPolicy
    def initialize(access_recording:)
      @access_recording = access_recording
    end

    def can_read?
      RecordingStudio::AccessRoles.value_for(access_role).present?
    end

    def can_write?
      RecordingStudio::AccessRoles.satisfies?(role: access_role, minimum_role: :edit)
    end

    def can_admin?
      RecordingStudio::AccessRoles.satisfies?(role: access_role, minimum_role: :admin)
    end

    private

    attr_reader :access_recording

    def access_role
      access = access_recording&.recordable
      return unless access.is_a?(RecordingStudio::Access)

      access.role
    end
  end
end
