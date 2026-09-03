# frozen_string_literal: true

require "json"
require_relative "../../simplecov_helper"
require "minitest/autorun"

class CursorBootFilesTest < Minitest::Test
  def test_cloud_agent_hooks_point_at_tracked_scripts_and_dummy_terminals
    root = File.expand_path("../../..", __dir__)
    env = JSON.parse(File.read(File.join(root, ".cursor/environment.json")))

    assert_equal ".cursor/install.sh", env.fetch("install")
    assert_equal ".cursor/start.sh", env.fetch("start")
    assert File.executable?(File.join(root, env.fetch("install")))
    assert File.executable?(File.join(root, env.fetch("start")))
    assert File.executable?(File.join(root, ".cursor/fetch-skills.sh"))

    commands = env.fetch("terminals").map { |terminal| terminal.fetch("command") }
    assert commands.any? { |command| command.include?("test/dummy") && command.include?("rails server") }
    assert commands.any? { |command| command.include?("test/dummy") && command.include?("tailwindcss:watch") }
  end
end
