# frozen_string_literal: true

module RecordingStudioApi
  # One aggregate over the already authorized list scope, plus the grant
  # and the request that shapes the page. Used as the ETag and Last-Modified
  # for collection GETs. The aggregate changes when any recording in the
  # filtered scope is created, updated, or removed. The grant, filters, and
  # page cursor are part of the validator so two different pages do not share it.
  class CollectionFreshness
    def self.not_modified?(controller, freshness)
      return false if controller.nil?

      options = {
        etag: freshness.validator,
        public: false,
        cache_control: { private: true, must_revalidate: true }
      }
      last_modified = freshness.last_modified
      options[:last_modified] = last_modified if last_modified
      controller.fresh_when(**options)
      controller.request.fresh?(controller.response)
    end

    def initialize(relation:, grant_key:, representation:)
      @relation = relation
      @grant_key = grant_key
      @representation = representation
    end

    def validator
      [
        "collection-v1",
        stamp,
        grant_key,
        representation
      ]
    end

    def last_modified
      snapshot[:max_updated_at]
    end

    def total_count
      snapshot[:total_count]
    end

    private

    attr_reader :relation, :grant_key, :representation

    def stamp
      updated_at = snapshot[:max_updated_at]
      [updated_at.respond_to?(:utc) ? updated_at.utc.iso8601(6) : updated_at, snapshot[:total_count]]
    end

    def snapshot
      @snapshot ||= load_snapshot
    end

    def load_snapshot
      counted = relation.except(:order, :includes, :preload, :eager_load)
      table = counted.klass.arel_table
      count = if plain_relation?(counted)
                Arel.star.count
              else
                table[counted.klass.primary_key].count(true)
              end
      max_updated_at, total = counted.pick(table[:updated_at].maximum, count)
      {
        max_updated_at: max_updated_at,
        total_count: total.to_i
      }
    end

    def plain_relation?(counted)
      return false if counted.joins_values.any?
      return false if counted.left_outer_joins_values.any?
      return false if counted.distinct_value
      return false if counted.eager_load_values.any?
      return false if counted.includes_values.any? && counted.references_values.any?
      return false unless counted.from_clause.empty?

      true
    end
  end
end
