# frozen_string_literal: true

source "https://rubygems.org"

require_relative "test/support/widen_recording_studio_requirement"

# Specify your gem's dependencies in recording_studio_api.gemspec
gem "devise"
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.22.1"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.7.0"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.5.0"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.5.0"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.12.0", require: false
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v4.0.1"
gem "recording_studio_root_switchable", github: "bowerbird-app/RecordingStudio_root_switchable", tag: "v0.11.0"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.320"
gem "pg", "~> 1.1"

gem "puma"
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"

group :development, :test do
  gem "recording_studio_cache", github: "bowerbird-app/RecordingStudio_cache", tag: "v0.6.0"
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
