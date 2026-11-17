# frozen_string_literal: true

module RecordingStudioApi
  # Recordings the owner can view under one grant anchor.
  #
  # A root anchor uses Accessible's fast path (`Recording.within`) when that
  # relation is not a parent walk. Every other anchor keeps the relation
  # `authorized_recording_ids` returns. Trashed rows stay out unless asked for.
  class VisibleRecordings
    def initialize(owner:, anchor:, grant_role:)
      @owner = owner
      @anchor = anchor
      @grant_role = grant_role
      @relations = {}
      @ids = {}
      @authorized_ids = :unset
    end

    def relation(include_trashed: false)
      @relations[include_trashed] ||= build_relation(include_trashed)
    end

    def recording_ids(include_trashed: false)
      @ids[include_trashed] ||= relation(include_trashed: include_trashed).pluck(:id)
    end

    private

    def build_relation(include_trashed)
      ids = authorized_ids
      return recordings.none if ids.nil?

      apply_kept(base_relation(ids), include_trashed)
    end

    def authorized_ids
      return @authorized_ids unless @authorized_ids.equal?(:unset)

      @authorized_ids = lookup_authorized_ids
    end

    def lookup_authorized_ids
      return if @owner.nil? || @anchor.nil?
      return unless view_role?

      RecordingStudioAccessible.authorized_recording_ids(actor: @owner, root: @anchor, role: :view)
    end

    def view_role?
      RecordingStudio::AccessRoles.satisfies?(role: @grant_role, minimum_role: :view)
    end

    def base_relation(ids)
      return recordings.within(@anchor) if root_fast_path?(ids)

      recordings.where(id: ids)
    end

    def root_fast_path?(ids)
      return false if @anchor.parent_recording_id.present?

      sql = ids.to_sql
      !sql.include?("WITH RECURSIVE") && !sql.include?("1=0") && sql.include?("root_recording_id")
    end

    def apply_kept(relation, include_trashed)
      return relation if include_trashed

      relation.where(RecordingStudio.kept_sql(relation.klass.table_name))
    end

    def recordings
      RecordingStudio::Recording.unscoped
    end
  end
end
