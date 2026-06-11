# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  # Configure timeout, token_ttl, hooks, and action registration here.

  config.admin_layout_name = "flat_pack_sidebar"
  config.rate_limit_api_pre_auth_enabled = true
  config.rate_limit_api_enabled = true
  config.rate_limit_redis_url = ENV.fetch("RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL", "redis://127.0.0.1:6379/0")
  config.api_request_logging_enabled = true

  config.admin_dashboard_path_resolver = lambda do |controller:, **|
    controller.main_app.admin_api_path
  end

  config.admin_requests_path_resolver = lambda do |controller:, **params|
    controller.main_app.admin_api_requests_path(params)
  end

  config.admin_errors_path_resolver = lambda do |controller:, **params|
    controller.main_app.admin_api_errors_path(params)
  end

  config.admin_logs_path_resolver = lambda do |controller:, **params|
    controller.main_app.admin_api_logs_path(params)
  end

  config.action_registry.register(
    :trash,
    capability: :trashable,
    http_verb: :post,
    handler: ->(context) { Dummy::Api::Actions::TrashRecording.call(context) },
    openapi: {
      summary: "Trash",
      description: "Soft-delete a trashable resource and return the updated recording payload.",
      responses: {
        "200" => {
          description: "Recording moved to trash.",
          content: {
            "application/json" => {
              examples: {
                trashed: {
                  value: {
                    data: {
                      id: "74c7a8bd-9787-45dc-8479-40347f8c0422",
                      type: "page",
                      actions: ["trash"],
                      root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                      parent_id: "a8f2ab7d-2f2e-4062-9fe2-10e490a2d664",
                      trashed_at: "2026-05-26T00:00:00Z",
                      attributes: {
                        title: "Homepage"
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

  config.action_registry.register(
    :move,
    capability: :movable,
    http_verb: :post,
    handler: RecordingStudioApi::Services::MoveRecording,
    serializer: RecordingStudioApi::Serializers::ResourceRecordingSerializer,
    openapi: {
      summary: "Move",
      description: "Move item to allowed destination",
      request_body: {
        required: true,
        content: {
          "application/json" => {
            schema: {
              type: "object",
              properties: {
                parent_id: { type: "string", description: "Destination resource id." }
              },
              required: ["parent_id"]
            },
            examples: {
              default: {
                value: {
                  parent_id: "a8f2ab7d-2f2e-4062-9fe2-10e490a2d664"
                }
              }
            }
          }
        }
      },
      responses: {
        "200" => {
          description: "Moved recording payload.",
          content: {
            "application/json" => {
              examples: {
                moved: {
                  value: {
                    data: {
                      id: "74c7a8bd-9787-45dc-8479-40347f8c0422",
                      type: "folder",
                      actions: ["move"],
                      root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                      parent_id: "a8f2ab7d-2f2e-4062-9fe2-10e490a2d664",
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
  )
end

RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  serializer: ->(recordable) { { name: recordable.name } },
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

