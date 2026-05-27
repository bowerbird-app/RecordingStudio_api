# RecordingStudio API

 Mountable Rails engine for a programmable Recording Studio API.

This repository now completes the last unfinished agent pass by renaming the live engine surfaces to `recording_studio_api` / `RecordingStudioApi` and replacing the placeholder docs with the original architecture handoff for the API gem.

## Current Scope

- OAuth2 client_credentials authentication backed by `RecordingStudioApi::ApiClient`, `ApiCredential`, and issued access tokens
- API client recordables stored beneath `RecordingStudio::Access` recordings in the Recording Studio tree
- capability-backed action registry with automatic action exposure when a recordable type enables that capability
- preserved template reference material in `docs/gem_template/`

The current codebase still ships the template engine mechanics (configuration, hooks, install generator, sample service objects), but the engine now also exposes a real JSON API surface for authenticated resource lookup and capability-backed member actions.

## Proposed API Architecture

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

- authorization should flow through accessible records in the authenticated root scope
- `ApiClient` is the acting API principal
- each access recording owns at most one active API credential record
- raw secrets should only be revealed at creation or rotation time

`ApiClient` is an immutable Recording Studio recordable. It is recorded as a child of a `RecordingStudio::Access` recording, while mutable credential and issued-token state lives in `ApiCredential` and `ApiAccessToken` with digest, rotation, revocation, and last-used tracking.

### Boot validation

The eventual runtime should fail fast when:

- an API action points at a capability that is not enabled
- duplicate action names are registered
- required handlers or serializers are missing

## Current Ruby Surface

The renamed engine currently exposes the same basic Ruby integration points as the template:

```ruby
RecordingStudioApi.configure do |config|
  config.enable_feature_x = false
  config.timeout = 5
  config.layout_name = "application"
end

RecordingStudioApi.configuration
RecordingStudioApi::Hooks.run(:before_initialize)
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

1. OAuth2 authentication validates the bearer access token.
2. The engine resolves `current_api_client`, `current_api_credential`, `current_access_recording`, and `current_root_recording`.
3. Recording Studio accessible scopes constrain resource queries and member actions to what that authenticated client can access.

## Mobile Integration Guidance

The current engine implements OAuth2 `client_credentials` for machine-to-machine access.
For mobile apps, prefer a backend-for-frontend pattern first:

1. Mobile app authenticates the user with host-app auth.
2. Mobile app calls your backend.
3. Backend exchanges/uses API credentials and calls RecordingStudioApi.
4. Backend returns scoped data to the app.

This keeps API secrets off-device while preserving workspace-scoped auditability in the Recording Studio tree.

If direct mobile-to-API OAuth is required, staged implementation guidance is documented in [docs/MOBILE_AUTH_ROADMAP.md](docs/MOBILE_AUTH_ROADMAP.md).

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

### API endpoints

- `POST /recording_studio_api/oauth/token` — issue OAuth2 access token using `client_credentials`
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
- `/docs/api` and `/docs/api_routes` document OAuth2 exchange and mounted API endpoints
- `/docs/auth` explains token exchange plus post-auth Recording Studio access scoping
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
