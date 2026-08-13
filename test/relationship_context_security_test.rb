# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class RelationshipContextSecurityTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    user = create_user
    @primary, = create_access_recording_for(user: user)
    @grant = Object.new
  end

  teardown do
    reset_recording_studio_api_configuration!
    Current.actor = nil if defined?(Current)
  end

  test "strictly selects normalized fields and relationships" do
    registration = registration(
      fields: { "always" => field(true), "requested" => field(:request), "disabled" => field(false) },
      relationships: { "related" => relationship, "hidden" => relationship(include: false) }
    )
    with_registration(registration) do
      context = context_for("requested,related")
      assert_equal %w[always related requested], context.selected_include_names.sort
      ["unknown", "disabled", "hidden", "requested,requested", "requested,", "*", "nested.path", "true"].each do |value|
        assert_raises(RecordingStudioApi::InvalidActionInputError) { context_for(value) }
      end
      assert_raises(RecordingStudioApi::InvalidActionInputError) { context_for(true) }
      assert_raises(RecordingStudioApi::InvalidActionInputError) { context_for(["requested"]) }
    end
  end

  test "never resolves rejected names and safely resolves direct scoped children" do
    called = false
    folder = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Direct"), parent_recording: @primary)
    RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Descendant"), parent_recording: folder)
    registration = registration(relationships: {
      "folders" => relationship(source: :children, child_type: "Folder", many: true),
      "custom" => relationship(resolver: ->(_context) { called = true })
    })
    with_registration(registration) do
      assert_raises(RecordingStudioApi::InvalidActionInputError) { context_for("unknown") }
      refute called
      context = context_for("folders", scope: [@primary, folder])
      assert_equal [folder], context.relationship_value(@primary, "folders", registration.relationships.fetch("folders"))
    end
  end

  test "validates custom targets scopes them and uses shared context authorization" do
    visible = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Visible"), parent_recording: @primary)
    hidden = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Hidden"), parent_recording: @primary)
    received = nil
    registration = registration(relationships: {
      "many" => relationship(many: true, resolver: ->(context) { received = context; [visible, hidden] }),
      "invalid" => relationship(resolver: ->(_context) { Folder.first }),
      "denied" => relationship(authorize: ->(_context) { false })
    })
    with_registration(registration) do
      context = context_for("many,invalid,denied", scope: [@primary, visible], params: { "filter" => "recent" })
      assert_equal [visible], context.relationship_value(@primary, "many", registration.relationships.fetch("many"))
      assert_equal @primary, received.recording
      assert_equal @grant, received.access_grant
      assert_equal "v1", received.api_version
      assert_equal :public, received.api_key
      assert_equal "recent", received.params.fetch("filter")
      assert_equal registration.relationships.fetch("many"), received.current_relationship
      assert_raises(RecordingStudioApi::InvalidActionInputError) { context.relationship_value(@primary, "invalid", registration.relationships.fetch("invalid")) }
      assert_raises(RecordingStudioApi::AuthorizationError) { context.relationship_value(@primary, "denied", registration.relationships.fetch("denied")) }
      assert_raises(RecordingStudioApi::AuthorizationError) { context_for("many", scope: [@primary, visible], access_grant: nil).relationship_value(@primary, "many", registration.relationships.fetch("many")) }
    end
  end

  test "returns prepared results without invoking the single resolver" do
    target = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Target"), parent_recording: @primary)
    resolver = Class.new do
      attr_reader :single_calls, :batch_calls

      def initialize(target)
        @target = target
        @single_calls = 0
        @batch_calls = 0
      end

      def call(_context)
        @single_calls += 1
        raise "single resolver must not run for a prepared result"
      end

      def call_many(contexts)
        @batch_calls += 1
        contexts.to_h { |context| [context.recording.id, @target] }
      end
    end.new(target)
    registration = registration(relationships: { "related" => relationship(resolver: resolver) })

    with_registration(registration) do
      context = context_for("related", scope: [@primary, target], batch: true)
      assert_equal target, context.relationship_value(@primary, "related", registration.relationships.fetch("related"))
      assert_nil context.relationship_metadata(@primary, "related")
    end

    assert_equal 0, resolver.single_calls
    assert_equal 1, resolver.batch_calls
  end

  test "uses the single resolver with the shared context outside batching" do
    target = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Target"), parent_recording: @primary)
    resolver = Class.new do
      attr_reader :single_calls, :batch_calls, :received_context

      def initialize(target)
        @target = target
        @single_calls = 0
        @batch_calls = 0
      end

      def call(context)
        @single_calls += 1
        @received_context = context
        @target
      end

      def call_many(_contexts)
        @batch_calls += 1
        raise "batch resolver must not run outside index batching"
      end
    end.new(target)
    definition = relationship(resolver: resolver, authorize: ->(context) { context.current_relationship && context.access_grant == @grant })
    registration = registration(relationships: { "related" => definition })

    with_registration(registration) do
      context = context_for("related", scope: [@primary, target], batch: false)
      assert_equal target, context.relationship_value(@primary, "related", registration.relationships.fetch("related"))
    end

    assert_equal 1, resolver.single_calls
    assert_equal 0, resolver.batch_calls
    assert_equal @primary, resolver.received_context.recording
    assert_equal registration.relationships.fetch("related"), resolver.received_context.current_relationship
  end

  private

  def registration(fields: {}, relationships: {})
    RecordingStudioApi::RecordableRegistration.new(recordable_type: "Workspace", fields: fields, relationships: relationships)
  end

  def field(include)
    { resolver: ->(_context) { "value" }, include: include }
  end

  def relationship(source: :custom, child_type: nil, many: false, include: :request, resolver: nil, authorize: nil)
    options = { source: source, many: many, include: include, serializer: ->(_value) { { "name" => "value" } }, output_keys: ["name"], authorize: authorize }
    source == :children ? options[:child_type] = child_type : options[:resolver] = resolver || ->(_context) { nil }
    options[:limit] = 10 if many
    options
  end

  def context_for(include_values, scope: [@primary], access_grant: @grant, params: {}, batch: false)
    RecordingStudioApi::RelationshipContext.for(recordings: [@primary], include_values: include_values, scoped_recordings: RecordingStudio::Recording.where(id: scope.map(&:id)), api_key: :public, api_version: "v1", access_grant: access_grant, params: params, batch: batch)
  end

  def with_registration(registration)
    RecordingStudioApi.stub(:recordable_registration_for, ->(*, **) { registration }) { yield }
  end
end
