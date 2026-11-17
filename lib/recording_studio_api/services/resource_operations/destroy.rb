# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Destroy < Base
        def call
          authorize_access!(recording, role: :edit, include_trashed: true)

          serialized_recording = serialize_recording(recording)
          deleted_via = delete_recording!(recording)

          { json: serialize_delete_result(serialized_recording, deleted_via: deleted_via) }
        end

        private

        def delete_recording!(target_recording)
          if ResourceOperations.trashable_type?(target_recording.recordable_type)
            trash_recording!(target_recording)
            "trashed"
          else
            destroy_recording!(target_recording)
            "destroyed"
          end
        end

        # Trashable owns permission, events, children, and its other rules.
        def trash_recording!(target_recording)
          target_recording.recording_studio_trashable_trash!(
            actor: write_actor,
            impersonator: write_impersonator,
            metadata: { source: "recording_studio_api", api_action: "trash" }
          )
        end

        # Core refuses a parent that still has children and removes this
        # recording's events. The recordable snapshot stays.
        def destroy_recording!(target_recording)
          target_recording.destroy!
        rescue ActiveRecord::RecordNotDestroyed => e
          message = e.record.errors.full_messages.to_sentence.presence ||
                    "This recording still has children"
          raise RecordingStudioApi::InvalidActionInputError, message
        end
      end
    end
  end
end