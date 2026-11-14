# frozen_string_literal: true

return if ENV["DISABLE_SIMPLECOV"] == "true"

begin
  require "simplecov"
rescue LoadError
  return
end

# Gem tests, dummy tests, and the docs integration file load this helper.
# SimpleCov can start once per process.
return if SimpleCov.pid

GEM_ROOT = File.expand_path("..", __dir__)

SimpleCov.start do
  root GEM_ROOT
  coverage_dir "coverage"
  command_name ENV.fetch("COVERAGE_COMMAND_NAME", "Gem")
  enable_coverage :branch
  merging true
  merge_timeout 3600

  # Count the gem's app and lib only. Dummy app files and tests stay out,
  # including when the dummy suite boots the engine.
  skip do |source|
    relative = source.filename.delete_prefix("#{GEM_ROOT}/")
    !(relative.start_with?("app/") || relative.start_with?("lib/"))
  end

  group "App", "app/"
  group "Lib", "lib/"
end
