# frozen_string_literal: true

class DocsController < ApplicationController
  def install
  end

  def configuration
    render :config
  end

  def recordable_types
    @recordable_types = Array(RecordingStudio.configuration.recordable_types).filter_map do |recordable_type|
      normalize_recordable_type(recordable_type)
    end
  end

  def recordings_tree
    recordings = RecordingStudio::Recording.unscoped.includes(:recordable).reorder(:created_at, :id).to_a
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)
    recording_ids = recordings.each_with_object({}) { |recording, ids| ids[recording.id] = true }

    root_recordings = recordings_by_parent_id.fetch(nil, [])
    disconnected_roots = recordings.select do |recording|
      recording.parent_recording_id.present? && !recording_ids.key?(recording.parent_recording_id)
    end

    visited = {}

    @recording_tree = (root_recordings + disconnected_roots).filter_map do |recording|
      build_recording_node(recording, recordings_by_parent_id, visited)
    end

    remaining_recordings = recordings.reject { |recording| visited.key?(recording.id) }
    @recording_tree.concat(
      remaining_recordings.filter_map { |recording| build_recording_node(recording, recordings_by_parent_id, visited) }
    )

    @recordings_count = recordings.size
  end

  def gem_views
    prefix = "#{RecordingStudioApi::Engine.root}/"

    @engine_views = Dir.glob(RecordingStudioApi::Engine.root.join("app/views/recording_studio_api/**/*.erb").to_s)
      .sort
      .map do |path|
        relative_path = path.delete_prefix(prefix)
        logical_path = relative_path.delete_prefix("app/views/").delete_suffix(".html.erb")
        segments = logical_path.split("/")

        {
          logical_path: logical_path,
          directory: segments[0...-1].join("/"),
          template: segments.last,
          partial: segments.last.start_with?("_"),
          relative_path: relative_path
        }
      end
  end

  def api_routes
    @api_catalog = RecordingStudioApi::Services::DocumentationCatalog.call
  end

  def openapi
    render json: RecordingStudioApi::Services::OpenapiDocument.call
  end

  def scalar
    @openapi_path = docs_openapi_path
  end

  def scalar_fullscreen
    @openapi_path = docs_openapi_path
    render :scalar_fullscreen, layout: false
  end

  def global_allow_list
  end

  def add_capability
  end

  def auth
  end

  def methods
  end

  private

  def normalize_recordable_type(recordable_type)
    type_name = recordable_type.is_a?(Class) ? recordable_type.name : recordable_type.to_s
    return if type_name.blank?

    {
      name: type_name,
      label: type_name.demodulize.underscore.humanize,
      recordings_count: RecordingStudio::Recording.where(recordable_type: type_name).count,
      recordables_count: count_recordables_for(type_name)
    }
  end

  def count_recordables_for(type_name)
    recordable_class = type_name.safe_constantize
    return 0 unless recordable_class&.<= ActiveRecord::Base
    return 0 unless recordable_class.table_exists?

    recordable_class.count
  rescue ActiveRecord::ActiveRecordError
    0
  end

  def build_recording_node(recording, recordings_by_parent_id, visited)
    return if visited.key?(recording.id)

    visited[recording.id] = true

    {
      label: recording_label(recording),
      children: recordings_by_parent_id.fetch(recording.id, []).map do |child_recording|
        build_recording_node(child_recording, recordings_by_parent_id, visited)
      end.compact
    }
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(recording.recordable)
    trashed_label = recording.trashed_at.present? ? " [trashed]" : ""

    "#{type_label}: #{identifier} (recording ##{recording.id})#{trashed_label}"
  end

  def recordable_identifier(recordable)
    return "Unknown recordable" if recordable.nil?

    %i[name title email label slug identifier].each do |attribute|
      next unless recordable.respond_to?(attribute)

      value = recordable.public_send(attribute)
      return value if value.present?
    end

    actor = recordable.actor if recordable.respond_to?(:actor)
    actor_email = actor.email if actor&.respond_to?(:email) && actor.email.present?

    if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
      return "#{recordable.role.to_s.humanize} for #{actor_email}"
    end

    return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

    return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
      recordable.minimum_role.present?

    "##{recordable.id}"
  end
end
