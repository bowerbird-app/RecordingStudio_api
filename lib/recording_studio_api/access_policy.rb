# frozen_string_literal: true

module RecordingStudioApi
  class AccessPolicy
    def initialize(access_recording:)
      @access_recording = access_recording
    end

    def can_read?
      !role_rank.nil?
    end

    def can_write?
      role_rank && role_rank >= required_rank(:edit)
    end

    def can_admin?
      role_rank && role_rank >= required_rank(:admin)
    end

    private

    attr_reader :access_recording

    def role_rank
      @role_rank ||= begin
        access = access_recording&.recordable
        return unless access.is_a?(RecordingStudio::Access)

        RecordingStudio::Access.roles[access.role]
      end
    end

    def required_rank(role)
      RecordingStudio::Access.roles.fetch(role.to_s)
    end
  end
end