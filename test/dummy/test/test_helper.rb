# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require File.expand_path("../../support/recording_studio_authorized_writes", __dir__)

RecordingStudioAuthorizedWrites.install!
