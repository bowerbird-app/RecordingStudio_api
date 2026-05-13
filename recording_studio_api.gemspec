# frozen_string_literal: true

require_relative "lib/recording_studio_api/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_api"
  spec.version     = RecordingStudioApi::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_api"
  spec.summary     = "Recording Studio programmable API engine scaffold"
  spec.description = "A renamed Rails engine shell that documents and stages the Recording Studio API " \
                     "architecture, install flow, and host-app validation surfaces"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_api"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_api/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.1.0"
end
