# RecordingStudio API

 Mountable Rails engine for a programmable Recording Studio API.

`RecordingStudioApi` is a mountable Rails engine that provides authenticated, capability-backed JSON APIs for Recording Studio addons.

Companion pins on current main: Trashable `>= 0.17.0, < 2.0` / `~> 1.3` / `v1.3.0`
(query-only), Admin `~> 2.19` / `v2.19.1` (development and dummy only), Moveable `>= 5.0, < 7.0` / `~> 6.1` / `v6.1.0`, Root Switchable
`~> 0.17` / `v0.17.0`, Cache `~> 0.8` / `v0.8.0` (development/test), Icons `~> 0.5` / `v0.5.0`, Accessible `>= 0.50.0, < 2.0`
(`~> 0.58`, `tag: v0.58.0`), RecordingStudio `~> 7.8` / `v7.8.0`
(`>= 7.7.0, < 8.0`), Flatpack `~> 0.2` / `v0.2.0`
(`tag: v0.2.0`, `>= 0.1.356, < 2.0`),
Metrics `~> 0.10` / `v0.10.0` (`>= 0.9.0, < 2.0`), Logs `~> 0.9` / `v0.9.0` (`>= 0.8.0, < 2.0`). Recording Studio MCP `v0.17.0`
allows this gem at `>= 0.11.0, < 0.12`, so it cannot take `0.12.0` or `0.13.0` until
MCP widens that pin. Recording Studio Oauth `v0.12.2`
allows `>= 0.5.2, < 0.12`. For Trashable query-only keep/trash helpers in
`0.7.0`, metrics window fixes in `0.6.16`, and earlier companion pins,
see [UPGRADING.md](UPGRADING.md).

## Current Scope

- OAuth2 `client_credentials` authentication backed by `RecordingStudioApi::ApiClient`, `ApiCredential`, and issued access tokens
- pluggable OAuth grant handlers so `recording_studio_oauth` can add `authorization_code` and `refresh_token` on the same token endpoints
- external bearer-token authenticator support for host application authentication systems
- API client recordables stored beneath `RecordingStudio::Access` recordings in the Recording Studio tree
- authenticated API requests resolved into a `RecordingStudioApi::AccessGrant` that is passed to capability handlers
- OAuth user writes use `access_grant.actor` (the signed-in person) as the event actor and store the API client as `impersonator`; they also store `authorized_by_type` and `authorized_by_id` on the event. A `client_credentials` grant with no user still writes as the API client.
- capability-backed action registry with automatic action exposure when a recordable type enables that capability
- `register_endpoint` for named JSON endpoints that are not a recordable collection
- optional `ui:` widget id on those registrations, plus `ui_for` / `actions_for_ui` lookups
- optional `sensitive:` on type operations, capability actions, and named endpoints, plus `lookup` for the registered handler, input contract, and output schema
- site-wide API usage metrics on the operations API via Recording Studio Metrics
- preserved template reference material in `docs/gem_template/`
- shared fixed-window rate limits through `RecordingStudioApi::RateLimit`

The current codebase still ships the template engine mechanics (configuration, hooks, install generator, sample service objects), but the engine now also exposes a real JSON API surface for authenticated resource lookup, capability-backed member actions, and named endpoints that are not a recordable.

## Recording Studio 6.5.0 write authorization

See Recording Studio core's own documentation (RecordingStudio core, write authorization).

Resource create calls `Recording#record` on the parent root. It passes the same
actor, impersonator, and metadata as an update, so core authorises the write
and runs `before_record` / `after_record` plus the created event. A create with
no parent is rejected. `RecordingStudio.root_recording_for` only finds an
existing root. `RecordingStudio.create_root_recording!(recordable, actor:)`
creates one through the same write path.

API client role edits call `RecordingStudioAccessible::Services::UpdateRecordingAccess`.
Moving the access point creates a new client with `ProvisionApiClient` under a
new Access grant on the selected recording, then revokes the old Access grant
and the old client's credentials and access tokens in the same transaction.
A refused provision or revoke leaves the previous client, its tokens, and its
Access unchanged. The edit form still uses Save changes. The response shows the new
secret once. The client name and credential expiry are columns on this gem's
tables.

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

Embedded docs use `api.documentation_layout_name`, then `config.layout`, then
`RecordingStudio.configuration.layout`, then `recording_studio/default_layout`.
Set the shell with `config.layout` (`nil`, `false`, a layout name, or `->(controller:) { ... }`).
`config.layout_name = "name"` still assigns `config.layout`. Custom layouts should render
`content_for(:page_nav_right)` beside `page_nav_button_group` to display the **Full width** action.
The fullscreen response is layout-free. A host may override
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

API clients are bound to exactly one API. Provision and authenticate named clients with `api:`.
A `client_credentials` public token is rejected on every named API and vice versa. A public Oauth
client that implements `registered_for_api?` (RecordingStudio Oauth 0.2.2) may present its
delegated bearer on a named resource path. The existing site-wide API switch remains a global kill switch, while `ApiSetting.for_api`
supports additional per-API switches. Admins can also set runtime overrides for request logging,
credential/access-token TTLs, retention, and rate-limit enables/thresholds from the Admin API
settings and rate-limiting pages. Blank override fields fall back to initializer defaults; Redis
URL/namespace and digest peppers stay deploy-time only.

Named APIs inherit credential and token TTLs, rate-limit windows, and request-payload logging policy
from the public configuration when declared. Each definition can then override those values without
changing another API. Redis connectivity, namespaces, and telemetry retention remain shared
infrastructure.

Create idempotency uses that same Redis client
(`rate_limit_redis_url` and `rate_limit_redis_namespace`). When Redis is missing or raises
`Redis::BaseError`, `IdempotencyStore` writes the first response to
`Rails.cache` with `unless_exist`. Redis uses `SET NX`.
If that cache is process-local (`MemoryStore` or `NullStore`), the first
read or write logs one warning and does not repeat it in the process:

```
[RecordingStudioApi] idempotency keys are not durable. Redis is unavailable (Redis client is missing) and Rails.cache is ActiveSupport::Cache::MemoryStore, which is process-local and keeps keys in this process only.
```

A reachable Redis client does not log that warning.
`NullStore` still cannot replay. A shared cache fallback does not log the warning.
A later built-in create with the same `Idempotency-Key` from the same API client
returns that stored JSON for 24 hours when the fingerprint matches.
The fingerprint is `IdempotencyStore.fingerprint(method:, path:, params:)`.
It is the SHA256 of the HTTP method, the path or resource type, and the
request body. Hash keys are sorted at every level. Header values are not
included. The same key with a different fingerprint raises
`RecordingStudioApi::IdempotencyKeyMismatchError` (`code` is
`idempotency_key_reused`, `message` is
"Idempotency key already used with different parameters").
Built-in HTTP create renders that as 422
`{ "error": { "code": "idempotency_key_reused", "message": "Idempotency key already used with different parameters" } }`
and does not create a record. Rescue the same error in another gem and pass
`code` and `message` through.
`fetch` and `write` take an optional `fingerprint:`. Omit it and fetch
replays whatever is stored. Pass it, and a stored fingerprint that differs
raises. A stored entry with no fingerprint, including create entries written before
1.19.0, still replays for the rest of its 24 hours.
The stored key is
`{namespace}:idempotency:{api}:{api_client.id}:{digest}`. Index cursors use
the same client id as `client:{api_client.id}` inside the pagination token.
An in-process grant with an actor and no API client (MCP tools running for
a signed-in user) uses `actor:{ActorType}:{actor id}` for both. Idempotency
storage is `{namespace}:idempotency:{api}:actor:{ActorType}:{actor id}:{digest}`.
The pagination scope is `actor:{ActorType}:{actor id}`. Actor type is the
record's polymorphic name. A request with neither an API client nor an actor
raises `AuthorizationError` instead of skipping the idempotency store or
sharing a cursor scope. `null_store` cannot replay.

