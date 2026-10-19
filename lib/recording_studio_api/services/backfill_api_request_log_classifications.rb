# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class BackfillApiRequestLogClassifications
      DEFAULT_BATCH_SIZE = 1_000

      class << self
        def call(batch_size: DEFAULT_BATCH_SIZE)
          new(batch_size: batch_size).call
        end
      end

      def initialize(batch_size:)
        @batch_size = [Integer(batch_size), 1].max
      end

      def call
        return 0 unless ApiRequestLog.table_available?

        total = 0
        loop do
          updated = process_batch
          break if updated.zero?

          total += updated
        end
        total
      end

      def process_batch
        return 0 unless ApiRequestLog.table_available?

        ids = pending_ids
        return 0 if ids.empty?

        table = ApiRequestLog.quoted_table_name
        bucket_sql = ApiRequestLogClassification.bucket_case_sql("logs.duration_ms")
        id_list = ids.map { |id| quote(id) }.join(", ")
        sql = <<~SQL.squish
          UPDATE #{table} AS logs
          SET
            arrived_at = COALESCE(logs.arrived_at, logs.created_at, logs.occurred_at),
            latency_bucket_ms = COALESCE(
              logs.latency_bucket_ms,
              CASE #{bucket_sql} END
            ),
            api_key = COALESCE(NULLIF(BTRIM(logs.api_key), ''), #{quote(ApiRequestLogClassification::DEFAULT_API_KEY)}),
            route_name = COALESCE(NULLIF(BTRIM(logs.route_name), ''), #{quote(ApiRequestLogClassification::DEFAULT_ROUTE_NAME)}),
            updated_at = CURRENT_TIMESTAMP
          WHERE logs.id IN (#{id_list})
        SQL

        ApiRequestLog.connection.update(sql)
      end

      private

      attr_reader :batch_size

      def pending_ids
        ApiRequestLog.unscoped
                     .where("arrived_at IS NULL OR latency_bucket_ms IS NULL OR api_key IS NULL OR BTRIM(api_key) = '' OR route_name IS NULL OR BTRIM(route_name) = ''")
                     .order(:occurred_at, :id)
                     .limit(batch_size)
                     .pluck(:id)
      end

      def quote(value)
        ApiRequestLog.connection.quote(value)
      end
    end
  end
end
