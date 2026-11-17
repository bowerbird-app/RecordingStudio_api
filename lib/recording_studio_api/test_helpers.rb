# frozen_string_literal: true

module RecordingStudioApi
  # Assertions for gems and hosts. Require it from the test helper:
  #
  #   require "recording_studio_api/test_helpers"
  #
  #   class ActionTest < ActionDispatch::IntegrationTest
  #     include RecordingStudioApi::TestHelpers
  #   end
  module TestHelpers
    DETAIL_KEYS = BillingCodes::DETAIL_KEYS.map(&:to_s).freeze

    def assert_billing_denial(code, details: {}, response: nil)
      denial_code = begin
        BillingCodes::Registry.normalize(code)
      rescue ArgumentError
        flunk "#{code.inspect} is not a registered billing code"
      end
      assert(
        RecordingStudioApi.configuration.billing_code?(denial_code),
        "#{denial_code} is not a registered billing code"
      )

      http_response = response || (respond_to?(:response) ? self.response : nil)
      flunk "Pass the response to assert_billing_denial" if http_response.nil?

      assert_equal 402, http_response.status
      body = JSON.parse(http_response.body)
      error = body.fetch("error")
      assert_equal denial_code.to_s, error.fetch("code")
      assert_equal [], error.keys - %w[code message details]
      returned = error["details"] || {}
      assert_instance_of Hash, returned
      extra = returned.keys - DETAIL_KEYS
      assert_empty extra, "billing denial leaked details: #{extra.join(', ')}"
      assert_equal returned.fetch("message"), error.fetch("message") if returned.key?("message")
      details.each do |key, value|
        assert_equal value, returned[key.to_s], "details.#{key}"
      end
      error
    end
  end
end
