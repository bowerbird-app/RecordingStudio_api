# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  # Configure timeout, credential TTL, access token TTL, hooks, and action registration here.

  config.openapi_title = "Recording Studio API"
  config.openapi_description = "API endpoints for accessing and managing Recording Studio workspaces, folders, and pages."
  config.documentation_enabled = true
  config.documentation_access = :public
  config.layout_name = "recording_studio/default_layout"
  config.admin_layout_name = "recording_studio/default_layout"
  config.rate_limit_api_pre_auth_enabled = true
  config.rate_limit_api_enabled = true
  config.rate_limit_redis_url = ENV.fetch("RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL", "redis://127.0.0.1:6379/0")
  config.api_request_logging_enabled = true

  config.api :operations do |api|
    api.openapi_title = "Recording Studio Operations API"
    api.openapi_description = "Read-only operational access for trusted administrators and automation."
    api.documentation_enabled = true
    api.documentation_access = lambda do |controller:, actor:, api:|
      root_recording = controller.send(:current_root_recording)
      controller.send(:admin_root_current?) && RecordingStudioApi::Admin::ApiAuthorization.authorized?(
        actor: actor,
        api: api,
        root_recording: root_recording,
        role: RecordingStudioApi.configuration.access_management_view_role,
        create: true
      )
    end
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
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name],
)

RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name],
  writable_attributes: %i[name],
  relationships: {
    folders: {
      source: :children,
      child_type: "Folder",
      many: true,
      include: true,
      serializer: ->(folder, **) { { name: folder.name } },
      output_keys: %i[name],
      description: "The folders directly inside this workspace.",
      limit: 20,
      endpoints: %i[index show]
    },
    pages: {
      source: :children,
      child_type: "Page",
      many: true,
      include: :request,
      serializer: ->(page, **) { { title: page.title } },
      output_keys: %i[title],
      description: "The pages directly inside this workspace.",
      limit: 20,
      endpoints: %i[index show]
    },
    featured_folder: {
      source: :custom,
      many: false,
      include: :request,
      resolver: ->(context) do
        context.scoped_recordings.where(
          parent_recording_id: context.recording.id,
          recordable_type: "Folder"
        ).order(:created_at, :id).first
      end,
      serializer: ->(folder, **) { { name: folder.name } },
      output_keys: %i[name],
      description: "The first Folder directly inside this workspace."
    }
  },
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
                    records: [
                      {
                        id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        type: "workspace",
                        root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        parent_id: nil,
                        created_at: "2026-01-01T00:00:00Z",
                        updated_at: "2026-01-01T00:00:00Z",
                        name: "Editorial"
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
                    id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                    type: "workspace",
                    root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                    parent_id: nil,
                    created_at: "2026-01-01T00:00:00Z",
                    updated_at: "2026-01-01T00:00:00Z",
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
)

RecordingStudioApi.register_recordable_type_api(
  "Page",
  operations: %i[index show],
  serializer: ->(recordable, **) { { title: recordable.title } },
  output_keys: %i[title]
)

RecordingStudioApi.register_recordable_type_api(
  "Folder",
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name],
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
                    records: [
                      {
                        id: "74c7a8bd-9787-45dc-8479-40347f8c0422",
                        type: "folder",
                        root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                        parent_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        created_at: "2026-01-01T00:00:00Z",
                        updated_at: "2026-01-01T00:00:00Z",
                        name: "Marketing"
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
                    id: "74c7a8bd-9787-45dc-8479-40347f8c0422",
                    type: "folder",
                    root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                    parent_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                    created_at: "2026-01-01T00:00:00Z",
                    updated_at: "2026-01-01T00:00:00Z",
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
)
