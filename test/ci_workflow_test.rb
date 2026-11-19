# frozen_string_literal: true

require "test_helper"
require "yaml"

class CiWorkflowTest < Minitest::Test
  def test_ci_runs_redis_and_passes_the_shared_master_key_secret
    workflow = YAML.safe_load_file(workflow_path)
    job = workflow.fetch("jobs").fetch("test")

    assert_equal ["3.3"], job.dig("strategy", "matrix", "ruby-version")
    assert_equal false, job.dig("strategy", "fail-fast")
    refute workflow_source.include?("continue-on-error")

    postgres = job.dig("services", "postgres")
    assert_equal "postgres:16", postgres.fetch("image")
    assert_includes postgres.fetch("ports"), "5432:5432"
    assert_includes postgres.fetch("options"), "pg_isready -U postgres"

    redis = job.dig("services", "redis")
    assert_equal "redis:7", redis.fetch("image")
    assert_includes redis.fetch("ports"), "6379:6379"
    assert_includes redis.fetch("options"), "redis-cli ping"

    assert_equal "redis://127.0.0.1:6379/0", job.dig("env", "REDIS_URL")
    assert_equal "redis://127.0.0.1:6379/0", job.dig("env", "RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL")

    test_steps = job.fetch("steps").select { |step| ["Run tests", "Run dummy app tests"].include?(step["name"]) }
    test_step_names = test_steps.map { |step| step.fetch("name") }
    assert_equal ["Run tests", "Run dummy app tests"], test_step_names
    test_steps.each do |step|
      assert_equal "${{ secrets.RAILS_MASTER_KEY }}", step.dig("env", "RAILS_MASTER_KEY")
      assert_includes step.fetch("run"), "unset RAILS_MASTER_KEY"
    end

    step_names = job.fetch("steps").map { |step| step["name"] }
    assert_includes step_names, "Run RuboCop"
    assert_includes step_names, "Prepare test databases"
    assert_includes step_names, "Install dummy app dependencies"
  end

  private

  def workflow_path
    File.expand_path("../.github/workflows/ci.yml", __dir__)
  end

  def workflow_source
    File.read(workflow_path)
  end
end
