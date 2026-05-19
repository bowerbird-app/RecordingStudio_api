# frozen_string_literal: true

module RecordingStudioApi
  class AccessibleRecordingScope
    def initialize(scope_recording:, access_recording:)
      @scope_recording = scope_recording
      @access_recording = access_recording
    end

    def relation
      RecordingStudio::Recording.unscoped.where("id IN (#{accessible_recording_ids_sql})")
    end

    private

    attr_reader :scope_recording, :access_recording

    def accessible_recording_ids_sql
      return "SELECT NULL::uuid WHERE FALSE" if scope_recording.nil? || access_role_rank.nil?

      @accessible_recording_ids_sql ||= begin
        recordings_table = RecordingStudio::Recording.table_name
        boundaries_table = RecordingStudio::AccessBoundary.table_name
        root_id = connection.quote(scope_recording.id)
        access_boundary_type = connection.quote("RecordingStudio::AccessBoundary")
        minimum_role_rank = connection.quote(access_role_rank)

        <<~SQL.squish
          WITH RECURSIVE
          scope_tree AS (
            SELECT id, 0 AS depth
            FROM #{recordings_table}
            WHERE id = #{root_id}

            UNION ALL

            SELECT child.id, parent.depth + 1
            FROM #{recordings_table} child
            INNER JOIN scope_tree parent ON child.parent_recording_id = parent.id
            WHERE child.trashed_at IS NULL
          ),
          blocked_roots AS (
            SELECT recording.id
            FROM scope_tree
            INNER JOIN #{recordings_table} recording ON recording.id = scope_tree.id
            INNER JOIN #{boundaries_table} boundary ON boundary.id = recording.recordable_id
            WHERE scope_tree.depth > 0
              AND recording.trashed_at IS NULL
              AND recording.recordable_type = #{access_boundary_type}
              AND boundary.minimum_role > #{minimum_role_rank}
          ),
          blocked_tree AS (
            SELECT id
            FROM blocked_roots

            UNION ALL

            SELECT child.id
            FROM #{recordings_table} child
            INNER JOIN blocked_tree parent ON child.parent_recording_id = parent.id
            WHERE child.trashed_at IS NULL
          )
          SELECT scope_tree.id
          FROM scope_tree
          LEFT JOIN blocked_tree ON blocked_tree.id = scope_tree.id
          WHERE blocked_tree.id IS NULL
        SQL
      end
    end

    def access_role_rank
      @access_role_rank ||= begin
        access = access_recording&.recordable
        return unless access.is_a?(RecordingStudio::Access)

        RecordingStudio::Access.roles[access.role]
      end
    end

    def connection
      RecordingStudio::Recording.connection
    end
  end
end
