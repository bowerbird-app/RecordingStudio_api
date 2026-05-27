# frozen_string_literal: true

require "base64"
require "json"
require "time"
require "bigdecimal"

module RecordingStudioApi
  module Services
    class PaginateResourceCollection < BaseService
      SUPPORTED_ORDERS = %w[asc desc].freeze
      PAGINATION_TOKEN_VERSION = 1

      def initialize(relation:, resource:, recordable_type:, limit:, pagination_token:, sort:, order:)
        @relation = relation
        @resource = resource.to_s
        @recordable_type = recordable_type.to_s
        @limit = limit
        @pagination_token = pagination_token
        @sort = sort
        @order = order
      end

      private

      attr_reader :relation, :resource, :recordable_type, :limit, :pagination_token, :sort, :order

      def perform
        sortable_context = resolve_sortable_context
        normalized_order = normalize_order
        normalized_sort = normalize_sort(sortable_context)
        normalized_limit = normalize_limit
        pagination_token_payload = decode_pagination_token(normalized_sort, normalized_order)

        paged_relation = ordered_relation(normalized_sort, normalized_order, sortable_context)
        if pagination_token_payload
          paged_relation = apply_pagination_token(paged_relation, pagination_token_payload, normalized_sort, normalized_order, sortable_context)
        end

        rows = paged_relation.limit(normalized_limit + 1).to_a
        has_more = rows.length > normalized_limit
        items = has_more ? rows.first(normalized_limit) : rows

        success(
          {
            rows: items,
            meta: {
              limit: normalized_limit,
              sort: normalized_sort,
              order: normalized_order,
              has_more: has_more,
              next_pagination_token: next_pagination_token_for(items, normalized_sort, normalized_order, has_more, sortable_context)
            }
          }
        )
      rescue ArgumentError, TypeError, JSON::ParserError
        failure(RecordingStudioApi::InvalidPaginationTokenError.new("Invalid pagination token"))
      end

      def ordered_relation(normalized_sort, normalized_order, sortable_context)
        recording_table = relation.klass.arel_table

        if normalized_sort == "created_at"
          return relation.reorder(created_at: normalized_order, id: normalized_order)
        end

        recordable_table_alias = Arel::Table.new(sortable_context.fetch(:recordable_table_alias))
        joined_relation = relation.joins(recordable_sort_join_sql(sortable_context))
        joined_relation.reorder(recordable_table_alias[normalized_sort].send(normalized_order), recording_table[:id].send(normalized_order))
      end

      def apply_pagination_token(current_relation, pagination_token_payload, normalized_sort, normalized_order, sortable_context)
        last_sort_value = cast_sort_value(pagination_token_payload.fetch("last_sort_value"), sortable_context)
        id = pagination_token_payload.fetch("last_id")
        table = current_relation.klass.arel_table
        sort_column = sort_column_for(normalized_sort, sortable_context)

        comparison = if normalized_order == "asc"
                       sort_column.gt(last_sort_value)
                                  .or(sort_column.eq(last_sort_value).and(table[:id].gt(id)))
                     else
                       sort_column.lt(last_sort_value)
                                  .or(sort_column.eq(last_sort_value).and(table[:id].lt(id)))
                     end

        current_relation.where(comparison)
      end

      def next_pagination_token_for(items, normalized_sort, normalized_order, has_more, sortable_context)
        return nil unless has_more

        last = items.last
        encode_pagination_token(
          {
            "v" => PAGINATION_TOKEN_VERSION,
            "resource" => resource,
            "sort" => normalized_sort,
            "order" => normalized_order,
            "last_sort_value" => token_sort_value(last, normalized_sort, sortable_context),
            "last_id" => last.id
          }
        )
      end

      def normalize_sort(sortable_context)
        normalized = sort.to_s.presence || "created_at"
        allowed = sortable_context.fetch(:allowed_sort_attributes)

        unless allowed.include?(normalized)
          raise RecordingStudioApi::InvalidPaginationTokenError,
                "sort must be one of: #{allowed.join(', ')}"
        end

        normalized
      end

      def normalize_order
        normalized = order.to_s.downcase
        normalized = "asc" if normalized.blank?
        raise RecordingStudioApi::InvalidPaginationTokenError, "order must be asc or desc" unless SUPPORTED_ORDERS.include?(normalized)

        normalized
      end

      def normalize_limit
        default_limit = RecordingStudioApi.configuration.pagination_default_limit.to_i
        max_limit = RecordingStudioApi.configuration.pagination_max_limit.to_i

        resolved_default = default_limit.positive? ? default_limit : 50
        resolved_max = max_limit.positive? ? max_limit : 100

        requested = limit.to_i
        requested = resolved_default if requested <= 0

        [requested, resolved_max].min
      end

      def decode_pagination_token(normalized_sort, normalized_order)
        return nil if pagination_token.blank?

        payload = JSON.parse(Base64.urlsafe_decode64(pagination_token.to_s))
        raise RecordingStudioApi::InvalidPaginationTokenError, "Invalid pagination token" unless payload.is_a?(Hash)
        raise RecordingStudioApi::InvalidPaginationTokenError, "Invalid pagination token" unless payload.fetch("v") == PAGINATION_TOKEN_VERSION
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested resource" unless payload.fetch("resource") == resource
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested sort" unless payload.fetch("sort") == normalized_sort
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested order" unless payload.fetch("order") == normalized_order

        payload
      end

      def encode_pagination_token(payload)
        Base64.urlsafe_encode64(payload.to_json)
      end

      def service_args
        {
          resource: resource,
          recordable_type: recordable_type,
          pagination_token_present: pagination_token.present?,
          sort: sort,
          limit: limit,
          order: order
        }
      end

      def resolve_sortable_context
        recordable_class = recordable_type.safe_constantize
        if recordable_class.nil?
          raise RecordingStudioApi::InvalidPaginationTokenError,
                "Unknown API resource #{resource}"
        end

        recordable_table_name = recordable_class.table_name
        allowed_sort_attributes = RecordingStudioApi.sortable_attributes_for(recordable_type).select do |attribute|
          attribute == "created_at" || recordable_class.column_names.include?(attribute)
        end

        {
          recordable_class: recordable_class,
          recordable_table_name: recordable_table_name,
          recordable_table_alias: "recordable_sort_#{recordable_table_name}",
          allowed_sort_attributes: allowed_sort_attributes,
          sort_type_by_attribute: sort_type_by_attribute(recordable_class)
        }
      end

      def sort_type_by_attribute(recordable_class)
        recordable_class.columns_hash.transform_values(&:type)
      end

      def recordable_sort_join_sql(sortable_context)
        recordings_table_name = relation.klass.table_name
        table_name = sortable_context.fetch(:recordable_table_name)
        table_alias = sortable_context.fetch(:recordable_table_alias)
        quoted_recordable_type = relation.connection.quote(recordable_type)

        <<~SQL.squish
          INNER JOIN #{table_name} #{table_alias}
            ON #{table_alias}.id = #{recordings_table_name}.recordable_id
           AND #{recordings_table_name}.recordable_type = #{quoted_recordable_type}
        SQL
      end

      def sort_column_for(normalized_sort, sortable_context)
        return relation.klass.arel_table[:created_at] if normalized_sort == "created_at"

        Arel::Table.new(sortable_context.fetch(:recordable_table_alias))[normalized_sort]
      end

      def token_sort_value(recording, normalized_sort, sortable_context)
        value = if normalized_sort == "created_at"
                  recording.created_at
                else
                  recording.recordable.public_send(normalized_sort)
                end

        serialize_sort_value(value, normalized_sort, sortable_context)
      end

      def serialize_sort_value(value, normalized_sort, sortable_context)
        return value&.utc&.iso8601(6) if sort_type(normalized_sort, sortable_context).in?([:datetime, :time])

        value
      end

      def cast_sort_value(value, sortable_context)
        attribute = sort.to_s.presence || "created_at"
        type = sort_type(attribute, sortable_context)

        case type
        when :integer
          value.to_i
        when :float
          value.to_f
        when :decimal
          BigDecimal(value.to_s)
        when :datetime, :time
          Time.iso8601(value.to_s)
        when :boolean
          ActiveModel::Type::Boolean.new.cast(value)
        else
          value.to_s
        end
      end

      def sort_type(attribute, sortable_context)
        return :datetime if attribute == "created_at"

        sortable_context.fetch(:sort_type_by_attribute).fetch(attribute, :string)
      end
    end
  end
end
