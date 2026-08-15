# RecordingStudio API

 Mountable Rails engine for a programmable Recording Studio API.

`RecordingStudioApi` is a mountable Rails engine that provides authenticated, capability-backed JSON APIs for Recording Studio addons.

For breaking changes in `0.4.0` (safer defaults and hardening) and the flat API contract from
`0.3.0`, see [UPGRADING.md](UPGRADING.md).

## Current Scope

- OAuth2 `client_credentials` authentication backed by `RecordingStudioApi::ApiClient`, `ApiCredential`, and issued access tokens
- external bearer-token authenticator support for host application authentication systems
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

## Scalar API documentation

Install a named Scalar reference in a host application:

```sh
bin/rails generate recording_studio_api:scalar_docs public_api \
  --mount-path=/api-docs \
  --api-mount-path=/recording_studio_api
```

The gem owns the Scalar controller, default views, OpenAPI endpoint, version checks, and access
enforcement, so gem upgrades update existing installations automatically. The generator adds a
marked route declaration and a small initializer; it does not copy controllers or views into the
host application.

The routes serve `/api-docs/v1`, `/api-docs/v1/fullscreen`, and
`/api-docs/v1/openapi.json`. Unsupported versions and disabled documentation return `404`.
The generated access mode defaults to `authenticated`; pass `--access=public` only when publishing
the API schema is intentional.

Configure a callable policy for private APIs in the main initializer:

```ruby
RecordingStudioApi.configure do |config|
  config.api :operations do |api|
    api.documentation_enabled = true
    api.documentation_access = lambda do |controller:, actor:, api:|
      OperationsDocsPolicy.allowed?(controller: controller, actor: actor, api: api)
    end
  end
end
```

The policy protects the embedded page, fullscreen page, and OpenAPI JSON. It receives the engine
controller, resolved actor, and canonical API name. A missing actor returns `401`; a rejected
authenticated actor returns `403`.

When documentation access is `:public`, the canonical version URL renders the standalone,
full-width reference for anonymous visitors. Signed-in visitors receive the configured embedded
layout and its **Full width** action. Responses from the canonical public URL vary on the session
cookie so shared caches do not mix the two presentations.

Install a named API at a host-selected path with:

```sh
bin/rails generate recording_studio_api:scalar_docs operations_api \
  --mount-path=/admin/operations-api/docs \
  --api-surface=operations
```

The equivalent manual route declaration is:

```ruby
recording_studio_api_scalar_docs_for :operations,
  at: "/admin/operations-api/docs",
  as: :operations_api_scalar_docs,
  engine_mount_path: "/recording_studio_api"
```

Embedded docs use `api.documentation_layout_name`, then `config.layout_name`, then
`recording_studio/default_layout`. Custom layouts should render the `page_nav_right` content slot
to display the **Full width** action. The fullscreen response is layout-free. A host may override
the gem views through normal Rails view lookup or add
`recording_studio_api/scalar_docs/_extension.html.erb` for application-specific content.

An optional local test-token page can be installed separately after the Scalar routes:

```sh
bin/rails generate recording_studio_api:test_auth public_api \
  --mount-path=/docs/scalar \
  --api-surface=public
```

This generates a standalone host-owned page at
`/docs/scalar/:version/test-credential`; it does not add token controls to the API documentation.
The page and its create/revoke actions are local-only by default and require both an authenticated
actor and manageable API access. Disabled access returns `404`, missing authentication returns
`401`, and insufficient access returns `403`. Generated tokens are real, scoped, audited, and
revocable credentials, so production enablement must use an explicit host policy.

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

### Named APIs

The legacy configuration is the `public` API. Additional APIs have independent versions,
registries, OpenAPI metadata, enablement, logging, and request dispatch while sharing host-level
infrastructure such as Redis connectivity and access-role policy.

```ruby
RecordingStudioApi.configure do |config|
  config.api :operations do |api|
    api.openapi_title = "Operations API"
    api.openapi_description = "Read-only diagnostics for trusted automation."
    api.api_versions = %w[v1]
    api.default_access = :read_only
    api.api_management_authorization_required = true
    api.credential_ttl = 12.hours
    api.access_token_ttl = 15.minutes
    api.rate_limit_api_read_requests = 30
    api.api_request_logging_enabled = true
  end
end

RecordingStudioApi.register_recordable_type_api(
  "AdminRoot",
  api: :operations,
  operations: %i[index show]
)
```

