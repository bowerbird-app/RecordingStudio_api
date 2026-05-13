# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

DUMMY_TEST_FILE = File.expand_path("test/controllers/docs_controller_test.rb", __dir__)
DUMMY_GEMFILE = File.expand_path("test/dummy/Gemfile", __dir__)
DUMMY_APP_ROOT = File.expand_path("test/dummy", __dir__)
ROOT_TEST_EXCLUSIONS = %w[test/controllers/docs_controller_test.rb test/rename_verification_test.rb].freeze

def run_command!(env, *command)
  return if system(env, *command)

  raise "Command failed (#{Process.last_status.exitstatus}): #{command.join(' ')}"
end

def dummy_bundle_env
  dummy_bundle_base_env.merge(dummy_bundle_cleared_env)
end

def dummy_bundle_base_env
  {
    "BUNDLE_APP_CONFIG" => ENV.fetch("BUNDLE_APP_CONFIG", nil),
    "BUNDLE_GEMFILE" => DUMMY_GEMFILE,
    "BUNDLE_PATH" => ENV.fetch("BUNDLE_PATH", nil),
    "DISABLE_SIMPLECOV" => "true",
    "GEM_HOME" => ENV.fetch("BUNDLER_ORIG_GEM_HOME", ENV.fetch("GEM_HOME", nil)),
    "GEM_PATH" => ENV.fetch("BUNDLER_ORIG_GEM_PATH", nil)
  }
end

def dummy_bundle_cleared_env
  {
    "BUNDLE_BIN_PATH" => nil,
    "BUNDLE_GEMFILE" => DUMMY_GEMFILE,
    "BUNDLE_LOCKFILE" => nil,
    "BUNDLER_SETUP" => nil,
    "BUNDLER_VERSION" => nil,
    "RUBYLIB" => nil,
    "RUBYOPT" => nil
  }
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude(*ROOT_TEST_EXCLUSIONS)
  t.verbose = false
end

namespace :test do
  desc "Run rename verification tests to validate gem naming consistency"
  task :rename_verification do
    ruby "test/rename_verification_test.rb", verbose: true
  end

  desc "Run rename verification tests in verbose mode"
  task :rename_verification_verbose do
    ruby "test/rename_verification_test.rb", "--verbose", verbose: true
  end

  desc "Run dummy app integration tests under the dummy app bundle"
  task :dummy do
    Dir.chdir(DUMMY_APP_ROOT) do
      env = dummy_bundle_env

      run_command!(env, "bin/rails", "db:prepare")
      run_command!(env, "bundle", "exec", "ruby", "-I/workspace/test", DUMMY_TEST_FILE)
    end
  end

  desc "Run gem and dummy app tests"
  task all: %i[test dummy]
end

namespace :app do
  desc "Run all tests for the gem"
  task test: :test
end

task default: :test
