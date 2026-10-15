# frozen_string_literal: true

require "test_helper"

class RecordableMetricsTest < Minitest::Test
  MetricSample = Class.new
  Child = Class.new(MetricSample)
  OtherSample = Class.new

  SAMPLE = "RecordableMetricsTest::MetricSample"
  CHILD = "RecordableMetricsTest::Child"

  def setup
    @original_configuration = RecordingStudioApi.configuration
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
    RecordingStudioMetrics.registry.reset!
  end

  def teardown
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudioMetrics.registry.reset!
    restore_api_metrics!
  end

  def test_equal_allowlists_reregister_and_omitted_metrics_keep_the_set
    registry = RecordingStudioApi::RecordableRegistry.new
    registry.register(SAMPLE, metrics: %w[metric_samples.total metric_samples.other])
    registry.register(SAMPLE, metrics: %w[metric_samples.other metric_samples.total])

    registration = registry.fetch(SAMPLE)
    assert_equal %w[metric_samples.other metric_samples.total], registration.metric_names
    assert_predicate registration.metric_names, :frozen?
    assert_predicate registration, :metrics_supplied?

    registry.register(SAMPLE, writable_attributes: [:name])
    kept = registry.fetch(SAMPLE)
    assert_equal %w[metric_samples.other metric_samples.total], kept.metric_names
    assert_equal ["name"], kept.writable_attributes
    assert_predicate kept, :metrics_supplied?
  end

  def test_a_different_allowlist_raises
    registry = RecordingStudioApi::RecordableRegistry.new
    registry.register(SAMPLE, metrics: %w[metric_samples.total])

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      registry.register(SAMPLE, metrics: %w[metric_samples.other])
    end
    assert_equal "Metrics cannot be redefined incompatibly", error.message

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      registry.register(SAMPLE, metrics: [])
    end
    assert_equal "Metrics cannot be redefined incompatibly", error.message
    assert_equal ["metric_samples.total"], registry.fetch(SAMPLE).metric_names
  end

  def test_invalid_metric_names_and_wrong_prefixes_raise_at_registration
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: SAMPLE, metrics: ["Total"])
    end
    assert_equal "Metric name is invalid for #{SAMPLE}: Total", error.message

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: SAMPLE, metrics: ["pages.total"])
    end
    assert_equal "Metric pages.total does not belong to #{SAMPLE}", error.message
  end

  def test_metrics_for_projects_description_and_list_filter_parameters
    register_sample(sortable_attributes: %i[name], writable_attributes: %i[created_at])
    register_definition(
      description: nil,
      title: "Sample total",
      intervals: %i[day week],
      group_by: %i[name]
    )

    entry = RecordingStudioApi.metrics_for(SAMPLE).fetch(0)

    assert_equal(
      {
        name: "metric_samples.total",
        description: "Sample total",
        parameters: [
          period_parameter("from", "Inclusive period start, as an ISO-8601 date-time. start and start_at are aliases.", format: "date-time"),
          period_parameter("to", "Exclusive period end, as an ISO-8601 date-time. end and end_at are aliases.", format: "date-time"),
          choice_parameter("interval", "Time-series bucket size.", enum: %w[day week]),
          choice_parameter("group_by", "Grouping column for this metric.", enum: %w[name]),
          query_parameter("q", "Case-insensitive substring search across filterable attributes for this resource."),
          query_parameter("filter[name]", "Exact match filter on name."),
          query_parameter("filter[created_at]", "Exact match filter on created_at.")
        ]
      },
      entry.as_json
    )
    assert_predicate entry, :frozen?
    assert_raises(FrozenError) { entry.parameters.first[:name] = "changed" }
  end

  def test_metrics_for_uses_the_definition_description_when_present
    register_sample
    register_definition(description: "How many samples are in this scope.", title: "Sample total")

    entry = RecordingStudioApi.metrics_for(SAMPLE).fetch(0)

    assert_equal "How many samples are in this scope.", entry.description
    assert_nil entry.parameters.find { |parameter| parameter[:name] == "interval" }.dig(:schema, :enum)
    assert_nil entry.parameters.find { |parameter| parameter[:name] == "group_by" }.dig(:schema, :enum)
  end

  def test_metrics_for_accepts_inheritance_in_either_direction
    register_sample
    register_definition(model: Child)
    assert_equal "metric_samples.total", RecordingStudioApi.metrics_for(SAMPLE).fetch(0).name

    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi.register_recordable_type_api(CHILD, metrics: %w[children.total])
    register_definition(resource: :children, model: MetricSample)
    assert_equal "children.total", RecordingStudioApi.metrics_for(CHILD).fetch(0).name
  end

  def test_a_scope_proc_stays_eligible
    register_sample
    register_definition(scope: ->(relation) { relation })

    RecordingStudioApi.configuration.validate!
    assert_equal ["metric_samples.total"], RecordingStudioApi.metrics_for(SAMPLE).map(&:name)
  end

  def test_validate_skips_a_missing_definition_and_metrics_for_raises
    register_sample(metrics: %w[metric_samples.absent])

    RecordingStudioApi.configuration.validate!
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.metrics_for(SAMPLE)
    end
    assert_equal "Metric metric_samples.absent is not registered with RecordingStudioMetrics", error.message
  end

  def test_site_and_recording_blast_radius_raise
    register_sample
    register_definition(blast_radius: :site)

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.configuration.validate!
    end
    assert_equal "Metric metric_samples.total must use root blast radius", error.message

    RecordingStudioMetrics.registry.reset!
    register_definition(blast_radius: :recording)
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.metrics_for(SAMPLE)
    end
    assert_equal "Metric metric_samples.total must use root blast radius", error.message
  end

  def test_named_api_validation_rejects_a_non_root_metric
    RecordingStudioApi.configuration.api(:billing)
    RecordingStudioApi.register_recordable_type_api(SAMPLE, api: :billing, metrics: %w[metric_samples.total])
    register_definition(blast_radius: :site)

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.configuration.validate!
    end
    assert_equal "Metric metric_samples.total must use root blast radius", error.message
  end

  def test_a_metric_exposed_on_a_configured_api_raises
    register_sample
    register_definition(expose: :public)

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.metrics_for(SAMPLE)
    end
    assert_equal "Metric metric_samples.total is already exposed on an API", error.message
  end

  def test_declared_metric_filters_raise
    register_sample
    RecordingStudioMetrics.register(:metric_samples, model: MetricSample, blast_radius: :root) do
      count :total, title: "Sample total", description: "How many samples are in this scope." do
        filter :status, type: :string, field: :name
      end
    end

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.metrics_for(SAMPLE)
    end
    assert_equal "Metric metric_samples.total declares metric filters", error.message
  end

  def test_a_model_mismatch_raises
    register_sample
    register_definition(model: OtherSample)

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.metrics_for(SAMPLE)
    end
    assert_equal "Metric metric_samples.total model does not match #{SAMPLE}", error.message
  end

  def test_a_custom_index_handler_raises
    register_sample
    register_definition
    RecordingStudioApi.register_resource_handler(SAMPLE, "index", handler: ->(*) { {} })

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.configuration.validate!
    end
    assert_equal "Metric metric_samples.total cannot be listed when #{SAMPLE} has a custom index handler", error.message
  end

  def test_routes_declare_resource_metrics_in_all_three_draw_blocks
    source = File.read(File.expand_path("../config/routes.rb", __dir__))

    assert_equal 3, source.scan("resource_metrics#index").length
    assert_equal 3, source.scan("resource_metrics#show").length
    [
      'to: "resource_metrics#index"',
      'to: "/recording_studio_api/api/v1/resource_metrics#index"',
      'to: "api/v1/resource_metrics#index"'
    ].each { |index_target| assert_includes source, index_target }
    [
      'get "/:resource/metrics/:name", to: "resource_metrics#show", constraints: resource_metrics_constraint, name: %r{[^/]+}, format: false, as: :resource_metric',
      'get "/:resource/metrics/:name", to: "/recording_studio_api/api/v1/resource_metrics#show", constraints: resource_metrics_constraint, name: %r{[^/]+}, format: false, as: :resource_metric',
      'get "/:resource/metrics/:name", to: "api/v1/resource_metrics#show", constraints: resource_metrics_constraint, name: %r{[^/]+}, format: false, as: :resource_metric'
    ].each do |show_line|
      assert_includes source, show_line
      rest = source[(source.index(show_line) + show_line.length)..]
      assert_match(%r{\A\n\s+get "/:resource/:id"}, rest)
    end
  end

  private

  def register_sample(metrics: %w[metric_samples.total], sortable_attributes: %i[name], writable_attributes: %i[name])
    RecordingStudioApi.register_recordable_type_api(
      SAMPLE,
      sortable_attributes: sortable_attributes,
      writable_attributes: writable_attributes,
      metrics: metrics
    )
  end

  def register_definition(resource: :metric_samples, model: MetricSample, blast_radius: :root, scope: nil, expose: nil, description: "How many samples are in this scope.", title: "Sample total", intervals: [], group_by: [])
    options = { blast_radius: blast_radius }
    options[:scope] = scope if scope
    RecordingStudioMetrics.register(resource, model: model, **options) do
      count_options = { title: title }
      count_options[:description] = description if description
      count_options[:expose] = expose if expose
      count_options[:intervals] = intervals if intervals.any?
      count_options[:group_by] = group_by if group_by.any?
      count :total, **count_options
    end
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

  def choice_parameter(name, description, enum:)
    {
      name: name,
      in: "query",
      required: false,
      description: description,
      schema: { type: "string", enum: enum }
    }
  end

  def query_parameter(name, description)
    {
      name: name,
      in: "query",
      required: false,
      description: description,
      schema: { type: "string" }
    }
  end

  def restore_api_metrics!
    loaded = %w[ApiDailyMetric ApiCredential].all? do |name|
      RecordingStudioApi.const_defined?(name, false) && RecordingStudioApi.autoload?(name).nil?
    end
    return unless loaded

    RecordingStudioApi::Metrics.register!
  rescue RecordingStudioMetrics::Errors::DuplicateRegistration
    nil
  end
end
