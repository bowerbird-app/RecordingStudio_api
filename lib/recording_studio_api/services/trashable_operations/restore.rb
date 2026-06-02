# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module TrashableOperations
      class Restore < RecordingStudioApi::Services::ResourceOperations::Base
        def call
          authorize_access!(recording, role: :edit, include_trashed: true)

          restore_resource!(recording)

          { json: { data: serialize_recording(recording.reload) } }
        end

        private

        def restore_resource!(target_recording)
          if target_recording.respond_to?(:restore!)
            invoke_resource_method(target_recording, :restore!, actor: api_client, metadata: restore_metadata)
            return
          end

          recordable = target_recording.recordable
          if recordable.respond_to?(:restore!)
            invoke_resource_method(recordable, :restore!, actor: api_client, metadata: restore_metadata)
            return
          end

          if target_recording.respond_to?(:has_attribute?) && target_recording.has_attribute?(:trashed_at)
            target_recording.update!(trashed_at: nil)
            return
          end

          raise RecordingStudioApi::UnsupportedActionError, "Restore is not supported for #{target_recording.recordable_type}"
        end

        def invoke_resource_method(target, method_name, **kwargs)
          target.public_send(method_name, **kwargs)
        rescue ArgumentError
          target.public_send(method_name)
        end

        def restore_metadata
          {
            api_action: "restore",
            api_client_id: api_client.id,
            api_credential_id: credential.id
          }
        end
      end
    end
  end
end