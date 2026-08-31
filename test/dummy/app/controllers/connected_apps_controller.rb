# frozen_string_literal: true

class ConnectedAppsController < ApplicationController
  helper_method :connected_app_status

  def index
    @authorizations = RecordingStudioApi::OauthAuthorization
      .includes(:oauth_client, :access_recording)
      .where(manager_actor: current_user)
      .order(created_at: :desc)
  end

  def destroy
    authorization = RecordingStudioApi::OauthAuthorization.find_by!(id: params[:id], manager_actor: current_user)
    RecordingStudioApi::Services::VoidOauthAuthorization.call(authorization: authorization)

    redirect_to connected_apps_path, notice: "App access removed."
  end

  private

  def connected_app_status(authorization)
    workspace = authorization.workspace_recording&.recordable
    workspace_name = workspace.respond_to?(:name) ? workspace.name : "workspace"
    permission = authorization.role.to_s.humanize
    return "#{permission} on #{workspace_name} · removed" if authorization.revoked_at.present?

    "#{permission} on #{workspace_name}"
  end
end