Public routes remain `/recording_studio_api/api/<version>`. Named APIs use
`/recording_studio_api/apis/<api-name>/<version>` and obtain tokens from
`/recording_studio_api/apis/<api-name>/oauth/token`.

API clients are bound to exactly one API. Provision and authenticate named clients with `api:`;
a public token is rejected on every named API and vice versa. The existing site-wide API switch remains a global kill switch, while `ApiSetting.for_api`
supports additional per-API switches. Admins can also set runtime overrides for request logging,
credential/access-token TTLs, retention, and rate-limit enables/thresholds from the Admin API
settings and rate-limiting pages. Blank override fields fall back to initializer defaults; Redis
URL/namespace and digest peppers stay deploy-time only.

Named APIs inherit credential and token TTLs, rate-limit windows, and request-payload logging policy
from the public configuration when declared. Each definition can then override those values without
changing another API. Redis connectivity, namespaces, and telemetry retention remain shared
infrastructure.

Set `api_management_authorization_required` for trusted APIs. Credential creation then requires both
the requested RecordingStudioAccessible data grant and management access to that API's `AdminApi`
recording beneath the configured admin root. Public and unprotected named APIs retain the existing
access-point delegation behavior.

### Admin surfaces

Generate host integration declarations for the public and named APIs together:

```sh
bin/rails generate recording_studio_api:admin_screens \
  --user-roots Workspace \
  --user-apis public \
  --admin-roots AdminRoot \
  --admin-apis public operations
```

This adds RecordingStudioAdmin routes and section declarations only. RecordingStudioApi owns and
registers the shared screens, widgets, queries, and state-changing credential controllers, so gem
upgrades do not leave copied host files behind. Named surfaces pass an API context into those shared
definitions and remain independently authorized, configured, and filtered. Keeping `operations` out
of `--user-apis` makes it available only from the site administration root. Every recordable used as
an API credential access point must enable Recording Studio's `api_access_point` capability; the gem
then intersects that capability with the selected API's registered recordables.

### Request logging and metrics retention

When `api_request_logging_enabled` is on, each API request can write a row to the API logging
database. Admin charts prefer rolled-up daily metrics, so hosts should run maintenance nightly:

1. Aggregate the last few complete days into `api_daily_metrics` (and latency histogram buckets).
2. Delete raw `api_request_logs` older than `api_request_log_retention_days` (default 30).
3. Optionally delete daily metrics older than `api_daily_metric_retention_days` (default `nil` =
   keep forever).

```sh
# Synchronous maintain (cron / Kamal / systemd timer)
bin/rails recording_studio_api:api_metrics:maintain

# Or enqueue for an ActiveJob backend (Solid Queue, Sidekiq, etc.)
bin/rails recording_studio_api:api_metrics:enqueue_maintain
```

Solid Queue recurring example:

```ruby
# config/recurring.yml
maintain_api_metrics:
  class: RecordingStudioApi::MaintainApiMetricsJob
  queue: recording_studio_api_metrics
  schedule: every day at 2am
```

Without a schedule, retention config is inert and raw request logs keep growing.

### Core registries

`RecordingStudioApi` is intended to expose explicit registration layers for:

- authenticated API resources resolved from declared `RecordingStudio.configuration.recordable_types`
- actions backed by Recording Studio capabilities
- addon-owned handlers and serializers registered against those actions

Recording Studio 3.x requires every configured ActiveRecord recordable to declare its hierarchy with
`recording_studio_recordable(...)`. Host apps must mark real roots with `root: true`, declare
`allowed_parent_types` for child-capable recordables, and enable `RecordingStudio.enable_capability(:accessible, on: ...)`
for every recordable that can own direct access grants. Enable `RecordingStudio.enable_capability(:api_access_point, on: ...)`
for recordables that may act as API key access points. The dummy app marks `Workspace` and `Folder` as root-capable,
keeps `Page` as a child recordable, and the API engine registers its internal `RecordingStudio::Access`, API client,
credential, access-token, and admin API recordables with explicit parent rules.

Each action declares its verb, capability mapping, handler, and serializer so addon gems can register an API action once and let the API expose it automatically for any recordable type that enables the capability.

