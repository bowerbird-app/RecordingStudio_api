# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "recording_studio_api"

class Object
  unless method_defined?(:stub)
    def stub(method_name, callable_or_value)
      singleton = class << self; self; end
      alias_name = "__test_stub_original_#{method_name}"
      had_original = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
      singleton.alias_method(alias_name, method_name) if had_original

      singleton.define_method(method_name) do |*args, **kwargs, &block|
        if callable_or_value.respond_to?(:call)
          callable_or_value.call(*args, **kwargs, &block)
        else
          callable_or_value
        end
      end

      yield self
    ensure
      singleton.send(:remove_method, method_name) if singleton.method_defined?(method_name)

      if had_original
        singleton.alias_method(method_name, alias_name)
        singleton.send(:remove_method, alias_name)
      end
    end
  end
end

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
