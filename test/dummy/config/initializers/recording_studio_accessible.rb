# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [ "User", "RecordingStudioApi::ApiClient" ]

  config.admin_root_resolver = lambda do
    admin_root = AdminRoot.find_by(name: "Admin")
    next unless admin_root

    RecordingStudio.root_recording_for(admin_root)
  end

  config.avatar_resolver = lambda do |access_holder|
    next unless access_holder.is_a?(User)

    email = access_holder.email.to_s.strip
    next if email.blank?

    {
      name: email.split("@").first.tr("._-", " ").squish.titleize,
      alt: email
    }
  end
end
