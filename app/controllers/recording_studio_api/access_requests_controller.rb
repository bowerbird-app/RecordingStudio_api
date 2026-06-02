# frozen_string_literal: true

module RecordingStudioApi
  class AccessRequestsController < ApplicationController
    before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!, true) }
    before_action :authorize_access_management_edit_for_new_request!, only: %i[new create]
    before_action :load_form_state, only: %i[new create]
    before_action :load_api_access_list, only: :index
    before_action :load_api_access_detail, only: %i[show edit update]
    before_action :authorize_access_management_edit_for_loaded_client!, only: %i[edit update]

    def index
    end

    def show
    end

    def edit
      load_edit_form_state
    end

    def new
    end

    def create
      expires_at = parsed_expires_at
      return render_invalid_form if @errors.any?

      result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
        root_recording: selected_root_recording,
        actor: current_request_actor,
        role: @form_values.fetch(:role),
        api_client_name: @form_values.fetch(:api_client_name),
        expires_at: expires_at
      )

      if result.failure?
        @errors << result.error
        render_invalid_form
      else
        @payload = result.value
        render :create, status: :created
      end
    end

    def update
      load_edit_form_state
      expires_at = parsed_edit_expires_at
      @errors << "Name can't be blank" if @form_values.fetch(:api_client_name).blank?
      @errors << "Role is invalid" unless role_options.any? { |(_label, value)| value == @form_values.fetch(:role) }
      return render :edit, status: :unprocessable_entity if @errors.any?

      return redirect_to(api_client_path(@api_client, page_nav_close_param), notice: "API access updated.") if persist_access_updates(expires_at)

      @errors << "The API client could not be updated"
      render :edit, status: :unprocessable_entity
    end

    private

    def load_form_state
      @errors = []
      @root_type = normalized_root_type
      @root_recordings = available_root_recordings(@root_type)
      @role_options = role_options
      root_recording = @root_recordings.first
      @form_values = {
        root_type: @root_type,
        root_recording_id: root_recording&.id,
        role: api_client_params[:role].presence || "admin",
        api_client_name: api_client_params[:api_client_name].presence || default_api_client_name,
        expires_at: api_client_params[:expires_at].to_s
      }
    end

    def api_client_params
      params.fetch(:api_client, params.fetch(:access_request, {})).permit(:root_type, :role, :api_client_name, :expires_at)
    end

    def api_client_update_params
      params.fetch(:api_client, params.fetch(:access_request, {})).permit(:role, :api_client_name, :expires_at)
    end

    def normalized_root_type
      requested_root_type = api_client_params[:root_type].presence || params[:root_type].presence
      allowed_root_types.include?(requested_root_type) ? requested_root_type : allowed_root_types.first
    end

    def allowed_root_types
      @allowed_root_types ||= RecordingStudioApi.api_recordable_types & %w[Workspace Folder]
    end

    def available_root_recordings(root_type)
      return [] if root_type.blank?

      manageable_root_recordings.select { |recording| recording.recordable_type == root_type }
    end

    def role_options
      %w[view edit admin].map { |value| [value.humanize, value] }
    end

    def default_api_client_name
      "My api access"
    end

    def selected_root_recording
      @selected_root_recording ||= @root_recordings.first
    end

    def current_request_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def authorize_access_management_edit_for_new_request!
      return if access_management_policy.can_manage_root_recording?(selected_root_recording_for_request)

      raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
    end

    def authorize_access_management_edit_for_loaded_client!
      root_recording = @api_client&.access_recording&.root_recording
      return if access_management_policy.can_manage_root_recording?(root_recording)

      raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
    end

    def selected_root_recording_for_request
      root_type = normalized_root_type
      return nil if root_type.blank?

      available_root_recordings(root_type).first
    end

    def access_management_policy
      @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_request_actor)
    end

    def visible_access_recordings
      access_management_policy.visible_access_recordings
    end

    def visible_root_recordings
      access_management_policy.visible_root_recordings
    end

    def manageable_root_recordings
      access_management_policy.manageable_root_recordings
    end

    def parsed_expires_at
      raw_value = @form_values.fetch(:expires_at)
      return nil if raw_value.blank?

      parsed_value = Time.zone.parse(raw_value)
      return parsed_value if parsed_value.present?

      @errors << "Expiry must be a valid date and time"
      nil
    rescue ArgumentError
      @errors << "Expiry must be a valid date and time"
      nil
    end

    def parsed_edit_expires_at
      raw_value = @form_values.fetch(:expires_at)
      return nil if raw_value.blank?

      parsed_value = Time.zone.parse(raw_value)
      return parsed_value if parsed_value.present?

      @errors << "Expiry must be a valid date and time"
      nil
    rescue ArgumentError
      @errors << "Expiry must be a valid date and time"
      nil
    end

    def render_invalid_form
      @errors << "A #{human_root_type.downcase} recording must be selected" if selected_root_recording.nil?
      render :new, status: :unprocessable_entity
    end

    def human_root_type
      @root_type.to_s.demodulize.underscore.humanize
    end
    helper_method :human_root_type, :allowed_root_types, :recording_label, :credential_status_label

    def load_api_access_list
      root_type_filter = params[:root_type].presence
      scoped_recording_filter = params[:recording_id].presence || params[:root_recording_id].presence
      scoped_recording = scoped_access_list_recording(scoped_recording_filter)
      scoped_recording_ids = scoped_recording_subtree_ids(scoped_recording)
      visible_access_recording_ids = visible_access_recordings.map(&:id)
      @can_manage_access_requests = visible_root_recordings.any? do |recording|
        access_management_policy.can_manage_root_recording?(recording)
      end

      api_clients = RecordingStudioApi::ApiClient
        .includes(:credentials, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .where(access_recording_id: visible_access_recording_ids)
        .reorder(:created_at, :id)
        .to_a

      @api_access_rows = api_clients.filter_map do |api_client|
        access_recording = api_client.access_recording
        next if access_recording.nil?

        root_recording = access_recording.root_recording
        next if root_recording.nil?
        next if root_type_filter.present? && root_recording.recordable_type != root_type_filter
        next if scoped_recording_ids.present? && !scoped_recording_ids.include?(access_recording.id)

        access_point_recording = access_point_recording_for(access_recording)

        latest_credential = api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }

        {
          id: api_client.id,
          root_recording: root_recording,
          access_point_recording: access_point_recording,
          name: api_client.name,
          access_point: access_point_label(access_point_recording),
          role: access_recording.recordable&.try(:role).to_s.humanize.presence || "Unknown",
          credentials_count: api_client.credentials.size,
          expires: credential_expires_label(latest_credential),
          latest_credential_status: credential_status_label(latest_credential)
        }
      end

      @access_list_subtitle = resolve_access_list_subtitle(
        rows: @api_access_rows,
        scoped_recording: scoped_recording,
        root_type_filter: root_type_filter
      )
    end

    def resolve_access_list_subtitle(rows:, scoped_recording:, root_type_filter:)
      if scoped_recording.present?
        return subtitle_for_scoped_recording(scoped_recording, rows) if scoped_recording.present?
      end

      unique_root_recordings = rows.filter_map { |row| row[:root_recording] }.uniq { |recording| recording.id }
      return "API access below #{humanized_recording_type(unique_root_recordings.first)}." if unique_root_recordings.one?

      return "API access below #{root_type_filter.to_s.demodulize.underscore.humanize}." if root_type_filter.present?

      "API access below all roots."
    end

    def scoped_access_list_recording(recording_id)
      return nil if recording_id.blank?

      RecordingStudio::Recording.includes(:recordable).find_by(id: recording_id)
    end

    def scoped_recording_subtree_ids(recording)
      return nil if recording.nil?

      recording.subtree_recordings(include_self: true).pluck(:id)
    end

    def subtitle_for_scoped_recording(recording, rows)
      access_points = rows.filter_map { |row| row[:access_point_recording] }.uniq { |access_point| access_point.id }
      return "API access below #{recording_label(access_points.first)}." if access_points.one? && access_points.first.parent_recording_id.present?

      "API access below #{recording_label(recording)}."
    end

    def humanized_recording_type(recording)
      recording.recordable_type.to_s.demodulize.underscore.humanize
    end

    def access_point_recording_for(access_recording)
      parent_recording = access_recording.parent_recording

      return access_recording.root_recording if parent_recording.nil?

      parent_recording
    end

    def access_point_label(recording)
      return "Unknown" if recording.nil?

      if recording.parent_recording_id.nil?
        return recording.recordable_type.to_s.demodulize.underscore.humanize
      end

      recordable_identifier(recording.recordable)
    end

    def load_api_access_detail
      @api_client = RecordingStudioApi::ApiClient
        .includes(credentials: :access_tokens, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .where(access_recording_id: visible_access_recordings.map(&:id))
        .find(params[:id])

      @access_recording = @api_client.access_recording
      @root_recording = @access_recording&.root_recording
      @can_manage_access_request = access_management_policy.can_manage_root_recording?(@root_recording)
      @latest_credential = @api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }
      load_api_token_activity
      load_oauth_activity
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def load_api_token_activity
      all_tokens = @api_client.credentials.flat_map(&:access_tokens)
      active_tokens = all_tokens.select do |token|
        token.revoked_at.nil? && token.expires_at.present? && token.expires_at.future?
      end

      @api_token_activity_rows = [
        { field: "Issued tokens", value: all_tokens.count.to_s, actions: "" },
        { field: "Active tokens", value: active_tokens.count.to_s, actions: "" },
        { field: "Revoked tokens", value: all_tokens.count { |token| token.revoked_at.present? }.to_s, actions: "" },
        {
          field: "Next expiry",
          value: format_activity_timestamp(active_tokens.filter_map(&:expires_at).min, fallback: "No active tokens"),
          actions: ""
        },
        {
          field: "Last used",
          value: format_activity_timestamp(all_tokens.filter_map(&:last_used_at).max),
          actions: ""
        }
      ]
    end

    def load_oauth_activity
      if @access_recording.nil?
        @oauth_activity_rows = [
          { field: "Active grant sessions", value: "Unavailable", actions: "" },
          { field: "Last session use", value: "Unavailable", actions: "" },
          { field: "Active OAuth access tokens", value: "Unavailable", actions: "" },
          { field: "Active refresh tokens", value: "Unavailable", actions: "" },
          { field: "Auth codes consumed (7d)", value: "Unavailable", actions: "" }
        ]
        return
      end

      active_sessions = RecordingStudioApi::OauthGrantSession.where(access_recording_id: @access_recording.id, revoked_at: nil)
      active_session_ids = active_sessions.pluck(:id)
      now = Time.current

      active_oauth_access_token_count = if active_session_ids.empty?
                                          0
                                        else
                                          RecordingStudioApi::OauthSessionAccessToken.where(oauth_grant_session_id: active_session_ids, revoked_at: nil)
                                                                                    .where(RecordingStudioApi::OauthSessionAccessToken.arel_table[:expires_at].gt(now))
                                                                                    .count
                                        end

      active_refresh_token_count = if active_session_ids.empty?
                                     0
                                   else
                                     RecordingStudioApi::OauthRefreshToken.where(
                                       oauth_grant_session_id: active_session_ids,
                                       revoked_at: nil,
                                       consumed_at: nil
                                     ).where(RecordingStudioApi::OauthRefreshToken.arel_table[:expires_at].gt(now)).count
                                   end

      consumed_code_count = RecordingStudioApi::OauthAuthorizationCode.where(access_recording_id: @access_recording.id)
                                                                       .where.not(consumed_at: nil)
                                                                       .where(RecordingStudioApi::OauthAuthorizationCode.arel_table[:consumed_at].gteq(7.days.ago))
                                                                       .count

      @oauth_activity_rows = [
        {
          field: "Active grant sessions",
          value: active_sessions.count.to_s,
          actions: view_context.link_to("View sessions", oauth_grant_sessions_path(access_recording_id: @access_recording.id), class: "text-(--surface-content-color) underline decoration-(--surface-border-color) underline-offset-2 hover:decoration-(--surface-content-color)")
        },
        {
          field: "Last session use",
          value: format_activity_timestamp(active_sessions.maximum(:last_used_at)),
          actions: ""
        },
        {
          field: "Active OAuth access tokens",
          value: active_oauth_access_token_count.to_s,
          actions: ""
        },
        {
          field: "Active refresh tokens",
          value: active_refresh_token_count.to_s,
          actions: ""
        },
        {
          field: "Auth codes consumed (7d)",
          value: consumed_code_count.to_s,
          actions: ""
        }
      ]
    end

    def format_activity_timestamp(value, fallback: "Never")
      return fallback if value.blank?

      human_readable_timestamp(value)
    end

    def load_edit_form_state
      @errors = []
      @role_options = role_options
      @form_values = {
        role: api_client_update_params[:role].presence || resolved_edit_role_value,
        api_client_name: api_client_update_params[:api_client_name].presence || @api_client.name,
        expires_at: resolved_edit_expires_at_value
      }
    end

    def resolved_edit_role_value
      @access_recording&.recordable&.try(:role).to_s.presence || "admin"
    end

    def resolved_edit_expires_at_value
      return api_client_update_params[:expires_at].to_s if api_client_update_params.key?(:expires_at)

      datetime_local_value(@latest_credential&.expires_at)
    end

    def datetime_local_value(value)
      return "" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%dT%H:%M")
    end

    def persist_access_updates(expires_at)
      now = Time.current
      access_record = @access_recording&.recordable

      ActiveRecord::Base.transaction do
        if access_record.respond_to?(:id) && access_record.respond_to?(:has_attribute?) && access_record.has_attribute?(:role)
          update_attributes = { role: @form_values.fetch(:role) }
          update_attributes[:updated_at] = now if access_record.has_attribute?(:updated_at)

          updated_access_records = access_record.class.where(id: access_record.id).update_all(update_attributes)

          raise ActiveRecord::ActiveRecordError, "Access update failed" unless updated_access_records == 1
        end

        updated_clients = RecordingStudioApi::ApiClient.where(id: @api_client.id).update_all(
          name: @form_values.fetch(:api_client_name),
          updated_at: now
        )

        raise ActiveRecord::ActiveRecordError, "API client update failed" unless updated_clients == 1

        if @latest_credential.present?
          updated_credentials = RecordingStudioApi::ApiCredential.where(id: @latest_credential.id).update_all(
            expires_at: expires_at,
            updated_at: now
          )

          raise ActiveRecord::ActiveRecordError, "Credential update failed" unless updated_credentials == 1
        end
      end

      true
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def credential_status_label(credential)
      return "No credentials" if credential.nil?
      return "Revoked" if credential.revoked_at.present?
      return "Expired" if credential.expires_at.present? && credential.expires_at.past?

      "Active"
    end

    def credential_expires_label(credential)
      return "No credentials" if credential.nil?
      return "Never" if credential.expires_at.blank?

      human_readable_timestamp(credential.expires_at)
    end

    def human_readable_timestamp(value)
      timestamp = value.in_time_zone
      "#{timestamp.strftime("%B %-d, %Y at %-l:%M %p")} #{timestamp.strftime("%Z")}".strip
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
      actor_email = actor.email if actor.respond_to?(:email) && actor.email.present?

      if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
        return "#{recordable.role.to_s.humanize} for #{actor_email}"
      end

      return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

      "Unknown recordable"
    end
  end
end