### Routing model

- top-level resources represent recordable roots or directly addressable records
- nested resources mirror the real recording tree, not ad hoc controller structure
- capability actions sit beside resources as explicit member or collection endpoints

### Access model

- the API core authenticates credentials and resolves the `RecordingStudio::Access` recording attached to those credentials
- `RecordingStudioApi::AccessGrant` carries `api_client`, `credential`, `access_recording`, `root_recording`, and the access actor into handlers
- capability handlers own authorization and should call `context.access_grant.authorize!` or `RecordingStudioAccessible.authorized?` before doing work
- the built-in resource and move handlers already perform their own grant checks
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
RecordingStudioApi.register_recordable_type_api(
  "Page",
  serializer: ->(recordable, **) { { title: recordable.title } },
  output_keys: %i[title],
  fields: {
    cover_image_url: { resolver: ->(context) { context.recordable.cover_image_url }, include: true }
  },
  writable_attributes: %i[title],
  operations: %i[index show create update],
  capability_actions: %i[publish]
)
RecordingStudioApi.register_capability_action(
  :publish,
  capability: :publishable,
  required_role: :edit,
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

Member actions require `:edit` by default. A host can override an action's role without replacing its handler:

```ruby
RecordingStudioApi.configure do |config|
  config.capability_action_roles = { publish: :admin }
end
```

`writable_attributes` is an explicit allowlist for API create and update operations. OpenAPI
field metadata describes response data only and never grants write access.

### Fields, relationships, and includes

Resource registration declares the flat fields and named relationships an API may expose.
`output_keys` is the serializer response allowlist. `fields` declares separately resolved flat
response fields with a callable `resolver`, an `include` policy, and optional OpenAPI metadata.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Project",
  serializer: ->(project, **) { { name: project.name, external_key: project.external_key } },
  output_keys: %i[name external_key],
  fields: {
    cover_image_url: {
      resolver: ->(context) { context.recordable.cover_image_url },
      include: true,
      openapi: { type: :string }
    }
  },
  writable_attributes: %i[name external_key],
  immutable_fields: %i[external_key],
  relationships: {
    tasks: { source: :children, child_type: "Task", many: true, include: :request,
         serializer: ->(task, **) { { name: task.name } }, output_keys: %i[name], limit: 20,
         endpoints: %i[index show create update destroy] },
    owner: {
      source: :custom,
      many: false,
      include: true,
      resolver: ->(context) { context.recordable.owner },
      serializer: ->(owner, **) { { name: owner.name } },
      output_keys: %i[name]
    }
  }
)
```

`immutable_fields` must be a subset of `writable_attributes`: it may be supplied at create time
but is ignored on updates. Relationship names are application-defined. A `children` source reads
the real Recording Studio child edge and can opt into generic writes. A `custom` source uses its
resolver and is read-only through the engine. `include: true`
always emits a relationship; `include: :request` emits it only when requested. `?include=tasks`
selects only configured request-enabled names. There is no `?include=true`, wildcard, nested-path,
or arbitrary-name form.

Responses are flat. A record always includes `id`, `type`, `root_id`, `parent_id`, `created_at`,
and `updated_at`; serializer output keys, always-included fields, and expanded relationship names
sit beside those keys. There are no `data`, `attributes`, or `relationships` wrappers. Collections
use `records` plus `meta`; a record's `_meta` reports `limit` and `has_more` for emitted collection
relationships.

Write bodies use the same flat field layout. Send registered writable fields at the request body
root, with `parent_id` only for top-level creates that select a parent Recording Studio record.
Nested creates take their parent from the URL, and updates do not accept `parent_id`; use the
registered move action to change a record's parent. The legacy `{ attributes: { ... } }` envelope
is rejected.

The engine fetches requested `children` relationships in one scoped query per response,
preventing serializer-driven N+1 queries. A custom resolver is application code and may issue
queries; preload its associations where needed and use `context.scoped_recordings` when resolving
Recording Studio records. Custom relationships must declare a serializer and output keys, so
the engine never serializes arbitrary model attributes. Registered writable child relationships expose
generic named endpoints:

```text
GET    /api/v1/projects/:parent_id/tasks
GET    /api/v1/projects/:parent_id/tasks/:relationship_id
POST   /api/v1/projects/:parent_id/tasks              # { "name": "Planning" }
PATCH  /api/v1/projects/:parent_id/tasks/:relationship_id # { "name": "Planning" }
DELETE /api/v1/projects/:parent_id/tasks/:relationship_id
```

All structural operations remain scoped and role-authorized, and enforce the host application's
Recording Studio parent declarations.

## Flat Response Upgrade

This pre-production release is a breaking API response contract change with no runtime legacy
response compatibility.

- Former `attributes` values are top-level: replace `response.attributes.title` with `response.title`.
- There is no `relationships` object or relationship `data` wrapper: replace `response.relationships.comments.data` with `response.comments`.
- Recording wrapper keys (`id`, `type`, `parent_id`, `root_id`, `created_at`, and `updated_at`) remain top-level metadata.
- Replace legacy registration DSL with the explicit `fields:` and `relationships:` definitions above.
- `?include=comments` selects only configured request-enabled entries.
- Upgrade OpenAPI snapshots, fixtures, and consumer tests with the new flat payloads and nested endpoint bodies.

Scalar section descriptions are generated from OpenAPI tags. Resource sections default to a
plain-language description and can be customized through the existing `openapi` metadata:

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Page",
  openapi: {
    tag: {
      description: "Create and organize the content pages in a workspace."
    }
  }
)
```

