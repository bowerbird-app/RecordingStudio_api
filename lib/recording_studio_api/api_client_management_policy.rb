# frozen_string_literal: true

module RecordingStudioApi
  class ApiClientManagementPolicy
    def initialize(actor:)
      @actor = actor
    end

    def view?(api_client)
      authorized?(api_client, role: RecordingStudioApi.configuration.access_management_view_role)
    end

    def manage?(api_client)
      authorized?(api_client, role: RecordingStudioApi.configuration.access_management_edit_role)
    end

    private

    attr_reader :actor

    def authorized?(api_client, role:)
      return false if actor.nil? || api_client.nil?
      return false unless RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: access_point_recording(api_client),
        role: role
      )

      authorized_for_api_admin?(api_client, role: role)
    end

    def authorized_for_api_admin?(api_client, role:)
      api = RecordingStudioApi.configuration.fetch_api(api_client.api_key)
      return true unless api.api_management_authorization_required

      root_recording = api_client.root_recording
      return false if root_recording.nil?

      RecordingStudioApi::Admin::ApiAuthorization.authorized?(
        actor: actor,
        api: api,
        root_recording: root_recording,
        role: role,
        create: false
      )
    rescue RecordingStudioApi::ConfigurationError
      false
    end

    def access_point_recording(api_client)
      access_recording = api_client.access_recording
      access_recording&.parent_recording || access_recording&.root_recording
    end
  end
end