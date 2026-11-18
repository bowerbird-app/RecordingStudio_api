# frozen_string_literal: true

require "time"
require "bigdecimal"

module RecordingStudioApi
  module Services
    class PaginateResourceCollection < RecordingStudio::Services::BaseService
      Page = Data.define(:rows, :meta) do
        def response_body
          yield rows, meta
        end
      end

      TotalCount = Data.define(:total_count) do
        def response_body
          { total_count: total_count }
        end
      end

      SUPPORTED_ORDERS = %w[asc desc].freeze
      PAGINATION_TOKEN_VERSION = 2
      PAGINATION_TOKEN_PURPOSE = "recording_studio_api.pagination.v2"
      COUNT_TRUE = ["true", "1", true].freeze
      COUNT_FALSE = ["false", "0", "", nil, false].freeze

      def self.flag(value, name:)
        normalized = value.is_a?(String) ? value.strip.downcase : value
        return true if COUNT_TRUE.include?(normalized)
        return false if COUNT_FALSE.include?(normalized)

        raise RecordingStudioApi::InvalidActionInputError, "#{name} must be true or false"
      end

      def initialize(relation:, resource:, recordable_type:, limit:, pagination_token:, sort:, order:, api: :public, scope_key: nil, count: nil, include_total: nil)
        @relation = relation
        @resource = resource.to_s
        @recordable_type = recordable_type.to_s
        @limit = limit
        @pagination_token = pagination_token
        @sort = sort
        @order = order
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
        @scope_key = scope_key.to_s.presence
        raise RecordingStudioApi::AuthorizationError, RecordingStudioApi::AuthorizationError::MISSING_REQUEST_PRINCIPAL if @scope_key.nil?

        @count = count
        @include_total = include_total
      end

      private

      def normalize_page!
        sortable_context = resolve_sortable_context
        normalized_order = normalize_order
        normalized_sort = normalize_sort(sortable_context)
        normalized_limit = normalize_limit
        decode_pagination_token(normalized_sort, normalized_order)

        {
          sortable_context: sortable_context,
          sort: normalized_sort,
          order: normalized_order,
          limit: normalized_limit
        }
      end

      attr_reader :relation, :resource, :recordable_type, :limit, :pagination_token, :sort, :order, :api_key, :scope_key, :count,
                  :include_total

      def perform
        include_total?
        return success(TotalCount.new(total_count: total_count)) if count_only?

        page = normalize_page!
        sortable_context = page.fetch(:sortable_context)
        normalized_order = page.fetch(:order)
        normalized_sort = page.fetch(:sort)
        normalized_limit = page.fetch(:limit)
        pagination_token_payload = decode_pagination_token(normalized_sort, normalized_order)

        paged_relation = ordered_relation(normalized_sort, normalized_order, sortable_context)
        if pagination_token_payload
          paged_relation = apply_pagination_token(paged_relation, pagination_token_payload, normalized_sort, normalized_order, sortable_context)
        end

        rows = paged_relation.limit(normalized_limit + 1).to_a
        has_more = rows.length > normalized_limit
        items = has_more ? rows.first(normalized_limit) : rows
        preload_page_recordables(items)
        meta = {
          limit: normalized_limit,
          sort: normalized_sort,
          order: normalized_order,
          has_more: has_more,
          next_pagination_token: next_pagination_token_for(
            items, normalized_sort, normalized_order, has_more, sortable_context, pagination_token_payload
          )
        }
        meta[:total_count] = total_count if include_total?

        success(Page.new(rows: items, meta: meta))
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError
        failure(RecordingStudioApi::InvalidPaginationTokenError.new("Invalid pagination token"))
      end

      def count_only?
        self.class.flag(count, name: "count")
      end

      def include_total?
        self.class.flag(include_total, name: "include_total")
      end

      def total_count
        @total_count ||= begin
          counted = relation.unscope(:order)
          if plain_count?(counted)
            counted.count
          else
            counted.distinct.count(counted.klass.arel_table[counted.klass.primary_key])
          end
        end
      end

      def plain_count?(counted)
        return false if counted.joins_values.any?
        return false if counted.left_outer_joins_values.any?
        return false if counted.distinct_value
        return false if counted.eager_load_values.any?
        return false if counted.includes_values.any? && counted.references_values.any?
        return false unless counted.from_clause.empty?

        true
      end

      def preload_page_recordables(items)
        return if items.empty?

        ActiveRecord::Associations::Preloader.new(records: items, associations: :recordable).call
      end

      def ordered_relation(normalized_sort, normalized_order, sortable_context)
        if normalized_sort == DefaultListOrder::CALLABLE_SORT
          return default_order.apply_callable(relation)
        end

        recording_table = relation.klass.arel_table
        if recording_column_sort?(normalized_sort)
          return relation.reorder(normalized_sort => normalized_order, id: normalized_order)
        end

        ensure_default_column!(normalized_sort, sortable_context)
        recordable_table_alias = Arel::Table.new(sortable_context.fetch(:recordable_table_alias))
        joined_relation = relation.joins(recordable_sort_join_sql(sortable_context))
        joined_relation.reorder(recordable_table_alias[normalized_sort].send(normalized_order), recording_table[:id].send(normalized_order))
      end

      def apply_pagination_token(current_relation, pagination_token_payload, normalized_sort, normalized_order, sortable_context)
        if normalized_sort == DefaultListOrder::CALLABLE_SORT
          return current_relation.offset(callable_offset(pagination_token_payload))
        end

        last_sort_value = cast_sort_value(pagination_token_payload.fetch("last_sort_value"), normalized_sort, sortable_context)
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

      def next_pagination_token_for(items, normalized_sort, normalized_order, has_more, sortable_context, pagination_token_payload)
        return nil unless has_more

        last = items.last
        payload = {
          "v" => PAGINATION_TOKEN_VERSION,
          "api_key" => api_key,
          "scope" => scope_key,
          "resource" => resource,
          "sort" => normalized_sort,
          "order" => normalized_order,
          "last_id" => last.id
        }
        if normalized_sort == DefaultListOrder::CALLABLE_SORT
          payload["last_sort_value"] = last.id
          payload["offset"] = callable_offset_base(pagination_token_payload) + items.length
        else
          payload["last_sort_value"] = token_sort_value(last, normalized_sort, sortable_context)
        end

        encode_pagination_token(payload)
      end

      def normalize_sort(sortable_context)
        if sort.to_s == DefaultListOrder::CALLABLE_SORT
          return DefaultListOrder::CALLABLE_SORT if default_order&.callable?

          raise RecordingStudioApi::InvalidPaginationTokenError,
                "sort must be one of: #{sortable_context.fetch(:allowed_sort_attributes).join(', ')}"
        end

        if explicit_sort?
          normalized = sort.to_s
          allowed = sortable_context.fetch(:allowed_sort_attributes)
          unless allowed.include?(normalized)
            raise RecordingStudioApi::InvalidPaginationTokenError,
                  "sort must be one of: #{allowed.join(', ')}"
          end

          return normalized
        end

        return default_order.column if default_order&.column?
        return DefaultListOrder::CALLABLE_SORT if default_order&.callable?

        "created_at"
      end

      def normalize_order
        supplied = order.to_s.downcase
        active_default = explicit_sort? ? nil : default_order

        if supplied.blank?
          return active_default.direction if active_default&.column?

          return "asc"
        end

        unless SUPPORTED_ORDERS.include?(supplied)
          raise RecordingStudioApi::InvalidPaginationTokenError, "order must be asc or desc"
        end
        if active_default&.callable?
          raise RecordingStudioApi::InvalidPaginationTokenError,
                "order requires sort when this resource uses a computed default order"
        end

        supplied
      end

      def normalize_limit
        default_limit = RecordingStudioApi.configuration.pagination_default_limit.to_i
        max_limit = RecordingStudioApi.configuration.pagination_max_limit.to_i

        resolved_default = default_limit.positive? ? default_limit : 50
        resolved_max = max_limit.positive? ? max_limit : 100

        return resolved_default if omitted_limit?

        requested = parsed_limit
        unless requested&.positive?
          raise RecordingStudioApi::InvalidActionInputError,
                "limit must be a whole number from 1 to #{resolved_max}"
        end

        [requested, resolved_max].min
      end

      def omitted_limit?
        limit.nil? || (limit.is_a?(String) && limit.strip.empty?)
      end

      def parsed_limit
        return limit if limit.is_a?(Integer)
        return Integer(limit.strip, 10) if limit.is_a?(String) && /\A[+-]?\d+\z/.match?(limit.strip)

        nil
      end

      def decode_pagination_token(normalized_sort, normalized_order)
        return nil if pagination_token.blank?

        payload = pagination_token_verifier.verify(pagination_token.to_s, purpose: PAGINATION_TOKEN_PURPOSE)
        raise RecordingStudioApi::InvalidPaginationTokenError, "Invalid pagination token" unless payload.is_a?(Hash)
        raise RecordingStudioApi::InvalidPaginationTokenError, "Invalid pagination token" unless payload.fetch("v") == PAGINATION_TOKEN_VERSION
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested API" unless payload.fetch("api_key") == api_key
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match authenticated client" unless payload.fetch("scope") == scope_key
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested resource" unless payload.fetch("resource") == resource
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested sort" unless payload.fetch("sort") == normalized_sort
        raise RecordingStudioApi::InvalidPaginationTokenError, "Pagination token does not match requested order" unless payload.fetch("order") == normalized_order

        payload
      end

      def encode_pagination_token(payload)
        pagination_token_verifier.generate(payload, purpose: PAGINATION_TOKEN_PURPOSE)
      end

      def pagination_token_verifier
        Rails.application.message_verifier(PAGINATION_TOKEN_PURPOSE)
      end

      def hook_subject
        copy = dup
        copy.remove_instance_variable(:@pagination_token) if copy.instance_variable_defined?(:@pagination_token)
        copy
      end

      def service_args
        {
          resource: resource,
          recordable_type: recordable_type,
          pagination_token_present: pagination_token.present?,
          sort: sort,
          limit: limit,
          order: order,
          count: count,
          include_total: include_total
        }
      end

      def resolve_sortable_context
        recordable_class = recordable_type.safe_constantize
        if recordable_class.nil?
          raise RecordingStudioApi::InvalidPaginationTokenError,
                "Unknown API resource #{resource}"
        end

        recordable_table_name = recordable_class.table_name
        allowed_sort_attributes = RecordingStudioApi.sortable_attributes_for(recordable_type, api: api_key).select do |attribute|
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
        if recording_column_sort?(normalized_sort)
          return relation.klass.arel_table[normalized_sort]
        end

        Arel::Table.new(sortable_context.fetch(:recordable_table_alias))[normalized_sort]
      end

      def token_sort_value(recording, normalized_sort, sortable_context)
        value = if recording_column_sort?(normalized_sort)
                  recording.public_send(normalized_sort)
                else
                  recording.recordable.public_send(normalized_sort)
                end

        serialize_sort_value(value, normalized_sort, sortable_context)
      end

      def serialize_sort_value(value, normalized_sort, sortable_context)
        return value&.utc&.iso8601(6) if sort_type(normalized_sort, sortable_context).in?([:datetime, :time])

        value
      end

      def cast_sort_value(value, normalized_sort, sortable_context)
        type = sort_type(normalized_sort, sortable_context)

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
        if recording_column_sort?(attribute)
          return relation.klass.columns_hash.fetch(attribute).type
        end

        sortable_context.fetch(:sort_type_by_attribute).fetch(attribute, :string)
      end

      def default_order
        RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)&.default_order
      end

      def explicit_sort?
        value = sort.to_s
        value.present? && value != DefaultListOrder::CALLABLE_SORT
      end

      def recording_column_sort?(normalized_sort)
        return true if normalized_sort == "created_at"
        return false if explicit_sort?

        list_order = default_order
        list_order&.column? && list_order.column == normalized_sort && list_order.recording_column?(relation.klass)
      end

      def ensure_default_column!(normalized_sort, sortable_context)
        list_order = default_order
        return unless list_order&.column? && list_order.column == normalized_sort && !explicit_sort?

        list_order.ensure_column!(sortable_context.fetch(:recordable_class), relation.klass)
      end

      def callable_offset(payload)
        offset = payload.fetch("offset")
        raise RecordingStudioApi::InvalidPaginationTokenError, "Invalid pagination token" unless offset.is_a?(Integer) && offset >= 0

        offset
      end

      def callable_offset_base(payload)
        return 0 if payload.nil?

        callable_offset(payload)
      end
    end
  end
end