`RecordingStudioApi::Idempotency.replay` is the shared entry point for that
store. `RecordingStudioApi::Idempotency.client_id` builds the client id above.
Built-in create calls `replay` with `fingerprint:` from
`IdempotencyStore.fingerprint`. A different body raises
`IdempotencyKeyMismatchError` and creates nothing. A `register_resource_handler`
for `create`, including a nested create, calls `replay` without `input` or
`fingerprint`, so a different body still returns the first response.

A member action does not replay unless `register_capability_action` or the
member `register_resource_handler` passes `creates: true`. Either flag is
enough. The header is read on both member paths and copied to
`ActionContext#idempotency_key`. The store key adds the action name and the
target recording id. `replay` hashes `input` and passes that digest to
`IdempotencyStore.fetch`. The same key and the same input return the first
successful JSON and status. The same key with different input raises
`IdempotencyKeyMismatchError` (422 `idempotency_key_reused`).
OpenAPI lists `Idempotency-Key` on flagged actions only.

MCP should call `replay` for an action instead of `IdempotencyStore` directly.
Pass `action`, `recording_id`, and `input`. The block returns
`{ json:, status: }`. A blank key runs the block and stores nothing.

```ruby
RecordingStudioApi::Idempotency.replay(
  api: context.api_key,
  client_id: RecordingStudioApi::Idempotency.client_id(api_client: context.api_client, actor: context.actor),
  key: context.idempotency_key,
  action: "attach",
  recording_id: context.recording&.id,
  input: context.params
) { { json: payload, status: :created } }
```

