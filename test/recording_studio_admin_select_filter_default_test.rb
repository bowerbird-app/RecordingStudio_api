# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "test_helper"
require "recording_studio_api/admin"

class RecordingStudioAdminSelectFilterDefaultTest < Minitest::Test
  def test_select_filter_uses_default_when_param_is_missing
    assert_equal "active", status_filter.normalize({})
  end

  def test_select_filter_prefers_explicit_param_over_default
    assert_equal "revoked", status_filter.normalize(status: "revoked")
  end

  def test_blank_select_param_means_all
    assert_nil status_filter.normalize(status: "")
  end

  def test_api_does_not_ship_a_select_filter_patch
    root = File.expand_path("..", __dir__)

    refute File.exist?(File.join(root, "lib/recording_studio_api/admin/select_filter_default_patch.rb"))
    refute_includes File.read(File.join(root, "lib/recording_studio_api/admin.rb")), "select_filter_default_patch"
  end

  private

  def status_filter
    definition = RecordingStudioAdmin::Definitions::FilterDefinition.new(
      :status,
      :select,
      values: %w[active expired revoked missing],
      default: :active
    )

    RecordingStudioAdmin::Filters::SelectFilter.new(definition)
  end
end
