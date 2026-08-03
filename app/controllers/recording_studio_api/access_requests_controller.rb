# frozen_string_literal: true

module RecordingStudioApi
  # rubocop:disable Metrics/ClassLength
  class AccessRequestsController < ApplicationController
    PER_PAGE = 25
    REQUESTS_CHART_STATUS_LISTS = [
      ["Successful (2xx)", "success"],
      ["Client errors (4xx)", "client_error"],
      ["Server errors (5xx)", "server_error"]
    ].freeze

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

    def load_form_state
      @errors = []
      @root_type = normalized_root_type
      @root_recording = selected_root_recording
      @access_point_recordings = available_access_point_recordings(@root_recording)
      @role_options = role_options
      @api_options = RecordingStudioApi.configuration.each_api.map { |api| [api.name.humanize, api.name] }
      access_point_recording = selected_access_point_recording
      @form_values = {
        root_type: @root_type,
        root_recording_id: @root_recording&.id,
        access_point_recording_id: api_client_params[:access_point_recording_id].presence || access_point_recording&.id,
        role: api_client_params[:role].presence || "admin",
        api_client_name: api_client_params[:api_client_name].presence || default_api_client_name,
        expires_at: api_client_params[:expires_at].to_s,
        api_key: selected_api.name
      }
    end

    def api_client_params
      params.fetch(:api_client, params.fetch(:access_request, {})).permit(:root_type, :root_recording_id, :access_point_recording_id, :role, :api_client_name, :expires_at, :api_key)
    end

    def selected_api
      RecordingStudioApi.configuration.fetch_api(api_client_params[:api_key].presence || params[:api_key].presence || :public)
    end

    def api_client_update_params
      params.fetch(:api_client, params.fetch(:access_request, {})).permit(:access_point_recording_id, :role, :api_client_name, :expires_at)
    end

    def normalized_root_type
      root_recording = selected_root_recording
      return root_recording.recordable_type if root_recording.present?

      requested_root_type = requested_root_type_value
      allowed_root_types.include?(requested_root_type) ? requested_root_type : allowed_root_types.first
    end

    def allowed_root_types
      @allowed_root_types ||= manageable_root_recordings.map(&:recordable_type).uniq &
                              RecordingStudioApi.api_recordable_types(api: selected_api.name)
    end

    def available_root_recordings(root_type)
      return [] if root_type.blank?

      manageable_root_recordings.select { |recording| recording.recordable_type == root_type }
    end

    def available_access_point_recordings(root_recording)
      access_point_types = RecordingStudioApi.api_access_point_recordable_types(api: selected_api.name)
      return [] if access_point_types.empty?

      roots = root_recording.present? ? [root_recording] : manageable_root_recordings
      recordings = roots.flat_map do |available_root_recording|
        available_root_recording.subtree_recordings(include_self: true)
          .includes(:recordable)
          .where(recordable_type: access_point_types, trashed_at: nil)
          .reorder(:created_at, :id)
          .to_a
      end

      recordings.uniq { |recording| recording.id }
    end

    def selected_root_recording
      @selected_root_recording ||= begin
        recording = RecordingStudio::Recording.includes(:recordable).find_by(id: requested_root_recording_id) if requested_root_recording_id.present?
        recording = nil unless manageable_root_recording?(recording)
        recording ||= available_root_recordings(requested_root_type_value).first if requested_root_type_value.present?
        recording || manageable_root_recordings.find { |candidate| allowed_root_types.include?(candidate.recordable_type) }
      end
    end

    def role_options
      %w[view edit admin].map { |value| [value.humanize, value] }
    end

    def default_api_client_name
      "My api access"
    end

    def selected_access_point_recording
      @selected_access_point_recording ||= begin
        requested_recording = @access_point_recordings.find { |recording| recording.id == requested_id } if requested_id.present?
        requested_recording || @access_point_recordings.first unless requested_access_point_recording_id.present? && requested_recording.nil?
      end
    end

    def current_request_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def authorize_access_management_edit_for_new_request!
      access_point_recording = selected_access_point_recording_for_request
      return if access_management_policy.can_manage_recording?(access_point_recording) && authorized_to_manage_selected_api?(access_point_recording)

      raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
    end

    def authorized_to_manage_selected_api?(access_point_recording)
      api = selected_api
      return true unless api.api_management_authorization_required
      return false if access_point_recording.nil?

      root_recording = access_point_recording.root_recording || access_point_recording
      return false unless RecordingStudioApi.configuration.admin_root_recordable_type_names.include?(root_recording.recordable_type)

      RecordingStudioApi::Admin::ApiAuthorization.authorized?(
        actor: current_request_actor,
        api: api,
        root_recording: root_recording,
        role: RecordingStudioApi.configuration.access_management_edit_role,
        create: true
      )
    end

    def authorize_access_management_edit_for_loaded_client!
      return if api_client_management_policy.manage?(@api_client)

      raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
    end

    def selected_access_point_recording_for_request
      access_point_recordings = available_access_point_recordings(selected_root_recording)
      requested_recording = access_point_recordings.find { |recording| recording.id == requested_id } if requested_id.present?
      return requested_recording if requested_access_point_recording_id.present? || requested_recording.present?

      access_point_recordings.first
    end

    def requested_root_type_value
      api_client_params[:root_type].presence || params[:root_type].presence
    end

    def requested_root_recording_id
      api_client_params[:root_recording_id].presence || params[:root_recording_id].presence
    end

    def requested_id
      requested_access_point_recording_id || requested_root_recording_id
    end

    def requested_access_point_recording_id
      api_client_params[:access_point_recording_id].presence ||
        params[:access_point_recording_id].presence ||
        params[:parent_recording_id].presence ||
        params[:recording_id].presence
    end

    def manageable_root_recording?(recording)
      return false if recording.nil? || recording.parent_recording_id.present?

      manageable_root_recordings.any? { |candidate| candidate.id == recording.id }
    end

    def access_management_policy
      @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_request_actor)
    end

    def api_client_management_policy
      @api_client_management_policy ||= RecordingStudioApi::ApiClientManagementPolicy.new(actor: current_request_actor)
    end

    def visible_access_recordings
      access_management_policy.visible_access_recordings
    end

    def visible_api_client_access_recordings
      access_management_policy.visible_api_client_access_recordings
    end

    def visible_api_client_ids
      @visible_api_client_ids ||= RecordingStudioApi::ApiClient
                                  .includes(access_recording: [:recordable, { parent_recording: :parent_recording }])
                                  .where(access_recording_id: visible_api_client_access_recordings.map(&:id))
                                  .select { |api_client| api_client_management_policy.view?(api_client) }
                                  .map(&:id)
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
      @errors << "An access point recording must be selected" if selected_access_point_recording.nil?
      render :new, status: :unprocessable_entity
    end

    def human_root_type
      @root_type.to_s.demodulize.underscore.humanize
    end
    helper_method :human_root_type,
                  :allowed_root_types,
                  :recording_label,
                  :masked_api_key

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def load_api_access_list
      @page = infinite_api_access_request? ? resolved_page : 1
      root_type_filter = params[:root_type].presence
      @scoped_root_recording = scoped_root_recording(params[:root_recording_id].presence)
      @scoped_parent_recording = scoped_parent_recording(
        resolved_parent_scope_recording_id,
        scoped_root_recording: @scoped_root_recording
      )
      @include_children = include_children_filter?

      scoped_recording = @scoped_parent_recording || @scoped_root_recording
      scoped_recording_ids = scoped_recording_filter_ids(scoped_recording, include_children: @include_children)
      visible_access_recording_ids = visible_api_client_access_recordings.map(&:id)
      @can_manage_access_requests = visible_root_recordings.any? do |recording|
        access_management_policy.can_manage_recording?(recording)
      end

      api_clients = RecordingStudioApi::ApiClient
        .includes(:credentials, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .where(access_recording_id: visible_access_recording_ids)
        .where(id: visible_api_client_ids)
        .reorder(:created_at, :id)
        .to_a

      all_api_access_rows = api_clients.filter_map do |api_client|
        access_recording = api_client.access_recording
        next if access_recording.nil?

        root_recording = access_recording.root_recording
        next if root_recording.nil?
        next if @scoped_root_recording.present? && root_recording.id != @scoped_root_recording.id
        next if root_type_filter.present? && root_recording.recordable_type != root_type_filter

        access_point_recording = access_point_recording_for(access_recording)
        next if scoped_recording_ids.present? && !scoped_recording_ids.include?(access_point_recording&.id)

        latest_credential = api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }

        expires_at_value = nil
        expires_text = if latest_credential.nil?
                         "No credentials"
                       elsif latest_credential.revoked_at.present?
                         "Revoked"
                       elsif latest_credential.expires_at.present? && latest_credential.expires_at.past?
                         "Expired"
                       elsif latest_credential.expires_at.blank?
                         "Never"
                       else
                         expires_at_value = latest_credential.expires_at
                         "Never"
                       end

        {
          id: api_client.id,
          root_recording: root_recording,
          access_point_recording: access_point_recording,
          name: api_client.name,
          api_key: latest_credential&.oauth_client_id || "Unknown",
          access_point: access_point_label(access_point_recording),
          role: access_recording.recordable&.try(:role).to_s.humanize.presence || "Unknown",
          credentials_count: api_client.credentials.size,
          expires_at: expires_at_value,
          expires_text: expires_text,
          latest_credential_status: credential_status_label(latest_credential)
        }
      end

      @api_access_rows = paged_rows_for(all_api_access_rows, page: @page)
      @api_access_has_more = more_rows?(all_api_access_rows, page: @page)

      @access_list_subtitle = resolve_access_list_subtitle(
        rows: all_api_access_rows,
        scoped_recording: scoped_recording,
        root_type_filter: root_type_filter
      )

      load_api_key_chart_data(all_api_access_rows)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def load_api_key_chart_data(rows)
      @most_used_api_keys = top_api_key_chart_rows(rows)
      @total_api_keys = rows.size
      load_requests_chart_data(rows: rows)
    end

    def load_requests_chart_data(rows:)
      initialize_requests_chart_filters(rows: rows)
      date_window = @requests_chart_start_date..@requests_chart_end_date
      @requests_chart_categories = date_window.map { |day| day.strftime("%a") }

      if rows.blank? || !RecordingStudioApi::ApiRequestLog.table_available?
        @requests_chart_series = Array.new(@requests_chart_categories.length, 0)
        return
      end

      client_ids = rows.map { |row| row.fetch(:id) }

      if client_ids.blank?
        @requests_chart_series = Array.new(@requests_chart_categories.length, 0)
        return
      end

      counts_by_date = filtered_requests_chart_scope(client_ids: client_ids)
        .group("DATE(occurred_at)")
        .count

      @requests_chart_series = date_window.map do |day|
        counts_by_date.fetch(day, counts_by_date.fetch(day.to_s, 0))
      end
    end

    def initialize_requests_chart_filters(rows:)
      @requests_chart_start_date = parsed_requests_chart_date(params[:start_date]) || 29.days.ago.to_date
      @requests_chart_end_date = parsed_requests_chart_date(params[:end_date]) || Date.current

      if @requests_chart_start_date > @requests_chart_end_date
        @requests_chart_start_date, @requests_chart_end_date = @requests_chart_end_date, @requests_chart_start_date
      end

      @requests_chart_status_lists = REQUESTS_CHART_STATUS_LISTS
      @requests_chart_status = normalized_requests_chart_status
      @requests_chart_api_client_options = requests_chart_api_client_options(rows)
      @requests_chart_api_client_id = normalized_requests_chart_api_client_id(rows)
    end

    def parsed_requests_chart_date(raw_date)
      return nil if raw_date.blank?

      Date.iso8601(raw_date.to_s)
    rescue ArgumentError
      nil
    end

    def normalized_requests_chart_status
      requested_status = params[:status].to_s
      allowed_statuses = REQUESTS_CHART_STATUS_LISTS.map { |(_label, value)| value }
      allowed_statuses.include?(requested_status) ? requested_status : nil
    end

    def requests_chart_api_client_options(rows)
      rows
        .sort_by { |row| [row.fetch(:name).to_s.downcase, row.fetch(:api_key).to_s] }
        .map do |row|
          ["#{row.fetch(:name)} (#{row.fetch(:api_key)})", row.fetch(:id)]
        end
    end

    def normalized_requests_chart_api_client_id(rows)
      requested_api_client_id = params[:api_client_id].presence
      return nil if requested_api_client_id.blank?

      allowed_api_client_ids = rows.map { |row| row.fetch(:id).to_s }
      allowed_api_client_ids.include?(requested_api_client_id.to_s) ? requested_api_client_id.to_s : nil
    end

    def filtered_requests_chart_scope(client_ids:)
      scope = RecordingStudioApi::ApiRequestLog.where(
        api_client_id: client_ids,
        occurred_at: @requests_chart_start_date.beginning_of_day..@requests_chart_end_date.end_of_day
      )

      scope = scope.where(api_client_id: @requests_chart_api_client_id) if @requests_chart_api_client_id.present?

      case @requests_chart_status
      when "success"
        scope.where(status_code: 200..299)
      when "client_error"
        scope.where(status_code: 400..499)
      when "server_error"
        scope.where(status_code: 500..599)
      else
        scope
      end
    end

    def requests_chart_link_params
      page_nav_close_param.merge(
        request.query_parameters.slice(
          "root_type",
          "root_recording_id",
          "recording_id",
          "parent_recording_id",
          "include_children",
          "api_client_id",
          "start_date",
          "end_date",
          "status"
        )
      )
    end
    helper_method :requests_chart_link_params

    def requests_chart_filter_form_params
      requests_chart_link_params.except(:api_client_id, :start_date, :end_date, :status, "api_client_id", "start_date", "end_date", "status")
    end
    helper_method :requests_chart_filter_form_params

    def requests_chart_back_params
      requests_chart_link_params.except(:close_url).merge(page_nav_close_param)
    end
    helper_method :requests_chart_back_params

    def resolved_page
      requested_page = params[:page].to_i
      requested_page.positive? ? requested_page : 1
    end

    def paged_rows_for(rows, page:)
      offset = (page - 1) * PER_PAGE
      rows.slice(offset, PER_PAGE) || []
    end

    def more_rows?(rows, page:)
      (page * PER_PAGE) < rows.size
    end

    def next_api_access_page_url
      api_clients_path(request.query_parameters.except("page").merge(page: @page + 1))
    end
    helper_method :next_api_access_page_url

    def infinite_api_access_request?
      request.xhr? && params[:page].present?
    end

    def top_api_key_chart_rows(rows)
      return [] if rows.blank?

      request_counts_by_client_id = api_request_counts_by_client_id(rows)

      chart_rows = rows.map do |row|
        {
          id: row.fetch(:id),
          name: row.fetch(:name),
          request_count: request_counts_by_client_id.fetch(row.fetch(:id), 0)
        }
      end

      chart_rows
        .sort_by { |row| [-row.fetch(:request_count), row.fetch(:name).downcase] }
        .first(5)
    end

    def api_request_counts_by_client_id(rows)
      return {} unless RecordingStudioApi::ApiRequestLog.table_available?

      client_ids = rows.map { |row| row.fetch(:id) }
      return {} if client_ids.empty?

      RecordingStudioApi::ApiRequestLog.where(api_client_id: client_ids).group(:api_client_id).count
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

    def scoped_root_recording(recording_id)
      return nil if recording_id.blank?

      root_recording = RecordingStudio::Recording.includes(:recordable).find_by(id: recording_id)
      raise RecordingStudioApi::AuthorizationError, "Root scope must reference a root recording" if root_recording.nil? || root_recording.parent_recording_id.present?

      authorize_scope_recording_view!(root_recording)
      root_recording
    end

    def resolved_parent_scope_recording_id
      params[:parent_recording_id].presence || params[:recording_id].presence
    end

    def scoped_parent_recording(recording_id, scoped_root_recording:)
      return nil if recording_id.blank?

      recording = RecordingStudio::Recording.includes(:recordable).find_by(id: recording_id)
      raise RecordingStudioApi::AuthorizationError, "Parent scope recording not found" if recording.nil?

      authorize_scope_recording_view!(recording)

      return recording if scoped_root_recording.blank?

      recording_root = recording.root_recording || recording
      return recording if recording_root.id == scoped_root_recording.id

      raise RecordingStudioApi::AuthorizationError, "Parent scope must belong to the selected root"
    end

    def authorize_scope_recording_view!(recording)
      return if access_management_policy.authorized_for_recording?(
        recording,
        access_management_role: RecordingStudioApi.configuration.access_management_view_role
      )

      raise RecordingStudioApi::AuthorizationError, "API access list scope is not available for the current actor"
    end

    def include_children_filter?
      return true unless params.key?(:include_children)

      ActiveModel::Type::Boolean.new.cast(params[:include_children])
    end

    def scoped_recording_filter_ids(recording, include_children:)
      return nil if recording.nil?
      return [recording.id] unless include_children

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
        .includes(:credentials, access_recording: [:recordable, { parent_recording: :parent_recording }])
        .where(id: visible_api_client_ids)
        .find(params[:id])

      @access_recording = @api_client.access_recording
      @root_recording = @access_recording&.root_recording
      @can_manage_access_request = api_client_management_policy.manage?(@api_client)
      @latest_credential = @api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }
      @rotated_credential_rows = rotated_credential_rows_for(@api_client.credentials, @latest_credential)
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def rotated_credential_rows_for(credentials, latest_credential)
      credentials
        .reject { |credential| credential.id == latest_credential&.id }
        .sort_by { |credential| [credential.created_at.to_i, credential.id.to_s] }
        .reverse
        .map { |credential| rotated_credential_row(credential) }
    end

    def rotated_credential_row(credential)
      {
        api_key: credential.oauth_client_id,
        status_text: credential_status_label(credential),
        status_style: credential_status_style(credential),
        last_used_at: credential.last_used_at,
        revoked_at: credential.revoked_at,
        expires_at: expires_at_for(credential),
        expires_text: expires_text_for(credential)
      }
    end

    def credential_status_style(credential)
      return :danger if credential.revoked_at.present?
      return :default if credential.expires_at.present? && credential.expires_at.past?

      :success
    end

    def expires_at_for(credential)
      return if credential.expires_at.blank? || credential.expires_at.past?

      credential.expires_at
    end

    def expires_text_for(credential)
      return "Expired" if credential.expires_at.present? && credential.expires_at.past?
      return "Never" if credential.expires_at.blank?

      credential.expires_at.to_date.to_s
    end

    def load_edit_form_state
      @errors = []
      @root_recording = @api_client.access_recording&.root_recording
      @access_point_recordings = available_access_point_recordings(@root_recording)
      @role_options = role_options
      @api_options = [[@api_client.api_key.humanize, @api_client.api_key]]
      @form_values = {
        access_point_recording_id: api_client_update_params[:access_point_recording_id].presence || access_point_recording_for(@api_client.access_recording)&.id,
        role: api_client_update_params[:role].presence || resolved_edit_role_value,
        api_client_name: api_client_update_params[:api_client_name].presence || @api_client.name,
        expires_at: resolved_edit_expires_at_value,
        api_key: @api_client.api_key
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
      access_point_recording_id = @form_values.fetch(:access_point_recording_id)
      return false unless access_management_policy.can_assign_role?(selected_edit_access_point_recording, @form_values.fetch(:role))

      ActiveRecord::Base.transaction do
        if access_point_recording_id.present? && @access_recording.parent_recording_id != access_point_recording_id
          updated_access_recordings = RecordingStudio::Recording.unscoped.where(id: @access_recording.id).update_all(
            parent_recording_id: access_point_recording_id,
            updated_at: now
          )

          raise ActiveRecord::ActiveRecordError, "Access recording update failed" unless updated_access_recordings == 1
        end

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

    def selected_edit_access_point_recording
      @access_point_recordings.find { |recording| recording.id == @form_values.fetch(:access_point_recording_id) }
    end

    def credential_status_label(credential)
      return "No credentials" if credential.nil?
      return "Revoked" if credential.revoked_at.present?
      return "Expired" if credential.expires_at.present? && credential.expires_at.past?

      "Active"
    end

    def masked_api_key(credential)
      oauth_client_id = credential&.oauth_client_id.to_s
      return "Unavailable" if oauth_client_id.blank?

      visible_prefix = oauth_client_id.first(2)
      visible_suffix = oauth_client_id.last(2)
      masked_length = [oauth_client_id.length - 4, 0].max

      "#{visible_prefix}#{"*" * masked_length}#{visible_suffix}"
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
  # rubocop:enable Metrics/ClassLength
end