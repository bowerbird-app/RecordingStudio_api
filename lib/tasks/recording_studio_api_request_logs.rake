# frozen_string_literal: true

namespace :recording_studio_api do
  namespace :api_request_logs do
    desc "Backfill arrived_at, latency buckets, and blank API/route names in bounded batches"
    task backfill_classifications: :environment do
      batch_size = Integer(ENV.fetch("BATCH_SIZE", RecordingStudioApi::Services::BackfillApiRequestLogClassifications::DEFAULT_BATCH_SIZE))
      updated = RecordingStudioApi::Services::BackfillApiRequestLogClassifications.call(batch_size: batch_size)
      puts "Updated #{updated} API request log rows"
    end
  end
end
