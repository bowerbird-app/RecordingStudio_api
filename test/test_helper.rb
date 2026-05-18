# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "recording_studio_api"

module Minitest
  module Assertions
    # Rails cops prefer assert_not* APIs, but this test suite runs with a
    # Minitest version that only exposes refute* helpers by default.
    unless method_defined?(:assert_not)
      def assert_not(value, msg = nil)
        refute(value, msg)
      end
    end

    unless method_defined?(:assert_not_nil)
      def assert_not_nil(value, msg = nil)
        refute_nil(value, msg)
      end
    end

    unless method_defined?(:assert_not_empty)
      def assert_not_empty(value, msg = nil)
        refute_empty(value, msg)
      end
    end

    unless method_defined?(:assert_not_includes)
      def assert_not_includes(collection, object, msg = nil)
        refute_includes(collection, object, msg)
      end
    end

    unless method_defined?(:assert_not_respond_to)
      def assert_not_respond_to(object, method_name, msg = nil)
        refute_respond_to(object, method_name, msg)
      end
    end
  end
end
