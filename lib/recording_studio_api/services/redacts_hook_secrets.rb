# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module RedactsHookSecrets
      SECRET_KEYS = %w[
        token
        access_token
        refresh_token
        client_secret
        code
        code_verifier
        id_token
        password
        assertion
        client_assertion
        device_code
        user_code
        authorization_code
      ].freeze
      PARAM_KEYS = %w[
        grant_type
        client_id
        redirect_uri
        scope
        resource
        token_type_hint
        response_type
      ].freeze
      SECRET_IVARS = %i[@client_secret @token @authorization_header].freeze

      private

      def hook_result(result)
        return redact_hook_value(result) unless core_result?(result)

        RecordingStudio::Services::BaseService::Result.new(
          success: result.success?,
          value: redact_hook_value(result.value),
          error: redact_hook_value(result.error),
          errors: redact_hook_value(result.errors)
        )
      end

      def hook_subject
        copy = dup
        allowlist_subject_params(copy)
        SECRET_IVARS.each do |name|
          copy.remove_instance_variable(name) if copy.instance_variable_defined?(name)
        end
        copy
      end

      def allowlist_subject_params(copy)
        return unless copy.instance_variable_defined?(:@params)

        params = copy.instance_variable_get(:@params)
        copy.instance_variable_set(:@params, allowlisted_params(params))
      end

      def allowlisted_params(params)
        hash = params_hash(params)
        hash.each_with_object({}) do |(key, value), kept|
          next unless PARAM_KEYS.include?(key.to_s)

          kept[key] = value
        end
      end

      def redact_hook_value(object)
        return nil if credential_record?(object)
        return object.with(credential: nil) if authenticated_client?(object)
        return redact_hash(hash_for_redaction(object)) if hash_source?(object)

        case object
        when Hash then redact_hash(object)
        when Array then object.map { |item| redact_hook_value(item) }
        when String then known_secret?(object) ? nil : object
        else object
        end
      end

      def hash_source?(object)
        parameters?(object) || object.is_a?(Struct) || object.is_a?(Data)
      end

      def hash_for_redaction(object)
        return parameters_hash(object) if parameters?(object)

        object.to_h
      end

      def parameters?(object)
        return false unless defined?(ActionController::Parameters)

        object.is_a?(ActionController::Parameters)
      end

      def parameters_hash(params)
        params.to_unsafe_h
      end

      def params_hash(params)
        return parameters_hash(params) if parameters?(params)
        return params if params.is_a?(Hash)

        {}
      end

      def authenticated_client?(object)
        return false unless defined?(RecordingStudioApi::AuthenticatedClient)

        object.is_a?(RecordingStudioApi::AuthenticatedClient)
      end

      def credential_record?(object)
        return false unless RecordingStudioApi.const_defined?(:ApiCredential, false)

        object.is_a?(RecordingStudioApi::ApiCredential)
      end

      def redact_hash(object)
        object.each_with_object({}) do |(key, value), redacted|
          redacted[key] = secret_string?(key, value) ? nil : redact_hook_value(value)
        end
      end

      def secret_string?(key, value)
        value.is_a?(String) && SECRET_KEYS.include?(key.to_s)
      end

      def known_secret?(text)
        return false if text.empty?

        secret_texts.include?(text)
      end

      def secret_texts
        texts = SECRET_IVARS.filter_map { |name| ivar_string(name) }
        header = ivar_string(:@authorization_header)
        texts << header.split(" ", 2).last if header
        texts.compact.reject(&:empty?).uniq
      end

      def ivar_string(name)
        return unless instance_variable_defined?(name)

        value = instance_variable_get(name)
        value if value.is_a?(String)
      end

      def core_result?(result)
        result.is_a?(RecordingStudio::Services::BaseService::Result)
      end
    end
  end
end
