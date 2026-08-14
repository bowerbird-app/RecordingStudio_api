# frozen_string_literal: true

module RecordingStudioApi
  class SerializerContext
    attr_reader :recording, :recordable, :access_grant, :scoped_recordings, :api_version,
                :api_key, :params, :registration, :current_field, :current_relationship,
                :selected_include_names, :target_recording

    def self.build(recording:, context:, api_version:, api_key:, registration:, field: nil, relationship: nil)
      if context.is_a?(self)
        return context.with(recording: recording, recordable: recording.recordable, registration: registration,
                            field: field, relationship: relationship, target_recording: nil)
      end

      new(
        recording: recording,
        recordable: recording.recordable,
        access_grant: context_value(context, :access_grant),
        scoped_recordings: context_value(context, :scoped_recordings),
        api_version: context_value(context, :api_version) || api_version,
        api_key: context_value(context, :api_key) || api_key,
        params: context_value(context, :params),
        registration: registration,
        selected_include_names: context_value(context, :selected_include_names),
        relationship_context: context,
        field: field,
        relationship: relationship
      )
    end

    def initialize(recording:, recordable:, access_grant:, scoped_recordings:, api_version:, api_key:, params:,
                   registration:, selected_include_names: nil, relationship_context: nil, field: nil, relationship: nil,
                   target_recording: nil)
      @recording = recording
      @recordable = recordable
      @access_grant = access_grant
      @scoped_recordings = scoped_recordings
      @api_version = api_version
      @api_key = api_key
      @params = params
      @registration = registration
      @selected_include_names = Array(selected_include_names).map(&:to_s).freeze
      @target_recording = target_recording
      @relationship_context = relationship_context
      @field = field
      @current_field = field
      @relationship = relationship
      @current_relationship = relationship
    end

    def with(recording: @recording, recordable: @recordable, registration: @registration, field: @field, relationship: @relationship,
             target_recording: @target_recording)
      self.class.new(
        recording: recording, recordable: recordable, access_grant: access_grant,
        scoped_recordings: scoped_recordings, api_version: api_version, api_key: api_key, params: params,
        registration: registration, selected_include_names: selected_include_names,
        relationship_context: @relationship_context, field: field, relationship: relationship, target_recording: target_recording
      )
    end

    def include?(name, definition = nil)
      return @relationship_context.include?(name, definition) if @relationship_context.respond_to?(:include?)

      selected_include_names.include?(name.to_s)
    end

    def relationship_value(recording, name, definition)
      @relationship_context.relationship_value(recording, name, definition) if @relationship_context.respond_to?(:relationship_value)
    end

    def relationship_metadata(recording, name)
      @relationship_context.relationship_metadata(recording, name) if @relationship_context.respond_to?(:relationship_metadata)
    end

    def self.context_value(context, name)
      context.public_send(name) if context.respond_to?(name)
    end
  end
end