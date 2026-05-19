# frozen_string_literal: true

module RecordingStudioApi
  class ActionInputContract
    ALLOWED_TYPES = %i[string integer float boolean symbol array hash].freeze

    ContractResult = Struct.new(:success?, :value, :errors, keyword_init: true)

    def initialize(definition)
      @definition = normalize_definition(definition)
      validate_definition!
    end

    def call(raw_params)
      params = normalize_input_params(raw_params)
      errors = []
      output = {}

      unknown_keys = params.keys - fields.keys
      if reject_unknown? && unknown_keys.any?
        errors << "Unknown parameters: #{unknown_keys.sort.join(', ')}"
      end

      fields.each do |field_name, rules|
        resolved = resolve_field_value(params, field_name, rules)
        next if resolved[:skip]

        if resolved[:missing_required]
          errors << "#{field_name} is required"
          next
        end

        coerced_value, error = coerce_value(resolved[:value], rules)
        if error
          errors << "#{field_name} #{error}"
          next
        end

        if rules[:enum] && !rules[:enum].include?(coerced_value)
          errors << "#{field_name} must be one of: #{rules[:enum].join(', ')}"
          next
        end

        if rules.fetch(:allow_blank, true) == false && coerced_value.respond_to?(:blank?) && coerced_value.blank?
          errors << "#{field_name} cannot be blank"
          next
        end

        output[field_name] = coerced_value
      end

      if reject_unknown?
        ContractResult.new(success?: errors.empty?, value: errors.empty? ? output : nil, errors: errors)
      else
        passthrough = params.except(*fields.keys)
        ContractResult.new(success?: errors.empty?, value: errors.empty? ? output.merge(passthrough) : nil, errors: errors)
      end
    end

    def as_json(*)
      @definition
    end

    private

    def normalize_definition(definition)
      unless definition.respond_to?(:to_h)
        raise ConfigurationError, "Action input contract must be a hash"
      end

      definition.to_h.deep_symbolize_keys
    end

    def validate_definition!
      unless @definition[:fields].is_a?(Hash)
        raise ConfigurationError, "Action input contract fields must be a hash"
      end

      fields.each do |field_name, rules|
        unless rules.is_a?(Hash)
          raise ConfigurationError, "Action input contract field #{field_name} must be a hash"
        end

        type = rules[:type]&.to_sym
        unless ALLOWED_TYPES.include?(type)
          raise ConfigurationError, "Action input contract field #{field_name} has unsupported type #{rules[:type]}"
        end

        if rules.key?(:enum) && !rules[:enum].is_a?(Array)
          raise ConfigurationError, "Action input contract field #{field_name} enum must be an array"
        end

        if rules.key?(:required) && ![true, false].include?(rules[:required])
          raise ConfigurationError, "Action input contract field #{field_name} required must be true or false"
        end

        if rules.key?(:allow_blank) && ![true, false].include?(rules[:allow_blank])
          raise ConfigurationError, "Action input contract field #{field_name} allow_blank must be true or false"
        end
      end

      if @definition.key?(:reject_unknown) && ![true, false].include?(@definition[:reject_unknown])
        raise ConfigurationError, "Action input contract reject_unknown must be true or false"
      end
    end

    def fields
      @fields ||= @definition[:fields].each_with_object({}) do |(name, rules), output|
        output[name.to_sym] = rules.deep_symbolize_keys
      end
    end

    def reject_unknown?
      @definition.fetch(:reject_unknown, true)
    end

    def resolve_field_value(params, field_name, rules)
      if params.key?(field_name)
        { value: params[field_name], missing_required: false, skip: false }
      elsif rules.key?(:default)
        { value: rules[:default], missing_required: false, skip: false }
      elsif rules.fetch(:required, false)
        { value: nil, missing_required: true, skip: false }
      else
        { value: nil, missing_required: false, skip: true }
      end
    end

    def normalize_input_params(raw_params)
      return {} unless raw_params.respond_to?(:to_h)

      raw_params.to_h.deep_symbolize_keys
    end

    def coerce_value(value, rules)
      case rules[:type].to_sym
      when :string
        [value.to_s, nil]
      when :integer
        [Integer(value), nil]
      when :float
        [Float(value), nil]
      when :boolean
        coerce_boolean(value)
      when :symbol
        [value.to_sym, nil]
      when :array
        return [value, nil] if value.is_a?(Array)

        [nil, "must be an array"]
      when :hash
        return [value.deep_symbolize_keys, nil] if value.respond_to?(:to_h)

        [nil, "must be a hash"]
      else
        [nil, "has unsupported type #{rules[:type]}"]
      end
    rescue ArgumentError, TypeError
      [nil, "must be a valid #{rules[:type]}"]
    end

    def coerce_boolean(value)
      return [true, nil] if value == true || value.to_s == "true" || value.to_s == "1"
      return [false, nil] if value == false || value.to_s == "false" || value.to_s == "0"

      [nil, "must be a valid boolean"]
    end
  end
end