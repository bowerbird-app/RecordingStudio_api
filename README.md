# RecordingStudio API

 Mountable Rails engine for a programmable Recording Studio API.

This repository now completes the last unfinished agent pass by renaming the live engine surfaces to `recording_studio_api` / `RecordingStudioApi` and replacing the placeholder docs with the original architecture handoff for the API gem.

## Current Scope

- OAuth2 client_credentials authentication backed by `RecordingStudioApi::ApiClient`, `ApiCredential`, and issued access tokens
- OAuth2 Authorization Code + PKCE, refresh-token rotation, and revocation for public mobile clients
- API client recordables stored beneath `RecordingStudio::Access` recordings in the Recording Studio tree
- authenticated API requests resolved into a `RecordingStudioApi::AccessGrant` that is passed to capability handlers
- capability-backed action registry with automatic action exposure when a recordable type enables that capability
- preserved template reference material in `docs/gem_template/`

The current codebase still ships the template engine mechanics (configuration, hooks, install generator, sample service objects), but the engine now also exposes a real JSON API surface for authenticated resource lookup and capability-backed member actions.

## API Architecture

### Core registries

`RecordingStudioApi` is intended to expose explicit registration layers for:

- authenticated API resources resolved from `RecordingStudio.configuration.recordable_types`
- actions backed by Recording Studio capabilities
- addon-owned handlers and serializers registered against those actions

Each action declares its verb, capability mapping, handler, and serializer so addon gems can register an API action once and let the API expose it automatically for any recordable type that enables the capability.

### Routing model

- top-level resources represent recordable roots or directly addressable records
- nested resources mirror the real recording tree, not ad hoc controller structure
- capability actions sit beside resources as explicit member or collection endpoints

### Access model

- the API core authenticates credentials and resolves the `RecordingStudio::Access` recording attached to those credentials
- `RecordingStudioApi::AccessGrant` carries `api_client`, `credential`, `access_recording`, `root_recording`, and the access actor into handlers
- capability handlers own authorization and should call `context.access_grant.authorize!` or `RecordingStudioAccessible.authorized?` before doing work
- the built-in resource, trash, and move handlers already perform their own grant checks
- `ApiClient` is the API credential principal for audit metadata, while the `RecordingStudio::Access` actor remains the Recording Studio authorization actor
- each access recording owns at most one active API credential record
- raw secrets should only be revealed at creation or rotation time

`ApiClient` is an immutable Recording Studio recordable. It is recorded as a child of a `RecordingStudio::Access` recording, while mutable credential and issued-token state lives in `ApiCredential` and `ApiAccessToken` with digest, rotation, revocation, and last-used tracking.

### Boot validation

The runtime should fail fast when:

- an API action points at a capability that is not enabled
- duplicate action names are registered
- required handlers or serializers are missing

## Ruby Integration Surface

Host apps and addon gems use these entrypoints for configuration, resource exposure, and capability registration:

```ruby
RecordingStudioApi.configure do |config|
  config.enable_feature_x = false
  config.timeout = 5
  config.layout_name = "application"
end

RecordingStudioApi.configuration
RecordingStudioApi::Hooks.run(:before_initialize)
RecordingStudioApi.register_recordable_type_api("Page", serializer: PageSerializer)
RecordingStudioApi.register_capability_action(:publish, capability: :publishable, handler: PublishRecording)
```

### Access management role settings

The gem uses Recording Studio access roles to control access-management UI and actions.

- `config.access_management_view_role` controls who can see API access records.
- `config.access_management_edit_role` controls who can create, edit, and revoke API access.

Defaults:

- `access_management_view_role: :view`
- `access_management_edit_role: :admin`

This means users with view-level access can inspect API access in the UI, but only admin-level access can mutate API access.

Example overrides:

```ruby
RecordingStudioApi.configure do |config|
  config.access_management_view_role = :edit
  config.access_management_edit_role = :admin
end
```

```ruby
RecordingStudioApi.configure do |config|
  config.access_management_view_role = :view
  config.access_management_edit_role = :edit
end
```

Allowed values are `:view`, `:edit`, and `:admin`. The view role must be less than or equal to the edit role.

Inbound API authentication uses OAuth2 access tokens issued from provisioned API client credentials.

### Provisioning and authentication

Provision client credentials from an existing `RecordingStudio::Access` recording:

```ruby
result = RecordingStudioApi::Services::ProvisionApiClient.call(
  access_recording: access_recording,
  name: "Primary token"
)

client_id = result.value.fetch(:credential).oauth_client_id
client_secret = result.value.fetch(:token)

oauth = RecordingStudioApi::Services::IssueOauthAccessToken.call(
  grant_type: "client_credentials",
  client_id: client_id,
  client_secret: client_secret
)

access_token = oauth.value.fetch(:access_token)
```

Or exchange credentials over HTTP:

```http
POST /recording_studio_api/oauth/token
grant_type=client_credentials&client_id=<client_id>&client_secret=<client_secret>
```

Authenticate API requests with:

```http
Authorization: Bearer <access_token>
```

### Authentication and authorization order

Each API request is evaluated in this order:

