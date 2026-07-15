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
    @api_admin_path = api_admin_path
  end

  def api_admin_path
    ["/api", { anchor_url: root_path }.to_query].join("?")
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
