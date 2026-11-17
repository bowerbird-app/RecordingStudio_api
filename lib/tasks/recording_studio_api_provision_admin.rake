# frozen_string_literal: true

namespace :recording_studio_api do
  desc "Provision the Admin API recording under every admin root. Safe to run again."
  task provision_admin: :environment do
    actor = RecordingStudio.configuration.actor&.call
    declared_root_types = RecordingStudio.root_recordable_types.map(&:to_s)
    types = RecordingStudioApi::Engine.admin_root_recordable_type_names & declared_root_types
    table = RecordingStudio::Recording.arel_table
    roots = RecordingStudio::Recording.unscoped.kept
                                      .where(recordable_type: types)
                                      .where(table[:root_recording_id].eq(table[:id]))
                                      .order(:created_at, :id)

    roots.each do |root|
      RecordingStudioApi.configuration.each_api do |api|
        recording = RecordingStudioApi::Admin::ApiAuthorization.provision!(
          api: api.name,
          root_recording: root,
          actor: actor
        )
        puts "Provisioned #{api.name} on admin root #{root.id} as #{recording.id}"
      end
    end

    puts "No admin roots to provision" if roots.empty?
  end
end