1. If enabled, the API pre-auth limiter throttles `/api/v1` requests by IP before bearer-token lookup.
2. OAuth2 authentication validates the bearer access token.
3. The engine resolves `current_api_client`, `current_api_credential`, `current_access_recording`, `current_root_recording`, and `current_access_grant`.
4. If enabled, the authenticated API limiter throttles by API credential/client, split between read and write buckets.
5. The API controller resolves the requested resource or action and dispatches to the registered handler with the access grant in context.
6. The capability handler authorizes its own behavior with the passed grant. Simple handlers can call `context.access_grant.authorize!(recording: ..., role: ...)`; complex handlers can check multiple recordings or roles with Recording Studio Accessible.

## Mobile Integration Guidance

The engine supports OAuth2 `client_credentials` for machine-to-machine access and Authorization Code + PKCE for public mobile clients. For mobile apps that can use a backend-for-frontend pattern, prefer it first:

1. Mobile app authenticates the user with host-app auth.
2. Mobile app calls your backend.
3. Backend exchanges/uses API credentials and calls RecordingStudioApi.
4. Backend returns scoped data to the app.

This keeps API secrets off-device while preserving workspace-scoped auditability in the Recording Studio tree.

If direct mobile-to-API OAuth is required, register a public OAuth client with an exact redirect URI, send users through `/recording_studio_api/oauth/authorize`, and let the token endpoint exchange authorization codes or refresh tokens. The same access-grant dispatch model is used after the mobile access token is presented to the JSON API.

### Capability-backed actions

Addon gems register actions once:

```ruby
RecordingStudioApi.register_capability_action(
  :move,
  capability: :movable,
  http_verb: :post,
  handler: RecordingStudioApi::Services::MoveRecording
)
```

If a recordable type enables `:movable`, the API automatically exposes the `move` action for that resource.

Handlers receive `RecordingStudioApi::ActionContext` or `RecordingStudioApi::ResourceOperationContext`. Custom handlers should authorize through the grant before mutating or exposing sensitive data:

```ruby
class PublishRecording
  def self.call(context)
    context.access_grant.authorize!(recording: context.recording, role: :edit)

    context.recording.recordable.update!(published_at: Time.current)
    context.recording
  end
end
```

### API endpoints

- `GET /recording_studio_api/admin_api` — browser admin dashboard for configured API access
- `GET /recording_studio_api/admin_api/logs` — browser admin request-log view
- `GET /recording_studio_api/oauth/authorize` — issue a PKCE authorization code for a public OAuth client
- `POST /recording_studio_api/oauth/token` — issue or refresh OAuth2 access tokens using `client_credentials`, `authorization_code`, or `refresh_token`
- `POST /recording_studio_api/oauth/revoke` — revoke a mobile OAuth grant session or token family
- `GET /recording_studio_api/api/v1` — list available API resources
- `GET /recording_studio_api/api/v1/:resource` — list recordings of a resource type inside the authenticated root
- `GET /recording_studio_api/api/v1/:resource/:id` — show one recording
- `GET /recording_studio_api/api/v1/trash` — list trashed recordings across all resource types in the authenticated root
- `GET /recording_studio_api/api/v1/trash/:id` — show one trashed recording
- `POST /recording_studio_api/api/v1/trash/:id/restore` — restore one trashed recording
- `DELETE /recording_studio_api/api/v1/trash/:id` — permanently delete one trashed recording
- `GET /recording_studio_api/api/v1/:resource/:id/actions` — list enabled capability actions
- `POST|PATCH|PUT|DELETE /recording_studio_api/api/v1/:resource/:id/actions/:action_name` — execute a capability-backed action via nested child actions (for example `/folders/:id/actions/move`)
- `POST|PATCH|PUT|DELETE /recording_studio_api/api/v1/:resource/:id/:action_name` — compatibility alias for existing clients

## Dummy App

Use `test/dummy/` as the review surface for the completed handoff:

- `/docs/install` documents the renamed install and migration flow
- `/docs/config` records the current config API plus the capability action registry
- `/docs/api_routes` documents mounted API endpoints and the generated JSON endpoint inventory
- `/docs/scalar` renders the generated OpenAPI explorer
- `/docs/auth` explains token exchange, access-grant resolution, and capability-owned authorization
- `/docs/add_capability` shows capability action registration patterns
- `/docs/methods` documents the live Ruby entrypoints
- `/docs/recordable_types`, `/docs/recordings_tree`, and `/docs/gem_views` verify Recording Studio wiring and the current gem view footprint

### Quick start

```bash
cd test/dummy
bin/rails db:setup
bin/dev
```

Sign in with:

- Email: `admin@admin.com`
- Password: `Password`

## Tech Stack

| Component       | Version |
|-----------------|---------|
| Ruby            | 3.3+    |
| Rails           | 8.1+    |
| PostgreSQL      | 16      |
| TailwindCSS     | 4       |
| RecordingStudio | v1.2.0 (pinned in `test/dummy/Gemfile`) |
| FlatPack        | v0.1.33 (pinned in `test/dummy/Gemfile`) |
| Devise          | latest  |

## Documentation

The original gem template documentation is preserved in this repository under `docs/gem_template/` as architectural reference material. Those files are for contributors reviewing the repo, not packaged gem docs; the README and dummy app are now the source of truth for the Recording Studio API design handoff.
