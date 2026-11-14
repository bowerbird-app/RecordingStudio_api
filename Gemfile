# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_api.gemspec
gem "devise"
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.14.0"
# 0.42.0 is not tagged yet. This commit is Accessible PR 81, which uses
# Recording.kept / RecordingStudio.kept_sql and accepts Trashable 0.16.0.
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", ref: "75f1958a5b098b28666cd3c7fe661cc3f5971649"
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.13.0"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.4"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.8.0"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.16.0", require: false
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.2.1"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v4.1.1"
gem "recording_studio_root_switchable", github: "bowerbird-app/RecordingStudio_root_switchable", tag: "v0.15.0"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.356"
gem "pg", "~> 1.1"

gem "puma"
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"

group :development, :test do
  gem "recording_studio_cache", github: "bowerbird-app/RecordingStudio_cache", tag: "v0.6.3"
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