Read and write rate limits use this same Redis. See [Rate limits](#rate-limits).

### Rate limits

HTTP requests and other gems share one fixed-window counter,
`RecordingStudioApi::RateLimit`. The key is
`{namespace}:{kind}:{identifier}:{window}`.

`kind` is `:read` or `:write`, stored as `api_read` or `api_write`. The HTTP
limiter also counts `oauth`, `api_pre_auth`, and `api_failed_auth` on this
counter. `window` is `now.to_i / period`. The default namespace is
`recording_studio_api` (`rate_limit_redis_namespace`). A named API prefixes
that namespace with the API name (`recording_studio_api:operations`). Pass
`namespace:` when the prefix is already built.

Use the same identifier the HTTP limiter would, so the counters stay shared:

- `credential:{id}`
- `client:{id}`
- `ip:{remote_ip}`
- `actor:{ActorType}:{id}` for an in-process actor with no API client

`ip:{remote_ip}` uses `request.remote_ip`. Rails sets that from the socket
address unless the peer is in `config.action_dispatch.trusted_proxies`. Set
`trusted_proxies` to the proxies this host runs. Leave a real proxy off that
list and every client behind it shares one IP bucket. Trust a proxy you do
not run and the client can choose the address that becomes the bucket.

```ruby
decision = RecordingStudioApi::RateLimit.check(
  kind: :read,
  identifier: "actor:User:#{user.id}"
)

if decision.nil?
  # Nothing was counted. Allow this call, or reject it here.
else
  decision.allowed?    # false once the count is above the limit
  decision.count
  decision.limit
  decision.remaining
  decision.retry_after # seconds until this window expires
  decision.reset_at
  decision.key
end
```

`nil` means the counter did not move. That happens when the limit or period
is not positive, or when Redis is missing and fail closed is off. Do not
read `nil` as "over the limit". The caller decides whether to allow the
work. A Redis or connection error is logged, the shared client is reset,
and then the error propagates, so rescue it if you need a fallback of your
own. Any other error, such as a bug in the caller, propagates immediately
even when fail closed is on.

Pass `fail_closed: true` when a missing Redis, or a Redis or connection
error, should count as limited. `check` then returns a decision with
`allowed?` false, `count` 0, `remaining` 0, and `retry_after` set to the
period. The counter still did not move. `fail_closed:` must be nil, true,
or false. nil reads `config.rate_limit_check_fail_closed`, which must be
true or false and defaults to false, so existing callers keep the nil
result. Turn it on for a caller that must not proceed without a counter.
The HTTP limiter always passes `fail_closed: false` into `RateLimit.check`,
so `rate_limit_check_fail_closed` does not change request limiting. It is
separate from `config.rate_limit_fail_closed`, which is the HTTP limiter's
bucket policy for `oauth`, `api_pre_auth`, and `api_failed_auth`.

A request with no bearer token counts on `api_pre_auth`. A bearer token that
fails authentication counts on `api_pre_auth` and on `api_failed_auth`. The
failed-auth default is 20 requests per 60 seconds
(`rate_limit_api_failed_auth_requests`,
`rate_limit_api_failed_auth_period_seconds`,
`rate_limit_api_failed_auth_enabled`). The limiter reads that counter before
authentication and returns 429 when the window is already full. It increments
the counter when authentication rejects the bearer. A bearer token that
authenticates skips both IP buckets and uses `api_read` or `api_write`.
Keys stay `credential:{id}`, `client:{id}`, or `ip:{remote_ip}`. The limiter
does not put the raw token in the key or in the fallback log.

When Redis is missing or raises a connection error, `api_read` and `api_write`
use `RecordingStudioApi::RateLimit::ProcessWindow`. That window lives in the
process, guards its counts with a mutex, expires each window on the first
hit's deadline, and keeps at most 10,000 keys in a `MemoryStore`. Every
fallback is logged and sent to `Rails.error.report`. `oauth`, `api_pre_auth`,
and `api_failed_auth` stay fail-closed and do not use the process window.
The bucket name `api` matches nothing. An initializer that still lists `api`
keeps this fallback for read and write. `api_failed_auth` fails closed
whenever `rate_limit_fail_closed` is true, including when an older bucket
list does not name it. During a Redis outage the read and write limits apply
once per process.

```ruby
RecordingStudioApi::RateLimit.check(
  kind: :write,
  identifier: "actor:User:#{user.id}",
  fail_closed: true
)
```

`check` reads the read or write limit for `api:` (default `:public`) from
the API runtime policy. A read or write value that is not positive falls
back to the shared API limit. Pass `limit:` and `period:` together to use
another pair. Omit `redis:` to use the shared client (`rate_limit_redis_url`).

The increment is one Redis `INCR`. `EXPIRE` runs on the first hit in the
window, and again when the key has no TTL. A call that lands on the limit
is still allowed. The next call is not, and it still increments.
`retry_after` is the key TTL, or the period when that TTL is not positive.

`RateLimit.key` builds the counter key without incrementing:

```ruby
RecordingStudioApi::RateLimit.key(
  kind: :write,
  identifier: "client:#{client.id}",
  window: Time.current.to_i / 60
)
# => "recording_studio_api:api_write:client:<id>:<window>"
```

`RateLimit.limits(kind:, policy:)` returns `[limit, period_seconds]` for a
policy.

### `authorized_by`

Bearer authentication resolves `authorized_by` once, from the credential or
token record's `oauth_authorization.manager_actor`. It is stored on the
access grant and exposed on action, resource, and registered-endpoint
contexts. Update and move merge `authorized_by_type` and `authorized_by_id`
into the event metadata they already write. Resource updates write as
`access_grant.actor` (the signed-in user on an OAuth user token) and keep
the API client as event `impersonator` when it is not that actor.
`Current.actor` stays the access grant actor. A `client_credentials`
grant with no user still writes as the API client. API credentials have
no manager, so API-key writes add no `authorized_by` keys.
`with_authorized_by` drops client-sent `authorized_by_type` and
`authorized_by_id` (string or symbol keys) before it writes the server value,
including on client_credentials and API-key writes. Handlers that record
their own events can call `context.with_authorized_by(metadata)`. Delete does
not record an event.

Set `api_management_authorization_required` for trusted APIs. Credential creation then requires both
the requested RecordingStudioAccessible data grant and management access to that API's `AdminApi`
recording beneath the configured admin root. Create that recording once with
`RecordingStudioApi::Admin::ApiAuthorization.provision!` after the admin root exists, or run
`bin/rails recording_studio_api:provision_admin` once per admin root. The task calls `provision!`
for every configured API and is safe to run again. It provisions a recording only when that
recording's type is a declared root and `root_recording_id` is its own id. A parentless recording
of any other type is skipped. Authorization checks only read the recording.
A missing recording returns 403 and names `provision!` and `recording_studio_api:provision_admin`. Public and
unprotected named APIs retain the existing access-point delegation behavior.

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
upgrades do not leave copied host files behind. `RecordingStudioApi::AdminApi` is declared and added
to `recordable_types` only when a configured admin root class is loaded. The default name is
`AdminRoot` (`admin_root_recordable_type_names`). A host with no admin root leaves that setting
alone and does not list `AdminApi` itself. Request completion clears the admin credential query
cache only when Recording Studio Admin is loaded. Named surfaces pass an API context into those shared
definitions and remain independently authorized, configured, and filtered. Keeping `operations` out
of `--user-apis` makes it available only from the site administration root. Every recordable used as
an API credential access point must enable Recording Studio's `api_access_point` capability; the gem
then intersects that capability with the selected API's registered recordables.

### Request logging and metrics retention

When `api_request_logging_enabled` is on, each API request can write a row to the API logging
database (`api_logging` when that database is configured). New rows store `arrived_at` from
PostgreSQL `clock_timestamp()` at insert, and `latency_bucket_ms` from the same bucket labels
the daily histogram already uses (`25` through `10000`, then overflow label `30000` for anything
above `10000`). Blank API names become `public`. Blank routes become `unknown`.
API registers the raw request-log table with Recording Studio Logs (root column,
no partitions, `retention: :indefinite`) and does not declare aggregatable columns.
It does not write or read Logs summary tables.

Admin charts prefer rolled-up daily metrics, so hosts should run maintenance nightly:

1. Aggregate the last few complete local days into `api_daily_metrics` and latency
   histogram buckets.
2. Delete raw `api_request_logs` older than `api_request_log_retention_days` (default 30).
   Do not schedule Logs partition or aggregation jobs for this table.
3. Optionally delete daily metrics older than `api_daily_metric_retention_days` (default `nil` =
   keep forever).

```sh
# Synchronous maintain (cron / Kamal / systemd timer)
bin/rails recording_studio_api:api_metrics:maintain

# Or enqueue for an ActiveJob backend (Solid Queue, Sidekiq, etc.)
bin/rails recording_studio_api:api_metrics:enqueue_maintain
```

The engine also registers `:api_requests` and `:api_keys` with Recording Studio
Metrics (`blast_radius: :site`, operations only). `api_requests.*` read
`api_daily_metrics`. `api_requests.over_time`
sums `request_count` on `metric_date`. `api_requests.errors_over_time` sums
`client_error_count + server_error_count` on that same date column, with the
same window, interval, timezone, and zero-filled buckets.
`api_requests.server_errors_over_time` (unit `count`) sums only
`server_error_count` (5xx responses) from the daily rollup, with the same
window and buckets. It accepts `group_by=route_name` or
`group_by=request_method`; any other `group_by` is `422`. Client, credential
and IP fields are never grouping keys. Raw request logs are not read.
`api_requests.rate_limited_over_time` (unit `count`) sums `rate_limited_count`
per day from the same rollup, with the same window, buckets, and
`group_by=route_name` / `group_by=request_method`.
`api_keys.expiring_soon` (unit `count`) counts active keys whose
`expires_at` is within the next 30 days. `api_keys.stale` (unit `count`)
counts active keys with `last_used_at` over 90 days ago, or never used and
created over 90 days ago. Both are point-in-time (no window, no `group_by`,
no metric filters) and are not cached. When Recording Studio Admin is
loaded, the Admin API section shows those two health widgets on their own
compact row, with captions from `EXPIRING_SOON_WINDOW` and `STALE_AFTER`
and distinct `clock` / `pause` icons. Each widget counts the same rows as
the API credentials screen for the current API with default
`status=active` and `health=expiring_soon` or `health=stale`. That screen's
chart uses the same filtered rows as the table. The Admin API
section also links to API performance so the latency widget can open it.
Failing endpoints filters by exact `request_path` and shows those filters
inline. API performance filters by date range, group-by, exact
`request_method`, and `request_path`, all inline. Chart and table share
that scope, and it has no table search.
`api_authorize` allows an actor with the access-management view role on the
site admin root. This gem does not call `RecordingStudioMetrics::Api.register!`.
The host registers Metrics endpoints once:

```ruby
RecordingStudioMetrics::Api.register!(api: :operations)
```

Paths on the operations API are `GET /metrics`,
`GET /metrics?resource=api_requests`, `GET /:resource/metrics`,
`GET /metrics/:resource/:name`, and `GET /:resource/metrics/:name`.
A resource with no registered metrics is `404` `not_found`. A known
resource with no authorized metrics is `{ "metrics": [] }`.
`start`, `start_at`, and `from` set the window start. `start` and `from`
must match when both are sent. `start_at` is the fallback when neither is
sent. `end`, `end_at`, and `to` follow the same rule. `group_by` is passed through when the metric declares it. A resource-first
path is served only when that first segment is not a recordable on the API. Recordable metrics are a separate
allowlist, described under Recordable metrics. Those routes do not replace
`GET /metrics` or `GET /:resource/metrics` for a first segment that is not a
recordable.

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
for recordables that may act as API key access points. When an admin root has none for the selected API, the new-key form lists manageable roots that do, and creates the key there. It does not nest that access point under the admin root. A workspace stays on the access points already in its tree. The dummy app marks `Workspace` and `Folder` as root-capable and keeps `Page` as a child recordable. Accessible owns `RecordingStudio::Access`. The API engine registers API client, credential, access-token, and admin API recordables with explicit parent rules. API clients still nest under an Access recording.

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
- `AccessGrant#accessible_recordings` is the owner's live `authorized_recordings`, rooted at the grant anchor. Callers pass the recording scope (a list passes its type and filters). Pagination applies the keyset, order, and limit on that relation. A root anchor uses `Recording.within`. A nested anchor does not walk the subtree into an id list before the limit. `authorize!` uses the lower of the grant role and `RecordingStudioAccessible.role_for` on that recording. `role_for` walks the recording and its ancestors. A trashed recording uses that same call, which is how Trashable authorizes restore and purge. `include_trashed: true` puts the trashed recording in scope. It does not move the role check to the parent. If the owner loses access, the token loses it on the next request. A key with no owner sees nothing. Trashed recordings stay out of the default scope. A kept recording under a trashed ancestor stays visible when the owner can still view it. `accessible_recording_ids` returns those ids when a caller asks for the list.
- `ApiClient` is the API credential principal for audit metadata, while the `RecordingStudio::Access` actor remains the Recording Studio authorization actor
- each access recording owns at most one active API credential record
- raw secrets should only be revealed at creation or rotation time

`ApiClient` is an immutable Recording Studio recordable. It is recorded as a child of a `RecordingStudio::Access` recording, while mutable credential and issued-token state lives in `ApiCredential` and `ApiAccessToken` with digest, rotation, revocation, and last-used tracking.

### Boot validation

The runtime should fail fast when:

- `config/recording_studio_api.yml` is missing or invalid, or `config.x.recording_studio_api` cannot be read

- an API action points at a capability that is not enabled
- duplicate action name plus contribution version pairs are registered
- required handlers or serializers are missing
- contribution versions or version-profile constraints are malformed
- two recordable types in one named API resolve to the same public name

## Ruby Integration Surface

Host apps and addon gems use these entrypoints for configuration, resource exposure, and capability registration.

Service calls report through Recording Studio's own hooks. Register `before_service`, `after_service`, and `around_service` on `RecordingStudio.configuration.hooks`. `after_service` and `around_service` see a result that omits issued tokens, refresh tokens, authorization codes, client secrets, and credential records. `around_service` receives a copy of the service. The caller still receives the secret once. A hook that raises during API authentication returns 500. Model and controller extensions, including Moveable's conflict handler, stay on `RecordingStudioApi.configuration.hooks`. `extend_controller` applies to `ActionController::Base` and `ActionController::API` controllers, including `ApiController`. Register it before that controller loads. Prepare applies it to controllers already loaded, and autoload applies it when the controller loads.

```ruby
RecordingStudioApi.configure do |config|
  config.enable_feature_x = false
  config.timeout = 5
  config.layout = "application"
end

RecordingStudioApi.configuration
RecordingStudioApi.configuration.hooks.run(:before_initialize)
RecordingStudioApi.register_recordable_type_api(
  "Page",
  serializer: ->(recordable, **) { { title: recordable.title } },
  output_keys: %i[title],
  fields: {
    cover_image_url: { resolver: ->(context) { context.recordable.cover_image_url }, include: true }
  },
  writable_attributes: %i[title],
  operations: %i[index show create update destroy],
  sensitive: %i[destroy],
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
RecordingStudioApi.register_endpoint(
  :ping,
  api: :public,
  http_verb: :get,
  path: "ping",
  handler: ->(_context) { { ok: true } }
)
```

`sensitive:` is optional. On `register_recordable_type_api` it is a list of operation names (`index`, `show`, `create`, `update`, `destroy`). Those names are added to the named API's defaults and never remove them. Public registrations default to not sensitive, so `sensitive: %i[destroy]` marks destroy only. An operations or other named API stays sensitive for every operation, including show when `sensitive: %i[destroy]` is given. An unknown name raises `ConfigurationError`. On `register_capability_action` and `register_endpoint` it is `true` or `false`. A registration that exists only on an operations or other named API defaults to sensitive. Repeat registrations still merge with the existing explicit-set rules. The flag lives on the registration object and on `lookup`. Registration `as_json` dumps and OpenAPI omit it.

`RecordingStudioApi.lookup` is the read-only resolver for one named API. Pass exactly one of `operation` (with `recordable_type`), `action`, or `endpoint`. The handler is the same callable HTTP uses, so Accessible authorization stays in the handler. The result also has the input contract fields (`type`, `required`, `allow_blank`, plus `enum`, nested `items` / `properties`, `description`, and `example` when the schema or action contract sets them), the output schema, the effective `sensitive` flag, and the named APIs that expose the target. Create and update field hashes come from `DocumentationCatalog.attributes_schema_for`. Create `required` follows `details_schema` required names. Update always reports `required: false`. `allow_blank` is false when the field is required on create or its schema has `minLength` of 1 or more.

```ruby
RecordingStudioApi.lookup(api: :public, recordable_type: "Page", operation: :destroy)
RecordingStudioApi.lookup(api: :public, action: :publish)
RecordingStudioApi.lookup(api: :public, endpoint: :ping)
```

Member actions require `:edit` by default. A host can override an action's role without replacing its handler:

```ruby
RecordingStudioApi.configure do |config|
  config.capability_action_roles = { publish: :admin }
end
```

### Public names

`public_name:` is the short name for a registered type. Leave it blank and the name is the class without its namespace. The value is a string identifier, with no spaces.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::PressKit",
  public_name: "PressKit",
  serializer: ->(press_kit, **) { { title: press_kit.title } },
  output_keys: %i[title]
)
```

`registration.public_name` returns `"PressKit"`. `RecordingStudioApi.recordable_type_for_public_name("PressKit", api: :public)` returns `"RecordingStudioPresskits::PressKit"`. It checks the public name first, then the exact full class name. A miss returns nil. Pass `api:` for a named API. The full class name still finds the registration through `recordable_registration_for`. A create that is missing `parent_id` names that public type (`parent_id is required for PressKit`). When there is no registration, the message still uses the class name.

Resolved public names are unique inside one named API, including the public API. A clash raises `RecordingStudioApi::ConfigurationError` and names both classes and the public name. The same public name may be registered on two different named APIs. A later registration of the same type keeps the established public name. Passing a different `public_name:` raises `ConfigurationError`.

REST paths, the JSON `type`, and OpenAPI keep the full class name and the existing resource name.

`writable_attributes` is an explicit allowlist for API create and update operations. OpenAPI
field metadata describes response data only and never grants write access.

A create-only input is a writable attribute listed in `immutable_fields`. It may be a column or
another name the recordable accepts on create. `RecordingStudioApi.lookup` includes it on `:create`
and omits it on `:update`. Built-in create assigns it. Update ignores it. Put the field on
`details_schema` when lookup should copy a type. Authorization stays in Accessible.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::CreditLine",
  serializer: ->(line, **) { { role: line.role } },
  output_keys: %i[role],
  writable_attributes: %i[role credit_id],
  immutable_fields: %i[credit_id],
  openapi: {
    details_schema: {
      type: "object",
      properties: {
        role: { type: "string" },
        credit_id: { type: "string" }
      }
    }
  }
)
```

