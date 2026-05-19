# frozen_string_literal: true

module RecordingStudioApi
  class AccessRequestsController < ApplicationController
    before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!, true) }
    before_action :load_form_state, only: %i[new create]
    before_action :load_api_access_list, only: :index
    before_action :load_api_access_detail, only: %i[show edit update]

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

      return redirect_to(access_request_path(@api_client), notice: "API access updated.") if persist_access_updates(expires_at)

      @errors << "The request could not be updated"
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
        role: access_request_params[:role].presence || "admin",
        api_client_name: access_request_params[:api_client_name].presence || default_api_client_name,
        expires_at: access_request_params[:expires_at].to_s
      }
    end

    def access_request_params
      params.fetch(:access_request, {}).permit(:root_type, :role, :api_client_name, :expires_at)
    end

    def access_request_update_params
      params.fetch(:access_request, {}).permit(:role, :api_client_name, :expires_at)
    end

    def normalized_root_type
      requested_root_type = access_request_params[:root_type].presence || params[:root_type].presence
      allowed_root_types.include?(requested_root_type) ? requested_root_type : allowed_root_types.first
    end

    def allowed_root_types
      @allowed_root_types ||= RecordingStudioApi.api_recordable_types & %w[Workspace Folder]
    end

    def available_root_recordings(root_type)
      return [] if root_type.blank?

      RecordingStudio::Recording
        .includes(:recordable)
        .where(parent_recording_id: nil, recordable_type: root_type)
        .reorder(:created_at, :id)
        .to_a
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
      root_recording_id_filter = params[:root_recording_id].presence

      api_clients = RecordingStudioApi::ApiClient
        .includes(:credentials, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .reorder(:created_at, :id)
        .to_a

      @api_access_rows = api_clients.filter_map do |api_client|
        access_recording = api_client.access_recording
        next if access_recording.nil?

        root_recording = access_recording.root_recording
        next if root_recording.nil?
        next if root_type_filter.present? && root_recording.recordable_type != root_type_filter
        next if root_recording_id_filter.present? && root_recording.id.to_s != root_recording_id_filter

        access_point_recording = access_point_recording_for(access_recording)

        latest_credential = api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }

        {
          id: api_client.id,
          root_recording: root_recording,
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
        root_recording_id_filter: root_recording_id_filter,
        root_type_filter: root_type_filter
      )
    end

    def resolve_access_list_subtitle(rows:, root_recording_id_filter:, root_type_filter:)
      if root_recording_id_filter.present?
        scoped_recording = RecordingStudio::Recording.includes(:recordable).find_by(id: root_recording_id_filter)
        return subtitle_for_scoped_recording(scoped_recording) if scoped_recording.present?
      end

      unique_root_recordings = rows.filter_map { |row| row[:root_recording] }.uniq { |recording| recording.id }
      return subtitle_for_scoped_recording(unique_root_recordings.first) if unique_root_recordings.one?

      return "Showing API access for #{root_type_filter.to_s.demodulize.underscore.humanize}." if root_type_filter.present?

      "Review provisioned API access."
    end

    def subtitle_for_scoped_recording(recording)
      "Showing API access for #{recordable_identifier(recording.recordable)}."
    end

    def access_point_recording_for(access_recording)
      parent_recording = access_recording.parent_recording
      return access_recording.root_recording if parent_recording.nil?

      if parent_recording.recordable_type == "RecordingStudio::AccessBoundary"
        return parent_recording.parent_recording || access_recording.root_recording
      end

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
        .includes(:credentials, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .find(params[:id])

      @access_recording = @api_client.access_recording
      @root_recording = @access_recording&.root_recording
      @latest_credential = @api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def load_edit_form_state
      @errors = []
      @role_options = role_options
      @form_values = {
        role: access_request_update_params[:role].presence || resolved_edit_role_value,
        api_client_name: access_request_update_params[:api_client_name].presence || @api_client.name,
        expires_at: resolved_edit_expires_at_value
      }
    end

    def resolved_edit_role_value
      @access_recording&.recordable&.try(:role).to_s.presence || "admin"
    end

    def resolved_edit_expires_at_value
      return access_request_update_params[:expires_at].to_s if access_request_update_params.key?(:expires_at)

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

      credential.expires_at.in_time_zone.strftime("%Y-%m-%d %H:%M")
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

      return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
        recordable.minimum_role.present?

      "##{recordable.id}"
    end
  end
end