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
    FIX_PATH = %r{\A/(?!/)[^\s]*\z}

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
      return relative_fix_path(value) if key == :fix_path

      scalar(value)
    end

    def scalar(value)
      case value
      when String then value unless value.empty?
      when Symbol then value.to_s
      when Integer, true, false then value
      when Float then value if value.finite?
      end
    end

    def relative_fix_path(value)
      path = scalar(value)
      return unless path.is_a?(String)
      return if path.include?("://") || path.include?("\\")
      return unless FIX_PATH.match?(path)

      path
    end

    private_class_method :interpret_decision, :interpret_error, :publish, :known?,
                         :denial_code, :denial_details, :notice_unknown, :development?,
                         :message_for, :public_details, :public_value, :scalar, :relative_fix_path
  end
end
