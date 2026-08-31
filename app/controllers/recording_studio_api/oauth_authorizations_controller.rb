# frozen_string_literal: true

module RecordingStudioApi
  class OauthAuthorizationsController < RecordingStudioApi::ApplicationController
    include RecordingStudioApi::Concerns::ApiContext

    before_action :authenticate_host_user!
    before_action :set_current_actor
    before_action :load_oauth_request

    def new
      return unless @oauth_client

      render :new
    end

    def create
      return unless @oauth_client

      if deny_requested?
        redirect_to_client(error: "access_denied", error_description: "The resource owner denied the request")
        return
      end

      selected = selected_access_recording
      if selected.nil?
        @errors << access_selection_error
        render :new, status: :unprocessable_entity
        return
      end

      unless can_assign_role?(selected, requested_role)
        @errors << "Requested role exceeds your access"
        render :new, status: :unprocessable_entity
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
        render :new, status: :unprocessable_entity
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
        requested_access_recording_id: params[:access_recording_id]
      )
      @access_candidates = grantable_access_recordings(resolved.fetch(:candidates))
      @selected_access_recording = selected_access_recording_for_display(resolved.fetch(:recording))
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

    def grantable_access_recordings(candidates)
      Array(candidates).select do |recording|
        access_point = recording.parent_recording || recording.root_recording
        next false unless RecordingStudioApi.api_access_point_recordable_type?(access_point&.recordable_type, api: current_api_key)

        can_assign_any_role?(access_point)
      end
    end

    def selected_access_recording
      requested_id = params[:access_recording_id].to_s.presence
      return @access_candidates.find { |recording| recording.id == requested_id } if requested_id.present?
      return @access_candidates.first if @access_candidates.one?

      nil
    end

    def selected_access_recording_for_display(resolved_recording)
      matched = @access_candidates.find { |recording| recording.id == resolved_recording&.id }
      return matched if matched.present?
      return @access_candidates.first if @access_candidates.one?
      return @access_candidates.first if @access_candidates.many? && request.get?

      nil
    end

    def consent_section_subtitle
      if @access_candidates.many?
        "Choose a workspace and the highest permission this app may use."
      else
        "Choose the highest permission this app may use."
      end
    end
    helper_method :consent_section_subtitle

    def access_selection_error
      return "No workspace access is available to connect" if @access_candidates.empty?
      return "Choose a workspace" if @access_candidates.many?

      "Access is invalid"
    end

    def deny_requested?
      params[:decision].to_s == "deny"
    end

    def requested_role
      params[:role].to_s.presence || @role_options.last&.last || "view"
    end

    def role_options_for(access_recording)
      access_point = access_recording&.parent_recording || access_recording&.root_recording
      OauthAuthorization::ROLES.filter_map do |role|
        next unless access_point && can_assign_role?(access_recording, role)

        [role.to_s.humanize, role]
      end
    end

    def can_assign_any_role?(access_point)
      OauthAuthorization::ROLES.any? { |role| policy.can_assign_role?(access_point, role) }
    end

    def can_assign_role?(access_recording, role)
      access_point = if access_recording.is_a?(RecordingStudio::Recording) && access_recording.recordable_type == "RecordingStudio::Access"
                       access_recording.parent_recording || access_recording.root_recording
                     else
                       access_recording
                     end
      policy.can_assign_role?(access_point, role)
    end

    def policy
      @policy ||= AccessManagementPolicy.new(actor: current_oauth_actor)
    end

    def authorize_form_url
      if current_api_key == "public"
        oauth_authorize_path
      else
        named_api_oauth_authorize_path(api_key: current_api_key)
      end
    end
    helper_method :authorize_form_url

    def access_workspace_name(access_recording)
      point = access_recording.parent_recording || access_recording.root_recording
      recordable = point&.recordable
      if recordable.respond_to?(:name) && recordable.name.present?
        recordable.name
      else
        point&.recordable_type.to_s.demodulize.underscore.humanize
      end
    end
    helper_method :access_workspace_name

    def access_recording_label(access_recording)
      workspace_name = access_workspace_name(access_recording)
      role = access_recording.recordable&.role.to_s.humanize
      role.present? ? "#{workspace_name} (#{role})" : workspace_name
    end
    helper_method :access_recording_label

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
