# frozen_string_literal: true

require "test_helper"

class ProgressReportingTest < Minitest::Test
  FakeReporter = Struct.new(:cancelled, :updates, keyword_init: true) do
    def initialize(cancelled: false, updates: [])
      super
    end

    def progress(current:, total: nil, message: nil)
      updates << { current: current, total: total, message: message }
      :reported
    end

    def cancelled?
      cancelled
    end
  end

  def test_action_context_defaults_reporter_to_nil
    context = action_context

    assert_nil context.progress_reporter
    assert_nil context.progress(current: 1, total: 2, message: "go")
    assert_equal false, context.cancelled?
  end

  def test_registered_endpoint_context_defaults_reporter_to_nil
    context = registered_endpoint_context

    assert_nil context.progress_reporter
    assert_nil context.progress(current: 1)
    assert_equal false, context.cancelled?
  end

  def test_resource_operation_context_defaults_reporter_to_nil
    context = resource_operation_context

    assert_nil context.progress_reporter
    assert_nil context.progress(current: 3, total: 10, message: "halfway")
    assert_equal false, context.cancelled?
  end

  def test_action_context_delegates_progress_and_cancelled_to_reporter
    reporter = FakeReporter.new(cancelled: true)
    context = action_context(progress_reporter: reporter)

    assert_equal :reported, context.progress(current: 2, total: 5, message: "step")
    assert_equal true, context.cancelled?
    assert_equal [{ current: 2, total: 5, message: "step" }], reporter.updates
  end

  def test_registered_endpoint_context_delegates_progress_and_cancelled_to_reporter
    reporter = FakeReporter.new
    context = registered_endpoint_context(progress_reporter: reporter)

    context.progress(current: 1, total: nil, message: nil)
    assert_equal false, context.cancelled?
    assert_equal [{ current: 1, total: nil, message: nil }], reporter.updates
  end

  def test_resource_operation_context_delegates_progress_and_cancelled_to_reporter
    reporter = FakeReporter.new(cancelled: true)
    context = resource_operation_context(progress_reporter: reporter)

    context.progress(current: 4, total: 4, message: "done")
    assert_equal true, context.cancelled?
    assert_equal [{ current: 4, total: 4, message: "done" }], reporter.updates
  end

  def test_action_context_with_and_equality_keep_working
    first = action_context(params: { name: "a" })
    second = action_context(params: { name: "a" })
    changed = first.with(params: { name: "b" })

    assert_equal first, second
    assert_equal({ name: "b" }, changed.params)
    assert_nil changed.progress_reporter
    refute_equal first, changed
  end

  def test_registered_endpoint_context_with_and_equality_keep_working
    first = registered_endpoint_context(params: { key: "a" })
    second = registered_endpoint_context(params: { key: "a" })
    reporter = FakeReporter.new
    with_reporter = first.with(progress_reporter: reporter)

    assert_equal first, second
    assert_equal reporter, with_reporter.progress_reporter
    refute_equal first, with_reporter
  end

  def test_resource_operation_context_with_and_equality_keep_working
    first = resource_operation_context(idempotency_key: "abc")
    second = resource_operation_context(idempotency_key: "abc")
    changed = first.with(idempotency_key: "xyz")

    assert_equal first, second
    assert_equal "xyz", changed.idempotency_key
    assert_nil changed.progress_reporter
    refute_equal first, changed
  end

  def test_rest_construction_sites_do_not_pass_a_progress_reporter
    sites = [
      "app/controllers/recording_studio_api/api/v1/member_actions_controller.rb",
      "app/controllers/recording_studio_api/api/v1/resources_controller.rb",
      "app/controllers/recording_studio_api/api/v1/relationship_resources_controller.rb",
      "app/controllers/recording_studio_api/api/v1/registered_endpoints_controller.rb"
    ]

    sites.each do |relative_path|
      source = File.read(File.expand_path("../#{relative_path}", __dir__))
      refute_includes source, "progress_reporter",
                      "#{relative_path} must not wire a progress reporter on the REST path"
    end
  end

  private

  def action_context(**overrides)
    RecordingStudioApi::ActionContext.new(
      **{
        recording: :recording,
        api_client: nil,
        credential: :credential,
        access_recording: :access_recording,
        access_grant: :access_grant,
        root_recording: :root_recording,
        params: {}
      }.merge(overrides)
    )
  end

  def registered_endpoint_context(**overrides)
    RecordingStudioApi::RegisteredEndpointContext.new(
      **{
        api_client: nil,
        credential: :credential,
        access_recording: :access_recording,
        access_grant: :access_grant,
        root_recording: :root_recording,
        params: {}
      }.merge(overrides)
    )
  end

  def resource_operation_context(**overrides)
    RecordingStudioApi::ResourceOperationContext.new(
      **{
        recording: :recording,
        recordable_type: "Page",
        resource_name: "pages",
        api_client: nil,
        credential: :credential,
        access_recording: :access_recording,
        access_grant: :access_grant,
        root_recording: :root_recording,
        api_version: "v1",
        params: {},
        request_params: {},
        scoped_recordings: [],
        parent_recording: nil
      }.merge(overrides)
    )
  end
end
