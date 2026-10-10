# frozen_string_literal: true

require "recording_studio_metrics"

module RecordingStudioApi
  module Metrics
    API = :operations
    EXPOSE = { api: [API] }.freeze
    ResolverContext = Struct.new(:controller)
    AUTHORIZE = lambda { |context|
      actor = context&.access_grant&.actor
      recording = site_admin_recording
      return false if actor.blank? || recording.blank?

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: recording,
        role: RecordingStudioApi.configuration.access_management_view_role
      )
    }

    module_function

    def site_admin_recording
      return unless defined?(RecordingStudioAdmin)

      config = RecordingStudioAdmin.configuration
      resolver = config.site_admin_recording_resolver || config.access_recording_resolver
      return unless resolver

      resolver.call(ResolverContext.new(nil))
    rescue StandardError
      nil
    end
    private_class_method :site_admin_recording

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
      dsl.timeseries :errors_over_time,
                     title: "API errors over time",
                     field: :metric_date,
                     measurement: :sum,
                     value_field: Arel.sql("client_error_count + server_error_count"),
                     expose: EXPOSE
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
  end
end
