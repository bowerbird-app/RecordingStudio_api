# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  # Configure timeout, token_ttl, hooks, and action registration here.

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
                      title: "Marketing",
                      actions: ["movable"],
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
      description: "List workspace recordings that are visible inside the authenticated scope.",
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
                        title: "Editorial",
                        actions: [],
                        root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        parent_id: nil,
                        attributes: {
                          name: "Editorial"
                        }
                      }
                    ]
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
      description: "Return one workspace recording with workspace-specific details.",
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
                      title: "Editorial",
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
    },
    actions: {
      summary: "List workspace actions",
      description: "List capability actions currently available for the selected workspace.",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    data: []
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
      description: "List folder recordings that the API client can access.",
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
                        title: "Marketing",
                        actions: ["movable"],
                        root_id: "8f8ee9f8-5448-4438-b65f-7578f69009f1",
                        parent_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        attributes: {
                          name: "Marketing"
                        }
                      }
                    ]
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
      description: "Return one folder recording, including folder details and enabled capabilities.",
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
                      title: "Marketing",
                      actions: ["movable"],
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
    },
    actions: {
      summary: "List folder actions",
      description: "List capability actions available for this folder (for example move).",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    data: [
                      {
                        name: "move",
                        action: "movable",
                        http_verb: "post",
                        scope: "member"
                      }
                    ]
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
  serializer: ->(recordable) { { title: recordable.title } },
  openapi: {
    details_schema: {
      type: "object",
      properties: {
        title: { type: "string", description: "Page attributes." }
      },
      required: ["title"]
    },
    index: {
      summary: "List pages",
      description: "List page recordings visible inside the authenticated root scope.",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    resource: "pages",
                    type: "page",
                    data: [
                      {
                        id: "a39ed0af-daf0-424a-8011-4c28889f658f",
                        type: "page",
                        title: "Welcome",
                        actions: [],
                        root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                        parent_id: "f8792164-4d83-4810-8c89-6484feff5d28",
                        attributes: {
                          title: "Welcome"
                        }
                      }
                    ]
                  }
                }
              }
            }
          }
        }
      }
    },
    show: {
      summary: "Get page",
      description: "Return one page recording with page-specific details.",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    data: {
                      id: "a39ed0af-daf0-424a-8011-4c28889f658f",
                      type: "page",
                      title: "Welcome",
                      actions: [],
                      root_id: "5ed47afc-f67f-4f4a-af7b-8f62f2eec85f",
                      parent_id: "f8792164-4d83-4810-8c89-6484feff5d28",
                      attributes: {
                        title: "Welcome"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    actions: {
      summary: "List page actions",
      description: "List capability actions available for this page.",
      responses: {
        "200" => {
          content: {
            "application/json" => {
              examples: {
                default: {
                  value: {
                    data: []
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
