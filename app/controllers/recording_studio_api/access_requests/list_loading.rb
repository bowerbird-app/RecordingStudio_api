# frozen_string_literal: true

module RecordingStudioApi
  module AccessRequests
    module ListLoading
      extend ActiveSupport::Concern

      PER_PAGE = 25
      REQUESTS_CHART_STATUS_LISTS = [
        ["Successful (2xx)", "success"],
        ["Client errors (4xx)", "client_error"],
        ["Server errors (5xx)", "server_error"]
      ].freeze

      included do
        helper_method :requests_chart_link_params,
                      :requests_chart_filter_form_params,
                      :requests_chart_back_params,
                      :next_api_access_page_url
      end

      private

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

      def requests_chart_filter_form_params
        requests_chart_link_params.except(:api_client_id, :start_date, :end_date, :status, "api_client_id", "start_date", "end_date", "status")
      end

      def requests_chart_back_params
        requests_chart_link_params.except(:close_url).merge(page_nav_close_param)
      end

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
    end
  end
end
