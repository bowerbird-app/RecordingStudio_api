# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class ResourcesController < RecordingStudioApi::ApiController
        def index
          if params[:resource].present?
            recordable_type = resolve_recordable_type!
            recordings = scoped_recordings.where(recordable_type: recordable_type)

            render json: {
              resource: params[:resource],
              recordable_type: recordable_type,
              data: recordings.map { |recording| serialize_recording(recording) }
            }
          else
            render json: {
              resources: RecordingStudioApi.api_recordable_types.map do |recordable_type|
                {
                  name: RecordingStudioApi.resource_name_for(recordable_type),
                  recordable_type: recordable_type
                }
              end
            }
          end
        end

        def show
          render json: { data: serialize_recording(resource_recording) }
        end

        def actions
          render json: {
            data: RecordingStudioApi.capability_actions_for(resource_recording.recordable_type).map(&:as_json)
          }
        end

        private

        def resource_recording
          @resource_recording ||= begin
            recordable_type = resolve_recordable_type!
            recording = scoped_recordings.find_by(id: params[:id])
            raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
            raise RecordingStudioApi::NotFoundError, "Resource type does not match #{recordable_type}" unless recording.recordable_type == recordable_type

            recording
          end
        end

        def scoped_recordings
          @scoped_recordings ||= RecordingStudio::Recording.unscoped.where(id: scoped_recording_ids)
        end

        def scoped_recording_ids
          @scoped_recording_ids ||= [current_scope_recording, *current_scope_recording.descendants].compact.map(&:id)
        end

        def resolve_recordable_type!
          recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource])
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

          recordable_type
        end

        def serialize_recording(recording)
          RecordingStudioApi::Serializers::RecordingSerializer.call(recording)
        end
      end
    end
  end
end
