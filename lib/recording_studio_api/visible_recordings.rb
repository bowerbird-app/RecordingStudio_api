# frozen_string_literal: true

module RecordingStudioApi
  # Defers `accessible_recordings` until a caller actually queries the relation.
  # Building that relation runs Accessible's subtree probe, so a list that
  # passes its own scope should not pay for a second unused one.
  class LazyRecordings < BasicObject
    def initialize(&block)
      @block = block
    end

    def respond_to?(*)
      true
    end

    def respond_to_missing?(*)
      true
    end

    def method_missing(...)
      __relation__.__send__(...)
    end

    def __relation__
      @__relation__ ||= @block.call
    end
  end

  # Recordings the owner can view under one grant anchor.
  #
  # `authorized_recordings` returns that set as a relation. Callers pass the
  # scope (a list passes its type and filters). Kept rows are applied unless
  # trashed rows were requested. Pagination then adds the keyset, order, and
  # limit. A root anchor stays on `Recording.within`. A nested anchor does not
  # walk the subtree into an id list before that limit.
  class VisibleRecordings
    def initialize(owner:, anchor:, grant_role:)
      @owner = owner
      @anchor = anchor
      @grant_role = grant_role
      @relations = {}
      @ids = {}
    end

    def relation(include_trashed: false, scope: nil)
      return build_relation(include_trashed, scope) unless scope.nil?

      @relations[include_trashed] ||= build_relation(include_trashed, nil)
    end

    def recording_ids(include_trashed: false)
      @ids[include_trashed] ||= relation(include_trashed: include_trashed).pluck(:id)
    end

    private

    def build_relation(include_trashed, scope)
      base = apply_kept(scope || recordings, include_trashed)
      return base.none unless viewable?

      RecordingStudioAccessible.authorized_recordings(
        actor: @owner,
        root: @anchor,
        scope: base,
        role: :view
      )
    end

    def viewable?
      !@owner.nil? && !@anchor.nil? && view_role?
    end

    def view_role?
      RecordingStudio::AccessRoles.satisfies?(role: @grant_role, minimum_role: :view)
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
