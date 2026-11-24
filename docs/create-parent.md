# Server-chosen create parent

A non-root create requires `parent_id` in the body. Pass an option when the server chooses the parent and the caller cannot look one up. The default stays the caller-supplied `parent_id`.

The documentation catalog sets `parent` to `"server"` on that create endpoint. The generated OpenAPI operation sets `x-parent` to `"server"`. Both leave `parent_id` out of the create request schema. A client that still sends `parent_id` is ignored. The value does not change the parent, and it is left out of the idempotency fingerprint.

The resolved parent is loaded again from the client's accessible recordings and must belong to the grant's root. A parent outside that scope is HTTP 404 `not_found`. Handler authorization is unchanged. The handler still calls `access_grant.authorize!` or Accessible.

## Built-in create

`create_parent: :server` requires `parent_resolver:`. The callable receives the resource operation context and returns a recording or an id. Omit the callable and registration raises `RecordingStudioApi::ConfigurationError`.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Note",
  create_parent: :server,
  parent_resolver: ->(context) { context.root_recording },
  serializer: ->(note, **) { { body: note.body } },
  output_keys: %i[body],
  writable_attributes: %i[body]
)
```

A nested create still uses the parent in the URL. The resolver runs for a top-level create.

## Custom create handler

Pass `parent: :server` on the create handler. Do not pass `parent_resolver`. On a top-level create, `context.parent_recording` is nil. The handler chooses the parent.

Support files a ticket with `TicketOpen`, which always uses support's own area and does not read `parent_id`. Add the option on that registration.

```ruby
# lib/recording_studio_support/api/ticket_type.rb
def register_handler(action, api:, handler:, owns_scoping: false, parent: nil)
  Registration.register_handler(
    TICKET_TYPE,
    action,
    api: api,
    handler: handler,
    owns_scoping: owns_scoping,
    parent: parent
  )
end

register_handler(:create, api: :public, handler: TicketOpen, parent: :server)
```

```ruby
# lib/recording_studio_support/api/registration.rb
def register_handler(type, action, api:, handler:, owns_scoping: false, parent: nil)
  return if RecordingStudioApi.resource_handler(type, action, api: api)

  RecordingStudioApi.register_resource_handler(
    type,
    action,
    api: api,
    handler: handler,
    owns_scoping: owns_scoping,
    parent: parent
  )
end
```

`parent: :server` on any action other than create raises `ConfigurationError`.

## Creating capability action

Pass `parent: :server` together with `creates: true`. Without `creates: true`, registration raises `ConfigurationError`. There is no resolver. `parent_id` is removed from the action input schema and ignored when a client sends it.

```ruby
RecordingStudioApi.register_capability_action(
  :file_note,
  capability: :notable,
  creates: true,
  parent: :server,
  handler: FileNote
)
```

## For MCP

Read `DocumentationCatalog`. On a create endpoint, `parent` is `"server"` when the server chooses the parent. Drop `parent_id` from the tool schema when that flag is set. The same flag is `x-parent` on the generated OpenAPI operation. A non-root type that does not set the flag still requires `parent_id`. `root_allowed?` does not replace the flag.
