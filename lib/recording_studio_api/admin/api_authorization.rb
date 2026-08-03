# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiAuthorization
      module_function

      def recording_for(api:, root_recording:, create: false)
        return if root_recording.nil?

        api_key = api.respond_to?(:name) ? api.name : api
        definition = RecordingStudioApi.configuration.fetch_api(api_key)
        admin_api = if create
                      RecordingStudioApi::AdminApi.find_or_create_by!(key: ApiContext.admin_record_key(definition.name)) do |record|
                        record.name = "Admin #{definition.name.humanize} API"
                      end
                    else
                      RecordingStudioApi::AdminApi.find_by(key: ApiContext.admin_record_key(definition.name))
                    end
        return if admin_api.nil?

        attributes = {
          recordable: admin_api,
          root_recording_id: root_recording.id,
          parent_recording_id: root_recording.id
        }
        create ? RecordingStudio::Recording.unscoped.find_or_create_by!(attributes) : RecordingStudio::Recording.unscoped.find_by(attributes)
      end

      def authorized?(actor:, api:, root_recording:, role:, create: false)
        recording = recording_for(api: api, root_recording: root_recording, create: create)
        return false if actor.nil? || recording.nil?

        RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)
      end
    end
  end
end
