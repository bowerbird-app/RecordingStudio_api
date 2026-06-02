# frozen_string_literal: true

RecordingStudio.configure do |config|
  # Host app recordables; addon engines append their own internal recordables.
  config.recordable_types = [ "Workspace", "Folder", "Page" ]
  config.require_recordable_declarations = true

  # Actor resolver for events when no actor is explicitly supplied
  config.actor = -> { Current.actor }

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Removed in RecordingStudio v1.2.0; keep compatibility with older tags.
  config.include_children = false if config.respond_to?(:include_children=)

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup

  # Built-in capabilities remain disabled until you opt a recordable type into
  # them by including the relevant RecordingStudio capability module.
  config.enable_capability(:movable, on: "Folder")
  config.enable_capability(:trashable, on: "Page")
end

RecordingStudio::Labels.register_formatter(
  "RecordingStudio::Access",
  name: lambda do |access|
    actor = access.respond_to?(:actor) ? access.actor : nil
    actor_email = actor&.respond_to?(:email) ? actor.email.to_s.squish : ""
    role_label = access.respond_to?(:role) ? access.role.to_s.humanize : ""

    if role_label.present? && actor_email.present?
      "#{role_label} for #{actor_email}"
    elsif role_label.present?
      role_label
    else
      nil
    end
  end
)
