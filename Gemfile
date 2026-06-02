# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_api.gemspec
gem "devise"
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "recording_studio/v2.0.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable"
gem "recording_studio_root_switchable", github: "bowerbird-app/RecordingStudio_root_switchable"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.66"
gem "pg", "~> 1.1"

gem "puma"
gem "sprockets-rails"
gem "importmap-rails"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
