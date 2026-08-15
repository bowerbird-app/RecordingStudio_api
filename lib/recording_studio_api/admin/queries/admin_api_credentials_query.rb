# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module Queries
      class AdminApiCredentialsQuery
        Row = Struct.new(
          :id,
          :api_credential,
          :api_client,
          :root_recording,
          :root,
          :root_type,
          :api_name,
          :access_point,
          :role,
          :api_key,
          :status,
          :expires_text,
          :request_count,
          :last_requested_at,
          keyword_init: true
        )

        class << self
          def call(api: :public)
            api_name = RecordingStudioApi::Admin::ApiContext.resolve(api).name
            cache = (Thread.current[:recording_studio_api_admin_credentials_query] ||= {})
            cache[api_name] ||= new(api: api).call
          end

          def clear_cache!
            Thread.current[:recording_studio_api_admin_credentials_query] = nil
          end
        end

        def initialize(api: :public)
          @api_key = RecordingStudioApi::Admin::ApiContext.resolve(api).name
        end

        def call
          rows = credentials.filter_map do |credential|
            api_client = credential.api_client
            access_recording = api_client&.access_recording
            root_recording = access_recording&.root_recording
            next if root_recording.nil?

            Row.new(
              id: credential.id,
              api_credential: credential,
              api_client: api_client,
              root_recording: root_recording,
              root: recordable_identifier(root_recording.recordable),
              root_type: root_recording.recordable_type.to_s.demodulize.underscore.humanize,
              api_name: api_client.api_key,
              access_point: access_point_label(access_recording),
              role: access_recording.recordable&.try(:role).to_s.humanize.presence || "Unknown",
              api_key: credential.oauth_client_id || "Unknown",
              status: credential_status_label(credential),
              expires_text: expires_text_for(credential),
              request_count: request_count_for(credential),
              last_requested_at: last_requested_at_for(credential)
            )
          end

          rows.sort_by { |row| [row.root.to_s.downcase, row.api_client.name.to_s.downcase, row.id.to_s] }
        end

        private

        attr_reader :api_key

        def credentials
          @credentials ||= RecordingStudioApi::ApiCredential
                           .includes(api_client: { access_recording: [:recordable, :root_recording] })
                           .where(api_client_id: RecordingStudioApi::ApiClient.where(api_key: api_key).select(:id))
                           .reorder(:created_at, :id)
                           .to_a
        end

        def request_count_for(credential)
          request_counts_by_credential_id.fetch(credential.id, 0)
        end

        def last_requested_at_for(credential)
          last_requests_by_credential_id.fetch(credential.id, nil)
        end

        def request_counts_by_credential_id
          return {} unless RecordingStudioApi::ApiRequestLog.table_available?

          @request_counts_by_credential_id ||= RecordingStudioApi::ApiRequestLog
                                               .where(api_credential_id: credentials.map(&:id))
                                               .group(:api_credential_id)
                                               .count
        end

        def last_requests_by_credential_id
          return {} unless RecordingStudioApi::ApiRequestLog.table_available?

          @last_requests_by_credential_id ||= RecordingStudioApi::ApiRequestLog
                                              .where(api_credential_id: credentials.map(&:id))
                                              .group(:api_credential_id)
                                              .maximum(:occurred_at)
        end

        def access_point_label(access_recording)
          return "Unknown" if access_recording.nil?

          recording = access_recording.parent_recording || access_recording.root_recording
          return "Unknown" if recording.nil?
          return recording.recordable_type.to_s.demodulize.underscore.humanize if recording.parent_recording_id.nil?

          recordable_identifier(recording.recordable)
        end

        def recordable_identifier(recordable)
          return "Unknown" if recordable.nil?

          %i[name title email label slug identifier].each do |attribute|
            next unless recordable.respond_to?(attribute)

            value = recordable.public_send(attribute)
            return value if value.present?
          end

          recordable.class.model_name.human
        end

        def expires_text_for(credential)
          return "Revoked" if credential.revoked_at.present?
          return "Expired" if credential.expires_at.present? && credential.expires_at.past?
          return "Never" if credential.expires_at.blank?

          credential.expires_at.to_date.to_s
        end

        def credential_status_label(credential)
          return "Revoked" if credential.revoked_at.present?
          return "Expired" if credential.expires_at.present? && credential.expires_at.past?

          "Active"
        end
      end
    end
  end
end