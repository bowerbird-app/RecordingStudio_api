# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    # Reads a billing denial only after the action has authorized the caller.
    module BillingDenials
      extend ActiveSupport::Concern

      UNRECOGNIZED_DENIAL_MESSAGE = "This action is not allowed"

      private

      def run_authorized_handler
        previous = @billing_denials_visible
        @billing_denials_visible = true
        result = yield
        render_handler_result(result)
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

      def render_handler_result(result)
        denial = BillingDenial.interpret(result)
        if denial
          render_billing_denial(denial)
        elsif unrecognized_gate_denial?(result)
          render_unrecognized_gate_denial
        end
      end

      def unrecognized_gate_denial?(result)
        result.is_a?(RecordingStudio::GateDecision) && result.denied?
      end

      def render_unrecognized_gate_denial
        render_error(code: "forbidden", message: UNRECOGNIZED_DENIAL_MESSAGE, status: :forbidden)
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
