# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  # Configure timeout, credential TTL, access token TTL, hooks, and action registration here.

  config.openapi_title = "Recording Studio API"
  config.openapi_description = "API endpoints for accessing and managing Recording Studio workspaces, folders, and pages."
  config.admin_layout_name = "recording_studio/default_layout"
  config.rate_limit_api_pre_auth_enabled = true
  config.rate_limit_api_enabled = true
  config.rate_limit_redis_url = ENV.fetch("RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL", "redis://127.0.0.1:6379/0")
  config.api_request_logging_enabled = true

  config.api :operations do |api|
    api.openapi_title = "Recording Studio Operations API"
    api.openapi_description = "Read-only operational access for trusted administrators and automation."
    api.authentication = :oauth
    api.default_access = :read_only
    api.api_management_authorization_required = true
    api.rate_limit_oauth_enabled = true
    api.rate_limit_api_pre_auth_enabled = true
    api.rate_limit_api_enabled = true
    api.api_request_logging_enabled = true
  end

  config.admin_dashboard_path_resolver = lambda do |controller:, api_key: "public", **|
    api_key.to_s == "public" ? "/admin/api" : "/admin/api/#{api_key}"
  end
end

RecordingStudioApi.register_recordable_type_api(
  "AdminRoot",
  api: :operations,
  operations: %i[index show],
  serializer: ->(recordable) { { name: recordable.name } }
)

RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  serializer: ->(recordable) { { name: recordable.name } },
  writable_attributes: %i[name],
  openapi: {
    details_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Workspace attributes." }
      },
      required: ["name"]
    },
    index: {
      summary: "List workspaces",
      description: "List workspaces",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    resource: "workspaces",
                    type: "workspace",
                    data: [
                      {
                        id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        type: "workspace",
                        actions: [],
                        root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        parent_id: nil,
                        attributes: {
                          name: "Editorial"
                        }
                      }
                    ],
                    meta: {
                      limit: 50,
                      sort: "created_at",
                      order: "asc",
                      has_more: false,
                      next_pagination_token: nil
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    show: {
      summary: "Get workspace",
      description: "Get workspace",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    data: {
                      id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                      type: "workspace",
                      actions: [],
                      root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                      parent_id: nil,
                      attributes: {
                        name: "Editorial"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
)

RecordingStudioApi.register_recordable_type_api(
  "Folder",
  serializer: ->(recordable) { { name: recordable.name } },
  writable_attributes: %i[name],
  capability_actions: %i[move],
  openapi: {
    details_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Folder attributes." }
      },
      required: ["name"]
    },
    index: {
      summary: "List folders",
      description: "List folders",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    resource: "folders",
                    type: "folder",
                    data: [
                      {
                        id: "74c7a8bd-9787-45dc-8479-40347f8c0422",
                        type: "folder",
                        actions: ["move"],
                        root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                        parent_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        attributes: {
                          name: "Marketing"
                        }
                      }
                    ],
                    meta: {
                      limit: 50,
                      sort: "created_at",
                      order: "asc",
                      has_more: false,
                      next_pagination_token: nil
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    show: {
      summary: "Get folder",
      description: "Get folder",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    data: {
                      id: "74c7a8bd-9787-45dc-8479-40347f8c0422",
                      type: "folder",
                      actions: ["move"],
                      root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                      parent_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                      attributes: {
                        name: "Marketing"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
)

