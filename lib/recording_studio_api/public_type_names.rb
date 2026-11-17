# frozen_string_literal: true

module RecordingStudioApi
  module PublicTypeNames
    # Class or class name -> public type string used in requests, replies, and docs.
    def public_name_for(recordable_type, api: :public)
      configuration.fetch_api(api).recordable_registry.public_name_for(recordable_type)
    end

    # Public type string -> registration. MCP resolves request `type` with this.
    def recordable_registration_for_public_name(public_name, api: :public)
      configuration.fetch_api(api).recordable_registry.fetch_by_public_name(public_name)
    end

    # Public type string -> class name. Registry first, then a unique match on this API's types.
    def recordable_type_for_public_name(public_name, api: :public)
      registration = recordable_registration_for_public_name(public_name, api: api)
      return registration.recordable_type if registration

      needle = public_name.to_s
      matches = types_for_api(api).select { |type| public_name_for(type, api: api) == needle }
      matches.first if matches.one?
    end

    # Class name -> public name for registered types and every type this API exposes.
    def public_name_map(api: :public)
      registry = configuration.fetch_api(api).recordable_registry
      map = registry.public_name_map
      types_for_api(api).each_with_object(map.dup) do |type, names|
        names[type] ||= registry.public_name_for(type)
      end
    end

    def public_type_names(api: :public)
      public_name_map(api: api).values.uniq.sort
    end

    def resolve_request_type!(name, api: :public)
      value = name.to_s
      raise RequestType.invalid_type("type is required") if value.blank?

      class_name = recordable_type_for_public_name(value, api: api)
      return class_name if class_name.present?

      if registered_class_name?(value, api: api)
        public_name = public_name_for(value, api: api)
        raise RequestType.invalid_type("Unknown type #{value}. Use the public name #{public_name}.") if public_name.present? && public_name != value
      end

      raise RequestType.invalid_type("Unknown type #{value}")
    end

    private

    def registered_class_name?(value, api:)
      return true if recordable_registration_for(value, api: api)
      return true if types_for_api(api).include?(value.to_s)

      false
    end

    # Public API stubs often omit `api:`. Named APIs still pass it.
    def types_for_api(api)
      return api_recordable_types if api.to_s == "public"

      api_recordable_types(api: api)
    end
  end
end
