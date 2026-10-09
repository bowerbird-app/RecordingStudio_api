# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_api.gemspec
gem "devise"
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.4.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.13.0"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.1.0"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v3.3.0"
gem "recording_studio_root_switchable", github: "bowerbird-app/RecordingStudio_root_switchable", tag: "v0.6.0"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.207"
gem "pg", "~> 1.1"

gem "puma"
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
