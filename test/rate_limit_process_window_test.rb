# frozen_string_literal: true

require "test_helper"

class RateLimitProcessWindowTest < ActiveSupport::TestCase
  setup do
    @window = RecordingStudioApi::RateLimit::ProcessWindow
    @window.reset!
  end

  teardown do
    @window.reset!
  end

  test "counts inside one window and starts again after the deadline" do
    key = "recording_studio_api:api_read:credential:9:1"

    first, = @window.increment(key, 30)
    _second, retry_after = @window.increment(key, 30)

    assert_equal 1, first
    assert_operator retry_after, :<=, 30
    assert_operator retry_after, :>, 0

    travel 31.seconds do
      restarted, = @window.increment(key, 30)
      assert_equal 1, restarted
    end
  end

  test "drops the oldest key once the window reaches its entry cap" do
    @window::MAX_ENTRIES.times { |index| @window.increment("credential:#{index}", 120) }

    assert_equal @window::MAX_ENTRIES, @window.entry_count

    @window.increment("credential:overflow", 120)

    assert_equal @window::MAX_ENTRIES, @window.entry_count
    count, = @window.increment("credential:overflow", 120)
    assert_equal 2, count
  end

  test "concurrent increments keep every hit" do
    key = "recording_studio_api:api_write:credential:3:8"
    threads = Array.new(8) do
      Thread.new { 25.times { @window.increment(key, 60) } }
    end
    threads.each(&:join)

    count, = @window.increment(key, 60)
    assert_equal 201, count
  end
end