### Default list order

`default_order:` is the order for a collection when the client omits `sort`.
Leave it unset and the list stays on `created_at` ascending, with `id` as the tiebreaker.

A column names one field and a direction. `asc` and `desc` are the only directions.
A column that exists on the recording, such as `created_at` or `updated_at`, orders that table.
Any other column must exist on the recordable table. Registration raises `ConfigurationError` for a bad shape, a bad direction, or a column on neither table.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Folder",
  serializer: ->(folder, **) { { name: folder.name } },
  output_keys: %i[name],
  sortable_attributes: %i[name],
  default_order: { name: :asc }
)
```

`recording_studio_orderable` stores the position on the recording as `recording_studio_orderable_position`.
This gem does not depend on that gem. A host that has the column can pass it directly.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::KitSection",
  default_order: { recording_studio_orderable_position: :asc }
)
```

A callable takes the authorized relation and returns an ordered relation of the same model.
Use it when the position lives on another table. The callable's joins stay.
If it drops the authorization filters, the list intersects the result with the authorized ids.
`id` ascending is appended so ties stay stable. Send `sort` to replace this order. `order` without `sort` is 422.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::KitSection",
  default_order: ->(recordings) {
    recordings.joins(<<~SQL.squish)
      LEFT OUTER JOIN section_positions
        ON section_positions.recording_id = recording_studio_recordings.id
    SQL
    .reorder(Arel.sql("section_positions.position ASC"))
  }
)
```

An explicit `sort` always wins. For a column default, `order` without `sort` changes that column's direction.
OpenAPI shows a column default on the `sort` and `order` parameters when the column is one of the client sort fields.
A callable's OpenAPI description says the registered order applies when `sort` is omitted. The list `meta.sort` is then `default_order`.

Give that callable a name when clients should request it. `name` is the sort value. `order` takes the authorized relation and `"asc"` or `"desc"`. `direction:` is optional and defaults to `asc`. Use that direction in the order expression. `id` is added afterward, in the same direction. Omitting `sort` still uses this order. `sort=position&order=desc` reverses it. `order=desc` without `sort` does the same. The name is an allowed sort value and an OpenAPI `sort` enum entry.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "RecordingStudioPresskits::KitSection",
  default_order: {
    name: "position",
    order: ->(recordings, direction) {
      sql_direction = direction == "desc" ? "DESC" : "ASC"
      recordings.joins(<<~SQL.squish)
        LEFT OUTER JOIN section_positions
          ON section_positions.recording_id = recording_studio_recordings.id
      SQL
      .reorder(Arel.sql("section_positions.position #{sql_direction}"))
    }
  }
)
```

