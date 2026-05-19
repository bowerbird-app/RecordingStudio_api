# frozen_string_literal: true

require "test_helper"

class ActionInputContractTest < Minitest::Test
  def test_coerces_and_validates_known_fields
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        title: { type: :string, required: true },
        count: { type: :integer, required: true },
        enabled: { type: :boolean, default: false },
        metadata: { type: :hash },
        tags: { type: :array }
      }
    )

    result = contract.call(
      "title" => :hello,
      "count" => "42",
      "enabled" => "1",
      "metadata" => { "nested" => "value" },
      "tags" => %w[a b]
    )

    assert result.success?, result.errors.join(", ")
    assert_equal "hello", result.value[:title]
    assert_equal 42, result.value[:count]
    assert_equal true, result.value[:enabled]
    assert_equal({ nested: "value" }, result.value[:metadata])
    assert_equal %w[a b], result.value[:tags]
  end

  def test_rejects_unknown_keys_by_default
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        title: { type: :string, required: true }
      }
    )

    result = contract.call(title: "ok", unexpected: "value")

    assert_equal false, result.success?
    assert_includes result.errors, "Unknown parameters: unexpected"
  end

  def test_reports_missing_required_and_invalid_types
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        count: { type: :integer, required: true },
        enabled: { type: :boolean, required: true }
      }
    )

    result = contract.call(count: "NaN", enabled: "maybe")

    assert_equal false, result.success?
    assert_includes result.errors, "count must be a valid integer"
    assert_includes result.errors, "enabled must be a valid boolean"
  end

  def test_allows_passthrough_when_reject_unknown_is_false
    contract = RecordingStudioApi::ActionInputContract.new(
      reject_unknown: false,
      fields: {
        title: { type: :string, required: true }
      }
    )

    result = contract.call(title: "ok", extra: "value")

    assert result.success?, result.errors.join(", ")
    assert_equal "ok", result.value[:title]
    assert_equal "value", result.value[:extra]
  end

  def test_rejects_invalid_contract_definition
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new(
        fields: {
          count: { type: :timestamp }
        }
      )
    end

    assert_includes error.message, "unsupported type"
  end

  def test_action_registration_builds_input_contract_from_hash
    registration = RecordingStudioApi::ActionRegistration.new(
      name: :echo,
      capability: :echoable,
      http_verb: :post,
      handler: ->(_context) { true },
      input_contract: {
        fields: {
          title: { type: :string, required: true }
        }
      }
    )

    registration.validate!

    assert_kind_of RecordingStudioApi::ActionInputContract, registration.input_contract
    assert_equal true, registration.as_json[:input_contract][:fields][:title][:required]
  end
end