# frozen_string_literal: true

class AdminRoot < ApplicationRecord
  include RecordingStudio::Recordable
  include RecordingStudioAdmin::AllowsAdminSections

  recording_studio_recordable label: "Admin", root: true

  recording_studio_admin_sections do
    section :admin_api
    section :admin_operations_api
  end
end
