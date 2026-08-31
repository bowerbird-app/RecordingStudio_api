# frozen_string_literal: true

module RecordingStudioApi
  module DelegatedOauthVoiding
    module_function

    def install!
      install_recording_callback!
      install_access_callback!
    end

    def install_recording_callback!
      return unless defined?(RecordingStudio::Recording)

      recording_class = RecordingStudio::Recording
      return if recording_class.method_defined?(:recording_studio_api_sync_delegated_oauth)

      recording_class.class_eval do
        after_commit :recording_studio_api_sync_delegated_oauth, on: %i[update destroy]

        def recording_studio_api_sync_delegated_oauth
          RecordingStudioApi::DelegatedOauthVoiding.sync_from_recording(self)
        end
      end
    end

    def install_access_callback!
      return unless defined?(RecordingStudio::Access)

      access_class = RecordingStudio::Access
      return if access_class.method_defined?(:recording_studio_api_sync_delegated_oauth)

      access_class.class_eval do
        after_commit :recording_studio_api_sync_delegated_oauth, on: :update

        def recording_studio_api_sync_delegated_oauth
          RecordingStudioApi::DelegatedOauthVoiding.sync_from_access(self)
        end
      end
    end

    def sync_from_recording(recording)
      return if recording.nil?
      return unless recording.recordable_type == "RecordingStudio::Access"

      authorizations_for_manager_access(recording).find_each do |authorization|
        sync_authorization!(authorization)
      end
    end

    def sync_from_access(access)
      return if access.nil?

      recordings = RecordingStudio::Recording.unscoped.where(
        recordable_type: "RecordingStudio::Access",
        recordable_id: access.id
      )
      recordings.find_each { |recording| sync_from_recording(recording) }
    end

    def sync_authorization!(authorization)
      return if authorization.nil? || authorization.revoked?

      Services::VoidOauthAuthorization.call(authorization: authorization) unless authorization.manager_qualifies?
    end

    def authorizations_for_manager_access(recording)
      OauthAuthorization.active.where(manager_access_recording_id: recording.id)
    end
  end
end
