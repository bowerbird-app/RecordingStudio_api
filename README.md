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

## Versioning Model

RecordingStudioApi separates public API versions from addon contribution contract versions.

- Public API versions are route and documentation labels such as `v1` and `v2`.
- Addon gems can register multiple contribution contracts for the same action with `version:`.
- Host apps map each public API version to compatible contribution contracts with `config.version` and `api.use`.
- Runtime dispatch and OpenAPI generation filter out incompatible contribution versions, then select the newest matching version.

Example host-app profile configuration:

```ruby
RecordingStudioApi.configure do |config|
  config.api_versions = %w[v1 v2]
  config.default_api_version = "v2"

  config.version "v1" do |api|
    api.use :moveable, "~> 1.23"
  end

  config.version "v2" do |api|
    api.use :moveable, "~> 2.0"
  end
end
```

Example addon registration:

```ruby
RecordingStudioApi.register_capability_action(
  :move,
  capability: :movable,
  version: "1.23.4",
  version_notes: ["Initial move contract", "Requires parent_id"],
  deprecation: {
    deprecated: true,
    removal_date: "2026-12-31",
    reason: "Replaced by move v2 with structured conflict errors"
  },
  handler: MoveRecordingV1
)

RecordingStudioApi.register_capability_action(
  :move,
  capability: :movable,
  version: "2.0.0",
  version_notes: ["Adds destination validation", "Returns structured conflict errors"],
  handler: MoveRecordingV2
)
```

Validation rules:

- Contribution versions must be RubyGems-compatible `Gem::Version` strings.
- Profile constraints use `Gem::Requirement` syntax.
- Same action name plus same contribution version is rejected as a duplicate.
- `version_notes` and grouped `deprecation` metadata are optional and do not affect matching.
- If no registered contribution matches a profile, that action is omitted for that public API version.

## API Architecture

### Core registries

`RecordingStudioApi` is intended to expose explicit registration layers for:

- authenticated API resources resolved from declared `RecordingStudio.configuration.recordable_types`
- actions backed by Recording Studio capabilities
- addon-owned handlers and serializers registered against those actions

Recording Studio 3.x requires every configured ActiveRecord recordable to declare its hierarchy with
`recording_studio_recordable(...)`. Host apps must mark real roots with `root: true`, declare
`allowed_parent_types` for child-capable recordables, and enable `RecordingStudio.enable_capability(:accessible, on: ...)`
for every recordable that can own direct access grants. The dummy app marks `Workspace` and `Folder` as root-capable,
keeps `Page` as a child recordable, and the API engine registers its internal `RecordingStudio::Access`, API client,
credential, token, OAuth, and admin API recordables with explicit parent rules.

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
- duplicate action name plus contribution version pairs are registered
- required handlers or serializers are missing
- contribution versions or version-profile constraints are malformed

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
RecordingStudioApi.register_capability_action(
  :publish,
  capability: :publishable,
  version: "1.0.0",
  version_notes: ["Initial publish contract"],
  deprecation: {
    deprecated: true,
    removal_date: "2026-12-31",
    reason: "Use publish v2"
  },
  handler: PublishRecording
)
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

1. If enabled, the API pre-auth limiter throttles configured `/api/<version>` requests by IP before bearer-token lookup.
2. OAuth2 authentication validates the bearer access token.
3. The engine resolves `current_api_client`, `current_api_credential`, `current_access_recording`, `current_root_recording`, and `current_access_grant`.
4. If enabled, the authenticated API limiter throttles by API credential/client, split between read and write buckets.
5. The API controller resolves the requested public API version, selects the newest compatible contribution contract, and dispatches to the registered handler with the access grant in context.
6. The capability handler authorizes its own behavior with the passed grant. Simple handlers can call `context.access_grant.authorize!(recording: ..., role: ...)`; complex handlers can check multiple recordings or roles with Recording Studio Accessible.

### External auth gem integration contract

This gem exposes a small integration surface so a separate app-auth gem can authenticate bearer tokens and reuse RecordingStudioApi authorization without duplicating access-grant logic.

#### Public integration methods

- `RecordingStudioApi.authenticate_authorization_header(authorization_header:)`
  - Authenticates a `Bearer` header and returns a service result whose `value` is a `RecordingStudioApi::AuthenticatedClient`.
- `RecordingStudioApi.build_access_grant(authenticated_client:)`
  - Builds a `RecordingStudioApi::AccessGrant` from an authenticated client context.
