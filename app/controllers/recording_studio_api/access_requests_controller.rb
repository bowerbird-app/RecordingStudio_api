# frozen_string_literal: true

module RecordingStudioApi
  class AccessRequestsController < ApplicationController
    include RecordingStudioApi::AccessRequests::PolicyHelpers
    include RecordingStudioApi::AccessRequests::FormState
    include RecordingStudioApi::AccessRequests::ListLoading
    include RecordingStudioApi::AccessRequests::DetailLoading

    before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!, true) }
    before_action :authorize_access_management_edit_for_new_request!, only: %i[new create]
    before_action :load_form_state, only: %i[new create]
    before_action :load_api_access_list, only: %i[index requests_chart]
    before_action :load_api_access_detail, only: %i[show edit update revoke rotate]
    before_action :authorize_access_management_edit_for_loaded_client!, only: %i[edit update revoke rotate]

    def index
      return unless infinite_api_access_request?

      render partial: "recording_studio_api/access_requests/table_content"
    end

    def show
    end

    def requests_chart
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
        access_point_recording: selected_access_point_recording,
        actor: current_request_actor,
        role: @form_values.fetch(:role),
        api_client_name: @form_values.fetch(:api_client_name),
        expires_at: expires_at,
        api: @form_values.fetch(:api_key)
      )

      if result.failure?
        @errors << result.error
        render_invalid_form
      else
        @payload = result.value
        prevent_secret_response_storage!
        render :create, status: :created
      end
    end

    def update
      load_edit_form_state
      expires_at = parsed_edit_expires_at
      @errors << "Name can't be blank" if @form_values.fetch(:api_client_name).blank?
      @errors << "Access point is invalid" unless @access_point_recordings.any? { |recording| recording.id == @form_values.fetch(:access_point_recording_id) }
      @errors << "Role is invalid" unless role_options.any? { |(_label, value)| value == @form_values.fetch(:role) }
      @errors << "Requested API access role exceeds your access" unless access_management_policy.can_assign_role?(selected_edit_access_point_recording, @form_values.fetch(:role))
      return render :edit, status: :unprocessable_entity if @errors.any?

      return redirect_to(api_client_path(@api_client, page_nav_close_param), notice: "API access updated.") if persist_access_updates(expires_at)

      @errors << "The API client could not be updated"
      render :edit, status: :unprocessable_entity
    end

    def revoke
      return head :not_found if @latest_credential.nil?

      @latest_credential.revoke! if @latest_credential.revoked_at.nil?

      redirect_to api_client_path(@api_client, page_nav_close_param), notice: "API key revoked."
    end

    def rotate
      return head :not_found if @latest_credential.nil?

      result = RecordingStudioApi::Services::RotateApiCredential.call(
        api_client: @api_client,
        actor: current_request_actor,
        expires_at: @latest_credential.expires_at
      )

      if result.failure?
        redirect_to api_client_path(@api_client, page_nav_close_param), alert: result.error
        return
      end

      @payload = result.value
      prevent_secret_response_storage!
      render :rotate, status: :created
    end

    private

    def prevent_secret_response_storage!
      response.cache_control.replace(no_store: true, private: true)
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"
    end
  end
end
