# frozen_string_literal: true

module Dummy
  module Api
    module Actions
      class TrashRecording
        class << self
          def call(context)
            new(context).call
          end
        end

        def initialize(context)
          @context = context
        end

        def call
          trash_resource!
          recording.reload
        end

        private

        attr_reader :context

        delegate :recording, :api_client, :credential, to: :context

        def trash_resource!
          if recording.respond_to?(:trash!)
            invoke_resource_method(recording, :trash!, actor: api_client, metadata: trash_metadata)
            return
          end

          recordable = recording.recordable
          if recordable.respond_to?(:trash!)
            invoke_resource_method(recordable, :trash!, actor: api_client, metadata: trash_metadata)
            return
          end

          if recording.respond_to?(:has_attribute?) && recording.has_attribute?(:trashed_at)
            recording.update!(trashed_at: Time.current)
            return
          end

          raise RecordingStudioApi::UnsupportedActionError, "Trash is not supported for #{recording.recordable_type}"
        end

        def invoke_resource_method(target, method_name, **kwargs)
          target.public_send(method_name, **kwargs)
        rescue ArgumentError
          target.public_send(method_name)
        end

        def trash_metadata
          {
            api_action: "trash",
            api_client_id: api_client.id,
            api_credential_id: credential.id
          }
        end
      end
    end
  end
end