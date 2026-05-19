# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class DocumentationCatalog
      BASE_PATH = "/recording_studio_api"
      API_ROOT_PATH = "#{BASE_PATH}/api/v1"

      class << self
        def call
          new.call
        end
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
            path: "#{BASE_PATH}/oauth/token",
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
            path: API_ROOT_PATH,
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
        openapi_tag = openapi_tag_for(resource_name)
        registration = RecordingStudioApi.recordable_registration_for(recordable_type)
        openapi_overrides = registration&.openapi || {}

        [
          {
            verb: "GET",
            path: "#{API_ROOT_PATH}/#{resource_name}",
            action: "resources#index",
            summary: "List #{resource_name}",
            description: "List accessible #{resource_name} resources.",
            capability: nil,
            scope: nil,
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                responses: resource_list_responses(resource_name, recordable_type)
              },
              openapi_overrides.fetch(:index, {})
            )
          },
          {
            verb: "GET",
            path: "#{API_ROOT_PATH}/#{resource_name}/:id",
            action: "resources#show",
            summary: "Get #{resource_name.singularize}",
            description: "Get #{resource_name.singularize} by ID.",
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
            verb: "GET",
            path: "#{API_ROOT_PATH}/#{resource_name}/:id/actions",
            action: "resources#actions",
            summary: "Actions",
            description: "List actions available for this resource.",
            capability: nil,
            scope: nil,
            openapi: merge_hashes(
              {
                tags: [openapi_tag],
                parameters: [
                  id_parameter
                ],
                responses: resource_actions_responses(resource_name)
              },
              openapi_overrides.fetch(:actions, {})
            )
          }
        ]
      end

      def action_endpoints(resource_name, recordable_type)
        RecordingStudioApi.capability_actions_for(recordable_type)
          .sort_by(&:name)
          .map do |action|
            action_openapi = action.respond_to?(:openapi) && action.openapi.is_a?(Hash) ? action.openapi : {}

            {
              verb: action.http_verb.to_s.upcase,
              path: "#{API_ROOT_PATH}/#{resource_name}/:id/actions/#{action.name}",
              action: "member_actions#create",
              summary: action_openapi.fetch(:summary, "Execute #{action.name} for #{resource_name.singularize}"),
              description: "Execute the #{action.name} action.",
              action_name: action.capability.to_s,
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

      def default_action_openapi(resource_name, recordable_type, action)
        schema_name = RecordingStudioApi.recordable_recording_schema_name_for(recordable_type)
        openapi = {
          tags: [openapi_tag_for(resource_name)],
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
                      data: { "$ref" => "#/components/schemas/#{schema_name}" }
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

      def openapi_tag_for(resource_name)
        resource_name.to_s.singularize.humanize.titleize
      end

      def resource_list_responses(resource_name, recordable_type)
        schema_name = RecordingStudioApi.recordable_recording_schema_name_for(recordable_type)
        resource_type = recordable_type.to_s.demodulize.underscore

        {
          "200" => {
            description: "List #{resource_name} visible in scope.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    resource: { type: "string" },
                    type: { type: "string", example: resource_type },
                    data: {
                      type: "array",
                      items: { "$ref" => "#/components/schemas/#{schema_name}" }
                    }
                  },
                  required: %w[resource type data]
                }
              }
            }
          }
        }
      end

      def resource_item_responses(recordable_type)
        schema_name = RecordingStudioApi.recordable_recording_schema_name_for(recordable_type)

        {
          "200" => {
            description: "Single record payload.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    data: { "$ref" => "#/components/schemas/#{schema_name}" }
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

      def resource_actions_responses(_resource_name)
        {
          "200" => {
            description: "Actions available for this resource.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  properties: {
                    data: {
                      type: "array",
                      items: {
                        type: "object",
                        properties: {
                          name: { type: "string" },
                          action: { type: "string" },
                          http_verb: { type: "string" },
                          scope: { type: "string" }
                        },
                        required: %w[name action http_verb scope]
                      }
                    }
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
