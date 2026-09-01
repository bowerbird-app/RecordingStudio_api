# frozen_string_literal: true

module RecordingStudioApi
  class OauthAuthorizationsController < RecordingStudioApi::ApplicationController
    include RecordingStudioApi::Concerns::ApiContext

    before_action :authenticate_host_user!
    before_action :set_current_actor
    before_action :load_oauth_request

    def new
      return unless @oauth_client

      if @selected_access_recording.present?
        render :new
      else
        @errors << reconnect_missing_access_message if requested_access_recording_id.present?
        render :index
      end
    end

    def create
      return unless @oauth_client

      if deny_requested?
        redirect_to_client(error: "access_denied", error_description: "The resource owner denied the request")
        return
      end

      selected = @selected_access_recording
      if selected.nil?
        @errors << access_selection_error
        render :index, status: :unprocessable_entity
        return
      end

      unless role_allowed_for?(selected, requested_role)
        @errors << Services::CreateOauthAuthorization::ROLE_CHANGED_MESSAGE
        render :index, status: :unprocessable_entity
        return
      end

      result = RecordingStudioApi::Services::CreateOauthAuthorization.call(
        oauth_client: @oauth_client,
        manager_actor: current_oauth_actor,
        access_recording: selected,
        role: requested_role,
        redirect_uri: @redirect_uri,
        code_challenge: @code_challenge,
        code_challenge_method: @code_challenge_method
      )

      if result.failure?
        @errors << result.error.to_s
        template = reconnect_error?(result.error) ? :index : :new
        render template, status: :unprocessable_entity
        return
      end

      redirect_to_client(code: result.value.fetch(:code))
    end

    private

    def authenticate_host_user!
      return authenticate_user! if respond_to?(:authenticate_user!, true)

      head :unauthorized
    end

    def set_current_actor
      Current.actor = current_oauth_actor if defined?(Current) && Current.respond_to?(:actor=)
    end

    def current_oauth_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def load_oauth_request
      @errors = []
      @state = params[:state].to_s.presence
      @redirect_uri = params[:redirect_uri].to_s
      @code_challenge = params[:code_challenge].to_s.presence
      @code_challenge_method = params[:code_challenge_method].to_s.presence || (params[:code_challenge].present? ? Pkce::S256 : nil)
      @response_type = params[:response_type].to_s
      @resource = params[:resource].to_s.presence

      unless @response_type == "code"
        render_oauth_error("unsupported_response_type", "response_type must be code")
        return
      end

      client_result = Services::ResolveOauthClient.call(client_id: params[:client_id], api: current_api_key)
      unless client_result.success?
        render_oauth_error("invalid_client", "client is invalid")
        return
      end

      @oauth_client = client_result.value
      unless @oauth_client.redirect_uri_allowed?(@redirect_uri)
        render_oauth_error("invalid_request", "redirect_uri does not match")
        return
      end

      return unless pkce_allowed?

      resolved = RecordingStudioApi.resolve_access_recording_for_actor(
        actor: current_oauth_actor,
        requested_access_recording_id: requested_access_recording_id
      )
      @access_candidates = Array(resolved.fetch(:candidates))
      @selected_access_recording = selected_access_recording_from_params
      @role_options = role_options_for(@selected_access_recording)
    end

    def pkce_allowed?
      if @oauth_client.public? && (@code_challenge.blank? || @code_challenge_method != Pkce::S256)
        redirect_to_client(error: "invalid_request", error_description: "PKCE S256 is required for public clients")
        return false
      end

      if @code_challenge_method.present? && @code_challenge_method != Pkce::S256
        redirect_to_client(error: "invalid_request", error_description: "PKCE method must be S256")
        return false
      end

      true
    end

    def requested_access_recording_id
      params[:access_recording_id].to_s.presence
    end

    def selected_access_recording_from_params
      requested_id = requested_access_recording_id
      return nil if requested_id.blank?

      @access_candidates.find { |recording| recording.id == requested_id }
    end

    def connect_page_title
      "Connect #{@oauth_client.name}"
    end
    helper_method :connect_page_title

    def show_permission_choice?
      Array(@role_options).many?
    end
    helper_method :show_permission_choice?

    def access_selection_error
      return "Ask someone to invite you first" if @access_candidates.empty?
      return reconnect_missing_access_message if requested_access_recording_id.present?

      "Pick a place first"
    end

    def reconnect_missing_access_message
      Services::CreateOauthAuthorization::ACCESS_GONE_MESSAGE
    end

    def reconnect_error?(error)
      message = error.to_s
      message.include?("Connect again") || message.include?("exceed")
    end

    def deny_requested?
      %w[cancel deny].include?(params[:decision].to_s)
    end

    def requested_role
      params[:role].to_s.presence || default_consent_role
    end

    def default_consent_role
      view_option = Array(@role_options).find { |(_label, value)| value.to_s == "view" }
      view_option&.last || @role_options.first&.last || "view"
    end
    helper_method :default_consent_role

    def role_options_for(access_recording)
      current_role = manager_access_role(access_recording)
      return [] if current_role.blank?

      OauthAuthorization::ROLES.filter_map do |role|
        next unless OauthAuthorization.role_at_or_below?(role, current_role)

        [role.to_s.humanize, role]
      end
    end

    def role_allowed_for?(access_recording, role)
      OauthAuthorization.role_at_or_below?(role, manager_access_role(access_recording))
    end

    def manager_access_role(access_recording)
      recordable = access_recording&.recordable
      return unless recordable.is_a?(RecordingStudio::Access)

      recordable.role
    end

    def authorize_form_url
      if current_api_key == "public"
        oauth_authorize_path
      else
        named_api_oauth_authorize_path(api_key: current_api_key)
      end
    end
    helper_method :authorize_form_url

    def oauth_query_params
      {
        response_type: "code",
        client_id: @oauth_client.client_id,
        redirect_uri: @redirect_uri,
        state: @state,
        code_challenge: @code_challenge,
        code_challenge_method: @code_challenge_method,
        resource: @resource
      }.compact
    end

    def connect_choice_url(access_recording = nil)
      extras = oauth_query_params
      extras[:access_recording_id] = access_recording.id if access_recording
      if current_api_key == "public"
        oauth_authorize_path(extras)
      else
        named_api_oauth_authorize_path(extras.merge(api_key: current_api_key))
      end
    end
    helper_method :connect_choice_url

    def access_parent_name(access_recording)
      point = access_recording.parent_recording || access_recording.root_recording
      recordable = point&.recordable
      if recordable.respond_to?(:name) && recordable.name.present?
        recordable.name
      else
        point&.recordable_type.to_s.demodulize.underscore.humanize
      end
    end
    helper_method :access_parent_name

    def connection_status_for(access_recording)
      authorization = OauthAuthorization.for_client_manager_and_access(
        oauth_client: @oauth_client,
        manager_actor: current_oauth_actor,
        access_recording: access_recording
      )
      return nil unless authorization
      return "Connected" if authorization.active?

      "Reconnect"
    end
    helper_method :connection_status_for

    def redirect_to_client(**query)
      uri = URI.parse(@redirect_uri)
      existing = URI.decode_www_form(uri.query.to_s).to_h
      existing["state"] = @state if @state.present?
      query.each { |key, value| existing[key.to_s] = value if value.present? }
      uri.query = URI.encode_www_form(existing)
      redirect_to uri.to_s, allow_other_host: true
    end

    def render_oauth_error(code, description)
      @oauth_error = { error: code, error_description: description }
      render :error, status: OauthErrorMapper.status_for(@oauth_error)
    end
  end
end
