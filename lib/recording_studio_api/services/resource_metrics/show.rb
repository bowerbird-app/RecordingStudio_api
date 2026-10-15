# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceMetrics
      class Show < ResourceOperations::Base
        def call
          authorize_access!(access_scope_recording, role: :view)
          name = params[:name].to_s
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
          raise RecordingStudioApi::NotFoundError, "Metric #{name} is not available on this resource" unless registration&.metric_names&.include?(name)

          entry = RecordingStudioApi.metrics_for(recordable_type, api: api_key).find { |candidate| candidate.name == name }
          result = execute_metric(entry, folded_query)
          { json: result.as_json }
        rescue RecordingStudioMetrics::Errors::Error => e
          RecordingStudioMetrics::Api.raise_mapped!(e)
        end

        private

        def execute_metric(entry, folded)
          # Leave root_recording, access_recording, and workspace_id unset so apply_root_or_recording_scope returns authorized_relation.
          RecordingStudioMetrics.execute(
            entry.name,
            context: RecordingStudioMetrics::Context.new(
              actor: access_grant.actor,
              system: access_grant.actor.nil?,
              scope: :root,
              authorized_relation: scoped_relation(entry),
              site_authorized: false
            ),
            interval: folded[:interval],
            start_at: folded[:start],
            end_at: folded[:end],
            group_by: folded[:group_by],
            filters: {},
            cache: false # cache_vary hashes scope_key and params[:filters], not the relation or q / filter[attribute].
          )
        end

        def scoped_relation(entry)
          definition = RecordingStudioMetrics.find(entry.name)
          recordings = ResourceOperations.apply_list_filter(
            scoped_recordings.where(recordable_type: recordable_type),
            recordable_type: recordable_type,
            params: params,
            api: api_key
          )
          definition.model.where(id: recordings.reselect(RecordingStudio::Recording.arel_table[:recordable_id]))
        end

        def folded_query
          raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
          RecordingStudioApi::Metrics::Period.fold(raw.transform_keys(&:to_sym))
        end
      end
    end
  end
end