`GET /recording_studio_api/api/v1/kit_sections?sort=position&order=desc` returns that order. An unknown `sort` is still rejected. A column hash and an unnamed callable are unchanged.

### Recordable metrics

An owning gem registers the calculation with Recording Studio Metrics, then
names those metrics on the recordable. `metrics:` is the allowlist.
`RecordingStudioApi.metrics_for` reads name, description, unit, title,
timezone, freshness, and parameters from the live definition. Description and
parameters are not stored on the registration.

```ruby
RecordingStudioMetrics.register(:folders, model: Folder, blast_radius: :root) do
  count :total, title: "Folders", description: "How many folders are in this scope."
end

RecordingStudioApi.register_recordable_type_api(
  "Folder",
  serializer: ->(folder, **) { { name: folder.name } },
  output_keys: %i[name],
  sortable_attributes: %i[name],
  writable_attributes: %i[name],
  metrics: %w[folders.total]
)
```

`GET /recording_studio_api/api/v1/folders/metrics` returns
`{ "metrics" => [{ "name" => "folders.total", "description" => "...", "unit" => "count", "title" => "Folders", "timezone" => "UTC", "freshness" => { "cached" => false }, "parameters" => [...] }] }`.
`timezone` is the metrics engine default (UTC unless the host changed it).
There is no `timezone` query parameter. `freshness.cached` is false because
these calls run with `cache: false`.
`GET /recording_studio_api/api/v1/folders/metrics/folders.total` runs that
metric. Both calls require the same view grant as the list, and the
recordable must allow `index`. A disabled index is `422`
`unsupported_action` with `index is not enabled for Folder`.

A scalar count with no field accepts `q` and `filter[attribute]` only.
`from`, `to`, `interval`, and `group_by` are `422` `invalid_input`. A
scalar count that declares `field` also accepts `from` and `to`. Those
bounds limit that column on the authorized relation before `execute`
(inclusive start, exclusive end) and are not passed into the metrics
engine. `interval` is still `422`. A time series accepts `from`, `to`,
`interval`, and `group_by` when the definition lists columns. `start` must
match `from` when both are sent. `start_at` is used only when `start` and
`from` are absent. `end`, `to`, and `end_at` follow the same rule. A
conflict is `422`. OpenAPI on the shared show operation lists the union of
parameter names and omits enums. Each catalog entry carries that metric's
own enums.

`filter[attribute]` must be one scalar value. An array or a hash is `422`.
An unknown filter key is `422`. The same rules apply to the list. `q` is
the list search.

`group_by` is optional and only appears when the definition allowlists
columns. Owning gems must not allowlist a column that holds personal data.
Groups smaller than `min_group_size` (5) fold into `other`. That fold is
the only guard.

Once an allowlist exists, the path segment `metrics` is reserved.
`GET /folders/metrics` is the catalog, not the folder whose id is
`metrics`. `GET /folders/metrics.json.json` returns the API error body.
A type with no allowlist keeps its show route, so `GET /folders/metrics`
is still the folder with id `metrics` until Folder lists metrics.

### Per-type handlers

Register a handler for one recordable type and action when that gem already
owns the behavior. Other types keep the shared handler.

```ruby
RecordingStudioApi.register_resource_handler(
  "SupportPage",
  :create,
  api: :operations,
  handler: SupportPages::Api::Create
)

RecordingStudioApi.register_resource_handler(
  "SupportPage",
  :move,
  api: :operations,
  handler: SupportPages::Api::Move
)
```

Collection actions take the recordable type from the resource name. Nested
relationship routes use the relationship's child type. When a handler is
registered, this gem loads the route recording from the token's scope and
calls `access_grant.authorize!` before the handler runs. A missing, foreign,
or wrong-type id is 404 and the handler does not run. The handler returns
`{ json:, status: }`.

Resource and nested handlers get a `ResourceOperationContext` with:

- `id`, `parent_id`, `relationship_id`. These are the raw route ids. `id` is set on member routes. `parent_id` and `relationship_id` are set on nested routes.
- `params`, `request_params`, `api_client`, `access_grant`, `actor`
- `recordable_type`, `resource_name`, `credential`, `access_recording`,
  `root_recording`, `api_version`, `scoped_recordings`, `idempotency_key`

Read writable fields with `RecordingStudioApi::RequestPayload.call(context)`.
It prefers `request_params` (MCP) over `params`, then `to_unsafe_h` or
`to_h`. An empty `request_params` hash is the body; it does not fall back
to `params`. Builtin resource operations use the same helper.

Map a disallowed parent with
`RecordingStudioApi::InvalidParentInput.call(message, recordable_type:)`.
Builtin create raises that error. Access is unchanged.

Use `recording` and `parent_recording` from the context. Do not load a route
id with `Recording.find`. `id`, `parent_id`, `relationship_id`, and `params`
stay on the context so an existing handler still sees them.

`index` and `show` authorize `:view`. `create`, `update`, and `destroy`
authorize `:edit`. A nested index or create authorizes the parent. A nested
show, update, or destroy authorizes the child. A flat create does not scope
`parent_id` from the body. A move destination and any other id in the body
stay the handler's job.

`destroy` then follows the recordable type. A type with Trashable enabled
is moved to the trash with `recording_studio_trashable_trash!`. Trashable
checks permission, writes the events, and includes children. `deleted_via`
is `trashed`. The recording stays, so default lists omit it and show returns
404. Any other type is destroyed with `Recording#destroy!`. Core refuses a
recording that still has children, and the API returns 422 with that message.
Core removes that recording's events. The recordable snapshot stays.
`deleted_via` is `destroyed`. Permanent deletion of a trashed recording is
Trashable's `trashable_purge` action, which requires admin. This gem does
not add a second purge route.

Pass `include_trashed: true` on `register_resource_handler` when the action
must see a trashed recording. The default lookup is kept recordings only.

Pass `owns_scoping: true` only for a GET, or for built-in index or show, whose
effective role is `:view`. Registration rejects the flag on a write, including
a POST whose `required_role` is `:view`. Dispatch checks the effective role
again. Support uses this for public published help pages. The handler then
owns scoping, and this gem does not call `authorize!` for that action. There
is no write opt-out.

Pass `include_trashed: true` for a read, for built-in restore or destroy, or
with `trashed_semantics: :restore` or `:destroy`. Registration rejects it on
create, update, and other writes.

`trashed_semantics` lets a POST with a custom name, such as Trashable's
`trashable_restore` or `trashable_purge`, see trashed recordings.
The same keyword is on `register_capability_action`, `register_resource_handler`,
and `register_endpoint`. The role must be `:edit` or higher. `:admin` qualifies.
Registration rejects the declaration on a GET, with `required_role: :view`, and
with `owns_scoping: true`. Register the capability action before a resource
handler that uses the declaration, so the handler can see that verb and role.
Dispatch checks the effective role again. A later `:view` role does not include
trashed recordings. The lookup still goes through `ScopedRecording` and
`authorize!`. A trashed recording outside the token's scope is 404.

Member-action handlers (for example `move`) get an `ActionContext` with the
same scoped `recording`, plus:

- `id`, `recordable_type`
- `params`, `api_client`, `access_grant`, `actor`
- `credential`, `access_recording`, `root_recording`

The member action's `required_role` is the role passed to `authorize!`.
`authorize!` runs before the input contract. Route keys are omitted from a
capability handler's params before the contract runs. `include_trashed`,
`owns_scoping`, and `trashed_semantics` on
`register_capability_action` follow the same rules. Routes without a
per-type handler keep the shared lookup and operations.

### Pre-handler guard

`RecordingStudioApi::HandlerGuard` is the check those routes run before a
handler. REST controllers call it. Recording Studio MCP, or any other
dispatcher that runs a handler itself, calls the same methods and then calls
the handler. The guard returns the recordings and leaves the handler to the
caller.

```ruby
RecordingStudioApi::HandlerGuard.resource!(
  access_grant:,
  recordable_type:,
  action_name:,
  id:,
  registration:
)

RecordingStudioApi::HandlerGuard.capability!(
  access_grant:,
  api_client:,
  recordable_type:,
  action:,
  id:,
  registration:
)

RecordingStudioApi::HandlerGuard.endpoint!(
  access_grant:,
  endpoint:,
  id:
)
```

Each call returns `recording` and `parent_recording`. Flat routes leave
`parent_recording` nil. Pass the resource-handler registration into
`capability!` when a per-type handler supplies the scope flags. Pass
`registration: nil` when the capability action carries them.

`capability!` looks up the recording, runs an optional `before_authorize`
check, calls `authorize!`, then yields. The block is where the handler
context and the input contract run. A token that fails `authorize!` gets 403
and the contract does not run. `before_authorize` checks that the action is
enabled for `recording.recordable_type` after lookup and before `authorize!`.
It raises `UnsupportedActionError` only when `authorize!` would succeed. When
the token would get 403, that 403 is the response. A missing recording is 404
from the lookup, before the check.

An `owns_scoping` read is the exception. `capability!` yields nil and returns
without lookup, `before_authorize`, or `authorize!`. The handler owns scoping,
and the block still runs with a nil recording. A flat index or create returns
a nil recording. An endpoint with `scope_id: false` or no recording id also
returns a nil recording, after `endpoint!` calls `access_grant.authorize!` on
the grant anchor. The role is that endpoint's `authorization_role`. `show`,
`update`, `destroy`, capability actions, and id-scoped endpoints load through
`ScopedRecording.find!` and `authorize!`. The role is `:view` for index, show,
and GET, and `:edit` otherwise, unless `required_role:` or
`capability_action_role_for` says otherwise.
`include_trashed` and `trashed_semantics` go through
`HandlerScope.dispatch_include_trashed?`. A blank id on a scoped path raises
`NotFoundError`. An in-scope id of the wrong recordable type is also
`NotFoundError`. The message names the expected public type, the type of that
id, and asks the caller to pass an id of the expected type.

Nested relationship handlers still resolve the parent and child in
`RelationshipResourcesController`, which also authorizes the relationship.

### Billing denials

A billing block is rendered only after authentication and authorization.
`HandlerGuard` (or the nested route's `authorize!`) runs first. The handler
runs next. A token that fails access gets 403 or 404, and the handler does
not run.

The handler reports a block in one of two ways:

- return a denied `RecordingStudio::GateDecision` that has a `code`
- raise an error that `is_a?(RecordingStudio::Denial)`

`RecordingStudio.check_gate` copies `code` and `details` from the first deny.
Core defines no codes. This gem's registry does. A registered code renders
402 in the standard error envelope:

```json
{
  "error": {
    "code": "paywall_locked",
    "message": "Exports are locked",
    "details": {
      "message": "Exports are locked",
      "feature": "exports",
      "limit": 3,
      "fix_path": "/settings/plan",
      "fixable_by": "owner"
    }
  }
}
```

Built-in codes are `paywall_locked`, `plan_limit_reached`,
`meter_limit_reached`, and `seat_limit_reached`. Each one is HTTP 402.
Add another with `config.register_billing_code`.

```ruby
RecordingStudioApi.configure do |config|
  config.register_billing_code(:storage_limit_reached)
end
```

`details` keeps `message`, `feature`, `limit`, `fix_path`, and `fixable_by`.
`message`, `feature`, and `fixable_by` are strings. `message` is at most 500
characters. `feature` and `fixable_by` are at most 100. `limit` is an integer.
`fix_path` starts with one `/` and then only letters, digits, and `-._~/?=&`.
Percent-encoding, a backslash, a scheme, or a host is dropped. A value that
contains a Stripe id (`cus_`, `sub_`, `price_`, and the same shape) is dropped.
Prices and usage totals are omitted.

A denied `GateDecision` with an unknown or missing code renders 403,
`error.code` `forbidden`, and no details. A raised error with an unknown or
missing code keeps today's response: 403 for `AuthorizationError`, and
`invalid_input` for `InvalidActionInputError`. Development logs a warning for
an unknown code. An error that merely defines `#code`, including
`Stripe::StripeError`, is not a denial.

Gems and hosts prove the envelope with the test helper:

```ruby
require "recording_studio_api/test_helpers"

class ExportApiTest < ActionDispatch::IntegrationTest
  include RecordingStudioApi::TestHelpers

  test "a locked export tells the caller how to fix it" do
    post export_path, headers: bearer
    assert_billing_denial(:paywall_locked, details: { feature: "exports", fix_path: "/settings/plan" })
  end
end
```

`assert_billing_denial` fails when the code is not in the registry.

A dispatcher that calls a handler itself, including Recording Studio MCP,
calls `HandlerGuard` and then `RecordingStudioApi::BillingDenial.interpret`.
Render 402 only when that returns a payload. An `owns_scoping` handler
authorizes before it returns a billing denial.

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
use `records` plus `meta`. `meta.total_count` is omitted unless the request
passes `include_total=true`. It is the number of matching recordings across
every page. The count is `COUNT(*)` when that query has no join, no eager
load, no referenced include, no custom `FROM`, and is not already distinct.
Search, attribute filters, and any other join keep `COUNT(DISTINCT id)`, so a
joined row is not counted twice. `count=true` returns only `{ "total_count": N }`
and does not load records.

A record's `_meta` reports `limit` and `has_more` for emitted collection
relationships.

Write bodies use the same flat field layout. Send registered writable fields at the request body
root, with `parent_id` only for top-level creates that select a parent Recording Studio record.
Nested creates take their parent from the URL, and updates do not accept `parent_id`; use the
registered move action to change a record's parent. The legacy `{ attributes: { ... } }` envelope
is rejected.

A create can opt in to a server-chosen parent so callers do not send `parent_id`. See
[Server-chosen create parent](docs/create-parent.md). The default stays the same. A non-root
create without that option still requires `parent_id`.

The engine preloads the recordable for each list row before serialization, and it
fetches requested `children` relationships from the current page's recording ids,
one query per response, preventing serializer-driven N+1 queries. Each parent
returns at most 100 children, or the relationship `limit` when that is lower.
`_meta.has_more` is true when more children exist. A descendant-tree scope is
not walked again for those direct children. A narrower scope still drops ids
outside it. A custom resolver is application code and may issue
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
      description: "Create and organize the content pages in a workspace.",
      group: "Content"
    }
  }
)
```

`tag.group` is optional. When any registration sets it, the OpenAPI document includes
`x-tagGroups` so Scalar nests those tags under the group name. Tags without a group go
in one group named `API`, listed first. Named groups follow in the order they first
appear. If no registration sets `tag.group`, `x-tagGroups` is omitted.

On a read-only named API, omitted `operations` default to index and show only
on a type's first registration. A later `register_recordable_type_api` that
omits `operations` (including one that only passes `openapi:` tags) keeps the
established set and deep-merges the rest of the registration.

Standard index, show, create, update, and destroy operations get generated summaries and
descriptions from the registration (fields, filters, `include`, pagination, `count=true`,
create idempotency, and permanent delete). Index and show say results are scoped to what
the caller can access. Create and update say they require edit access. `q` is documented
only when the type has filterable attributes. Per-action `openapi` keys (`:index`, `:show`,
`:create`, `:update`, `:destroy`) replace that generated `summary` and `description`. A
`parameters` array on those keys is added to the built-in query and path parameters
(override wins on the same `name` + `in`; a blank `in` matches query). `parameters: []`
keeps the built-ins. `deprecated` and `externalDocs` on an action are passed through to
the OpenAPI operation.

`operations` controls which standard resource operations are exposed for that recordable type.
It accepts any of `:index`, `:show`, `:create`, `:update`, and `:destroy`; when omitted, all five
remain available for backward compatibility. For a collection-only resource, use
`operations: %i[index]`. Disabled operations are rejected by the API and omitted from OpenAPI.

`capability_actions` names extra member actions for that type. A capability action
requires a registered API action handler and the underlying Recording Studio capability on
the recordable type. When the action is registered with a `capability:` (for example
`:movable`), every API-registered type that declares that capability also gets the action
unless the type sets `auto_capability_actions: false`. That opt-out restores
`capability_actions` as an allowlist. OpenAPI and `capability_actions_for` include
auto-enabled actions. An explicit list still enables named extra member actions the same
way. Authorization (`required_role` and the handler) is separate from this enablement check.

### Access management role settings

The gem uses Recording Studio access roles to control access-management UI and actions.

- `config.access_management_view_role` controls who can see API access records.
- `config.access_management_edit_role` controls who can create, edit, and revoke API access.

Defaults:

- `access_management_view_role: :view`
- `access_management_edit_role: :admin`

This means users with view-level access can inspect API access in the UI, but only admin-level access can mutate API access.

`AccessManagementPolicy#can_view_recording?` and `#can_manage_recording?` ask Recording Studio Accessible about that recording. A grant on a folder covers that folder and its descendants. It does not cover a sibling folder or the workspace root. Lists of recordings someone can manage use `authorized_recordings` and `authorized_recording_ids` for the edit role. `root_recordings_for` only finds the workspaces to ask about.

