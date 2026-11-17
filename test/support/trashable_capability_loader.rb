# frozen_string_literal: true

# Loads Trashable's recording methods without the engine, then hides them
# again so the query-only boot checks stay true after the example.
module TrashableCapabilityLoader
  TRASH_METHODS = %i[
    recording_studio_trashable_trash!
    recording_studio_trashable_restore!
    recording_studio_trashable_purge!
    recording_studio_trashable_validate_purge!
  ].freeze

  module_function

  def ensure_columns!
    return if defined?(@columns_ready) && @columns_ready

    Thread.new { add_columns! }.join
    RecordingStudio::Recording.reset_column_information
    @columns_ready = true
  end

  def install!
    load_dependencies!
    return if RecordingStudio::Recording.method_defined?(:recording_studio_trashable_trash!)

    if @unbound
      restore_methods!
    else
      require "recording_studio/trashable/capabilities/trashable"
      remember_methods!
    end
  end

  def conceal!
    return unless RecordingStudio::Recording.method_defined?(:recording_studio_trashable_trash!)

    remember_methods!
    RecordingStudio.registered_capabilities.delete(:trashable)
    TRASH_METHODS.each do |name|
      RecordingStudio::Recording.undef_method(name) if RecordingStudio::Recording.method_defined?(name)
    end
  end

  def add_columns!
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      add_column_unless_present(connection, :trash_root, :boolean, default: false, null: false)
      add_column_unless_present(connection, :purge_at, :datetime)
    end
  end

  def add_column_unless_present(connection, name, type, **)
    return if connection.column_exists?(:recording_studio_recordings, name)

    connection.add_column(:recording_studio_recordings, name, type, **)
  end

  def load_dependencies!
    return if defined?(@dependencies_loaded) && @dependencies_loaded

    require "recording_studio_trashable/configuration"
    require "recording_studio_trashable/authorization"
    require "recording_studio_trashable/retention_policy"
    require "recording_studio_trashable/purge_stamp"
    define_trashable_entrypoints!
    @dependencies_loaded = true
  end

  def define_trashable_entrypoints!
    singleton = RecordingStudioTrashable.singleton_class
    unless singleton.method_defined?(:configuration)
      RecordingStudioTrashable.define_singleton_method(:configuration) do
        @configuration ||= RecordingStudioTrashable::Configuration.new
      end
    end
    unless singleton.method_defined?(:authorized?)
      RecordingStudioTrashable.define_singleton_method(:authorized?) do |**kwargs|
        RecordingStudioTrashable::Authorization.authorized?(**kwargs)
      end
    end
    return if singleton.method_defined?(:allow_user_retention_settings?)

    RecordingStudioTrashable.define_singleton_method(:allow_user_retention_settings?) { false }
    RecordingStudioTrashable.define_singleton_method(:capability_options_for) { |_| {} }
  end

  def remember_methods!
    @unbound = TRASH_METHODS.to_h do |name|
      [name, RecordingStudio::Recording.instance_method(name)]
    end
    @registration = RecordingStudio.registered_capabilities[:trashable]
  end

  def restore_methods!
    TRASH_METHODS.each do |name|
      RecordingStudio::Recording.define_method(name, @unbound.fetch(name))
    end
    RecordingStudio.registered_capabilities[:trashable] = @registration if @registration
  end
end
