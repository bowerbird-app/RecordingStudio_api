class RecordingTreePresenter
  def initialize(recordings:, include_trashed: false)
    @recordings = Array(recordings)
    @include_trashed = include_trashed
  end

  def nodes
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)
    recording_ids = recordings.each_with_object({}) { |recording, ids| ids[recording.id] = true }

    root_recordings = recordings.select do |recording|
      recording.parent_recording_id.nil? || !recording_ids.key?(recording.parent_recording_id)
    end

    visited = {}
    tree = root_recordings.filter_map do |recording|
      build_node(recording, recordings_by_parent_id, visited)
    end

    recordings.each do |recording|
      node = build_node(recording, recordings_by_parent_id, visited)
      tree << node if node
    end

    tree
  end

  private

  attr_reader :recordings, :include_trashed

  def build_node(recording, recordings_by_parent_id, visited)
    return if visited.key?(recording.id)

    visited[recording.id] = true

    {
      label: node_label(recording),
      children: recordings_by_parent_id.fetch(recording.id, []).map do |child_recording|
        build_node(child_recording, recordings_by_parent_id, visited)
      end.compact
    }
  end

  def node_label(recording)
    trashed_label = include_trashed && recording.trashed_at.present? ? " [trashed]" : ""
    "#{type_label_for(recording)}: #{identifier_for(safe_recordable(recording))}#{trashed_label}"
  end

  def type_label_for(recording)
    recording.recordable_type.to_s.demodulize.underscore.humanize
  end

  def identifier_for(recordable)
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

  def safe_recordable(recording)
    recording.recordable
  rescue NameError
    nil
  end
end
