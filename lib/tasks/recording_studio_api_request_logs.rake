# frozen_string_literal: true

namespace :recording_studio_api do
  namespace :api_request_logs do
    desc "Backfill arrived_at, latency buckets, and blank API/route names in bounded batches"
    task backfill_classifications: :environment do
      batch_size = Integer(ENV.fetch("BATCH_SIZE", RecordingStudioApi::Services::BackfillApiRequestLogClassifications::DEFAULT_BATCH_SIZE))
      updated = RecordingStudioApi::Services::BackfillApiRequestLogClassifications.call(batch_size: batch_size)
      puts "Updated #{updated} API request log rows"
    end

    desc "Rebuild Logs daily request and latency summaries for FROM..TO (inclusive UTC days)"
    task backfill_summaries: :environment do
      from = Date.iso8601(ENV.fetch("FROM"))
      to = Date.iso8601(ENV.fetch("TO"))
      RecordingStudioApi::Services::RebuildApiRequestLogSummaries.backfill!(from: from, to: to)
      puts "Rebuilt API request summaries from #{from} to #{to}"
    end
  end
end
