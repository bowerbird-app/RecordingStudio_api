class HomeController < ApplicationController
  def index
    @workspace_access_recordings = access_recordings_for("Workspace")
    @folder_access_recordings = access_recordings_for("Folder")
  end

  def workspace
    @recording_tree = recording_tree_for("Workspace")
  end

  def folder
    @recording_tree = recording_tree_for("Folder")
  end

  private

  def access_recordings_for(root_recordable_type)
    recordings = RecordingStudio::Recording.includes(:recordable).reorder(:created_at, :id).to_a
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)

    recordings_by_parent_id.fetch(nil, []).select do |recording|
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
    recordings = RecordingStudio::Recording.includes(:recordable).reorder(:created_at, :id).to_a
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)

    recordings_by_parent_id.fetch(nil, []).select do |recording|
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

    return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
      recordable.minimum_role.present?

    "##{recordable.id}"
  end
end
