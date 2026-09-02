# frozen_string_literal: true

require_relative "lib/recording_studio_api/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_api"
  spec.version     = RecordingStudioApi::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_api"
  spec.summary     = "Recording Studio programmable API engine"
  spec.description = "Rails engine providing OAuth2 API authentication, Recording Studio-backed API " \
                     "clients, and capability-driven API actions for Recording Studio addons"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_api"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_api/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "CHANGELOG.md", "MIT-LICENSE", "Rakefile", "README.md", "UPGRADING.md"]
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.2"
  spec.add_dependency "recording_studio_accessible", "~> 0.9"
  spec.add_dependency "redis", "~> 5.3"
end
