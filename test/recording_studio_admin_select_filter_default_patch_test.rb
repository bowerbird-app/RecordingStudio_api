# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "test_helper"
require "recording_studio_api/admin"

class RecordingStudioAdminSelectFilterDefaultPatchTest < Minitest::Test
  def test_select_filter_uses_default_when_param_is_missing
    filter = status_filter

    assert_equal "active", filter.normalize({})
  end

  def test_select_filter_prefers_explicit_param_over_default
    filter = status_filter

    assert_equal "revoked", filter.normalize(status: "revoked")
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