# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiAuthorization
      module_function

      def provision!(api:, root_recording:, actor: nil)
        root = required_admin_root!(root_recording)
        definition = definition_for(api)
        existing = recording_for(api: definition, root_recording: root)
        return existing if existing

        recording = nil
        RecordingStudioApi::AdminApi.transaction do
          admin_api = admin_api_for!(definition)
          recording = find_recording(admin_api, root)
          recording = record_admin_api!(root, admin_api, actor: actor, definition: definition) if recording.nil?
        end
        recording
      end

      def recording_for(api:, root_recording:)
        return if root_recording.nil?

        definition = definition_for(api)
        admin_api = RecordingStudioApi::AdminApi.find_by(key: ApiContext.admin_record_key(definition.name))
        return if admin_api.nil?

        find_recording(admin_api, RecordingStudio.root_recording_or_self(root_recording))
      end

      def authorized?(actor:, api:, root_recording:, role:)
        recording = recording_for(api: api, root_recording: root_recording)
        return false if actor.nil? || recording.nil?

        RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)
      end

      def definition_for(api)
        api_key = api.respond_to?(:name) ? api.name : api
        RecordingStudioApi.configuration.fetch_api(api_key)
      end
      private_class_method :definition_for

      def required_admin_root!(root_recording)
        raise ArgumentError, "Admin root recording is required" if root_recording.nil?

        root = RecordingStudio.root_recording_or_self(root_recording)
        return root if RecordingStudioApi.configuration.admin_root_recordable_type_names.include?(root.recordable_type)

        raise ArgumentError, "Admin API records belong under an admin root"
      end
      private_class_method :required_admin_root!

      def admin_api_for!(definition)
        RecordingStudioApi::AdminApi.find_or_create_by!(key: ApiContext.admin_record_key(definition.name)) do |record|
          record.name = "Admin #{definition.name.humanize} API"
        end
      end
      private_class_method :admin_api_for!

      def find_recording(admin_api, root)
        RecordingStudio::Recording.unscoped.find_by(
          recordable: admin_api,
          root_recording_id: root.id,
          parent_recording_id: root.id
        )
      end
      private_class_method :find_recording

      def record_admin_api!(root, admin_api, actor:, definition:)
        RecordingStudio.record!(
          action: "created",
          recordable: admin_api,
          root_recording: root,
          parent_recording: root,
          actor: actor,
          idempotency_key: idempotency_key_for(definition, root)
        ).recording
      end
      private_class_method :record_admin_api!

      def idempotency_key_for(definition, root)
        "recording-studio-api/admin-api/#{definition.name}/#{root.id}"
      end
      private_class_method :idempotency_key_for
    end
  end
end