`operations` controls which standard resource operations are exposed for that recordable type.
It accepts any of `:index`, `:show`, `:create`, `:update`, and `:destroy`; when omitted, all five
remain available for backward compatibility. For a collection-only resource, use
`operations: %i[index]`. Disabled operations are rejected by the API and omitted from OpenAPI.

`capability_actions` is a default-deny allowlist for custom capability actions. A capability action
requires the underlying Recording Studio capability, a registered API action handler, and an entry
in the recordable type's `capability_actions` list before it is callable or appears in OpenAPI.

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
- `GET /api/screens/api_keys` — RecordingStudioAdmin API key screen when the host mounts the API surface
- `GET /api/screens/api_requests` — RecordingStudioAdmin API request screen when the host mounts the API surface
- `GET /recording_studio_api/admin_api/logs` — browser admin request-log route
- `POST /recording_studio_api/oauth/token` — issue OAuth2 bearer access tokens using `client_credentials`
- `POST /recording_studio_api/apis/<api-name>/oauth/token` — issue OAuth2 bearer access tokens for a named API using `client_credentials`
- `GET /recording_studio_api/api/<version>` — list available API resources for the selected public API version
- `GET /recording_studio_api/api/<version>/:resource` — list recordings of a resource type inside the authenticated root
- `GET /recording_studio_api/api/<version>/:resource/:id` — show one recording
- `POST /recording_studio_api/api/<version>/:resource` — create a recording when the resource permits `:create`
- `PATCH /recording_studio_api/api/<version>/:resource/:id` — update a recording when the resource permits `:update`
- `DELETE /recording_studio_api/api/<version>/:resource/:id` — destroy a recording when the resource permits `:destroy`
- `GET /recording_studio_api/api/<version>/:resource/:id/:relationship` — list a registered named relationship
- `GET /recording_studio_api/api/<version>/:resource/:id/:relationship/:relationship_id` — show a direct child from a registered `children` relationship
- `POST /recording_studio_api/api/<version>/:resource/:id/:relationship` and `PATCH|DELETE /.../:relationship/:relationship_id` — mutate a writable `children` relationship
- `POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/:resource/:id/actions/:action_name` — execute the newest compatible contribution contract for that public API version
- `POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/:resource/:id/:action_name` — compatibility alias for existing clients

Named API resource routes use `/recording_studio_api/apis/<api-name>/<version>` with the same resource and action shapes.

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
| Rails           | ~> 8.1.1 |
| PostgreSQL      | 16      |
| TailwindCSS     | 4       |
| RecordingStudio | v3.0.2 (pinned in `test/dummy/Gemfile`) |
| FlatPack        | v0.1.124 (pinned in `test/dummy/Gemfile`) |
| Devise          | latest  |

## Documentation

The original gem template documentation is preserved in this repository under `docs/gem_template/` as architectural reference material. Those files are for contributors reviewing the repo, not packaged gem docs; the README and dummy app are now the source of truth for the Recording Studio API design handoff.
