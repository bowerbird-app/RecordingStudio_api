# frozen_string_literal: true

module RecordingStudioApi
  # Known billing denial codes. Each one renders as HTTP 402.
  # Core stores codes and does not define them. Hosts and gems add more
  # with `config.register_billing_code`.
  module BillingCodes
    BUILTIN = %i[
      paywall_locked
      plan_limit_reached
      meter_limit_reached
      seat_limit_reached
    ].freeze
    DETAIL_KEYS = %i[message feature limit fix_path fixable_by].freeze
    HTTP_STATUS = :payment_required
    CODE_FORMAT = /\A[a-z][a-z0-9_]*\z/

    class Registry
      def initialize(codes = BUILTIN)
        @statuses = {}
        Array(codes).each { |code| add(code) }
      end

      def add(code)
        normalized = self.class.normalize(code)
        @statuses[normalized] = HTTP_STATUS
        normalized
      end

      def include?(code)
        return false if code.nil?

        @statuses.key?(self.class.normalize(code))
      rescue ArgumentError
        false
      end

      def status_for(code)
        return unless include?(code)

        @statuses.fetch(self.class.normalize(code))
      end

      def codes
        @statuses.keys.dup.freeze
      end

      def self.normalize(code)
        name = case code
               when Symbol, String then code.to_s.strip
               else
                 raise ArgumentError, "billing code must be a Symbol or String"
               end
        raise ArgumentError, "billing code must be a lowercase identifier" unless CODE_FORMAT.match?(name)

        name.to_sym
      end
    end
  end

  # Mixed into Configuration so hosts register codes on `config`.
  module BillingCodeList
    def billing_codes
      @billing_codes ||= BillingCodes::Registry.new
    end

    def register_billing_code(code)
      billing_codes.add(code)
    end

    def billing_code?(code)
      billing_codes.include?(code)
    end

    def billing_codes=(codes)
      Array(codes).each { |code| register_billing_code(code) }
    end
  end
end
