# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module Queries
      class ApiAccessClientsQuery
        Row = Struct.new(
          :id,
          :api_credential,
          :api_client,
          :access_point_recording,
          :name,
          :api_key,
          :access_point,
          :role,
          :credentials_count,
          :expires_at,
          :expires_text,
          :status,
          :request_count,
          :last_requested_at,
          keyword_init: true
        )

        class << self
          def call(context)
            new(context).call
          end
        end

        def initialize(context)
          @context = context
        end

        def call
          filtered_rows.sort_by { |row| [row.name.to_s.downcase, row.id.to_s] }
        end

        private

        attr_reader :context

        def filtered_rows
          case status_filter_value
          when "active"
            rows.select { |row| row.status == "Active" }
          when "expired"
            rows.select { |row| row.status == "Expired" }
          when "revoked"
            rows.select { |row| row.status == "Revoked" }
          when "missing"
            rows.select { |row| row.status == "No credentials" }
          else
            rows
          end
        end

        def status_filter_value
          context.params[:status].presence || context.params["status"].presence || "active"
        end

        def rows
          api_credentials.filter_map do |api_credential|
            api_client = api_credential.api_client
            access_recording = api_client.access_recording
            next if access_recording.nil?

            root_recording = access_recording.root_recording
            next if root_recording.nil?

            access_point_recording = access_point_recording_for(access_recording)
            Row.new(
              id: api_credential.id,
              api_credential: api_credential,
              api_client: api_client,
              access_point_recording: access_point_recording,
              name: api_client.name,
              api_key: api_credential.oauth_client_id || "Unknown",
              access_point: access_point_label(access_point_recording),
              role: access_recording.recordable&.try(:role).to_s.humanize.presence || "Unknown",
              credentials_count: api_client.credentials.size,
              expires_at: expires_at_for(api_credential),
              expires_text: expires_text_for(api_credential),
              status: credential_status_label(api_credential),
              request_count: request_count_for(api_credential),
              last_requested_at: last_requested_at_for(api_credential)
            )
          end
        end

        def api_credentials
          @api_credentials ||= RecordingStudioApi::ApiCredential
                               .includes(
                                 api_client: [
                                   :credentials,
                                   { access_recording: [:recordable, :root_recording, { parent_recording: [:recordable, :parent_recording] }] }
                                 ]
                               )
                               .where(api_client_id: visible_api_clients.select(:id))
                               .reorder(:created_at, :id)
                               .to_a
        end

        def visible_api_clients
          @visible_api_clients ||= RecordingStudioApi::ApiClient
                                   .includes(
                                     :credentials,
                                     access_recording: [:recordable, :root_recording, { parent_recording: [:recordable, :parent_recording] }]
                                   )
                                   .where(access_recording_id: visible_api_client_access_recordings.select(:id))
                                   .reorder(:created_at, :id)
        end

        def visible_api_client_access_recordings
          @visible_api_client_access_recordings ||= begin
            scope = RecordingStudio::Recording.unscoped
                                              .where(id: RecordingStudioApi::ApiClient.select(:access_recording_id))
                                              .where(recordable_type: "RecordingStudio::Access", trashed_at: nil)
                                              .where(parent_recording_id: accessible_access_point_recordings.select(:id))
            scope = scope.where(root_recording_id: scoped_root_recording.id) if scoped_root_recording
            scope = scope.where(root_recording_id: root_recordings_for_type.select(:id)) if root_type_filter.present?
            scope = scope.where(parent_recording_id: scoped_recording_relation.select(:id)) if scoped_recording_relation
            scope
          end
        end

        def accessible_access_point_recordings
          RecordingStudio::Recording.unscoped.where("#{recordings_table}.id IN (#{accessible_access_point_ids_sql})")
        end

        def accessible_access_point_ids_sql
          return "SELECT NULL::uuid WHERE FALSE" if context.current_actor.nil? || access_management_role_rank.nil?

          actor_type = connection.quote(RecordingStudioAccessible::ActorType.for(context.current_actor))
          actor_id = connection.quote(context.current_actor.id)
          minimum_role = connection.quote(access_management_role_rank)

          <<~SQL.squish
            WITH RECURSIVE access_scope AS (
              SELECT #{recordings_table}.parent_recording_id AS id
              FROM #{recordings_table}
              INNER JOIN #{accesses_table}
                ON #{accesses_table}.id = #{recordings_table}.recordable_id
              WHERE #{recordings_table}.recordable_type = 'RecordingStudio::Access'
                AND #{recordings_table}.parent_recording_id IS NOT NULL
                AND #{recordings_table}.trashed_at IS NULL
                AND #{accesses_table}.actor_type = #{actor_type}
                AND #{accesses_table}.actor_id = #{actor_id}
                AND #{accesses_table}.role >= #{minimum_role}

              UNION

              SELECT child.id
              FROM #{recordings_table} child
              INNER JOIN access_scope parent ON child.parent_recording_id = parent.id
              WHERE child.trashed_at IS NULL
            )
            SELECT id FROM access_scope WHERE id IS NOT NULL
          SQL
        end

        def access_management_role_rank
          @access_management_role_rank ||= RecordingStudio::Access.roles[
            RecordingStudioApi.configuration.access_management_view_role.to_s
          ]
        end

        def scoped_root_recording
          @scoped_root_recording ||= begin
            requested_id = context.params[:root_recording_id].presence || context.params["root_recording_id"].presence
            recording = RecordingStudio::Recording.includes(:recordable).find_by(id: requested_id) if requested_id.present?
            recording ||= context.root_recording
            recording if recording&.parent_recording_id.nil?
          end
        end

        def scoped_parent_recording
          @scoped_parent_recording ||= begin
            requested_id = context.params[:parent_recording_id].presence || context.params["parent_recording_id"].presence ||
                           context.params[:recording_id].presence || context.params["recording_id"].presence
            RecordingStudio::Recording.includes(:recordable).find_by(id: requested_id) if requested_id.present?
          end
        end

        def scoped_recording_relation
          scoped_recording = scoped_parent_recording || scoped_root_recording
          return if scoped_recording.nil?
          return RecordingStudio::Recording.unscoped.where(id: scoped_recording.id) unless include_children?

          RecordingStudio::Recording.unscoped.where(
            "#{recordings_table}.id IN (#{scoped_recording_ids_sql(scoped_recording)})"
          )
        end

        def scoped_recording_ids_sql(scoped_recording)
          scoped_recording_id = connection.quote(scoped_recording.id)

          <<~SQL.squish
            WITH RECURSIVE scoped_tree AS (
              SELECT id
              FROM #{recordings_table}
              WHERE id = #{scoped_recording_id}

              UNION

              SELECT child.id
              FROM #{recordings_table} child
              INNER JOIN scoped_tree parent ON child.parent_recording_id = parent.id
              WHERE child.trashed_at IS NULL
            )
            SELECT id FROM scoped_tree
          SQL
        end

        def include_children?
          raw_value = context.params.key?(:include_children) ? context.params[:include_children] : context.params["include_children"]
          return true if raw_value.nil?

          ActiveModel::Type::Boolean.new.cast(raw_value)
        end

        def root_type_filter
          @root_type_filter ||= context.params[:root_type].presence || context.params["root_type"].presence
        end

        def root_recordings_for_type
          RecordingStudio::Recording.unscoped.where(parent_recording_id: nil, recordable_type: root_type_filter, trashed_at: nil)
        end

        def recordings_table
          RecordingStudio::Recording.table_name
        end

        def accesses_table
          RecordingStudio::Access.table_name
        end

        def connection
          RecordingStudio::Recording.connection
        end

        def expires_at_for(credential)
          return if credential.nil?
          return if credential.revoked_at.present?
          return if credential.expires_at.blank?
          return if credential.expires_at.past?

          credential.expires_at
        end

        def expires_text_for(credential)
          return "No credentials" if credential.nil?
          return "Revoked" if credential.revoked_at.present?
          return "Expired" if credential.expires_at.present? && credential.expires_at.past?
          return "Never" if credential.expires_at.blank?

          credential.expires_at.to_date.to_s
        end

        def credential_status_label(credential)
          return "No credentials" if credential.nil?
          return "Revoked" if credential.revoked_at.present?
          return "Expired" if credential.expires_at.present? && credential.expires_at.past?

          "Active"
        end

        def request_count_for(api_credential)
          request_counts_by_credential_id.fetch(api_credential.id, 0)
        end

        def last_requested_at_for(api_credential)
          last_requests_by_credential_id.fetch(api_credential.id, nil)
        end

        def request_counts_by_credential_id
          return {} unless RecordingStudioApi::ApiRequestLog.table_available?

          @request_counts_by_credential_id ||= RecordingStudioApi::ApiRequestLog
                                               .where(api_credential_id: api_credentials.map(&:id))
                                               .group(:api_credential_id)
                                               .count
        end

        def last_requests_by_credential_id
          return {} unless RecordingStudioApi::ApiRequestLog.table_available?

          @last_requests_by_credential_id ||= RecordingStudioApi::ApiRequestLog
                                              .where(api_credential_id: api_credentials.map(&:id))
                                              .group(:api_credential_id)
                                              .maximum(:occurred_at)
        end

        def access_point_recording_for(access_recording)
          access_recording.parent_recording || access_recording.root_recording
        end

        def access_point_label(recording)
          return "Unknown" if recording.nil?
          return recording.recordable_type.to_s.demodulize.underscore.humanize if recording.parent_recording_id.nil?

          recordable_identifier(recording.recordable)
        end

        def recordable_identifier(recordable)
          return "Unknown recordable" if recordable.nil?

          %i[name title email label slug identifier].each do |attribute|
            next unless recordable.respond_to?(attribute)

            value = recordable.public_send(attribute)
            return value if value.present?
          end

          "Unknown recordable"
        end
      end
    end
  end
end