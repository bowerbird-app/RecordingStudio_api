# frozen_string_literal: true

class DocsController < ApplicationController
  SCALAR_TEST_TOKEN_SESSION_KEY = "scalar_test_token"

  def install
  end

  def configuration
    render :config
  end

  def api_hierarchy
    @api_hierarchy = [
      {
        label: "Folder",
        children: [
          {
            label: "Access",
            children: [
              {
                label: "API client",
                children: [
                  { label: "API credential", children: [] },
                  { label: "API access token", children: [] },
                  {
                    label: "OAuth grant session",
                    children: [
                      { label: "OAuth authorization code", children: [] },
                      { label: "OAuth session access token", children: [] },
                      { label: "OAuth refresh token", children: [] }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  end

  def recordable_types
    @recordable_types = RecordingStudio::Recording.unscoped.reorder(nil).group(:recordable_type).count.sort_by do |recordable_type, _count|
      recordable_type.to_s
    end.filter_map do |recordable_type, recordings_count|
      normalize_recordable_type(recordable_type, recordings_count: recordings_count)
    end
  end

  def recordings_tree
    recordings = RecordingStudio::Recording.unscoped.includes(:recordable).reorder(:created_at, :id).to_a
    @recording_tree = RecordingTreePresenter.new(recordings: recordings, include_trashed: true).nodes

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
    load_scalar_test_auth
  end

  def scalar_fullscreen
    @openapi_path = docs_openapi_path
    render :scalar_fullscreen, layout: false
  end

  def add_capability
  end

  def auth
  end

  def mobile_auth
  end

  def methods
  end

  private

  def load_scalar_test_auth
    @scalar_test_token = session[SCALAR_TEST_TOKEN_SESSION_KEY]
    @scalar_test_notice = session.delete("scalar_test_token_notice")
    @scalar_test_error = session.delete("scalar_test_token_error")
    @scalar_test_access_points = scalar_test_access_points
    @scalar_test_roles = %w[view edit admin]
    @scalar_test_selected_access_point_id = @scalar_test_token&.fetch("scope_recording_id", nil) || @scalar_test_access_points.first&.fetch(:id)
    @scalar_test_context_rows = scalar_test_context_rows
    @scalar_test_sample_rows = scalar_test_sample_rows
    @scalar_test_auth_open = @scalar_test_token.present? || @scalar_test_notice.present? || @scalar_test_error.present?
  end

  def scalar_test_access_points
    manageable_roots.flat_map do |root_recording|
      root_recording.subtree_recordings(include_self: true)
        .includes(:recordable)
        .where(recordable_type: scalar_test_access_point_types, trashed_at: nil)
        .reorder(:created_at, :id)
        .map do |recording|
          {
            id: recording.id,
            label: recording_label(recording),
            root_label: recording_label(root_recording)
          }
        end
    end.uniq { |entry| entry.fetch(:id) }
  end

  def scalar_test_access_point_types
    RecordingStudioApi.api_recordable_types - [ "RecordingStudio::Access" ]
  end

  def manageable_roots
    @manageable_roots ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_user).manageable_root_recordings
  end

  def scalar_test_context_rows
    return [] if @scalar_test_token.blank?

    [
      { field: "Bearer token", value: "Bearer #{@scalar_test_token.fetch("access_token")}" },
      { field: "Role", value: @scalar_test_token.fetch("role").humanize },
      { field: "Scope", value: @scalar_test_token.fetch("scope_label") },
      { field: "Root", value: @scalar_test_token.fetch("root_label") },
      { field: "Client ID", value: @scalar_test_token.fetch("client_id") },
      { field: "Access recording ID", value: @scalar_test_token.fetch("access_recording_id") },
      { field: "Expires", value: format_scalar_test_timestamp(@scalar_test_token["expires_at"]) }
    ]
  end

  def scalar_test_sample_rows
    return [] if @scalar_test_token.blank?

    selected_recording = selected_scalar_test_recording
    access_recording = RecordingStudio::Recording.unscoped.includes(:recordable).find_by(id: @scalar_test_token["access_recording_id"])
    return [] if selected_recording.nil? || access_recording.nil?

    RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: selected_recording,
      access_recording: access_recording,
      include_trashed: true
    ).relation
      .includes(:recordable)
      .where(recordable_type: RecordingStudioApi.api_recordable_types)
      .reorder(:created_at, :id)
      .limit(8)
      .map do |recording|
        {
          resource: RecordingStudioApi.resource_name_for(recording.recordable_type),
          label: recording_label(recording),
          id: recording.id
        }
      end
  end

  def selected_scalar_test_recording
    recording_id = @scalar_test_token&.fetch("scope_recording_id", nil) || @scalar_test_selected_access_point_id
    return if recording_id.blank?

    RecordingStudio::Recording.unscoped.includes(:recordable).find_by(id: recording_id)
  end

  def format_scalar_test_timestamp(value)
    return "Unavailable" if value.blank?

    timestamp = Time.zone.parse(value.to_s)
    "#{timestamp.strftime("%B %-d, %Y at %-l:%M %p")} #{timestamp.strftime("%Z")}".strip
  rescue ArgumentError
    "Unavailable"
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(recording.recordable)

    "#{type_label}: #{identifier}"
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

    "##{recordable.id}"
  end

  def normalize_recordable_type(recordable_type, recordings_count: nil)
    type_name = recordable_type.is_a?(Class) ? recordable_type.name : recordable_type.to_s
    return if type_name.blank?

    {
      name: type_name,
      label: RecordingStudio.recordable_type_label(type_name),
      recordings_count: recordings_count || RecordingStudio::Recording.where(recordable_type: type_name).count,
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
end
