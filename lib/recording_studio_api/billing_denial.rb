# frozen_string_literal: true

require_relative "billing_codes"

module RecordingStudioApi
  # Turns a core denial into the public 402 envelope.
  #
  # A denial is a denied `RecordingStudio::GateDecision` that carries a code,
  # or a raised error that `is_a?(RecordingStudio::Denial)`. Nothing else.
  # `Stripe::StripeError#code` is not a denial.
  module BillingDenial
    DEFAULT_MESSAGE = "Payment required"
    MESSAGE_LIMIT = 500
    FIELD_LIMIT = 100
    # One leading slash, then only unreserved path characters. Percent-encoding,
    # backslash, and control characters fail the class and the path is dropped.
    FIX_PATH = %r{\A/(?!/)[A-Za-z0-9._~/?=&-]*\z}
    STRIPE_ID = /\b(?:cus|sub|price|prod|pi|in|si|acct|ch|pm|seti|evt)_[A-Za-z0-9]+/

    module_function

    def interpret(source)
      if source.is_a?(RecordingStudio::GateDecision)
        interpret_decision(source)
      elsif source.is_a?(RecordingStudio::Denial)
        interpret_error(source)
      end
    end

    def interpret_decision(decision)
      return unless decision.denied?

      publish(decision.code, decision.details)
    end

    def interpret_error(error)
      publish(denial_code(error), denial_details(error))
    end

    def publish(code, details)
      notice_unknown(code)
      return unless known?(code)

      copied = public_details(details)
      {
        code: code.to_s,
        message: message_for(copied),
        details: copied,
        status: BillingCodes::HTTP_STATUS
      }
    end

    def known?(code)
      RecordingStudioApi.configuration.billing_code?(code)
    end

    def denial_code(error)
      RecordingStudio::Denial.instance_method(:code).bind_call(error)
    end

    def denial_details(error)
      RecordingStudio::Denial.instance_method(:details).bind_call(error)
    end

    def notice_unknown(code)
      return if code.nil? || known?(code)
      return unless development?

      Rails.logger&.warn(
        "[RecordingStudioApi] Unknown billing denial code #{code.inspect}. " \
        "Register it with config.register_billing_code before it can return 402."
      )
    end

    def development?
      defined?(Rails) && Rails.respond_to?(:env) && Rails.env.development?
    end

    def message_for(details)
      text = details[:message]
      return text if text.is_a?(String)

      DEFAULT_MESSAGE
    end

    def public_details(details)
      return {} unless details.is_a?(Hash)

      BillingCodes::DETAIL_KEYS.each_with_object({}) do |key, output|
        next unless details.key?(key)

        value = public_value(key, details[key])
        output[key] = value unless value.nil?
      end
    end

    def public_value(key, value)
      case key
      when :message then bounded_text(value, MESSAGE_LIMIT)
      when :feature, :fixable_by then bounded_text(value, FIELD_LIMIT)
      when :limit then integer_limit(value)
      when :fix_path then relative_fix_path(value)
      end
    end

    def bounded_text(value, limit)
      text = text_value(value)
      return if text.nil? || text.empty?
      return if stripe_id?(text)

      text[0, limit]
    end

    def text_value(value)
      case value
      when String then value
      when Symbol, Integer, true, false then value.to_s
      when Float then value.to_s if value.finite?
      end
    end

    def integer_limit(value)
      value if value.is_a?(Integer)
    end

    def relative_fix_path(value)
      path = text_value(value)
      return unless path.is_a?(String)
      return if stripe_id?(path)
      return unless FIX_PATH.match?(path)

      path
    end

    def stripe_id?(text)
      text.match?(STRIPE_ID)
    end

    private_class_method :interpret_decision, :interpret_error, :publish, :known?,
                         :denial_code, :denial_details, :notice_unknown, :development?,
                         :message_for, :public_details, :public_value, :bounded_text, :text_value,
                         :integer_limit, :relative_fix_path, :stripe_id?
  end
end
