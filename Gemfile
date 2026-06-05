# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_api.gemspec
gem "devise"
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "recording_studio/v3.0.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", branch: "copilot/upgrade-recordingstudio-3-0-0"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", branch: "copilot/update-access-api-in-moveable"
gem "recording_studio_root_switchable", github: "bowerbird-app/RecordingStudio_root_switchable", ref: "e684aa3ad73d3239e61cab8013040a3c896d5609" # 0.3.0
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
