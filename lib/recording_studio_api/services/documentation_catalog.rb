# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class DocumentationCatalog # rubocop:disable Metrics/ClassLength
      DEFAULT_MOUNT_PATH = "/recording_studio_api"
      DEFAULT_API_MOUNT_PATH = "/api"
      BASE_PATH = DEFAULT_MOUNT_PATH

      class << self
        def call(version: nil, mount_path: nil, api_mount_path: nil, api: :public)
          new(version: version, mount_path: mount_path, api_mount_path: api_mount_path, api: api).call
        end
      end

      def initialize(version: nil, mount_path: nil, api_mount_path: nil, api: :public)
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
        @api_version = RecordingStudioApi.resolve_api_version(version, api: @api_key)
        @mount_path = normalized_mount_path(mount_path || DEFAULT_MOUNT_PATH)
        default_api_mount_path = @api_key == "public" ? DEFAULT_API_MOUNT_PATH : "/apis/#{@api_key}"
        @api_mount_path = normalized_mount_path(api_mount_path || default_api_mount_path, allow_root: false)
      end

      def call
        {
          auth_endpoints: auth_endpoints,
          root_endpoints: root_endpoints,
          resources: resource_sections
        }
      end

      private

      def auth_endpoints
        [
          {
            verb: "POST",
            path: oauth_token_path,
            action: "oauth#token",
            summary: "Exchange OAuth client credentials",
            description: "Exchange client credentials for an OAuth2 access token. Supply client_id and client_secret in the form body or via HTTP Basic authentication. Query-string credentials are rejected.",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["Authentication"],
              security: [],
              request_body: oauth_token_request_body,
              responses: oauth_token_responses
            }
          },
          {
            verb: "POST",
            path: oauth_revoke_path,
            action: "oauth#revoke",
            summary: "Revoke an OAuth access token",
            description: "Revoke a previously issued OAuth2 access token (RFC 7009). Authenticate with client credentials in the form body or via HTTP Basic. Unknown tokens still return 200 once the client authenticates.",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["Authentication"],
              security: [],
              request_body: oauth_revoke_request_body,
              responses: oauth_revoke_responses
            }
          }
        ]
      end

      def root_endpoints
        [
          {
            verb: "GET",
            path: api_root_path,
            action: "resources#index",
            summary: "List API resources",
            description: "List configured API resources.",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["resources"],
              responses: {
                "200" => {
                  description: "List of enabled resource collections.",
                  content: {
                    "application/json" => {
                      schema: {
                        type: "object",
                        properties: {
                          resources: {
                            type: "array",
                            items: {
                              type: "object",
                              properties: {
                                name: { type: "string" },
                                type: { type: "string" }
                              },
                              required: %w[name type]
                            }
                          }
                        },
                        required: ["resources"]
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      end

      def resource_sections
        api_recordable_types
          .map do |recordable_type|
            resource_name = RecordingStudioApi.resource_name_for(recordable_type)

            {
              resource: resource_name,
              recordable_type: recordable_type,
              endpoints: default_resource_endpoints(resource_name, recordable_type) +
                relationship_resource_endpoints(resource_name, recordable_type) +
                action_endpoints(resource_name, recordable_type)
            }
          end
          .sort_by { |section| section.fetch(:resource) }
      end

      def default_resource_endpoints(resource_name, recordable_type) # rubocop:disable Metrics/MethodLength
        openapi_tag = openapi_tag_for(resource_name, recordable_type)
        docs_resource_name = docs_resource_name_for(resource_name, recordable_type)
        registration = recordable_registration_for(recordable_type)
        openapi_overrides = registration&.openapi || {}

        endpoints = [
          {
            verb: "GET",
            path: "#{api_root_path}/#{resource_name}",
            action: "resources#index",
            summary: "List #{docs_resource_name}",
            description: "List #{docs_resource_name}",
            capability: nil,
            scope: nil,
            openapi: resource_openapi(
              {
                tags: [openapi_tag],
                parameters: pagination_parameters(recordable_type) + collection_filter_parameters(recordable_type) + include_parameters_for(recordable_type),
                responses: resource_list_responses(
                  resource_name,
                  recordable_type,
                  docs_resource_name,
                  relationship_examples: relationship_response_examples(recordable_type, collection: true)
                )
              },
              openapi_overrides.fetch(:index, {}),
              recordable_type,
              resource_name: resource_name,
              collection: true
            )
          },
          {
            verb: "POST",
            path: "#{api_root_path}/#{resource_name}",
            action: "resources#create",
            summary: "Create #{docs_resource_name}",
            description: "Create #{docs_resource_name}",
            capability: nil,
            scope: nil,
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                parameters: [idempotency_key_parameter],
                request_body: resource_write_request_body(recordable_type, operation: :create),
                responses: resource_create_responses(recordable_type)
              },
              openapi_overrides.fetch(:create, {})
            )
          },
          {
            verb: "GET",
            path: "#{api_root_path}/#{resource_name}/:id",
            action: "resources#show",
            summary: "Get #{docs_resource_name}",
            description: "Get #{docs_resource_name}",
            capability: nil,
            scope: nil,
            openapi: resource_openapi(
              {
                tags: [openapi_tag],
                parameters: [id_parameter] + include_parameters_for(recordable_type),
                responses: resource_item_responses(
                  recordable_type,
                  relationship_examples: relationship_response_examples(recordable_type)
                )
              },
              openapi_overrides.fetch(:show, {}),
              recordable_type,
              resource_name: resource_name,
              collection: false
            )
          },
          {
            verb: "PATCH",
            path: "#{api_root_path}/#{resource_name}/:id",
            action: "resources#update",
            summary: "Update #{docs_resource_name}",
            description: "Update #{docs_resource_name}",
            capability: nil,
            scope: nil,
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                parameters: [id_parameter],
                request_body: resource_write_request_body(recordable_type, operation: :update),
                responses: resource_item_responses(recordable_type)
              },
              openapi_overrides.fetch(:update, {})
            )
          },
          {
            verb: "DELETE",
            path: "#{api_root_path}/#{resource_name}/:id",
            action: "resources#destroy",
            summary: "Delete #{docs_resource_name}",
            description: destroy_description_for(resource_name, recordable_type),
            capability: nil,
            scope: nil,
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                parameters: [id_parameter],
                responses: resource_delete_responses(recordable_type)
              },
              openapi_overrides.fetch(:destroy, {})
            )
          }
        ]

        endpoints.select do |endpoint|
          registration.nil? || registration.supports_operation?(endpoint.fetch(:action).split("#").last)
        end
      end # rubocop:enable Metrics/MethodLength

      def relationship_resource_endpoints(resource_name, recordable_type)
        registration = recordable_registration_for(recordable_type)
        return [] unless registration

        registration.relationships.flat_map do |name, relationship|
          relationship_endpoints(resource_name, recordable_type, name, relationship, registration)
        end
      end

      def relationship_endpoints(resource_name, recordable_type, name, relationship, _registration)
        return [] unless nested_relationship?(relationship)

        path = "#{api_root_path}/#{resource_name}/:id/#{name}"
        endpoints = []
        if nested_operation_enabled?(relationship, :index)
          endpoints << {
            verb: "GET",
            path: path,
            action: "relationship_resources#index",
            summary: "List #{name.humanize.downcase} for #{docs_resource_name_for(resource_name, recordable_type)}",
            description: "List the registered #{name} relationship.",
            capability: nil,
            scope: :resource,
            openapi: {
              tags: [openapi_tag_for(resource_name, recordable_type)],
              parameters: [id_parameter],
              responses: relationship_collection_responses(relationship)
            }
          }
        end
        if nested_operation_enabled?(relationship, :show)
          endpoints << {
            verb: "GET",
            path: "#{path}/:relationship_id",
            action: "relationship_resources#show",
            summary: "Show #{name.humanize.downcase}",
            description: "Show a direct child record in the #{name} relationship.",
            capability: nil,
            scope: :resource,
            openapi: {
              tags: [openapi_tag_for(resource_name, recordable_type)],
              parameters: [id_parameter, relationship_id_parameter],
              responses: relationship_item_responses(relationship, operation: :show)
            }
          }
        end
        if nested_operation_enabled?(relationship, :create)
          endpoints << {
            verb: "POST",
            path: path,
            action: "relationship_resources#create",
            summary: "Create #{name.humanize.downcase}",
            description: "Create a record in the #{name} relationship.",
            capability: nil,
            scope: :resource,
            openapi: {
              tags: [openapi_tag_for(resource_name, recordable_type)],
              parameters: [id_parameter, idempotency_key_parameter],
              request_body: relationship_request_body(relationship, operation: :create),
              responses: relationship_create_responses(relationship)
            }
          }
        end

        if nested_operation_enabled?(relationship, :update)
          endpoints << {
            verb: "PATCH",
            path: "#{path}/:relationship_id",
            action: "relationship_resources#update",
            summary: "Update #{name.humanize.downcase}",
            description: "Update a record in the #{name} relationship.",
            capability: nil,
            scope: :resource,
            openapi: {
              tags: [openapi_tag_for(resource_name, recordable_type)],
              parameters: [id_parameter, relationship_id_parameter],
              request_body: relationship_request_body(relationship, operation: :update),
              responses: relationship_item_responses(relationship, operation: :update)
            }
          }
        end

        if nested_operation_enabled?(relationship, :destroy)
          endpoints << {
            verb: "DELETE",
            path: "#{path}/:relationship_id",
            action: "relationship_resources#destroy",
            summary: "Delete #{name.humanize.downcase}",
            description: "Delete a record in the #{name} relationship.",
            capability: nil,
            scope: :resource,
            openapi: {
              tags: [openapi_tag_for(resource_name, recordable_type)],
              parameters: [id_parameter, relationship_id_parameter],
              responses: relationship_delete_responses(relationship)
            }
          }
        end
        endpoints
      end

      def nested_relationship?(relationship)
        relationship.source == :children && relationship.many
      end

      def nested_operation_enabled?(relationship, operation)
        return false unless Array(relationship.endpoints).map(&:to_sym).include?(operation)

        child_registration = recordable_registration_for(relationship.child_type)
        child_registration.nil? || child_registration.supports_operation?(operation)
      end

      def action_endpoints(resource_name, recordable_type)
        capability_actions_for(recordable_type)
          .sort_by(&:name)
          .map do |action|
            action_openapi = action.respond_to?(:openapi) && action.openapi.is_a?(Hash) ? action.openapi : {}
            docs_resource_name_for(resource_name, recordable_type)

            {
              verb: action.http_verb.to_s.upcase,
              path: "#{api_root_path}/#{resource_name}/:id/actions/#{action.name}",
              action: "member_actions#create",
              summary: action_openapi.fetch(:summary, action.name.humanize),
              description: "Execute the #{action.name} action.",
              action_name: action.capability.to_s,
              capability: action.capability.to_s,
              scope: action.scope.to_s,
              openapi: merge_hashes(default_action_openapi(resource_name, recordable_type, action), action_openapi)
            }
          end
      end

      def merge_hashes(base_hash, override_hash)
        return base_hash unless override_hash.is_a?(Hash)

        base_hash.merge(override_hash) do |_key, base_value, override_value|
          if base_value.is_a?(Hash) && override_value.is_a?(Hash)
            merge_hashes(base_value, override_value)
          else
            override_value
          end
        end
      end

      def resource_openapi(default_openapi, override_openapi, recordable_type, resource_name:, collection:)
        openapi = merge_hashes(default_openapi, override_openapi)
        relationship_description = relationship_documentation_for(
          recordable_type,
          resource_name: resource_name,
          collection: collection
        )
        return openapi if relationship_description.blank?

        openapi.merge(description: [openapi[:description], relationship_description].compact.join("\n\n"))
      end

      def api_root_path
        RecordingStudioApi.api_base_path(
          version: @api_version,
          mount_path: @mount_path,
          api_mount_path: @api_mount_path,
          api: @api_key
        )
      end

      def oauth_token_path
        return mounted_path("/oauth/token") if @api_key == "public"

        mounted_path("/apis/#{@api_key}/oauth/token")
      end

      def oauth_revoke_path
        return mounted_path("/oauth/revoke") if @api_key == "public"

        mounted_path("/apis/#{@api_key}/oauth/revoke")
      end

      def api_recordable_types
        return RecordingStudioApi.api_recordable_types if @api_key == "public"

        RecordingStudioApi.api_recordable_types(api: @api_key)
      end

      def recordable_registration_for(recordable_type)
        return RecordingStudioApi.recordable_registration_for(recordable_type) if @api_key == "public"

        RecordingStudioApi.recordable_registration_for(recordable_type, api: @api_key)
      end

      def capability_actions_for(recordable_type)
        return RecordingStudioApi.capability_actions_for(recordable_type, version: @api_version) if @api_key == "public"

        RecordingStudioApi.capability_actions_for(recordable_type, version: @api_version, api: @api_key)
      end

      def sortable_attributes_for(recordable_type)
        return RecordingStudioApi.sortable_attributes_for(recordable_type) if @api_key == "public"

        RecordingStudioApi.sortable_attributes_for(recordable_type, api: @api_key)
      end

      def mounted_path(path)
        "/#{[@mount_path, path].flat_map { |entry| entry.split('/') }.reject(&:blank?).join('/')}"
      end

      def normalized_mount_path(value, allow_root: true)
        path = value.to_s.strip
        path = "/#{path}" unless path.start_with?("/")
        path = path.squeeze("/").sub(%r{/\z}, "")
        path = "/" if path.empty?
        raise ArgumentError, "mount paths must be safe absolute paths" unless path.match?(%r{\A/[a-zA-Z0-9._~!$&'()*+,;=@/-]*\z}) && !path.include?("..")

        raise ArgumentError, "api_mount_path must not be the root path" if !allow_root && path == "/"

        path
      end

      def default_action_openapi(resource_name, recordable_type, action)
        openapi = {
          tags: [openapi_tag_for(resource_name, recordable_type)],
          parameters: [
            id_parameter
          ],
          responses: {
            "200" => {
              description: "Action executed successfully.",
              content: {
                "application/json" => {
                  schema: recording_schema(recordable_type)
                }
              }
            }
          }
        }

        contract_request_body = input_contract_request_body(action)
        openapi[:request_body] = contract_request_body if contract_request_body

        openapi
      end

      def input_contract_request_body(action)
        contract = action.respond_to?(:input_contract) ? action.input_contract : nil
        definition = contract&.as_json
        return unless definition.is_a?(Hash)

        fields = definition.fetch(:fields, {})
        return unless fields.is_a?(Hash) && fields.any?

        properties = {}
        required = []

        fields.each do |field_name, rules|
          symbolized_rules = rules.respond_to?(:deep_symbolize_keys) ? rules.deep_symbolize_keys : {}
          field_schema = { type: openapi_type_for(symbolized_rules.fetch(:type, :string)) }
          field_schema[:enum] = symbolized_rules[:enum] if symbolized_rules[:enum].is_a?(Array)
          field_schema[:description] = symbolized_rules[:description] if symbolized_rules[:description].present?

          properties[field_name.to_s] = field_schema
          required << field_name.to_s if symbolized_rules[:required]
        end

        {
          required: required.any?,
          content: {
            "application/json" => {
              schema: {
                type: "object",
                properties: properties,
                required: required
              }
            }
          }
        }
      end

      def openapi_type_for(contract_type)
        case contract_type.to_sym
        when :integer
          "integer"
        when :float
          "number"
        when :boolean
          "boolean"
        when :array
          "array"
        when :hash
          "object"
        else
          "string"
        end
      end

      def openapi_tag_for(resource_name, recordable_type)
        docs_resource_name_for(resource_name, recordable_type)
      end

      def docs_resource_name_for(resource_name, recordable_type)
        return "Access" if recordable_type.to_s == "RecordingStudio::Access"

        resource_name.to_s.singularize.humanize.titleize
      end

      def destroy_description_for(resource_name, recordable_type)
        "Permanently delete #{docs_resource_name_for(resource_name, recordable_type)}. " \
          "Recording Studio API hard-deletes the recording and recordable; it does not soft-delete or move to trash."
      end

      def resource_list_responses(resource_name, recordable_type, docs_resource_name, item_schema: nil, relationship_examples: {})
        resource_type = resource_name.to_s.singularize

        {
          "200" => {
            description: "List #{docs_resource_name} visible in scope.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    resource: { type: "string" },
                    type: { type: "string", example: resource_type },
                    records: {
                      type: "array",
                      items: item_schema || recording_schema(recordable_type)
                    },
                    meta: {
                      type: "object",
                      properties: {
                        limit: { type: "integer", minimum: 1 },
                        sort: { type: "string", example: "created_at" },
                        order: { type: "string", enum: %w[asc desc] },
                        has_more: { type: "boolean" },
                        next_pagination_token: {
                          type: "string",
                          nullable: true,
                          description: "Use this as the pagination_token query parameter on your next request. Null means there are no more results."
                        }
                      },
                      example: {
                        limit: 50,
                        sort: "created_at",
                        order: "asc",
                        has_more: false,
                        next_pagination_token: nil
                      },
                      required: %w[limit sort order has_more next_pagination_token]
                    }
                  },
                  required: %w[resource type records meta]
                },
                examples: relationship_examples
              }
            }
          }
        }
      end

      def pagination_parameters(recordable_type)
        allowed_sorts = sortable_attributes_for(recordable_type)

        [
          {
            name: "limit",
            in: "query",
            required: false,
            description: "Maximum number of resources to return (default: 50).",
            schema: {
              type: "integer",
              minimum: 1,
              default: 50,
              maximum: 100
            }
          },
          {
            name: "pagination_token",
            in: "query",
            required: false,
            description: "Pagination token from the previous response. Leave blank on the first request, then pass next_pagination_token from the prior response as pagination_token to fetch the next results.",
            schema: {
              type: "string"
            }
          },
          {
            name: "sort",
            in: "query",
            required: false,
            description: "Sort field for this resource.",
            schema: {
              type: "string",
              enum: allowed_sorts,
              default: "created_at"
            }
          },
          {
            name: "order",
            in: "query",
            required: false,
            description: "Sort order for created_at and id.",
            schema: {
              type: "string",
              enum: %w[asc desc],
              default: "asc"
            }
          }
        ]
      end

      def collection_filter_parameters(recordable_type)
        filterable = filterable_attributes_for(recordable_type)
        parameters = [
          {
            name: "q",
            in: "query",
            required: false,
            description: "Case-insensitive substring search across filterable attributes for this resource.",
            schema: {
              type: "string"
            }
          }
        ]
        return parameters if filterable.empty?

        parameters + filterable.map do |attribute|
          {
            name: "filter[#{attribute}]",
            in: "query",
            required: false,
            description: "Exact match filter on #{attribute}.",
            schema: {
              type: "string"
            }
          }
        end
      end

      def filterable_attributes_for(recordable_type)
        registration = recordable_registration_for(recordable_type)
        return [] if registration.nil?

        (registration.sortable_attributes | registration.writable_attributes).map(&:to_s)
      end

      def idempotency_key_parameter
        {
          name: "Idempotency-Key",
          in: "header",
          required: false,
          description: "Optional client-supplied key. When Redis is available, identical create requests from the same API client reuse the first successful response for 24 hours.",
          schema: {
            type: "string",
            maxLength: 255
          }
        }
      end

      def resource_item_responses(recordable_type, relationship_examples: {})

        {
          "200" => {
            description: "Single record payload.",
            content: {
              "application/json" => {
                schema: recording_schema(recordable_type),
                examples: relationship_examples
              }
            }
          },
          "404" => {
            "$ref" => "#/components/responses/NotFound"
          }
        }
      end

      def resource_create_responses(recordable_type)

        {
          "201" => {
            description: "Resource created.",
            content: {
              "application/json" => {
                schema: recording_schema(recordable_type)
              }
            }
          }
        }
      end

      def resource_delete_responses(recordable_type)

        {
          "200" => {
            description: "Resource permanently deleted.",
            content: {
              "application/json" => {
                schema: {
                  allOf: [
                    recording_schema(recordable_type),
                    {
                      type: "object",
                      properties: {
                        deleted: { type: "boolean" },
                        deleted_via: { type: "string", enum: ["destroyed"] }
                      },
                      required: %w[deleted deleted_via]
                    }
                  ]
                }
              }
            }
          }
        }
      end

      def resource_write_request_body(recordable_type, operation:)
        attributes_schema = attributes_schema_for(recordable_type, mutable: operation == :update)
        properties = attributes_schema.fetch(:properties).deep_dup
        required_fields = []

        if operation == :create
          parent_id_schema = { type: "string" }
          if root_recordable_type?(recordable_type)
            parent_id_schema[:nullable] = true
          else
            required_fields << "parent_id"
          end
          properties[:parent_id] = parent_id_schema
        end

        {
          required: true,
          content: {
            "application/json" => {
              schema: {
                type: "object",
                properties: properties,
                additionalProperties: false,
                required: required_fields
              }
            }
          }
        }
      end

      def root_recordable_type?(recordable_type)
        RecordingStudio::RecordableDeclarations.root_allowed?(recordable_type)
      end

      def recording_schema(recordable_type = nil, output_keys: nil)
        properties = {
          id: { type: "string" },
          type: { type: "string" },
          root_id: { type: "string", example: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f" },
          parent_id: {
            type: "string",
            nullable: true,
            example: "f8792164-4d83-4810-8c89-6484feff5d28"
          },
          created_at: { type: "string", format: "date-time" },
          updated_at: { type: "string", format: "date-time" }
        }
        properties.merge!(field_properties_for(recordable_type, output_keys: output_keys))
        properties.merge!(relationship_properties_for(recordable_type)) if output_keys.nil?
        properties[:_meta] = relationship_meta_schema(recordable_type) if output_keys.nil? && relationship_meta_schema(recordable_type)

        {
          type: "object",
          properties: properties,
          required: %w[id type root_id created_at updated_at]
        }
      end

      def field_properties_for(recordable_type, output_keys: nil)
        registration = recordable_registration_for(recordable_type)
        return output_key_properties(output_keys) unless registration

        details = recordable_details_schema(recordable_type)&.fetch(:properties, {}) || {}
        keys = Array(output_keys || registration.output_keys)
        properties = keys.each_with_object({}) do |key, output|
          field = registration.fields[key.to_s] || registration.fields[key.to_sym]
          output[key.to_sym] = field_schema_for(field, details[key] || details[key.to_sym])
        end
        return properties unless output_keys.nil?

        registration.fields.each do |name, field|
          properties[name.to_sym] = field_schema_for(field, details[name] || details[name.to_sym]) if field.include == true
        end
        properties
      end

      def output_key_properties(output_keys)
        Array(output_keys).index_with { { type: "string" } }
      end

      def field_schema_for(field, fallback)
        if field.respond_to?(:openapi)
          field = field.openapi
        elsif !field.is_a?(Hash)
          return fallback || { type: "string" }
        end

        schema = field.fetch(:openapi, field).except(
          :source, :method, :resolver, :value, :required, :description
        )
        schema[:type] = openapi_type_for(schema[:type]) if schema[:type].present?
        schema[:description] ||= field[:description] if field[:description].present?
        schema.presence || fallback || { type: "string" }
      end

      def relationship_properties_for(recordable_type)
        registration = recordable_registration_for(recordable_type)
        return {} unless registration

        registration.relationships.each_with_object({}) do |(name, relationship), properties|
          next unless relationship.include

          properties[name.to_sym] = relationship_schema(relationship)
        end
      end

      def relationship_meta_schema(recordable_type)
        registration = recordable_registration_for(recordable_type)
        return unless registration

        properties = registration.relationships.each_with_object({}) do |(name, relationship), output|
          next unless relationship.include == true && relationship.many

          output[name.to_sym] = {
            type: "object",
            properties: {
              limit: { type: "integer", minimum: 1 },
              has_more: { type: "boolean" }
            },
            required: %w[limit has_more]
          }
        end
        return if properties.empty?

        { type: "object", properties: properties }
      end

      def relationship_schema(relationship)
        schema = relationship.openapi
        return schema if schema.is_a?(Hash) && schema.present?

        items = relationship_recording_schema(relationship)
        return { nullable: true, allOf: [items] } unless relationship.many

        {
          type: "array",
          items: items
        }
      end

      def attributes_schema_for(recordable_type, mutable: false)
        schema = recordable_details_schema(recordable_type)
        return schema || generic_attributes_schema unless mutable

        immutable_fields = Array(recordable_registration_for(recordable_type)&.immutable_fields)
        return schema || generic_attributes_schema if immutable_fields.empty?

        mutable_schema = (schema || generic_attributes_schema).deep_dup
        immutable_property_keys = immutable_fields.flat_map { |field| [field, field.to_sym] }
        mutable_schema[:properties] = mutable_schema.fetch(:properties).except(*immutable_property_keys)
        mutable_schema
      end

      def recordable_details_schema(recordable_type)
        return if recordable_type.blank?

        details_schema = recordable_registration_for(recordable_type)&.openapi&.dig(:details_schema)
        return unless details_schema.is_a?(Hash)

        properties = details_schema[:properties] || details_schema["properties"]
        return unless properties.is_a?(Hash) && properties.any?

        {
          type: "object",
          properties: properties,
          additionalProperties: false
        }
      end

      def generic_attributes_schema
        {
          type: "object",
          properties: {},
          additionalProperties: false
        }
      end

      def oauth_token_request_body
        {
          required: true,
          content: {
            "application/x-www-form-urlencoded" => {
              schema: {
                type: "object",
                properties: {
                  grant_type: { type: "string", enum: ["client_credentials"] },
                  client_id: {
                    type: "string",
                    description: "OAuth client id. Optional when supplied via HTTP Basic username."
                  },
                  client_secret: {
                    type: "string",
                    description: "OAuth client secret. Optional when supplied via HTTP Basic password."
                  }
                },
                required: %w[grant_type]
              }
            }
          }
        }
      end

      def oauth_revoke_request_body
        {
          required: true,
          content: {
            "application/x-www-form-urlencoded" => {
              schema: {
                type: "object",
                properties: {
                  token: { type: "string", description: "Access token to revoke." },
                  token_type_hint: { type: "string", enum: ["access_token"] },
                  client_id: {
                    type: "string",
                    description: "OAuth client id. Optional when supplied via HTTP Basic username."
                  },
                  client_secret: {
                    type: "string",
                    description: "OAuth client secret. Optional when supplied via HTTP Basic password."
                  }
                },
                required: %w[token]
              }
            }
          }
        }
      end

      def oauth_token_responses
        {
          "200" => {
            description: "OAuth access token issued.",
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthTokenResponse" }
              }
            }
          },
          "400" => {
            description: "Invalid OAuth token request.",
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthError" }
              }
            }
          },
          "401" => {
            description: "Client authentication failed.",
            headers: {
              "WWW-Authenticate" => {
                schema: { type: "string" },
                description: 'Basic realm="RecordingStudioApi"'
              }
            },
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthError" }
              }
            }
          },
          "429" => {
            description: "OAuth rate limit exceeded.",
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthError" }
              }
            }
          }
        }
      end

      def oauth_revoke_responses
        {
          "200" => {
            description: "Token revoked, or the token was unknown to this client."
          },
          "400" => {
            description: "Invalid OAuth revoke request.",
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthError" }
              }
            }
          },
          "401" => {
            description: "Client authentication failed.",
            headers: {
              "WWW-Authenticate" => {
                schema: { type: "string" },
                description: 'Basic realm="RecordingStudioApi"'
              }
            },
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthError" }
              }
            }
          },
          "429" => {
            description: "OAuth rate limit exceeded.",
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/OAuthError" }
              }
            }
          }
        }
      end

      def id_parameter
        {
          name: "id",
          in: "path",
          required: true,
          description: "Resource identifier.",
          schema: { type: "string" }
        }
      end

      def relationship_id_parameter
        id_parameter.merge(name: "relationship_id", description: "Relationship recording identifier.")
      end

      def include_parameters_for(recordable_type)
        registration = recordable_registration_for(recordable_type)
        return [] unless registration

        names = registration.fields.each_with_object([]) do |(name, field), output|
          output << name.to_s if field.include == :request
        end
        names.concat(registration.relationships.filter_map { |name, relationship| name.to_s if relationship.include == :request })
        return [] if names.empty?

        [include_parameter(names)]
      end

      def include_parameter(names)
        {
          name: "include",
          in: "query",
          required: false,
          description: "Comma-separated registered include names. Allowed values: #{names.join(', ')}.",
          schema: { type: "string", example: names.join(",") }
        }
      end

      def relationship_documentation_for(recordable_type, resource_name:, collection:)
        registration = recordable_registration_for(recordable_type)
        return unless registration

        included = registration.relationships.select { |_name, relationship| relationship.include == true }
        requested = registration.relationships.select { |_name, relationship| relationship.include == :request }
        return if included.empty? && requested.empty?

        included.map do |name, relationship|
          "#{response_subject(collection)} includes #{relationship_field_description(name, relationship)}."
        end.concat(
          requested.map do |name, relationship|
            "Add `include=#{name}` to also receive #{relationship_field_description(name, relationship)}."
          end
        ).concat(
          registration.relationships.filter_map do |name, relationship|
            relationship_route_description(name, relationship, resource_name)
          end
        ).join(" ")
      end

      def response_subject(collection)
        collection ? "Each item in `records`" : "The response"
      end

      def relationship_field_description(name, relationship)
        field = "`#{name}`"
        type = relationship.child_type.presence || "related"
        value = if relationship.many
                  "#{field}, an array of #{type} records"
                else
                  "#{field}, one #{type} record or `null`"
                end
        attributes = relationship.output_keys.map { |key| "`#{key}`" }.to_sentence
        value += " with #{attributes}" if attributes.present?
        value += " (up to #{relationship.limit})" if relationship.many && relationship.limit
        value += ". #{relationship.description}" if relationship.description.present?
        value
      end

      def relationship_route_description(name, relationship, resource_name)
        if relationship.source == :custom
          return "`#{name}` is available only in this response; there is no separate endpoint for it." if relationship.include

          return
        end
        return unless relationship.many && relationship.endpoints.any?

        "To browse #{name} separately, use `GET #{api_root_path}/#{resource_name}/{id}/#{name}`."
      end

      def relationship_response_examples(recordable_type, collection: false)
        registration = recordable_registration_for(recordable_type)
        return {} unless registration

        included = registration.relationships.select { |_name, relationship| relationship.include == true }
        requested = registration.relationships.select { |_name, relationship| relationship.include == :request }
        return {} if included.empty? && requested.empty?

        examples = {
          default_relationships: {
            summary: "#{example_subject(recordable_type, collection)} with included fields",
            description: "Shows the fields returned without an include query parameter.",
            value: relationship_example_response(recordable_type, included, collection: collection)
          }
        }
        return examples if requested.empty?

        examples[:requested_relationships] = {
          summary: "#{example_subject(recordable_type, collection)} with requested details",
          description: "Shows the additional fields returned by `include=#{requested.keys.join(',')}`.",
          value: relationship_example_response(recordable_type, included.merge(requested), collection: collection)
        }
        examples
      end

      def example_subject(recordable_type, collection)
        label = recordable_type.to_s.demodulize.humanize
        collection ? "#{label} list" : label
      end

      def relationship_example_response(recordable_type, relationships, collection:)
        record = relationship_example_record(recordable_type, relationships)
        return record unless collection

        resource_name = RecordingStudioApi.resource_name_for(recordable_type)
        {
          resource: resource_name,
          type: resource_name.to_s.singularize,
          records: [record],
          meta: {
            limit: 50,
            sort: "created_at",
            order: "asc",
            has_more: false,
            next_pagination_token: nil
          }
        }
      end

      def relationship_example_record(recordable_type, relationships)
        record = {
          id: "00000000-0000-4000-8000-000000000001",
          type: recordable_type.to_s,
          root_id: "00000000-0000-4000-8000-000000000001",
          parent_id: nil,
          created_at: "2026-01-01T00:00:00Z",
          updated_at: "2026-01-01T00:00:00Z"
        }
        relationships.each { |name, relationship| record[name.to_s] = relationship_example_value(relationship) }
        record
      end

      def relationship_example_value(relationship)
        child = {
          id: "00000000-0000-4000-8000-000000000002",
          type: relationship.child_type.presence || "Custom relationship",
          root_id: "00000000-0000-4000-8000-000000000001",
          parent_id: "00000000-0000-4000-8000-000000000001",
          created_at: "2026-01-01T00:00:00Z",
          updated_at: "2026-01-01T00:00:00Z"
        }
        relationship.output_keys.each { |key| child[key.to_s] = "Example #{key.to_s.humanize.downcase}" }
        relationship.many ? [child] : child
      end

      def relationship_request_body(relationship, operation:)
        attributes_schema = attributes_schema_for(relationship.child_type, mutable: operation == :update)

        {
          required: true,
          content: {
            "application/json" => {
              schema: {
                type: "object",
                properties: attributes_schema.fetch(:properties).deep_dup,
                additionalProperties: false
              }
            }
          }
        }
      end

      def relationship_collection_responses(relationship)
        child_resource_name = RecordingStudioApi.resource_name_for(relationship.child_type)
        resource_list_responses(
          child_resource_name,
          relationship.child_type,
          docs_resource_name_for(child_resource_name, relationship.child_type),
          item_schema: relationship_endpoint_item_schema(relationship)
        )
      end

      def relationship_create_responses(relationship)
        relationship_response("201", "Resource created.", relationship_recording_schema(relationship, operation: :create))
      end

      def relationship_item_responses(relationship, operation:)
        relationship_response("200", "Single record payload.", relationship_recording_schema(relationship, operation: operation))
          .merge("404" => { "$ref" => "#/components/responses/NotFound" })
      end

      def relationship_delete_responses(relationship)
        recording = relationship_recording_schema(relationship, operation: :destroy)
        relationship_response(
          "200",
          "Resource permanently deleted.",
          {
            allOf: [
              recording,
              {
                type: "object",
                properties: {
                  deleted: { type: "boolean" },
                  deleted_via: { type: "string", enum: ["destroyed"] }
                },
                required: %w[deleted deleted_via]
              }
            ]
          }
        )
      end

      def relationship_response(status, description, schema)
        {
          status => {
            description: description,
            content: {
              "application/json" => {
                schema: schema
              }
            }
          }
        }
      end

      def relationship_recording_schema(relationship, operation: nil)
        recording_schema(relationship.child_type, output_keys: relationship.output_keys)
      end

      def relationship_endpoint_item_schema(relationship)
        return relationship.openapi if relationship.openapi.is_a?(Hash) && relationship.openapi.present?

        relationship_recording_schema(relationship)
      end
    end
  end
end