`maximum_assignable_role_for` is `RecordingStudioAccessible.role_for` for that actor and recording. `can_assign_role?` is an early check for forms and provisioning: the actor can manage the recording, and Accessible's role ceiling allows the role. `GrantRecordingAccess` and `UpdateRecordingAccess` enforce that ceiling when the grant is written.

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

An API key is active only when its credential recording exists and `Recording#kept?` is true. OAuth access tokens also require a kept recording for the token and the credential. The access recording, the API client recording, and the root must pass `Recording#kept?`. Scope resolution loads the root with `RecordingStudio.root_recording_id_for` on the access recording. Relation filters use additive `Recording.kept`. SQL filters use `RecordingStudio.kept_sql`. Pin `recording_studio` `>= 7.7.0`, `< 8.0` and `recording_studio_trashable` `>= 0.17.0`, `< 2.0`, and load `recording_studio_trashable/query` only.

### OAuth resource server

This gem is the resource server. It issues machine tokens with `client_credentials` and turns Bearer tokens into an `AccessGrant`.

`authorization_code` and `refresh_token` live in `recording_studio_oauth` when that gem is installed. That gem registers those grant types on the same token endpoints:

```ruby
RecordingStudioApi.register_oauth_grant("authorization_code", handler: authorization_code_handler)
RecordingStudioApi.register_oauth_grant("refresh_token", handler: refresh_token_handler)
```

`RecordingStudioApi.oauth_grants` lists the registered grant types. A handler must respond to `call` with `grant_type:`, `params:`, `client_id:`, `client_secret:`, and `api:`. It returns a service Result. Success values are the token payload this endpoint already renders. Failure errors are OAuth error hashes.

Unknown grant types return `invalid_grant`. Machine `client_credentials` still works when the Oauth gem is absent. You cannot replace `client_credentials` through this hook.

### Capability-backed actions

Addon gems register actions once:

```ruby
RecordingStudioApi.register_capability_action(
  :move,
  capability: :movable,
  version: "2.0.0",
  version_notes: ["Adds destination validation"],
  http_verb: :post,
  handler: RecordingStudio::Moveable::Api::MoveRecording
)
```

If a recordable type enables `:movable`, the API automatically exposes the newest compatible `move` contribution selected for the current public API version.

`openapi:` is the generic copy for every type that gets the action. Pass optional
`openapi_for:` when a type needs its own title, summary, or description. The
callable receives `type:` and `action:` and returns a Hash or nil. Only keys
with a value overlay the generic hash for that type's OpenAPI path and MCP
catalog entry. Other types keep the generic copy.

```ruby
RecordingStudioApi.register_capability_action(
  :attach,
  capability: :attachable,
  handler: Attach,
  openapi: {
    title: "Attach",
    summary: "Attach a file.",
    description: "Attach a file."
  },
  openapi_for: ->(type:, action:) {
    next unless type.to_s == "RecordingStudioPresskits::PressKit"

    {
      title: "Add File",
      summary: "Attach a file to this press kit.",
      description: "Adds a file to the press kit Files section."
    }
  }
)
```

### Named endpoints that are not a recordable

Use `register_endpoint` when the host needs a JSON path that is not a tree collection. Do not invent a fake recordable or a one-off API controller.

```ruby
RecordingStudioApi.register_endpoint(
  :ping,
  api: :public,
  http_verb: :get,
  path: "ping",
  handler: ->(_context) { { ok: true } }
)

RecordingStudioApi.register_endpoint(
  :echo,
  api: :public,
  http_verb: :post,
  path: "echo/:key",
  handler: ->(context) { { key: context.params[:key], message: context.params[:message] } },
  openapi: {
    parameters: [
      { name: "key", in: "path", description: "Echo this key back." }
    ]
  }
)
```

Pass optional `ui:` with a string widget id when an MCP App should open a
widget for that action. The API stores the string only.

```ruby
RecordingStudioApi.register_endpoint(
  "presskits.edit",
  http_verb: :patch,
  path: "presskits/:id",
  scope_id: false,
  required_role: :edit,
  handler: Presskits::Edit,
  ui: "presskits.editor"
)

RecordingStudioApi.register_capability_action(
  :update_presskit,
  capability: :presskits,
  handler: Presskits::Update,
  ui: "presskits.editor"
)

RecordingStudioApi.ui_for("presskits.edit", api: :public, version: "v1")
# => "presskits.editor"

RecordingStudioApi.actions_for_ui("presskits.editor", api: :public, version: "v1")
# => matching endpoint and capability-action objects for that API and version
```

Omit `ui:` and lookups return `nil` or an empty list. Widget HTML lives in
MCP UI, not here.

Routes use the same mount and version prefix as the tree API (`/recording_studio_api/api/v1/ping`, or `/recording_studio_api/apis/<api-name>/<version>/...` for a named API). Bearer auth still applies. A public client cannot call an endpoint registered only on `:operations`.

Dispatch matches **path and HTTP verb**. Register `GET users` and `POST users` (or `GET users/:id` and `PATCH users/:id`) as separate endpoints. A request whose path matches but whose verb does not returns **405 Method Not Allowed** with an `Allow` header. Recordable CRUD stays on its own routes (`GET` index/show, `POST` create, `PATCH` update, `DELETE` destroy). Capability actions keep the verb they registered (`POST` unless declared otherwise).

