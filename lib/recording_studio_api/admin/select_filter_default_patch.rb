# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module SelectFilterDefaultPatch
      def normalize(params)
        value = params[@definition.param_key] || params[@definition.param_key.to_s]
        return super unless value.nil? || value.to_s.empty?

        default_value = @definition.options[:default]
        return super if default_value.nil? || default_value.to_s.empty?

        allowed = @definition.allowed_values
        return default_value.to_s if allowed.empty? || allowed.include?(default_value.to_s)

        super
      end
    end
  end
end

if defined?(RecordingStudioAdmin::Filters::SelectFilter) &&
   !RecordingStudioAdmin::Filters::SelectFilter.ancestors.include?(RecordingStudioApi::Admin::SelectFilterDefaultPatch)
  RecordingStudioAdmin::Filters::SelectFilter.prepend(RecordingStudioApi::Admin::SelectFilterDefaultPatch)
end