# frozen_string_literal: true

require "recording_studio_metrics"

module RecordingStudioApi
  module Metrics
    API = :operations
    EXPOSE = { api: [API] }.freeze
    AUTHORIZE = lambda { |context|
      RecordingStudioApi::Admin::ApiAuthorization.authorized?(
        actor: context.access_grant.actor,
        api: context.api_key,
        root_recording: context.root_recording,
        role: RecordingStudioApi.configuration.access_management_view_role
      )
    }

    module_function

    def register!
      register_api_requests!
      register_api_keys!
    end

    def register_api_requests!
      RecordingStudioMetrics.register(
        :api_requests,
        model: ApiDailyMetric,
        blast_radius: :site,
        api_authorize: AUTHORIZE
      ) do
        RecordingStudioApi::Metrics.define_api_requests(self)
      end
    end

    def register_api_keys!
      RecordingStudioMetrics.register(
        :api_keys,
        model: ApiCredential,
        blast_radius: :site,
        scope: ->(relation) { relation.merge(ApiCredential.active) },
        api_authorize: AUTHORIZE
      ) do
        count :active, title: "Active API keys", expose: RecordingStudioApi::Metrics::EXPOSE
      end
    end

    def define_api_requests(dsl)
      dsl.timeseries :over_time,
                     title: "API requests over time",
                     field: :metric_date,
                     measurement: :sum,
                     value_field: :request_count,
                     expose: EXPOSE
      dsl.custom :errors_over_time,
                 result_type: :timeseries,
                 title: "API errors over time",
                 expose: EXPOSE,
                 &errors_over_time_calculator
      dsl.breakdown :by_status_class,
                    title: "API requests by status class",
                    field: :status_class,
                    measurement: :sum,
                    value_field: :request_count,
                    expose: EXPOSE
      dsl.sum :rate_limited,
              title: "Rate limited API requests",
              field: :rate_limited_count,
              expose: EXPOSE
    end

    def errors_over_time_calculator
      lambda do |relation, _context|
        relation.group(:metric_date).sum(Arel.sql("client_error_count + server_error_count")).map do |metric_date, value|
          { date: metric_date.iso8601, value: value }
        end
      end
    end
  end
end
