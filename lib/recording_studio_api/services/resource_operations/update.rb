# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Update < Base
        def call
          reject_parent_id_input!
          authorize_access!(recording, role: :edit)

          attributes = resource_attributes.slice(*mutable_attribute_keys)
          revised_recording = if attributes.any?
                                recording.root_recording.revise(recording, actor: api_client) do |recordable|
                                  recordable.assign_attributes(attributes)
                                end
                              else
                                recording
                              end

          { json: serialize_recording(revised_recording, context: relationship_context_for([revised_recording])) }
        end

        private

        def reject_parent_id_input!
          return if context.parent_recording
          return unless request_payload.key?(:parent_id) || request_payload.key?("parent_id")

          raise RecordingStudioApi::InvalidActionInputError,
                "parent_id is not permitted for updates; use the move action instead"
        end
      end
    end
  end
end