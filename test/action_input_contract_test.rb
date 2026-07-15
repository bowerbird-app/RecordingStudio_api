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

  def test_supports_symbol_and_float_types
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        status: { type: :symbol, required: true },
        ratio: { type: :float, required: true }
      }
    )

    result = contract.call(status: "ready", ratio: "12.5")

    assert result.success?, result.errors.join(", ")
    assert_equal :ready, result.value[:status]
    assert_equal 12.5, result.value[:ratio]
  end

  def test_reports_blank_and_enum_validation_errors
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        title: { type: :string, allow_blank: false },
        mode: { type: :string, enum: %w[draft final] }
      }
    )

    result = contract.call(title: "", mode: "invalid")

    assert_equal false, result.success?
    assert_includes result.errors, "title cannot be blank"
    assert_includes result.errors, "mode must be one of: draft, final"
  end

  def test_reports_array_and_hash_type_errors
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        tags: { type: :array, required: true },
        metadata: { type: :hash, required: true }
      }
    )

    result = contract.call(tags: "nope", metadata: "also-nope")

    assert_equal false, result.success?
    assert_includes result.errors, "tags must be an array"
    assert_includes result.errors, "metadata must be a hash"
  end

  def test_uses_default_values_when_field_is_missing
    contract = RecordingStudioApi::ActionInputContract.new(
      fields: {
        enabled: { type: :boolean, default: true }
      }
    )

    result = contract.call({})

    assert result.success?, result.errors.join(", ")
    assert_equal true, result.value[:enabled]
  end

  def test_raises_for_non_hash_definition
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new("invalid")
    end

    assert_includes error.message, "must be a hash"
  end

  def test_raises_for_invalid_fields_definition
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new(fields: "invalid")
    end

    assert_includes error.message, "fields must be a hash"
  end

  def test_raises_for_invalid_field_rule_shape
    error = assert_raises(NoMethodError) do
      RecordingStudioApi::ActionInputContract.new(fields: { title: "invalid" })
    end

    assert_includes error.message, "deep_symbolize_keys"
  end

  def test_raises_for_invalid_enum_required_allow_blank_and_reject_unknown
    enum_error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new(fields: { title: { type: :string, enum: "x" } })
    end
    assert_includes enum_error.message, "enum must be an array"

    required_error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new(fields: { title: { type: :string, required: "yes" } })
    end
    assert_includes required_error.message, "required must be true or false"

    allow_blank_error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new(fields: { title: { type: :string, allow_blank: "no" } })
    end
    assert_includes allow_blank_error.message, "allow_blank must be true or false"

    reject_unknown_error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionInputContract.new(
        reject_unknown: "no",
        fields: { title: { type: :string } }
      )
    end
    assert_includes reject_unknown_error.message, "reject_unknown must be true or false"
  end

  def test_action_registration_builds_input_contract_from_hash
    registration = RecordingStudioApi::ActionRegistration.new(
      name: :echo,
      capability: :echoable,
      version_notes: ["Adds title validation"],
      deprecation: {
        deprecated: true,
        removal_date: "2026-10-01",
        reason: "Use echo v2"
      },
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
    assert_equal ["Adds title validation"], registration.version_notes
    assert_equal "2026-10-01", registration.deprecation[:removal_date]
    assert_equal true, registration.as_json[:input_contract][:fields][:title][:required]
  end

  def test_action_registration_normalizes_single_version_note_to_array
    registration = RecordingStudioApi::ActionRegistration.new(
      name: :echo,
      capability: :echoable,
      version_notes: "Initial release",
      http_verb: :post,
      handler: ->(_context) { true }
    )

    registration.validate!

    assert_equal ["Initial release"], registration.version_notes
    assert_equal ["Initial release"], registration.as_json[:version_notes]
  end

  def test_action_registration_rejects_invalid_required_role
    registration = RecordingStudioApi::ActionRegistration.new(
      name: :echo,
      capability: :echoable,
      http_verb: :post,
      required_role: :owner,
      handler: ->(_context) { true }
    )

    error = assert_raises(RecordingStudioApi::ConfigurationError) { registration.validate! }

    assert_includes error.message, "required_role must be one of"
  end

  def test_action_registration_normalizes_grouped_deprecation_metadata
    registration = RecordingStudioApi::ActionRegistration.new(
      name: :echo,
      capability: :echoable,
      deprecation: {
        deprecated: true,
        removal_date: Date.new(2026, 12, 31),
        reason: "Use echo v2"
      },
      http_verb: :post,
      handler: ->(_context) { true }
    )

    registration.validate!

    assert_equal true, registration.deprecation[:deprecated]
    assert_equal "2026-12-31", registration.deprecation[:removal_date]
    assert_equal "Use echo v2", registration.deprecation[:reason]
  end

  def test_action_registration_rejects_invalid_deprecation_metadata
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::ActionRegistration.new(
        name: :echo,
        capability: :echoable,
        deprecation: {
          deprecated: "yes",
          removal_date: "31-12-2026"
        },
        http_verb: :post,
        handler: ->(_context) { true }
      )
    end

    assert_match(/deprecation/, error.message)
  end
end