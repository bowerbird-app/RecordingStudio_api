# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module OpenapiOverrideMerge
      private

      def merge_openapi(base_hash, override_hash)
        return base_hash unless override_hash.is_a?(Hash)

        merged = merge_hashes(base_hash, override_hash.except(:parameters))
        return merged unless override_hash.key?(:parameters)

        merged.merge(parameters: merge_parameters(base_hash[:parameters], override_hash[:parameters]))
      end

      def merge_parameters(base_parameters, override_parameters)
        merged = Array(base_parameters).map(&:dup)
        Array(override_parameters).each do |parameter|
          normalized = parameter_with_default_in(parameter)
          key = parameter_identity(normalized)
          index = merged.index { |candidate| parameter_identity(candidate) == key }
          if index
            merged[index] = normalized
          else
            merged << normalized
          end
        end
        merged
      end

      def parameter_identity(parameter)
        [
          (parameter[:name] || parameter["name"]).to_s,
          parameter_in(parameter)
        ]
      end

      def parameter_with_default_in(parameter)
        location = parameter[:in] || parameter["in"]
        return parameter unless location.nil? || location.to_s.strip.empty?

        normalized = parameter.dup
        if normalized.key?("name") || normalized.key?("in")
          normalized["in"] = "query"
        else
          normalized[:in] = "query"
        end
        normalized
      end

      def parameter_in(parameter)
        location = parameter[:in] || parameter["in"]
        return "query" if location.nil? || location.to_s.strip.empty?

        location.to_s
      end
    end
  end
end
