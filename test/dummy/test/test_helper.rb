# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["COVERAGE_COMMAND_NAME"] ||= "Dummy"
require_relative "../../simplecov_helper"
require_relative "../config/environment"
require "rails/test_help"
require File.expand_path("../../support/recording_studio_authorized_writes", __dir__)

RecordingStudioAuthorizedWrites.install!

# This suite does not run Redis. OAuth and IP limits fail closed when the
# store is down, so a rejected bearer would come back as 429. Turn those
# limits off here. Read and write limits stay on and use the in-process window.
RecordingStudioApi.configuration.api_names.each do |api_name|
  RecordingStudioApi.configuration.api(api_name) do |api|
    api.rate_limit_oauth_enabled = false
    api.rate_limit_api_pre_auth_enabled = false
    api.rate_limit_api_failed_auth_enabled = false
  end
end
