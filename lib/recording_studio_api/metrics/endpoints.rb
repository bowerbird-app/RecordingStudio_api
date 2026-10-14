# frozen_string_literal: true

module RecordingStudioApi
  module Metrics
    module Period
      NAMES = {
        start: %i[start start_at from],
        end: %i[end end_at to]
      }.freeze

      module_function

      def fold(params)
        folded = params.except(:from, :to)
        NAMES.each do |canonical, names|
          value = names.lazy.map { |name| params[name].presence }.find(&:itself)
          folded[canonical] = value if value
        end
        folded
      end

      def openapi_parameters(documented_names)
        documented = Array(documented_names).map(&:to_s)
        NAMES.flat_map { |canonical, names| names.drop(1).map { |name| [canonical, name] } }
             .reject { |_canonical, name| documented.include?(name.to_s) }
             .map { |canonical, name| query_parameter(name, "Same as #{canonical}. ISO-8601.", format: "date-time") }
      end

      def query_parameter(name, description, format: nil)
        schema = { type: "string" }
        schema[:format] = format if format
        {
          name: name.to_s,
          in: "query",
          required: false,
          description: description,
          schema: schema
        }
      end
      private_class_method :query_parameter
    end

    module Endpoints
      GROUP_BY_PARAMETER = {
        name: "group_by",
        in: "query",
        required: false,
        description: "Grouping key, passed to the metric unchanged. Metrics that do not support grouping ignore it.",
        schema: { type: "string" }
      }.freeze

      RESOURCE_QUERY_PARAMETER = {
        name: "resource",
        in: "query",
        required: false,
        description: "Only list metrics for this resource.",
        schema: { type: "string" }
      }.freeze

      class CatalogHandler
        def self.call(api_context)
          catalog = RecordingStudioMetrics::Api::DiscoveryHandler.call(api_context)
          resource = api_context.params[:resource].to_s.presence
          return catalog unless resource

          catalog.merge(metrics: catalog.fetch(:metrics).select { |row| row[:resource].to_s == resource })
        end
      end

      class MetricHandler
        def self.call(api_context)
          RecordingStudioMetrics::Api::ExecuteHandler.call(
            api_context.with(params: Period.fold(api_context.params))
          )
        end
      end

      private_constant :CatalogHandler, :MetricHandler

      module_function

      def expand(name:, http_verb:, path:, handler:, serializer:, openapi:, input_contract:, ui:)
        registration = { name:, http_verb:, path:, handler:, serializer:, openapi:, input_contract:, ui: }
        return catalog_registrations(registration) if handler.equal?(RecordingStudioMetrics::Api::DiscoveryHandler)
        return metric_registrations(registration) if handler.equal?(RecordingStudioMetrics::Api::ExecuteHandler)

        [registration]
      end

      def catalog_registrations(registration)
        openapi = copied_openapi(registration)
        canonical = registration.merge(
          handler: CatalogHandler,
          openapi: openapi.merge(parameters: Array(openapi[:parameters]) + [RESOURCE_QUERY_PARAMETER])
        )
        prefix = relative_path(registration[:path])
        return [canonical] if prefix.split("/").any? { |segment| segment.start_with?(":") }

        [
          canonical,
          registration.merge(
            name: :"#{registration[:name]}_for_resource",
            path: ":resource/#{prefix}",
            handler: CatalogHandler,
            openapi: openapi.merge(summary: "List metrics for one resource")
          )
        ]
      end

      def metric_registrations(registration)
        openapi = copied_openapi(registration)
        documented = Array(openapi[:parameters]).map { |parameter| parameter[:name].to_s }
        parameters = Array(openapi[:parameters]) + Period.openapi_parameters(documented)
        parameters += [GROUP_BY_PARAMETER] unless documented.include?("group_by")
        canonical = registration.merge(handler: MetricHandler, openapi: openapi.merge(parameters: parameters))
        prefix = metric_prefix(registration[:path])
        return [canonical] if prefix.nil? || prefix.include?(":")

        [
          canonical,
          canonical.merge(name: :"#{registration[:name]}_for_resource", path: ":resource/#{prefix}/:name")
        ]
      end

      def copied_openapi(registration)
        (registration[:openapi] || {}).deep_dup
      end

      def relative_path(path)
        path.to_s.sub(%r{\A/}, "").sub(%r{/\z}, "")
      end

      def metric_prefix(path)
        relative_path(path)[%r{\A(.+)/:resource/:name\z}, 1]
      end

      private_class_method :catalog_registrations, :metric_registrations, :copied_openapi, :relative_path, :metric_prefix
    end
  end
end
