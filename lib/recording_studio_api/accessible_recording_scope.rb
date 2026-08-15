# frozen_string_literal: true

module RecordingStudioApi
  class AccessibleRecordingScope
    def initialize(scope_recording:, access_recording:, include_trashed: false)
      @scope_recording = scope_recording
      @access_recording = access_recording
      @include_trashed = include_trashed
    end

    # Prefer a SQL subquery so collection scans do not materialize every
    # descendant id into Ruby before filtering.
    def relation
      RecordingStudio::Recording.unscoped.where("id IN (#{accessible_recording_ids_sql})")
    end

    def recording_ids
      @recording_ids ||= connection.select_values(accessible_recording_ids_sql)
    end

    def include?(recording_id)
      return false if recording_id.blank?

      value = connection.select_value(
        "SELECT EXISTS(SELECT 1 FROM (#{accessible_recording_ids_sql}) AS accessible_ids WHERE id = #{connection.quote(recording_id)})"
      )
      ActiveRecord::Type::Boolean.new.cast(value)
    end

    private

    attr_reader :scope_recording, :access_recording, :include_trashed

    def accessible_recording_ids_sql
      return "SELECT NULL::uuid WHERE FALSE" if scope_recording.nil? || access_role_rank.nil?

      @accessible_recording_ids_sql ||= begin
        recordings_table = RecordingStudio::Recording.table_name
        root_id = connection.quote(scope_recording.id)
        trashed_filter = include_trashed ? "" : "WHERE child.trashed_at IS NULL"

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
            #{trashed_filter}
          )
          SELECT id
          FROM scope_tree
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
