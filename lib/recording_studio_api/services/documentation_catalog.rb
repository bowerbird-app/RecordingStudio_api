# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class DocumentationCatalog # rubocop:disable Metrics/ClassLength
      DEFAULT_MOUNT_PATH = "/recording_studio_api"
      DEFAULT_API_MOUNT_PATH = "/api"
      BASE_PATH = DEFAULT_MOUNT_PATH

      class << self
        def call(version: nil, mount_path: nil, api_mount_path: nil)
          new(version: version, mount_path: mount_path, api_mount_path: api_mount_path).call
        end
      end

      def initialize(version: nil, mount_path: nil, api_mount_path: nil)
        @api_version = RecordingStudioApi.resolve_api_version(version)
        @mount_path = normalized_mount_path(mount_path || DEFAULT_MOUNT_PATH)
        @api_mount_path = normalized_mount_path(api_mount_path || DEFAULT_API_MOUNT_PATH, allow_root: false)
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
            path: mounted_path("/oauth/token"),
            action: "oauth#token",
            summary: "Exchange OAuth client credentials",
            description: "Exchange client credentials for an OAuth2 access token.",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["auth"],
              request_body: oauth_token_request_body,
              responses: oauth_token_responses
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
          },
          {
            verb: "GET",
            path: "#{api_root_path}/trash",
            action: "resources#trash_index",
            summary: "List trashed",
            description: "List trashed",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["trash"],
              parameters: [
                {
                  name: "limit",
                  in: "query",
                  required: false,
                  description: "Maximum number of trashed resources to return (default: 50).",
                  schema: {
                    type: "integer",
                    minimum: 1,
                    default: 50,
                    maximum: 100
                  }
                }
              ],
              responses: global_trash_list_responses
            }
          },
          {
            verb: "GET",
            path: "#{api_root_path}/trash/:id",
            action: "resources#trash_show",
            summary: "Get trashed",
            description: "Get trashed",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["trash"],
              parameters: [id_parameter],
              responses: global_trash_item_responses
            }
          },
          {
            verb: "POST",
            path: "#{api_root_path}/trash/:id/restore",
            action: "resources#trash_restore",
            summary: "Restore trashed",
            description: "Restore trashed",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["trash"],
              parameters: [id_parameter],
              responses: global_trash_item_responses
            }
          },
          {
            verb: "DELETE",
            path: "#{api_root_path}/trash/:id",
            action: "resources#trash_destroy",
            summary: "Delete trashed",
            description: "Permanently delete trashed",
            capability: nil,
            scope: nil,
            openapi: {
              tags: ["trash"],
              parameters: [id_parameter],
              responses: global_trash_delete_responses
            }
          }
        ]
      end

      def resource_sections
        RecordingStudioApi.api_recordable_types
          .map do |recordable_type|
            resource_name = RecordingStudioApi.resource_name_for(recordable_type)

            {
              resource: resource_name,
              recordable_type: recordable_type,
              endpoints: default_resource_endpoints(resource_name, recordable_type) + action_endpoints(resource_name, recordable_type)
            }
          end
          .sort_by { |section| section.fetch(:resource) }
      end

      def default_resource_endpoints(resource_name, recordable_type)
        openapi_tag = openapi_tag_for(resource_name, recordable_type)
        docs_resource_name = docs_resource_name_for(resource_name, recordable_type)
        registration = RecordingStudioApi.recordable_registration_for(recordable_type)
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
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                parameters: pagination_parameters(recordable_type),
                responses: resource_list_responses(resource_name, recordable_type, docs_resource_name)
              },
              openapi_overrides.fetch(:index, {})
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
                request_body: resource_write_request_body(recordable_type),
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
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                parameters: [
                  id_parameter
                ],
                responses: resource_item_responses(recordable_type)
              },
              openapi_overrides.fetch(:show, {})
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
                request_body: resource_write_request_body(recordable_type),
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

        endpoints
      end

      def action_endpoints(resource_name, recordable_type)
        RecordingStudioApi.capability_actions_for(recordable_type, version: @api_version)
          .sort_by(&:name)
          .map do |action|
            action_openapi = action.respond_to?(:openapi) && action.openapi.is_a?(Hash) ? action.openapi : {}
            docs_resource_name = docs_resource_name_for(resource_name, recordable_type)

            {
              verb: action.http_verb.to_s.upcase,
              path: "#{api_root_path}/#{resource_name}/:id/actions/#{action.name}",
              action: "member_actions#create",
              summary: action_openapi.fetch(:summary, "Execute #{action.name} for #{docs_resource_name}"),
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

      def api_root_path
        RecordingStudioApi.api_base_path(
          version: @api_version,
          mount_path: @mount_path,
          api_mount_path: @api_mount_path
        )
      end

      def mounted_path(path)
        "/#{[@mount_path, path].flat_map { |entry| entry.split("/") }.reject(&:blank?).join('/')}"
      end

      def normalized_mount_path(value, allow_root: true)
        path = value.to_s.strip
        path = "/#{path}" unless path.start_with?("/")
        path = path.squeeze("/").sub(%r{/\z}, "")
        path = "/" if path.empty?
        unless path.match?(%r{\A/[a-zA-Z0-9._~!$&'()*+,;=@/-]*\z}) && !path.include?("..")
          raise ArgumentError, "mount paths must be safe absolute paths"
        end

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
                  schema: {
                    type: "object",
                    properties: {
                      data: recording_schema(recordable_type)
                    },
                    required: ["data"]
                  }
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
        "Delete #{docs_resource_name_for(resource_name, recordable_type)} permanently"
      end

      def resource_list_responses(_resource_name, recordable_type, docs_resource_name)
        resource_type = recordable_type.to_s.demodulize.underscore

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
                    data: {
                      type: "array",
                      items: recording_schema(recordable_type)
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
                  required: %w[resource type data meta]
                }
              }
            }
          }
        }
      end

      def pagination_parameters(recordable_type)
        allowed_sorts = RecordingStudioApi.sortable_attributes_for(recordable_type)

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

      def resource_item_responses(recordable_type)

        {
          "200" => {
            description: "Single record payload.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    data: recording_schema(recordable_type)
                  },
                  required: ["data"]
                }
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
                schema: {
                  type: "object",
                  properties: {
                    data: recording_schema(recordable_type)
                  },
                  required: ["data"]
                }
              }
            }
          }
        }
      end

      def resource_delete_responses(recordable_type)

        {
          "200" => {
            description: "Resource deleted or already trashed.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    data: {
                      allOf: [
                        recording_schema(recordable_type),
                        {
                          type: "object",
                          properties: {
                            deleted: { type: "boolean" },
                            deleted_via: { type: "string", enum: ["trashed", "destroyed"] }
                          },
                          required: %w[deleted deleted_via]
                        }
                      ]
                    }
                  },
                  required: ["data"]
                }
              }
            }
          }
        }
      end

      def global_trash_list_responses
        {
          "200" => {
            description: "List trashed resources visible in scope.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    resource: { type: "string", example: "trash" },
                    data: {
                      type: "array",
                      items: recording_schema
                    },
                    meta: {
                      type: "object",
                      properties: {
                        limit: { type: "integer", minimum: 1 },
                        returned: { type: "integer", minimum: 0 }
                      },
                      required: %w[limit returned]
                    }
                  },
                  required: %w[resource data meta]
                }
              }
            }
          }
        }
      end

      def global_trash_item_responses
        response = resource_item_responses(nil)
        response["200"][:description] = "Single trashed record payload."
        response
      end

      def global_trash_delete_responses
        response = resource_delete_responses(nil)
        response["200"][:description] = "Trashed item permanently deleted."
        response
      end

      def resource_write_request_body(recordable_type)
        parent_id_schema = { type: "string" }
        required_fields = ["attributes"]

        if root_recordable_type?(recordable_type)
          parent_id_schema[:nullable] = true
        else
          required_fields << "parent_id"
        end

        {
          required: true,
          content: {
            "application/json" => {
              schema: {
                type: "object",
                properties: {
                  attributes: attributes_schema_for(recordable_type),
                  parent_id: parent_id_schema
                },
                required: required_fields
              }
            }
          }
        }
      end

      def root_recordable_type?(recordable_type)
        RecordingStudio::RecordableDeclarations.root_allowed?(recordable_type)
      end

      def recording_schema(recordable_type = nil)
        {
          type: "object",
          properties: {
            id: { type: "string" },
            type: { type: "string" },
            actions: {
              type: "array",
              items: { type: "string" },
              example: []
            },
            root_id: { type: "string", example: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f" },
            parent_id: {
              type: "string",
              nullable: true,
              example: "f8792164-4d83-4810-8c89-6484feff5d28"
            },
            attributes: attributes_schema_for(recordable_type)
          },
          required: %w[id type actions root_id]
        }
      end

      def attributes_schema_for(recordable_type)
        schema = recordable_details_schema(recordable_type)
        schema || generic_attributes_schema
      end

      def recordable_details_schema(recordable_type)
        return if recordable_type.blank?

        details_schema = RecordingStudioApi.recordable_registration_for(recordable_type)&.openapi&.dig(:details_schema)
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
                  client_id: { type: "string" },
                  client_secret: { type: "string" }
                },
                required: %w[grant_type client_id client_secret]
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
          "401" => {
            "$ref" => "#/components/responses/Unauthorized"
          },
          "422" => {
            "$ref" => "#/components/responses/UnprocessableEntity"
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
    end
  end
end
