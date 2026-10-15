# frozen_string_literal: true

module RecordingStudioApi
  module MetricCatalog
    module_function

    def entries(recordable_type, api:)
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api)
      return [] if registration.nil? || registration.metric_names.empty?

      registration.metric_names.map { |name| build(registration, name, api: api) }
    end

    def validate_configured!(registry, api:)
      registry.to_h.each_key do |recordable_type|
        registration = registry[recordable_type]
        registration.metric_names.each do |name|
          definition = RecordingStudioMetrics.find(name)
          next if definition.nil?

          assert_eligible!(registration, name, definition, api: api)
        end
      end
    end

    def build(registration, name, api:)
      definition = RecordingStudioMetrics.find(name)
      raise ConfigurationError, "Metric #{name} is not registered with RecordingStudioMetrics" if definition.nil?

      assert_eligible!(registration, name, definition, api: api)
      MetricEntry.new(
        name: definition.identifier,
        description: definition.description.presence || definition.title,
        parameters: parameters_for(registration, definition),
        unit: definition.unit,
        title: definition.title.presence || definition.name.to_s,
        timezone: RecordingStudioMetrics.configuration.default_timezone,
        freshness: { cached: false }
      )
    end

    def parameters_for(registration, definition)
      [
        *window_parameters(definition),
        *group_parameters(definition),
        *Services::DocumentationCatalog.filter_query_parameters(registration.filterable_attributes)
      ]
    end

    def window_parameters(definition)
      return timeseries_window_parameters(definition) if definition.result_type == :timeseries
      return scalar_window_parameters(definition) if definition.field.present?

      []
    end

    def timeseries_window_parameters(definition)
      [
        period_parameter("from", "Inclusive period start, as an ISO-8601 date-time. start must match from when both are sent. start_at is the fallback.", format: "date-time"),
        period_parameter("to", "Exclusive period end, as an ISO-8601 date-time. end must match to when both are sent. end_at is the fallback.", format: "date-time"),
        choice_parameter("interval", "Time-series bucket size.", definition.intervals)
      ]
    end

    def scalar_window_parameters(_definition)
      [
        period_parameter("from", "Inclusive start for this count, applied on the metric field before execute. There is no timezone query parameter.", format: "date-time"),
        period_parameter("to", "Exclusive end for this count, applied on the metric field before execute.", format: "date-time")
      ]
    end

    def group_parameters(definition)
      return [] if definition.group_by.empty?

      [choice_parameter("group_by", "Grouping column for this metric. Do not allowlist a column that holds personal data. Groups under min_group_size fold into other.", definition.group_by)]
    end

    def period_parameter(name, description, format:)
      {
        name: name,
        in: "query",
        required: false,
        description: description,
        schema: { type: "string", format: format }
      }
    end

    def choice_parameter(name, description, values)
      schema = { type: "string" }
      schema[:enum] = values.map(&:to_s) if values.any?
      {
        name: name,
        in: "query",
        required: false,
        description: description,
        schema: schema
      }
    end

    def assert_eligible!(registration, name, definition, api:)
      raise ConfigurationError, "Metric #{name} must use root blast radius" unless definition.blast_radius == :root
      raise ConfigurationError, "Metric #{name} declares a scope" if definition.scope
      raise ConfigurationError, "Metric #{name} is already exposed on an API" if exposed_on_configured_api?(definition)
      raise ConfigurationError, "Metric #{name} declares metric filters" if definition.filters.any?

      recordable_klass = registration.recordable_type.safe_constantize
      raise ConfigurationError, "Metric #{name} model does not match #{registration.recordable_type}" unless recordable_klass && model_matches?(definition.model, recordable_klass)
      return unless RecordingStudioApi.resource_handler(registration.recordable_type, "index", api: api)

      raise ConfigurationError, "Metric #{name} cannot be listed when #{registration.recordable_type} has a custom index handler"
    end

    def exposed_on_configured_api?(definition)
      RecordingStudioApi.configuration.api_names.any? do |api_name|
        definition.exposed_to_api?(api_name)
      end
    end

    def model_matches?(model, recordable_klass)
      model <= recordable_klass || recordable_klass <= model
    end

    private_class_method :build, :parameters_for, :window_parameters, :timeseries_window_parameters,
                         :scalar_window_parameters, :group_parameters, :period_parameter, :choice_parameter,
                         :assert_eligible!, :exposed_on_configured_api?, :model_matches?
  end
  private_constant :MetricCatalog
end
