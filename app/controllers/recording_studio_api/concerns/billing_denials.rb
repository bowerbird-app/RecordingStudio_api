# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    # Reads a billing denial only after the action has authorized the caller.
    module BillingDenials
      extend ActiveSupport::Concern

      private

      def run_authorized_handler
        previous = @billing_denials_visible
        @billing_denials_visible = true
        result = yield
        render_billing_denial(BillingDenial.interpret(result))
        result
      rescue RecordingStudio::Denial => e
        raise unless @billing_denials_visible

        denial = BillingDenial.interpret(e)
        raise if denial.nil?

        render_billing_denial(denial)
        nil
      ensure
        @billing_denials_visible = previous
      end

      def render_billing_denial(denial)
        return if denial.nil?

        render_error(
          code: denial.fetch(:code),
          message: denial.fetch(:message),
          status: denial.fetch(:status),
          details: denial.fetch(:details).presence
        )
      end
    end
  end
end
