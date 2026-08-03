# frozen_string_literal: true

class DocsController < ApplicationController
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
                  { label: "API access token", children: [] }
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
    recordings = RecordingStudio::Recording.unscoped.reorder(:created_at, :id).to_a
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
    @api_version = selected_api_version
    @api_catalog = RecordingStudioApi::Services::DocumentationCatalog.call(version: @api_version)
  end

  def openapi
    render json: RecordingStudioApi::Services::OpenapiDocument.call(version: selected_api_version)
  end

  def add_capability
  end

  def auth
  end

  def methods
  end

  def versions
  end

  private

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

  def selected_api_version
    @selected_api_version ||= RecordingStudioApi.resolve_api_version(params[:version])
  end

end
