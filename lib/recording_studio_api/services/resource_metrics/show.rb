# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceMetrics
      class Show < ResourceOperations::Base
        def call
          assert_index_enabled!
          authorize_access!(access_scope_recording, role: :view)
          name = ClientText.cap(params[:name].to_s)
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
          raise RecordingStudioApi::NotFoundError, "Metric #{name} is not available on this resource" unless registration&.metric_names&.include?(params[:name].to_s)

          entry = RecordingStudioApi.metrics_for(recordable_type, api: api_key).find { |candidate| candidate.name == params[:name].to_s }
          query = metric_query(entry)
          result = execute_metric(entry, query)
          { json: metric_payload(result) }
        rescue RecordingStudioMetrics::Errors::Error => e
          mapped = RecordingStudioMetrics::Api.map_to_api_error(e)
          raise mapped.class, ClientText.cap(mapped.message)
        end

        private

        def execute_metric(entry, query)
          definition = RecordingStudioMetrics.find(entry.name)
          # Leave root_recording, access_recording, and workspace_id unset so apply_root_or_recording_scope returns authorized_relation.
          RecordingStudioMetrics.execute(
            entry.name,
            context: RecordingStudioMetrics::Context.new(
              actor: access_grant.actor,
              system: access_grant.actor.nil?,
              scope: :root,
              authorized_relation: scoped_relation(definition, query),
              site_authorized: false
            ),
            interval: query[:interval],
            start_at: definition.result_type == :timeseries ? query[:start] : nil,
            end_at: definition.result_type == :timeseries ? query[:end] : nil,
            group_by: query[:group_by],
            filters: {},
            cache: false # cache_vary hashes scope_key and params[:filters], not the relation or q / filter[attribute].
          )
        end

        def scoped_relation(definition, query)
          recordings = ResourceOperations.apply_list_filter(
            scoped_recordings.where(recordable_type: recordable_type),
            recordable_type: recordable_type,
            params: params,
            api: api_key
          )
          relation = definition.model.where(id: recordings.reselect(RecordingStudio::Recording.arel_table[:recordable_id]))
          window_scalar_relation(relation, definition, query)
        end

        def window_scalar_relation(relation, definition, query)
          return relation unless definition.result_type == :scalar && definition.field.present?
          return relation if query[:start].nil? && query[:end].nil?

          column = definition.field
          relation = relation.where(column => parse_time(query[:start])..) if query[:start]
          relation = relation.where(column => ...parse_time(query[:end])) if query[:end]
          relation
        end

        def metric_payload(result)
          payload = result.as_json
          payload.delete(:filters)
          payload.delete("filters")
          payload
        end

        def metric_query(entry)
          accepted = entry.parameters.map { |parameter| parameter[:name].to_s }
          raw = query_params
          reject_engine_filters!(raw)
          reject_structured_query!(raw)
          reject_unaccepted_window!(raw, accepted)
          {
            start: bound(raw, primary: :start, alias_key: :from, legacy: :start_at),
            end: bound(raw, primary: :end, alias_key: :to, legacy: :end_at),
            interval: raw[:interval],
            group_by: raw[:group_by]
          }
        end

        def query_params
          raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
          raw.to_h.transform_keys(&:to_sym)
        end

        def reject_engine_filters!(raw)
          return unless raw.key?(:filters)

          raise RecordingStudioApi::InvalidActionInputError, "filters is not accepted for this metric"
        end

        def reject_structured_query!(raw)
          %i[from to interval group_by start start_at end end_at timezone].each do |key|
            value = raw[key]
            next if value.nil? || value.is_a?(String)

            raise RecordingStudioApi::InvalidActionInputError, "#{key} must be a single value"
          end
        end

        def reject_unaccepted_window!(raw, accepted)
          %w[from to interval start start_at end end_at group_by timezone].each do |key|
            next if raw[key.to_sym].nil?
            next if accepted.include?(key) || accepted.include?(alias_for(key))

            raise RecordingStudioApi::InvalidActionInputError, "#{key} is not accepted for this metric"
          end
        end

        def alias_for(key)
          { "start" => "from", "start_at" => "from", "end" => "to", "end_at" => "to" }[key]
        end

        def bound(raw, primary:, alias_key:, legacy:)
          RecordingStudioMetrics::Api.period_bound(raw, primary: primary, alias_key: alias_key, legacy: legacy)
        end

        def parse_time(value)
          parsed = Time.zone.parse(value.to_s)
          raise RecordingStudioApi::InvalidActionInputError, "invalid time value" if parsed.nil?

          parsed
        rescue ArgumentError
          raise RecordingStudioApi::InvalidActionInputError, "invalid time value"
        end
      end
    end
  end
end