- `RecordingStudioApi.access_grant_from_authorization_header(authorization_header:)`
  - One-step helper that authenticates and returns an `AccessGrant` in the result `value`.
- `RecordingStudioApi.actor_access_recordings(actor:)`
  - Returns active access recordings available to an actor.
- `RecordingStudioApi.resolve_access_recording_for_actor(actor:, requested_access_recording_id: nil)`
  - Resolves access selection for multi-workspace actors and returns `{ recording:, candidates:, error: }`.
- `RecordingStudioApi.oauth_error_payload(error)` and `RecordingStudioApi.oauth_error_status(error)`
  - Maps OAuth-style errors to normalized payloads and HTTP statuses.

#### Token authenticator extension point

External gems can register additional bearer-token authenticators. If the external gem uses this gem's `rsapi_at_...` access-token format, the authenticator only needs to implement `call`. If it uses a different token prefix or shape, it should also implement `valid_format?` so the API gem knows to let it inspect that token.

```ruby
class MyAppAccess::TokenAuthenticator
  def self.valid_format?(token)
    token.to_s.start_with?("rsapp_at_")
  end

  def self.call(token:)
    session = MyAppAccess::Session.find_by_raw_token(token)
    return if session.nil?

    {
      credential: session.access_credential,
      token_record: session
    }
  end
end

RecordingStudioApi.register_token_authenticator(MyAppAccess::TokenAuthenticator)
```

Registered authenticators are evaluated by `RecordingStudioApi::Services::AuthenticateOauthAccessToken` after built-in API access-token checks.

Authenticator method contract:

- `valid_format?(token)` is optional for authenticators that use the built-in `RecordingStudioApi::OauthAccessToken` format.
- `valid_format?(token)` is required when the external gem uses its own token prefix or shape.
- `call(token:)` resolves an accepted token to an access context.

Accepted authenticator return values:

- `nil` to indicate no match.
- `Hash` with `credential:` and optional `token_record:`.
- `Array` in `[credential, token_record]` shape.
- Any credential-like object as shorthand (`token_record` defaults to that same object).

Credential contract required by token authentication:

- `active_for_authentication?`
- `effective_access_recording`
- `effective_access_recording_id`
- `api_client`
- writable `last_used_at` column (updated with `update_column`)

Token-record contract (if provided):

- `active_for_authentication?`
- writable `last_used_at` column (updated with `update_column`)

Both credential and token record must have active, non-trashed RecordingStudio recordables so scope resolution can derive the root recording.

### Capability-backed actions

Addon gems register actions once:

```ruby
RecordingStudioApi.register_capability_action(
  :move,
  capability: :movable,
  version: "2.0.0",
  version_notes: ["Adds destination validation"],
  http_verb: :post,
  handler: RecordingStudioApi::Services::MoveRecording
)
```

If a recordable type enables `:movable`, the API automatically exposes the newest compatible `move` contribution selected for the current public API version.

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
- `GET /admin/screens/api_logs` — RecordingStudioAdmin V1 API request-log screen when the host mounts the admin surface
- `GET /recording_studio_api/admin_api/logs` — legacy browser admin request-log route; redirects to the Admin V1 screen when RecordingStudioAdmin is available
- `POST /recording_studio_api/oauth/token` — issue OAuth2 bearer access tokens using `client_credentials`
- `GET /recording_studio_api/api/<version>` — list available API resources for the selected public API version
- `GET /recording_studio_api/api/<version>/:resource` — list recordings of a resource type inside the authenticated root
- `GET /recording_studio_api/api/<version>/:resource/:id` — show one recording
- `GET /recording_studio_api/api/<version>/trash` — list trashed recordings across all resource types in the authenticated root
- `GET /recording_studio_api/api/<version>/trash/:id` — show one trashed recording
- `POST /recording_studio_api/api/<version>/trash/:id/restore` — restore one trashed recording
- `DELETE /recording_studio_api/api/<version>/trash/:id` — permanently delete one trashed recording
- `POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/:resource/:id/actions/:action_name` — execute the newest compatible contribution contract for that public API version
- `POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/:resource/:id/:action_name` — compatibility alias for existing clients

Additional configured public API versions currently alias the shared controller implementation while still selecting version-specific contribution contracts and OpenAPI documents.

## Dummy App

Use `test/dummy/` as the review surface for the completed handoff:

- `/docs/install` documents the renamed install and migration flow
- `/docs/config` records the current config API plus the capability action registry
- `/docs/versions` explains public API versions, contribution versions, version notes, deprecation metadata, and validation rules
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
