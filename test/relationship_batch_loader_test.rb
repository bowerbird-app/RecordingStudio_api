# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class RelationshipBatchLoaderTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    user = create_user
    @primary, = create_access_recording_for(user: user)
    @access_grant = Object.new
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "constructs through for and exposes relationship value and metadata" do
    definition = relationship_definition(source: :custom, resolver: ->(_context) {})

    with_registration("owner" => definition) do
      context = build_context(include_values: "owner")

      assert context.include?("owner", definition)
      assert_nil context.relationship_value(@primary, "owner")
      assert_nil context.relationship_metadata(@primary, "owner")
    end
  end

  test "loads direct children once with scoped type filtering, limits, metadata, and preloaded recordables" do
    secondary = RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Secondary"))
    primary_children = create_children(@primary, 3, "Primary")
    secondary_children = create_children(secondary, 2, "Secondary")
    wrong_type = RecordingStudio::Recording.create!(recordable: Page.create!(title: "Wrong"), parent_recording: @primary)
    hidden = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Hidden"), parent_recording: @primary)
    set_identical_created_at(primary_children + secondary_children + [wrong_type, hidden])
    definition = relationship_definition(source: :children, child_type: "Folder", many: true, limit: 2,
                                         order: { "created_at" => :asc })
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] if payload[:sql].include?("ROW_NUMBER()")
    end

    with_registration("folders" => definition) do
      context = nil
      scope = [@primary, secondary, *primary_children, *secondary_children, wrong_type]
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        context = build_context(include_values: "folders", recordings: [@primary, secondary], scope: scope, batch: true)
      end

      assert_equal 1, queries.length
      prepared_reads = []
      prepared_read_subscriber = lambda do |_name, _start, _finish, _id, payload|
        prepared_reads << payload[:sql] if payload[:sql].match?(/FROM.*recording_studio_recordings/i)
      end
      primary_values = nil
      primary_metadata = nil
      ActiveSupport::Notifications.subscribed(prepared_read_subscriber, "sql.active_record") do
        primary_values = context.relationship_value(@primary, "folders")
        primary_metadata = context.relationship_metadata(@primary, "folders")
      end

      assert_equal primary_children.sort_by(&:id).first(2), primary_values
      assert_equal secondary_children.sort_by(&:id), context.relationship_value(secondary, "folders")
      assert_equal({ limit: 2, has_more: true }, primary_metadata)
      assert_empty prepared_reads
      assert_nil context.relationship_metadata(secondary, "folders")
      assert(context.relationship_value(@primary, "folders").all? { |recording| recording.association(:recordable).loaded? })
      refute_includes context.relationship_value(@primary, "folders"), wrong_type
      refute_includes context.relationship_value(@primary, "folders"), hidden
    end
  end

  test "prepares every relationship sharing a compatible child query" do
    children = create_children(@primary, 2, "Shared")
    definition = relationship_definition(source: :children, child_type: "Folder", many: true, limit: 2,
                                         order: { "created_at" => :asc })

    with_registration("folders" => definition, "recent_folders" => definition) do
      context = build_context(include_values: "folders,recent_folders", scope: [@primary, *children], batch: true)

      assert_equal children.sort_by { |recording| [recording.created_at, recording.id] }, context.relationship_value(@primary, "folders")
      assert_equal context.relationship_value(@primary, "folders"), context.relationship_value(@primary, "recent_folders")
    end
  end

  test "requires call_many for selected custom index expansion" do
    definition = relationship_definition(source: :custom, resolver: ->(_context) { @primary })

    with_registration("owner" => definition) do
      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        build_context(include_values: "owner", batch: true)
      end

      assert_includes error.message, "owner requires resolver.call_many(contexts)"
    end
  end

  test "uses call_many for singular and many custom values while filtering inaccessible targets" do
    visible = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Visible"), parent_recording: @primary)
    hidden = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Hidden"), parent_recording: @primary)
    resolver = BatchResolver.new do |contexts|
      contexts.to_h do |context|
        [context.recording.id, context.current_relationship.many ? [visible, hidden] : visible]
      end
    end
    singular = relationship_definition(source: :custom, resolver: resolver)
    many = relationship_definition(source: :custom, many: true, limit: 2, resolver: resolver)

    with_registration("owner" => singular, "folders" => many) do
      context = build_context(include_values: "owner,folders", scope: [@primary, visible], batch: true)

      assert_equal visible, context.relationship_value(@primary, "owner")
      assert_equal [visible], context.relationship_value(@primary, "folders")
      assert_equal 2, resolver.calls.length
    end
  end

  test "rejects invalid call_many keys and values" do
    invalid_key = BatchResolver.new { |_contexts| { "unknown" => @primary } }
    invalid_value = BatchResolver.new { |contexts| { contexts.first.recording.id => Folder.new } }

    [invalid_key, invalid_value].each do |resolver|
      definition = relationship_definition(source: :custom, resolver: resolver)
      with_registration("owner" => definition) do
        assert_raises(RecordingStudioApi::ConfigurationError) { build_context(include_values: "owner", batch: true) }
      end
    end
  end

  private

  BatchResolver = Struct.new(:implementation) do
    attr_reader :calls

    def initialize(&implementation)
      super(implementation)
      @calls = []
    end

    def call(_context)
      raise "call must not be used for index batching"
    end

    def call_many(contexts)
      calls << contexts
      implementation.call(contexts)
    end
  end

  def build_context(include_values:, recordings: [@primary], scope: [@primary], batch: false)
    RecordingStudioApi::RelationshipContext.for(
      recordings: recordings,
      include_values: include_values,
      scoped_recordings: RecordingStudio::Recording.where(id: scope.map(&:id)),
      api_key: :public,
      api_version: "v1",
      access_grant: @access_grant,
      params: {},
      batch: batch
    )
  end

  def relationship_definition(source:, child_type: nil, many: false, limit: nil, order: nil, resolver: nil)
    options = {
      source: source,
      many: many,
      include: :request,
      serializer: ->(value) { { label: value.to_s } },
      output_keys: %i[label]
    }
    options[:child_type] = child_type if child_type
    options[:resolver] = resolver if resolver
    options[:limit] = limit if many && limit
    options[:order] = order if many && order
    registration(relationships: { relationship: options }).relationships.fetch("relationship")
  end

  def with_registration(relationships, &)
    registration = registration(relationships: relationships)
    RecordingStudioApi.stub(:recordable_registration_for, ->(*, **) { registration }, &)
  end

  def registration(relationships:)
    RecordingStudioApi::RecordableRegistration.new(recordable_type: "Workspace", relationships: relationships)
  end

  def create_children(parent, count, prefix)
    count.times.map do |index|
      RecordingStudio::Recording.create!(recordable: Folder.create!(name: "#{prefix} #{index}"), parent_recording: parent)
    end
  end

  def set_identical_created_at(recordings)
    timestamp = Time.utc(2026, 1, 1)
    recordings.each { |recording| recording.update_columns(created_at: timestamp, updated_at: timestamp) }
  end
end
