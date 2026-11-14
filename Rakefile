# frozen_string_literal: true

require "bundler/gem_tasks"
require "fileutils"
require "rake/testtask"

DUMMY_TEST_FILE = File.expand_path("test/controllers/docs_controller_test.rb", __dir__)
DUMMY_GEMFILE = File.expand_path("test/dummy/Gemfile", __dir__)
DUMMY_APP_ROOT = File.expand_path("test/dummy", __dir__)
ROOT_TEST_EXCLUSIONS = %w[
  test/controllers/docs_controller_test.rb
  test/rename_verification_test.rb
  test/dummy/**/*
].freeze

def run_command!(env, *command)
  return if system(env, *command)

  raise "Command failed (#{Process.last_status.exitstatus}): #{command.join(' ')}"
end

# The docs pages render the default layout, which links tailwind.css.
# Propshaft raises when that build artifact is missing. The file is gitignored.
def write_dummy_tailwind_placeholder!
  builds = File.join(DUMMY_APP_ROOT, "app/assets/builds")
  FileUtils.mkdir_p(builds)
  path = File.join(builds, "tailwind.css")
  return if File.exist?(path)

  File.write(path, "/* Present so docs pages can render before Tailwind is built. */\n")
end

def with_dummy_bundle(&block)
  github_token = ENV.fetch("BUNDLE_GITHUB__COM", nil)
  coverage_command = ENV.fetch("COVERAGE_COMMAND_NAME", "Dummy")

  Bundler.with_unbundled_env do
    ENV["BUNDLE_GITHUB__COM"] = github_token if github_token
    ENV["BUNDLE_GEMFILE"] = DUMMY_GEMFILE
    ENV["RAILS_ENV"] = "test"
    ENV["COVERAGE_COMMAND_NAME"] = coverage_command
    Dir.chdir(DUMMY_APP_ROOT, &block)
  end
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
    with_dummy_bundle do
      ENV["COVERAGE_COMMAND_NAME"] = "Dummy"
      run_command!({}, "bin/rails", "db:prepare")
      run_command!({}, "bundle", "exec", "rails", "test", "test")
      write_dummy_tailwind_placeholder!
      ENV["COVERAGE_COMMAND_NAME"] = "Dummy docs"
      run_command!(
        {},
        "bundle", "exec", "ruby", "-I#{File.expand_path('test', __dir__)}", DUMMY_TEST_FILE
      )
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
