# frozen_string_literal: true

require "digest"
require "test_helper"

class ScalarAssetTest < ActiveSupport::TestCase
  test "vendored Scalar bundle matches pinned metadata" do
    asset_path = RecordingStudioApi::Engine.root.join(
      "app/assets/javascripts",
      RecordingStudioApi::ScalarAsset::LOGICAL_PATH
    )

    assert asset_path.file?
    assert_equal "1.64.0", RecordingStudioApi::ScalarAsset::VERSION
    assert_equal "MIT", RecordingStudioApi::ScalarAsset::LICENSE
    assert_equal RecordingStudioApi::ScalarAsset::SHA256, Digest::SHA256.file(asset_path).hexdigest
  end

  test "vendored Scalar asset is explicitly precompiled" do
    initializer = RecordingStudioApi::Engine.initializers.find do |candidate|
      candidate.name == "recording_studio_api.assets"
    end
    app = Struct.new(:config).new(Struct.new(:assets).new(Struct.new(:precompile).new([])))

    assert initializer
    initializer.run(app)
    assert_includes app.config.assets.precompile, RecordingStudioApi::ScalarAsset::LOGICAL_PATH
  end
end