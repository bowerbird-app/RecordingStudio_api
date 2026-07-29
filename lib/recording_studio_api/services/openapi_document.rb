# frozen_string_literal: true

require "digest"

module RecordingStudioApi
  module Services
    class OpenapiDocument
      OPENAPI_VERSION = "3.0.3"
      OAUTH_TOKEN_PATH = "/recording_studio_api/oauth/token"

      class << self
        def call(version: nil, mount_path: nil, api_mount_path: nil)
          new(version: version, mount_path: mount_path, api_mount_path: api_mount_path).call
        end
      end

      def initialize(version: nil, mount_path: nil, api_mount_path: nil)
        @api_version = RecordingStudioApi.resolve_api_version(version)
        @mount_path = mount_path
        @api_mount_path = api_mount_path
      end

      def call
        {
          openapi: OPENAPI_VERSION,
          info: {
            title: RecordingStudioApi.openapi_title,
            version: RecordingStudioApi::VERSION,
            description: RecordingStudioApi.openapi_description
          },
          servers: [
            { url: "/", description: "Host application root" }
          ],
          paths: paths,
          components: components,
          security: [
            { bearerAuth: [] }
          ]
        }
      end

      private

      def paths
        all_endpoints.each_with_object({}) do |endpoint, output|
          path = normalize_path(endpoint.fetch(:path))
          verb = endpoint.fetch(:verb).downcase

          output[path] ||= {}
          output[path][verb] = operation_for(endpoint)
        end
      end

      def all_endpoints
        catalog = RecordingStudioApi.documentation_catalog(
          version: @api_version,
          mount_path: @mount_path,
          api_mount_path: @api_mount_path
        )
        resource_endpoints = catalog.fetch(:resources).flat_map { |section| section.fetch(:endpoints) }

        catalog.fetch(:auth_endpoints) + catalog.fetch(:root_endpoints) + resource_endpoints
      end

      def operation_for(endpoint)
        metadata = endpoint.fetch(:openapi, {})
        summary = endpoint.fetch(:summary, endpoint.fetch(:description))

        operation = {
          operationId: operation_id_for(endpoint),
          summary: metadata.fetch(:summary, summary),
          description: metadata.fetch(:description, endpoint.fetch(:description)),
          tags: Array(metadata.fetch(:tags, [tag_for(endpoint)])),
          parameters: normalize_parameters(metadata.fetch(:parameters, [])),
          responses: responses_for(endpoint)
        }

        request_body = metadata[:request_body]
        operation[:requestBody] = request_body if request_body.present?

        security = security_for(endpoint, metadata)
        operation[:security] = security if security

        operation
      end

      def responses_for(endpoint)
        metadata = endpoint.fetch(:openapi, {})
        responses = default_responses_for(endpoint)
        responses.merge(stringify_keys(metadata.fetch(:responses, {})))
      end

      def default_responses_for(endpoint)
        if token_endpoint?(endpoint)
          {
            "401" => { "$ref" => "#/components/responses/Unauthorized" },
            "422" => { "$ref" => "#/components/responses/UnprocessableEntity" }
          }
        else
          {
            "401" => { "$ref" => "#/components/responses/Unauthorized" },
            "403" => { "$ref" => "#/components/responses/Forbidden" },
            "404" => { "$ref" => "#/components/responses/NotFound" }
          }
        end
      end

      def security_for(endpoint, metadata)
        return metadata.fetch(:security, []) if token_endpoint?(endpoint)

        metadata.fetch(:security, [{ bearerAuth: [] }])
      end

      def normalize_parameters(parameters)
        parameters.map { |parameter| stringify_keys(parameter) }
      end

      def normalize_path(path)
        path.gsub(/:([a-z_]+)/, '{\1}')
      end

      def operation_id_for(endpoint)
        action = endpoint.fetch(:action)
        suffix = endpoint.fetch(:verb).downcase

        "#{action.tr('#', '_')}_#{suffix}_#{Digest::SHA1.hexdigest(endpoint.fetch(:path))[0...8]}"
      end

      def components
        {
          securitySchemes: {
            bearerAuth: {
              type: "http",
              scheme: "bearer",
              bearerFormat: "OAuth2"
            },
            oauthClientCredentials: {
              type: "oauth2",
              flows: {
                clientCredentials: {
                  tokenUrl: oauth_token_path,
                  scopes: {}
                }
              }
            }
          },
          schemas: {
            Error: {
              type: "object",
              properties: {
                error: { type: "string" },
                details: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      attribute: { type: "string" },
                      message: { type: "string" },
                      full_message: { type: "string" },
                      type: { type: "string" }
                    }
                  }
                }
              },
              required: ["error"]
            },
            OAuthTokenResponse: {
              type: "object",
              properties: {
                access_token: { type: "string" },
                token_type: { type: "string", enum: ["Bearer"] },
                expires_in: { type: "integer" }
              },
              required: %w[access_token token_type expires_in]
            }
          },
          responses: {
            Unauthorized: {
              description: "Authentication failed.",
              content: {
                "application/json" => {
                  schema: { "$ref" => "#/components/schemas/Error" }
                }
              }
            },
            Forbidden: {
              description: "Caller does not have permission for this operation.",
              content: {
                "application/json" => {
                  schema: { "$ref" => "#/components/schemas/Error" }
                }
              }
            },
            NotFound: {
              description: "Requested resource was not found in scope.",
              content: {
                "application/json" => {
                  schema: { "$ref" => "#/components/schemas/Error" }
                }
              }
            },
            UnprocessableEntity: {
              description: "Request validation failed.",
              content: {
                "application/json" => {
                  schema: { "$ref" => "#/components/schemas/Error" }
                }
              }
            }
          }
        }
      end

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child_value), output|
            normalized_key = key.to_s
            normalized_value = stringify_keys(child_value)

            if output.key?(normalized_key)
              output[normalized_key] = merge_stringified_values(output[normalized_key], normalized_value)
            else
              output[normalized_key] = normalized_value
            end
          end
        when Array
          value.map { |child_value| stringify_keys(child_value) }
        else
          value
        end
      end

      def merge_stringified_values(existing_value, incoming_value)
        return existing_value.merge(incoming_value) { |_key, existing_child, incoming_child| merge_stringified_values(existing_child, incoming_child) } if existing_value.is_a?(Hash) && incoming_value.is_a?(Hash)

        incoming_value
      end

      def tag_for(endpoint)
        return "auth" if token_endpoint?(endpoint)

        "resources"
      end

      def token_endpoint?(endpoint)
        endpoint.fetch(:path) == oauth_token_path
      end

      def oauth_token_path
        @oauth_token_path ||= begin
          mount_path = @mount_path.presence || DocumentationCatalog::DEFAULT_MOUNT_PATH
          path_segments = mount_path.to_s.squeeze("/").split("/").reject(&:blank?)

          "/#{(path_segments + %w[oauth token]).join('/')}"
        end
      end
    end
  end
end