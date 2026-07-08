class HomeController < ApplicationController
  def index
    if admin_root_current?
      render :admin_root, layout: "flat_pack_sidebar"
    else
      load_standard_root_data
      render :standard_root, layout: "flat_pack_sidebar"
    end
  end

  def workspace
    @recording_tree = recording_tree_for("Workspace")
  end

  def folder
    @recording_tree = recording_tree_for("Folder")
  end

  private

  def load_standard_root_data
    @workspace_access_recordings = access_recordings_for("Workspace")
    @folder_access_recordings = access_recordings_for("Folder")
    @workspace_api_keys_params = workspace_api_keys_params
    @folder_api_keys_params = folder_api_keys_params
    @workspace_api_keys_path = api_keys_admin_screen_path(@workspace_api_keys_params)
    @folder_api_keys_path = api_keys_admin_screen_path(@folder_api_keys_params)
    @api_admin_path = api_admin_path
  end

  def api_admin_path
    ["/api", { anchor_url: root_path }.to_query].join("?")
  end

  def api_keys_admin_screen_path(params)
    query = params.compact.to_query
    mount_path = "/api"
    ["#{mount_path}/screens/api_keys", query.presence].compact.join("?")
  end

  def workspace_api_keys_params
    root_recording = current_root_for_type("Workspace") || root_recordings.find { |recording| recording.recordable_type == "Workspace" }
    return default_api_keys_params if root_recording.nil?

    default_api_keys_params.merge(
      root_recording_id: root_recording.id,
      parent_recording_id: root_recording.id,
      include_children: "1"
    )
  end

  def folder_api_keys_params
    current_folder_root = current_root_for_type("Folder")
    if current_folder_root.present?
      return default_api_keys_params.merge(
        root_recording_id: current_folder_root.id,
        parent_recording_id: current_folder_root.id,
        include_children: "1"
      )
    end

    folder_parent_recording = recordings.find do |recording|
      recording.recordable_type == "Folder" && recording.parent_recording_id.present?
    end

    folder_scope = if folder_parent_recording.present?
                     {
                       root_recording: folder_parent_recording.root_recording || folder_parent_recording,
                       parent_recording: folder_parent_recording
                     }
                   end

    if folder_scope.nil?
      folder_root = root_recordings.find { |recording| recording.recordable_type == "Folder" }
      return default_api_keys_params if folder_root.nil?

      folder_scope = {
        root_recording: folder_root,
        parent_recording: folder_root
      }
    end

    default_api_keys_params.merge(
      root_recording_id: folder_scope.fetch(:root_recording).id,
      parent_recording_id: folder_scope.fetch(:parent_recording).id,
      include_children: "1"
    )
  end

  def default_api_keys_params
    {
      close_url: root_path,
      anchor_url: root_path
    }
  end

  def current_root_for_type(recordable_type)
    current_root = current_root_recording if respond_to?(:current_root_recording, true)
    current_root if current_root&.recordable_type == recordable_type
  end

  def recordings
    @recordings ||= RecordingStudio::Recording.reorder(:created_at, :id).to_a
  end

  def recordings_by_parent_id
    @recordings_by_parent_id ||= recordings.group_by(&:parent_recording_id)
  end

  def root_recordings
    recordings_by_parent_id.fetch(nil, [])
  end

  def access_recordings_for(root_recordable_type)
    root_recordings.select do |recording|
      recording.recordable_type == root_recordable_type
    end.flat_map do |root_recording|
      child_access_recordings(root_recording, recordings_by_parent_id).map do |access_recording|
        {
          root: recording_label(root_recording),
          access_recording: recording_label(access_recording)
        }
      end
    end
  end

  def child_access_recordings(root_recording, recordings_by_parent_id)
    stack = Array(recordings_by_parent_id[root_recording.id]).dup
    access_recordings = []

    until stack.empty?
      recording = stack.shift
      access_recordings << recording if recording.recordable_type == "RecordingStudio::Access"
      stack.concat(Array(recordings_by_parent_id[recording.id]))
    end

    access_recordings
  end

  def recording_tree_for(root_recordable_type)
    root_recordings.select do |recording|
      recording.recordable_type == root_recordable_type
    end.map do |recording|
      build_recording_node(recording, recordings_by_parent_id)
    end
  end

  def build_recording_node(recording, recordings_by_parent_id)
    {
      label: recording_label(recording),
      children: recordings_by_parent_id.fetch(recording.id, []).map do |child_recording|
        build_recording_node(child_recording, recordings_by_parent_id)
      end
    }
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(safe_recordable(recording))

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

    return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
      recordable.minimum_role.present?

    "##{recordable.id}"
  end

  def safe_recordable(recording)
    recording.recordable
  rescue NameError
    nil
  end
end
