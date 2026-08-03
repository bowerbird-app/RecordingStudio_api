# frozen_string_literal: true

require "digest"

namespace :recording_studio_api do
  desc "Verify the vendored Scalar JavaScript bundle checksum"
  task verify_scalar_asset: :environment do
    asset_path = RecordingStudioApi::Engine.root.join(
      "app/assets/javascripts",
      RecordingStudioApi::ScalarAsset::LOGICAL_PATH
    )
    actual_checksum = Digest::SHA256.file(asset_path).hexdigest
    expected_checksum = RecordingStudioApi::ScalarAsset::SHA256

    abort "Scalar asset checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}" unless actual_checksum == expected_checksum

    puts "Verified Scalar #{RecordingStudioApi::ScalarAsset::VERSION} (SHA-256 #{actual_checksum})"
  end
end