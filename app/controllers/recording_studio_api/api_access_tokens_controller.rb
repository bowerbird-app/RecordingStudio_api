# frozen_string_literal: true

module RecordingStudioApi
  class ApiAccessTokensController < ApplicationController
    before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!, true) }
    before_action :load_api_client
    before_action :authorize_access_management_edit_for_loaded_client!, only: :revoke

    def index
      load_api_client_tokens
    end

    def revoke
      token = scoped_access_tokens.find_by(id: params[:id])
      return head :not_found if token.nil?

      token.revoke! if token.revoked_at.nil?

      redirect_to api_client_api_access_tokens_path(@api_client), notice: "Token revoked."
    end

    private

    def load_api_client
      @api_client = RecordingStudioApi::ApiClient
        .includes(credentials: :access_tokens, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .where(access_recording_id: visible_access_recordings.map(&:id))
        .find(params[:api_client_id] || params[:access_request_id])
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def load_api_client_tokens
      @token_rows = scoped_access_tokens.order(created_at: :desc).map do |token|
        {
          id: token.id,
          prefix: obfuscated_token_prefix(token.token_prefix),
          status: api_access_token_status(token),
          expires_at: format_activity_timestamp(token.expires_at, fallback: "Never"),
          last_used_at: format_activity_timestamp(token.last_used_at),
          issued_at: format_activity_timestamp(token.created_at),
          actions: revoke_action_for(token)
        }
      end
    end

    def scoped_access_tokens
      RecordingStudioApi::ApiAccessToken
        .joins(:credential)
        .where(recording_studio_api_api_credentials: { api_client_id: @api_client.id })
    end

    def revoke_action_for(token)
      return "" unless token.revoked_at.nil?
      return "" unless can_manage_access_request?

      view_context.button_to(
        "Revoke",
        revoke_api_client_api_access_token_path(@api_client, token),
        method: :post,
        data: { turbo_confirm: "Revoke this token?" },
        class: "inline-flex items-center justify-center gap-2 rounded-[var(--button-border-radius)] font-medium cursor-pointer transition-colors duration-base focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--button-focus-ring-color)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--button-focus-ring-offset-color)] px-[var(--button-padding-x-md)] py-[var(--button-padding-y-md)] text-sm bg-[var(--surface-background-color)] text-[var(--surface-content-color)] border border-[var(--surface-border-color)]"
      )
    end

    def can_manage_access_request?
      root_recording = @api_client&.access_recording&.root_recording
      access_management_policy.can_manage_root_recording?(root_recording)
    end

    def authorize_access_management_edit_for_loaded_client!
      return if can_manage_access_request?

      raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
    end

    def access_management_policy
      @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_request_actor)
    end

    def current_request_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def visible_access_recordings
      access_management_policy.visible_access_recordings
    end

    def obfuscated_token_prefix(prefix)
      token_prefix = prefix.to_s
      return "Hidden" if token_prefix.blank?

      visible_chars = 4
      return "*" * token_prefix.length if token_prefix.length <= visible_chars

      "#{"*" * (token_prefix.length - visible_chars)}#{token_prefix.last(visible_chars)}"
    end

    def api_access_token_status(token)
      return "Revoked" if token.revoked_at.present?
      return "Expired" if token.expires_at.present? && token.expires_at.past?

      "Active"
    end

    def format_activity_timestamp(value, fallback: "Never")
      return fallback if value.blank?

      timestamp = value.in_time_zone
      "#{timestamp.strftime("%B %-d, %Y at %-l:%M %p")} #{timestamp.strftime("%Z")}".strip
    end
  end
end
