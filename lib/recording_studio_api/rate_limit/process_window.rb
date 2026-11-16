# frozen_string_literal: true

require "active_support/cache"

module RecordingStudioApi
  class RateLimit
    # Per-process fixed window for api_read and api_write when Redis cannot count.
    # The first hit in a window sets the deadline. Later hits do not move it.
    # MemoryStore holds the counts and drops expired entries. The deadline map
    # caps how many keys this process keeps.
    class ProcessWindow
      MAX_BYTES = 8 * 1024 * 1024
      MAX_ENTRIES = 10_000

      class << self
        def increment(key, period)
          instance.increment(key, period)
        end

        def entry_count
          instance.entry_count
        end

        def reset!
          mutex.synchronize { @instance = nil }
        end

        private

        def instance
          mutex.synchronize { @instance ||= new }
        end

        def mutex
          @mutex ||= Mutex.new
        end
      end

      def initialize
        @store = ActiveSupport::Cache::MemoryStore.new(size: MAX_BYTES)
        @deadlines = {}
        @mutex = Mutex.new
      end

      def entry_count
        @mutex.synchronize { @deadlines.size }
      end

      # Returns [count, retry_after_seconds].
      def increment(key, period)
        seconds = period.to_i
        raise ArgumentError, "period must be positive" unless seconds.positive?

        @mutex.synchronize do
          now = Time.current.to_i
          prune(now)
          expires_at = @deadlines[key]
          if expires_at.nil? || expires_at <= now
            make_room(key)
            @deadlines[key] = now + seconds
            @store.write(key, 1, expires_in: seconds)
            return [1, seconds]
          end

          count = @store.read(key).to_i + 1
          remaining = [expires_at - now, 1].max
          @store.write(key, count, expires_in: remaining)
          [count, remaining]
        end
      end

      private

      def prune(now)
        @deadlines.delete_if do |key, expires_at|
          next false if expires_at > now

          @store.delete(key)
          true
        end
      end

      def make_room(key)
        return if @deadlines.key?(key)

        while @deadlines.size >= MAX_ENTRIES
          oldest_key, = @deadlines.min_by { |_stored_key, expires_at| expires_at }
          break if oldest_key.nil?

          @store.delete(oldest_key)
          @deadlines.delete(oldest_key)
        end
      end
    end
  end
end
