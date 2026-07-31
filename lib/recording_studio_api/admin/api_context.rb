# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiContext
      module_function

      def resolve(value = nil)
        api_key = value.respond_to?(:name) ? value.name : value
        RecordingStudioApi.configuration.fetch_api(api_key.to_s.presence || :public)
      end

      def from_context(context)
        resolve(context.params[:api_key].presence || context.params["api_key"].presence)
      end

      def key_from_context(context)
        from_context(context).name
      end

      def admin_record_key(api)
        api_key = resolve(api).name
        api_key == "public" ? "api" : "api_#{api_key}"
      end

      def query_params(api)
        api_key = resolve(api).name
        api_key == "public" ? {} : { api_key: api_key }
      end
    end
  end
end