Handlers receive `RecordingStudioApi::RegisteredEndpointContext`. That object has the client, credential, access recording, access grant, root, params, and `recording`.

A path that captures `:id` or `:recording_id` must pass `recordable_type:`. Registration raises when that type is missing. This gem loads the capture from the token's scope, checks the type, and calls `access_grant.authorize!` before the handler runs. `:recording_id` is scoped the same way as `:id`. GET defaults to `:view`. Every other verb defaults to `:edit`. Pass `required_role:` to override that default, so a POST search can require `:view`. A foreign or wrong-type id is 404 and the handler does not run.

Pass `scope_id: false` when the capture is not a recording, such as `people/:id`. `recording` stays nil and the handler owns that id. A non-GET with `scope_id: false` must pass `required_role:`. Registration raises when it is missing.

An endpoint that does not scope a recording still authorizes before the handler runs. `endpoint!` calls `access_grant.authorize!` with the grant anchor (`scope_recording`) and `authorization_role`. Membership is the `authorized_recordings` relation for that anchor. GET defaults to `:view`. Every other verb defaults to `:edit`. `required_role:` overrides that default, so a view key can mark a notification read. The effective role is the lower of the key grant and the owner's current role. A view key is refused on an unscoped write. A key whose owner lost access is refused. The response is the same 403 a collection index uses for that anchor. The handler does not run.

`include_trashed: true` is accepted on a read, on restore, on destroy, and when
the endpoint declares `trashed_semantics: :restore` or `:destroy`. Registration
rejects it on other actions. The declaration is rejected on a GET, with
`required_role: :view`, and with `owns_scoping`. Dispatch checks the endpoint
role again before the lookup.

`owns_scoping: true` skips the lookup and `authorize!` only while the action is still a GET, or a built-in index or show, and the effective role is still `:view`. `required_role: :view` on POST is not enough. Dispatch checks the effective role again, so a later edit role scopes the id. Support uses the opt-out for public published help pages. There is no write opt-out.

OpenAPI and Scalar list these routes under the `Endpoints` tag.

### Capability-backed handlers

Handlers receive `RecordingStudioApi::ActionContext` or `RecordingStudioApi::ResourceOperationContext`. The route recording is already scoped and authorized. Use `context.recording`. An id in the body is still the handler's job to scope and authorize.

```ruby
class PublishRecording
  def self.call(context)
    context.access_grant.authorize!(recording: context.recording, role: :edit)

    context.recording.recordable.update!(published_at: Time.current)
    context.recording
  end
end
```

### Progress on handler contexts

`ActionContext`, `ResourceOperationContext`, and `RegisteredEndpointContext`
accept an optional `progress_reporter`. REST controllers leave it `nil`. A
non-REST caller (for example RecordingStudio MCP wrapping a handler) can pass
any object that responds to `progress(current:, total:, message:)` and
`cancelled?`. This gem only forwards those messages.

```ruby
class ImportPages
  def self.call(context)
    pages.each_with_index do |page, index|
      break if context.cancelled?

      import_page(page)
      context.progress(
        current: index + 1,
        total: pages.size,
        message: "Imported #{page.title}"
      )
    end
  end
end
```

With no reporter, `progress` returns `nil` and `cancelled?` is `false`.

### API endpoints

- `GET /recording_studio_api/admin_api` — browser admin dashboard for configured API access
- `GET /api/screens/api_keys` — RecordingStudioAdmin API key screen when the host mounts the API surface
- `GET /api/screens/api_requests` — RecordingStudioAdmin API request screen when the host mounts the API surface
- `GET /recording_studio_api/admin_api/logs` — browser admin request-log route
- `POST /recording_studio_api/oauth/token` — issue OAuth2 bearer access tokens using `client_credentials`, or a grant type registered with `register_oauth_grant`
- `POST /recording_studio_api/apis/<api-name>/oauth/token` — issue OAuth2 bearer access tokens for a named API using `client_credentials`, or a registered grant type
- `GET /recording_studio_api/api/<version>` — list available API resources for the selected public API version
- `GET /recording_studio_api/api/<version>/:resource` — list recordings of a resource type inside the authenticated root
- `GET /recording_studio_api/api/<version>/:resource/metrics` — list allowlisted metrics for that resource. `metrics` is reserved once the allowlist exists
- `GET /recording_studio_api/api/<version>/:resource/metrics/:name` — run one allowlisted metric. `:name` is the full identifier, such as `folders.total`
- `GET /recording_studio_api/api/<version>/:resource/:id` — show one recording
- `POST /recording_studio_api/api/<version>/:resource` — create a recording when the resource permits `:create`
- `PATCH /recording_studio_api/api/<version>/:resource/:id` — update a recording when the resource permits `:update`
- `DELETE /recording_studio_api/api/<version>/:resource/:id` — delete a recording when the resource permits `:destroy`. A trashable type moves to the trash. Any other type is destroyed
- `GET /recording_studio_api/api/<version>/:resource/:id/:relationship` — list a registered named relationship
- `GET /recording_studio_api/api/<version>/:resource/:id/:relationship/:relationship_id` — show a direct child from a registered `children` relationship
- `POST /recording_studio_api/api/<version>/:resource/:id/:relationship` and `PATCH|DELETE /.../:relationship/:relationship_id` — mutate a writable `children` relationship
- `GET|POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/:resource/:id/actions/:action_name` — execute the newest compatible contribution contract for that public API version (`GET` only when the action registers `http_verb: :get`)
- `GET|POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/:resource/:id/:action_name` — compatibility alias for existing clients
- `GET|POST|PATCH|PUT|DELETE /recording_studio_api/api/<version>/<registered-path>` — execute a `register_endpoint` path that is not a tree collection. Matching uses the registered verb. A path with no handler for the request verb returns 405 and `Allow`.

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
- `/docs/methods` documents the live Ruby entrypoints, including `register_endpoint`
- Dummy `GET /recording_studio_api/api/v1/ping` is a proof hook for named endpoints that are not a recordable
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

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

GitHub Actions (`.github/workflows/ci.yml`) starts Postgres 16 and Redis 7. The test job sets `REDIS_URL` and `RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL` to `redis://127.0.0.1:6379/0`, which is the URL `IdempotencyStore` reads through `rate_limit_redis_url`. The gem and dummy test steps receive `RAILS_MASTER_KEY` from the Actions secret of the same name. When that secret is empty, those steps unset it and the credential tests skip.

## Cloud Agent boot

Cloud Agent Builds run `.cursor/install.sh`, then `.cursor/fetch-skills.sh`.
The install hook provisions a cold image. On a warm snapshot it skips apt,
ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are
already usable. If `RAILS_MASTER_KEY` is set, it writes gitignored
`test/dummy/config/master.key` so dummy credentials decrypt. Fetch-skills
always runs last. `.cursor/start.sh` starts PostgreSQL on each boot. Rebuild
with Draft off to load a new pack. See
[Cursor skills in Cloud Agents](docs/cursor-skills.md).

## Tech Stack

| Component       | Version |
|-----------------|---------|
| Ruby            | 3.3+    |
| Rails           | ~> 8.1.1 |
| PostgreSQL      | 16      |
| TailwindCSS     | 4       |
| RecordingStudio | v7.8.0 (pinned in `test/dummy/Gemfile`) |
| FlatPack        | v0.2.0 (pinned in `test/dummy/Gemfile`) |
| Devise          | latest  |

## Documentation

The original gem template documentation is preserved in this repository under `docs/gem_template/` as architectural reference material. Those files are for contributors reviewing the repo, not packaged gem docs; the README and dummy app are now the source of truth for the Recording Studio API design handoff.

Idempotency key reuse is described in [docs/idempotency.md](docs/idempotency.md).
