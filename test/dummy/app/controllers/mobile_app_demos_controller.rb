# frozen_string_literal: true

require "base64"
require "digest"

class MobileAppDemosController < ApplicationController
  DEMO_CLIENT_IDENTIFIER = "dummy-mobile-demo-client"

  before_action :ensure_demo_client!

  def show
    @status_message = session.delete(:mobile_app_demo_notice)
    @error_message = session.delete(:mobile_app_demo_error)
    @available_access_recordings = available_access_recordings
    @demo_client = @oauth_client
    @token_bundle = session[:mobile_app_demo_tokens]
    @api_preview = build_api_preview(@token_bundle&.fetch("access_token", nil))
    @recording_tree = recording_tree_for_oauth_grant_sessions
  end

  def start
    session[:mobile_app_demo_tokens] = nil
    session[:mobile_app_demo_authorization] = {
      "code_verifier" => code_verifier,
      "state" => SecureRandom.hex(16)
    }

    redirect_to authorize_demo_url
  end

  def callback
    authorization_state = session[:mobile_app_demo_authorization] || {}

    if params[:error].present?
      session[:mobile_app_demo_error] = oauth_error_message(params[:error], params[:error_description])
      redirect_to mobile_app_demo_path
      return
    end

    if params[:code].blank? || params[:state].blank? || authorization_state["state"] != params[:state]
      session[:mobile_app_demo_error] = "Mobile app demo callback was invalid or expired. Start the login flow again."
      redirect_to mobile_app_demo_path
      return
    end

    result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_identifier,
      code: params[:code].to_s,
      redirect_uri: @oauth_client.redirect_uri,
      code_verifier: authorization_state["code_verifier"].to_s
    )

    if result.failure?
      session[:mobile_app_demo_error] = oauth_error_message(result.error)
    else
      session[:mobile_app_demo_tokens] = {
        "access_token" => result.value.fetch(:access_token),
        "refresh_token" => result.value.fetch(:refresh_token),
        "token_type" => result.value.fetch(:token_type),
        "issued_at" => Time.current.iso8601
      }
      session[:mobile_app_demo_notice] = "Mobile app login completed. The demo token now has live API access."
    end

    session.delete(:mobile_app_demo_authorization)
    redirect_to mobile_app_demo_path
  end

  def refresh
    token_bundle = session[:mobile_app_demo_tokens] || {}
    refresh_token = token_bundle["refresh_token"].to_s

    if refresh_token.blank?
      session[:mobile_app_demo_error] = "No refresh token is available for this demo session."
      redirect_to mobile_app_demo_path
      return
    end

    result = RecordingStudioApi::Services::RefreshOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_identifier,
      refresh_token: refresh_token
    )

    if result.failure?
      session[:mobile_app_demo_error] = oauth_error_message(result.error)
    else
      session[:mobile_app_demo_tokens] = {
        "access_token" => result.value.fetch(:access_token),
        "refresh_token" => result.value.fetch(:refresh_token),
        "token_type" => result.value.fetch(:token_type),
        "issued_at" => Time.current.iso8601
      }
      session[:mobile_app_demo_notice] = "Mobile app demo token refreshed."
    end

    redirect_to mobile_app_demo_path
  end

  def revoke
    token_bundle = session[:mobile_app_demo_tokens] || {}
    token = token_bundle["refresh_token"].presence || token_bundle["access_token"].to_s

    if token.blank?
      session[:mobile_app_demo_error] = "There is no active mobile app demo session to revoke."
      redirect_to mobile_app_demo_path
      return
    end

    result = RecordingStudioApi::Services::RevokeOauthToken.call(
      client_id: @oauth_client.client_identifier,
      token: token,
      token_type_hint: token_bundle["refresh_token"].present? ? "refresh_token" : "access_token"
    )

    if result.failure?
      session[:mobile_app_demo_error] = oauth_error_message(result.error)
    else
      session[:mobile_app_demo_tokens] = nil
      session[:mobile_app_demo_notice] = "Mobile app demo session revoked."
    end

    redirect_to mobile_app_demo_path
  end

  private

  def ensure_demo_client!
    @oauth_client = RecordingStudioApi::OauthClient.find_or_initialize_by(client_identifier: DEMO_CLIENT_IDENTIFIER)
    @oauth_client.name = "Dummy Mobile App Demo"
    @oauth_client.redirect_uri = callback_mobile_app_demo_url
    @oauth_client.public_client = true
    @oauth_client.active = true
    @oauth_client.save! if @oauth_client.changed?
  end

  def available_access_recordings
    access_ids = RecordingStudio::Access.where(actor: current_user).pluck(:id)
    return [] if access_ids.empty?

    RecordingStudio::Recording.unscoped
      .where(recordable_type: "RecordingStudio::Access", recordable_id: access_ids, trashed_at: nil)
      .includes(parent_recording: :recordable)
      .order(:created_at, :id)
      .map do |recording|
        {
          id: recording.id,
          label: access_recording_label(recording),
          role: recording.recordable.role.to_s.humanize
        }
      end
  end

  def access_recording_label(recording)
    parent = recording.parent_recording
    return "Access #{recording.id.first(8)}" if parent.nil? || parent.recordable.nil?

    "#{parent.recordable.class.name.demodulize}: #{recordable_identifier(parent.recordable)}"
  end

  def recordable_identifier(recordable)
    return recordable.name if recordable.respond_to?(:name) && recordable.name.present?
    return recordable.title if recordable.respond_to?(:title) && recordable.title.present?

    recordable.id
  end

  def code_verifier
    SecureRandom.urlsafe_base64(64, false).first(96)
  end

  def authorize_demo_url
    "/recording_studio_api/oauth/authorize?#{authorize_demo_params.to_query}"
  end

  def authorize_demo_params
    code_verifier = session.fetch(:mobile_app_demo_authorization).fetch("code_verifier")

    {
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: @oauth_client.redirect_uri,
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false),
      code_challenge_method: "S256",
      state: session.fetch(:mobile_app_demo_authorization).fetch("state")
    }
  end

  def build_api_preview(access_token)
    return nil if access_token.blank?

    auth_result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{access_token}"
    )
    return { error: auth_result.error } if auth_result.failure?

    authenticated_client = auth_result.value
    scoped_recordings = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: authenticated_client.root_recording,
      access_recording: authenticated_client.access_recording
    ).relation

    resources = RecordingStudioApi.api_recordable_types.map do |recordable_type|
      {
        name: RecordingStudioApi.resource_name_for(recordable_type),
        type: recordable_type.to_s.demodulize.underscore
      }
    end

    sample_recordable_type = RecordingStudioApi.api_recordable_types.find do |recordable_type|
      scoped_recordings.where(recordable_type: recordable_type).exists?
    end

    sample_collection = if sample_recordable_type.present?
      {
        resource: RecordingStudioApi.resource_name_for(sample_recordable_type),
        type: sample_recordable_type.demodulize,
        data: scoped_recordings.where(recordable_type: sample_recordable_type).limit(5).map do |recording|
          RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(recording)
        end
      }
    end

    {
      auth_context: {
        api_client_id: authenticated_client.api_client.id,
        access_recording_id: authenticated_client.access_recording.id,
        root_recording_id: authenticated_client.root_recording.id
      },
      resource_index: { resources: resources },
      sample_collection: sample_collection
    }
  end

  def recording_tree_for_oauth_grant_sessions
    access_recording = selected_access_recording
    return [] if access_recording.nil?

    grant_session_recordings = RecordingStudio::Recording.unscoped
      .where(
        parent_recording_id: access_recording.id,
        recordable_type: "RecordingStudioApi::OauthGrantSession",
        trashed_at: nil
      )
      .includes(:recordable)
      .order(created_at: :desc, id: :desc)
      .to_a

    grant_session_descendants = grant_session_recordings.flat_map do |grant_session_recording|
      grant_session_recording.subtree_recordings(include_self: false).includes(:recordable).to_a
    end

    scoped_recordings = [access_recording, *grant_session_recordings, *grant_session_descendants]
      .uniq { |recording| recording.id }

    RecordingTreePresenter.new(recordings: scoped_recordings).nodes
  end

  def selected_access_recording
    active_access_recording_id = @api_preview&.dig(:auth_context, :access_recording_id)
    fallback_access_recording_id = @available_access_recordings.first&.fetch(:id, nil)
    access_recording_id = active_access_recording_id.presence || fallback_access_recording_id
    return nil if access_recording_id.blank?

    RecordingStudio::Recording.unscoped.includes(:parent_recording).find_by(
      id: access_recording_id,
      recordable_type: "RecordingStudio::Access",
      trashed_at: nil
    )
  end

  def oauth_error_message(error, description = nil)
    payload = error.is_a?(Hash) ? error.symbolize_keys : { error: error.to_s, error_description: description }
    [payload[:error], payload[:error_description]].compact.join(": ")
  end
end