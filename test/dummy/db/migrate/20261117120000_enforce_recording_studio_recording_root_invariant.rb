# frozen_string_literal: true

# This migration comes from recording_studio (originally 20261117120000).
class EnforceRecordingStudioRecordingRootInvariant < ActiveRecord::Migration[8.1]
  UNIQUE_INDEX = "index_rs_recordings_on_id_and_root"
  PARENT_ROOT_FK = "fk_rs_recordings_on_parent_and_root"
  PARENTLESS_CHECK = "chk_rs_recordings_parentless_own_root"
  # Parentless rows become their own root. Every other row takes the root of
  # its parentless ancestor. A cycle with no parentless row is left alone.
  REPAIR_ROOT_RECORDING_IDS_SQL = <<~SQL.squish.freeze
    WITH RECURSIVE rooted AS (
      SELECT id, id AS computed_root, ARRAY[id] AS path
      FROM recording_studio_recordings
      WHERE parent_recording_id IS NULL
      UNION ALL
      SELECT child.id, rooted.computed_root, rooted.path || child.id
      FROM recording_studio_recordings AS child
      INNER JOIN rooted ON child.parent_recording_id = rooted.id
      WHERE NOT (child.id = ANY (rooted.path))
    )
    UPDATE recording_studio_recordings AS recordings
    SET root_recording_id = rooted.computed_root
    FROM rooted
    WHERE recordings.id = rooted.id
      AND recordings.root_recording_id IS DISTINCT FROM rooted.computed_root
  SQL
  ROOT_VIOLATION_COUNT_SQL = <<~SQL.squish.freeze
    SELECT COUNT(*)
    FROM recording_studio_recordings AS recordings
    LEFT JOIN recording_studio_recordings AS parents
      ON parents.id = recordings.parent_recording_id
    WHERE recordings.root_recording_id IS NULL
       OR (
         recordings.parent_recording_id IS NULL
         AND recordings.root_recording_id IS DISTINCT FROM recordings.id
       )
       OR (
         recordings.parent_recording_id IS NOT NULL
         AND recordings.root_recording_id IS DISTINCT FROM parents.root_recording_id
       )
  SQL

  def up
    repair_root_recording_ids
    assert_roots_repaired!
    change_column_null :recording_studio_recordings, :root_recording_id, false
    add_root_identity_index
    add_parent_root_foreign_key
    add_parentless_check
  end

  def down
    remove_check_constraint :recording_studio_recordings, name: PARENTLESS_CHECK
    remove_foreign_key :recording_studio_recordings, name: PARENT_ROOT_FK
    remove_index :recording_studio_recordings, name: UNIQUE_INDEX
    change_column_null :recording_studio_recordings, :root_recording_id, true
  end

  private

  def repair_root_recording_ids
    execute REPAIR_ROOT_RECORDING_IDS_SQL
  end

  def assert_roots_repaired!
    count = select_value(ROOT_VIOLATION_COUNT_SQL).to_i
    return if count.zero?

    raise "#{count} recording_studio_recordings rows still break root_recording_id. " \
          "A cycle with no parentless recording cannot be repaired."
  end

  def add_root_identity_index
    add_index :recording_studio_recordings, %i[id root_recording_id],
              unique: true,
              name: UNIQUE_INDEX,
              if_not_exists: true
  end

  # ON DELETE / ON UPDATE stay NO ACTION (the default). RESTRICT cannot be
  # deferred, and CASCADE would hide a move that forgot its descendants.
  # MATCH SIMPLE skips the check when parent_recording_id is null.
  def add_parent_root_foreign_key
    add_foreign_key :recording_studio_recordings, :recording_studio_recordings,
                    column: %i[parent_recording_id root_recording_id],
                    primary_key: %i[id root_recording_id],
                    deferrable: :deferred,
                    name: PARENT_ROOT_FK,
                    if_not_exists: true,
                    validate: true
  end

  def add_parentless_check
    add_check_constraint :recording_studio_recordings,
                         "parent_recording_id IS NOT NULL OR root_recording_id = id",
                         name: PARENTLESS_CHECK,
                         if_not_exists: true,
                         validate: true
  end
end
