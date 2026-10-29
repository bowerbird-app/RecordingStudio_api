# Upgrading RecordingStudioApi

## Upgrading to 0.18.1

`0.18.1` caps Recording Studio at `>= 6.1.0, < 7`. No migration.

1. Bump the host gem to `0.18.1`.
2. Stay on Recording Studio 6.1 through 6.x. Core 7 is outside this release.
3. Do not resolve this gem against Recording Studio 4.x. The engine calls `RecordingStudio::ControllerLayout` and `RecordingStudio::Layout.accept`. Moveable `~> 4.0` also requires Recording Studio `>= 6.1.0`.
4. Development and dummy apps stay on GitHub tag `v6.1.0`.

## Upgrading to 0.18.0

`0.18.0` takes Moveable `v4.0.1` as a runtime dependency and lets Moveable
own the move action. No migration.

1. Bump the host gem to `0.18.0`.
2. Pin `recording_studio_moveable` to GitHub tag `v4.0.1` (`~> 4.0`).
3. Remove any host calls to `RecordingStudioApi::Services::MoveRecording`.
   `RecordingStudioApi.register_default_capability_actions!` registers
   Moveable's handler (`RecordingStudio::Moveable::Api::MoveRecording`).
4. Keep posting `parent_id`, `destination_id`, or `new_parent_id` to
   `POST .../actions/move`. Destination still has to be in the authenticated
   API scope.
5. A request with no destination now returns `unsupported_action` with
   `parent_id is required for move` (still HTTP 422). Moveable's contract
   drops `api_key` / `api_version` so those route keys are not treated as
   unknown body fields.
6. OAuth move events stamp `authorized_by_type` / `authorized_by_id` via
   Moveable `>= 4.0.1`. Update and other resource writes still stamp those
   keys. Move metadata also includes `api_action`, `api_client_id`, and
   `api_credential_id`.
7. Moveable 4.0 itself requires RecordingStudio `>= 6.1.0` and Flatpack
   `>= 0.1.315`, drops `config.full_page_layout`, and routes its own screens
   through `config.layout`. That is Moveable UI. This gem's JSON move
   endpoint does not change layout.

## Upgrading to 0.17.0

`0.17.0` adopts Recording Studio `v6.1.0` and Flatpack `0.1.319`. No migration.

1. Bump the host gem to `0.17.0`.
2. Pin `recording_studio` to GitHub tag `v6.1.0` (`>= 6.1.0`), `flat_pack` to commit `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (`0.1.319`, minimum `>= 0.1.315`), and `recording_studio_admin` to GitHub tag `v2.7.0`. `view_component` stays `>= 4.14, < 5`.
3. Rename `RecordingStudioAdmin` `config.engine_layout` to `config.layout`. Admin `v2.7.0` renders section and screen headings with `content_for :title` and `:subtitle`, back and close with `flat_pack_page_nav`, and actions with `register_page_nav`. Hosts no longer need a `recording_studio_page_nav` or legacy Flatpack keyword shim for Admin.
4. Set the page shell with `config.layout`. `nil` uses `RecordingStudio.configuration.layout`, then `recording_studio/default_layout`. `false` renders no layout. A string is a layout name. A callable is invoked as `call(controller:)` and must return a String, `nil`, or `false`.
5. `config.layout_name = "name"` still assigns `config.layout` for older initializers. `config.admin_layout_name` overrides the admin controller. `api.documentation_layout_name` overrides embedded Scalar docs. Leave those blank to use `config.layout`.
6. Do not call `layout "recording_studio/default_layout"` or include `RecordingStudio::UsesDefaultLayout`. Call `recording_studio_layout { RecordingStudioApi.configuration.layout }` on the host controller. Fullscreen Scalar docs stay `layout: false`.
7. Set `content_for :title` and `content_for :subtitle`. Remove the extra `FlatPack::PageTitle` so the layout renders one `<h1>`.
8. Replace `recording_studio_page_nav` with `flat_pack_page_nav(round: true, style: :default, back_href:, back_tooltip:, anchor_href:, anchor_tooltip:)`. Register right-side actions with `register_page_nav "Label", path, role: :primary` or `recording_studio_page_nav_right`.
9. `FlatPack::Card` takes `background:`, `border:`, and `shadow:`. It does not take `style:`.
10. Load `flat_pack/variables`, `flat_pack/application`, and `flat_pack/rich_text` before the host Tailwind sheet.
11. Sibling gems that still cap `recording_studio` below 5 need a Gemfile pin that allows `6.1.0`, or the same widen step this repo uses in `test/support/widen_recording_studio_requirement.rb` before `Bundler.setup`. `recording_studio_admin` `v2.7.0` already allows `6.1.0`, so that step does not rewrite its gemspec.

## Upgrading to 0.16.0

`0.16.0` records `authorized_by` for an OAuth token on write events. The event actor is still the OAuth client or API client. No migration.

1. Bump the host gem to `0.16.0`.
2. OAuth writes merge `authorized_by_type` and `authorized_by_id` into event metadata. API-key writes do not.
3. Action, resource, and registered-endpoint contexts expose `authorized_by` for handlers that record their own events. Use `with_authorized_by` to merge those keys into metadata you already pass. It removes client-sent `authorized_by_type` and `authorized_by_id` first, on OAuth and API-key writes alike.

## Upgrading to 0.15.0

`0.15.0` stops writing and reading Recording Studio Logs summaries. Run
migrations; it drops the unused summary tables and view (derived data
only; raw `api_request_logs` untouched). Admin metrics, `api_requests.*`,
nightly maintain, and raw prune stay on the existing daily-metric path.

1. Bump the host gem to `0.15.0`.
2. Run migrations. They drop `recording_studio_api_api_request_day_summaries`,
   `recording_studio_api_api_request_latency_day_summaries`, and
   `recording_studio_api_api_request_day_metric_rollups` when present.
   Hosts that never ran the create migration still migrate cleanly.
3. `config.logs_summaries_enabled` is deprecated and does nothing. Host
   initializers that still set it will boot. Remove the assignment when
   convenient.
4. Keep `recording_studio_api:api_metrics:maintain` (or
   `MaintainApiMetricsJob`). Raw rows still prune by
   `api_request_log_retention_days`. Logs registers this table with
   `retention: :indefinite` so Logs does not try to clean a log that has
   no aggregations.

## Upgrading to 0.14.1

`0.14.1` widens `recording_studio_logs` so API works with Logs `v0.5.0`.
No migration. `config.logs_summaries_enabled` still defaults to false.

1. Bump the host gem to `0.14.1`.
2. Pin `recording_studio_logs` to GitHub tag `v0.5.0` (allowed range
   `>= 0.4.1, < 0.6`).
3. Leave `config.logs_summaries_enabled` false.

## Upgrading to 0.14.0

`0.14.0` polishes Admin API key-health widgets and makes credentials,
performance, and failing-endpoints screens honour the same filters on
chart and table. No migration.

1. Bump the host gem to `0.14.0`.
2. **Expiring soon** and **Stale keys** stay on their own compact row, with
   captions derived from `EXPIRING_SOON_WINDOW` and `STALE_AFTER`.
3. API credentials chart counts the same filtered rows as the table
   (`status`, `health`, root filters).
4. API performance accepts a date range and group-by, applied to table and
   chart. Failing endpoints shows all filters on the page.

## Upgrading to 0.13.2

`0.13.2` makes the Admin API key health widgets match the credentials
screen they link to. No migration.

1. Bump the host gem to `0.13.2`.
2. **Expiring soon** and **Stale keys** now count active keys on the current
   API, using `AdminApiCredentialsQuery` plus the screen's default
   `status=active` and `health` filters. Keys on other APIs and inactive
   keys are not included. Site-wide `api_keys.expiring_soon` and
   `api_keys.stale` metrics are unchanged.

## Upgrading to 0.13.1

`0.13.1` widens `recording_studio_metrics` to `>= 0.3.0, < 0.6` and pins
GitHub tag `v0.5.0` in development and dummy. No migration.

1. Bump the host gem to `0.13.1`.
2. Update the host's `recording_studio_metrics` pin to `v0.5.0`.
3. Metrics `chart_series` now returns `{ x:, y: }` points. This gem does not
   remap pairs; pass the series through as Metrics emits it.

## Upgrading to 0.13.0

`0.13.0` registers API request logs with Recording Studio Logs `v0.4.1` and
adds ordinary daily summary tables. Readers, jobs, and raw prune stay on the
legacy path until `config.logs_summaries_enabled` is true.

1. Add `recording_studio_logs` at tag `v0.4.1`. Install migrations and migrate.
   New tables are `recording_studio_api_api_request_day_summaries` and
   `recording_studio_api_api_request_latency_day_summaries`. Logs run tables
   are created on the same database as `ApiRequestLog` (`api_logging` when
   configured). Legacy daily tables stay.
2. Run `bin/rails recording_studio_api:api_request_logs:backfill_classifications`
   if you have not already, then rebuild new summaries for the raw range:

```sh
FROM=2026-09-01 TO=2026-10-18 bin/rails recording_studio_api:api_request_logs:backfill_summaries
```

   Compare totals with the legacy daily tables over the same UTC days before
   you switch. `30000` remains the overflow latency label, not a finite cap.
3. Leave `config.logs_summaries_enabled` false until those totals match. When
   you turn it on, `recording_studio_api:api_metrics:maintain` rebuilds only
   `api/request_counts` and `api/request_latency` (not every Logs producer).
   Raw delete then requires a covering success on both aggregations. A
   logging failure still does not fail the API request.
4. Do not schedule `RecordingStudioLogs::PartitionMaintenanceJob` or
   `DailyAggregationJob` for this table. Keep the existing API maintain job.
   UTC midnight is the summary day. Local `Date.current` near midnight can
   disagree with the old rollup. Historical days that exist only in the
   legacy tables keep that coarser status-class shape. They do not gain
   invented roots or status codes.
5. Rollback is turning the flag off and pointing maintain at the legacy
   writers again. Raw rows deleted after a successful Logs prune do not come
   back. Recording Studio MCP `v0.17.0` still allows this gem only below
   `0.12`.
6. UTC midnight is the summary day. A request just after UTC midnight lands
   on that UTC date even when `Time.zone` is not UTC. Bucket-based
   percentiles use the stored labels, so overflow stays `30000` rather than
   the raw duration. Endpoint tables that need `request_path` still need
   retained raw rows. Logs may auto-publish `api_request_counts` and
   `api_request_latency`. Keep using authorized `api_requests.*` for
   operations reports.

## Upgrading to 0.12.0

`0.12.0` adds arrival time and latency buckets on raw API request logs. It does
not switch readers or retention to Recording Studio Logs.

1. Install migrations and migrate. The raw table keeps its UUID `id`. New
   columns are `arrived_at` (PostgreSQL default `clock_timestamp()`) and
   `latency_bucket_ms`.
2. Run `bin/rails recording_studio_api:api_request_logs:backfill_classifications`
   so older rows get a conservative `arrived_at` (`created_at`, then
   `occurred_at`), a bucket from `duration_ms`, `public` for a blank API name,
   and `unknown` for a blank route. Repeat the task until it updates 0 rows.
   Set `BATCH_SIZE` if you need smaller batches.
3. Leave `config.logs_summaries_enabled` false. It is wired and unused.
4. Recording Studio MCP `v0.17.0` still allows this gem only below `0.12`.
   Stay on `0.11.4` until MCP widens that range, or wait for a later MCP
   release.

## Upgrading to 0.11.5

`0.11.5` adds request filters on two site-wide Admin API screens. No
migrations. Hosts that do not load `recording_studio_admin` are unchanged.

1. **Failing endpoints** takes `request_path`. Match is exact against the
   compacted path shown in the table (`/site-wide-errors`, not the full
   logged URL). The chart uses the same filter.
2. **API performance** takes `request_method` (`GET`, `POST`, `PUT`,
   `PATCH`, `DELETE`) and `request_path`. Path match is exact against the
   logged path, the same as API requests. The latency chart uses both
   filters.
3. API performance no longer has table free-text search. Use
   `request_path` instead.

## Upgrading to 0.11.4

`0.11.4` adds two Admin API dashboard widgets for existing API key health
metrics. No migrations. Hosts that do not load `recording_studio_admin`
are unchanged.

1. The Admin API section shows **Expiring soon** and **Stale keys**. Counts
   come from `RecordingStudioMetrics` (`api_keys.expiring_soon` and
   `api_keys.stale`).
2. Each card links to the API credentials screen with `health=expiring_soon`
   or `health=stale`. That filter is new. Status and health stay visible
   on the page. Root and root type stay in the filter modal.
3. The Admin API section links to **API performance**. Admin enables a
   screen only when a section links to it, so the latency widget can open
   that page.
4. Named API admin sections and workspace API sections do not gain these
   widgets. The metrics stay site-wide. Named admin sections also gain
   the performance link when they already show the latency widget.

## Upgrading to 0.11.3

`0.11.3` stores create idempotency in Redis when Redis answers, and in
`Rails.cache` when it does not. No migrations. `fetch` and `write` keep the
same arguments.

1. A second create with the same `Idempotency-Key` from the same API client
   returns the first JSON for 24 hours even when Redis is down, as long as
   `Rails.cache` keeps values (`memory_store`, Redis cache, Memcached).
   `null_store` still cannot replay.
2. The first stored response wins. A later write with the same key does not
   replace it.
3. One process-wide warning is logged when the store uses `Rails.cache`
   because Redis is missing or raises `Redis::BaseError`.
4. `register_resource_handler` for `create` still skips this store. Call
   `IdempotencyStore` from that handler if you need the same replay.

## Upgrading to 0.11.2

`0.11.2` rejects a bad `limit` and tightens recordable metric JSON. No
migrations.

1. Callers that sent `limit=0`, a negative `limit`, or a non-integer `limit`
   and received the default page size now get `422` `invalid_input` with
   `limit must be a whole number from 1 to <max>`. Omit `limit` to keep the
   default. There is no `per_page` query parameter.
2. Recordable metric show JSON no longer includes `filters: {}`. The metrics
   engine `filters` object is `422`. List `filter[attribute]` and `q` still
   narrow the relation.
3. `GET /metrics?resource=` and `GET /:resource/metrics` for a resource
   with no registered metrics are `404` `not_found` (`Unknown API resource
   <name>`). They used to be `200` `{ "metrics": [] }`. A known resource
   the caller cannot see is still an empty list.
4. Custom index handlers that still call `fetch` on
   `PaginateResourceCollection::Page` need `response_body` (see 0.8.0). That
   crash is not fixed in this gem.

## Upgrading to 0.11.1

`0.11.1` adds `api_keys.expiring_soon` and `api_keys.stale`. No migrations.
The gemspec pin for `recording_studio_metrics` is now `>= 0.3.0, < 0.4`.
Recording Studio MCP `v0.17.0` allows `recording_studio_api` `>= 0.11.0, < 0.12`,
so a host on that MCP release can take 0.11.1.

## Upgrading to 0.11.0

`0.11.0` adds recordable metrics. No migrations.

1. Register the calculation with `RecordingStudioMetrics`, then pass
   `metrics:` to `register_recordable_type_api`. Each name is
   `<resource>.<short_name>`. `<resource>` is
   `RecordingStudioApi.resource_name_for` for that type, so a `Folder` metric
   is `folders.total`.
2. `blast_radius` must be `:root`. The definition model must be that
   recordable class, or one of the two classes must inherit from the other.
   A metric already exposed on a configured API, a metric that declares
   filters, and a type with a custom index handler are rejected when the
   definition can be found. A name the metrics gem does not have yet is
   skipped at boot and raises `ConfigurationError` when `metrics_for` reads
   it.
3. `GET /<resource>/metrics` returns `{ "metrics" => [...] }` with name,
   description, unit, title, timezone, freshness, and parameters.
   `timezone` is the metrics engine default and is not a query parameter.
   `freshness.cached` is false. `GET /<resource>/metrics/<name>` returns the
   `RecordingStudioMetrics` result. Both require the same view grant as the
   list, and `index` must be enabled. A disabled index is `422`
   `unsupported_action`. A denied view is 403. An unknown name is 404.
4. A time series accepts `from`, `to`, `interval`, and `group_by` when the
   definition lists columns. `start` must match `from` when both are sent.
   `start_at` is the fallback when `start` and `from` are absent. `end`,
   `to`, and `end_at` follow the same rule. A conflict is `422`. A scalar
   count with no field rejects `from`, `to`, `interval`, and `group_by`.
   A scalar count with `field` accepts `from` and `to` and applies them on
   that column before `execute`. It rejects `interval`. `q` and
   `filter[attribute]` limit rows the same way the list does. Filter values
   must be scalars. Unknown filter keys are `422`. The metrics engine
   `filters` object is not accepted. There is no `timezone` query parameter.
5. A definition `scope` proc is a configuration error
   (`Metric <name> declares a scope`). The metric count matches the list
   count for the same grant and filters.
6. Owning gems must not allowlist a `group_by` column that holds personal
   data. Groups under `min_group_size` fold into `other`. That is the only
   guard.
7. A type with an empty or missing allowlist is unchanged.
   `GET /folders/metrics` stays the folder show route when Folder has no
   allowlist. Once an allowlist exists, `metrics` is a reserved path
   segment. The four operations metrics endpoints are unchanged.
8. Recording Studio MCP `v0.14.4` still caps `recording_studio_api` at
   `>= 0.6.11, < 0.11`. A host that uses MCP needs a widened MCP release
   before it can take 0.11.0. Recording Studio Oauth `v0.12.2` allows
   `>= 0.5.2, < 0.12`, so it can take 0.11.0.

## Upgrading to 0.10.0

`0.10.0` adds `api_requests.rate_limited_over_time`. No migrations. Gems that
cap `recording_studio_api` below `0.10` (MCP `< 0.10`, Oauth `< 0.10`) need a
widened release before a host can take 0.10.0.

## Upgrading to 0.9.0

`0.9.0` adds `api_requests.server_errors_over_time` and requires
`recording_studio_metrics` `~> 0.3` (GitHub tag `v0.3.1`).

1. No migrations. The new metric reads the existing daily rollup.
2. Update the host's `recording_studio_metrics` pin to `v0.3.1`.
3. Clients that sent `group_by` to a metric without it now get `422` instead
   of an ungrouped result. Drop that param.

## Upgrading to 0.8.0

`0.8.0` adds list counts and resource-first metrics paths. Update the host
dependency to `recording_studio_api`, `~> 0.8.0`.

1. No migrations. Keep calling `RecordingStudioMetrics::Api.register!(api:)`.
   That call also registers `<api>_metrics_index_for_resource` at
   `:resource/metrics` and `<api>_metrics_show_for_resource` at
   `:resource/metrics/:name`. Those names and paths are reserved.
2. Each paginated list runs one extra count of distinct recording ids on
   the same relation, the same authorization scope, and the same filters,
   before the pagination token and before `limit + 1`.
3. Custom `:index` handlers, including custom nested index handlers, do
   not gain `total_count` or `count=true`. To opt in, call
   `PaginateResourceCollection` with `count:` and build the JSON inside
   `response_body`.
4. `PaginateResourceCollection` returns `Page` or `TotalCount` instead of
   `{ rows:, meta: }`. `after_service` hooks receive that object.
   `Page#response_body` yields the rows and meta. `TotalCount#response_body`
   returns `{ total_count: }` and does not yield, so count mode cannot
   serialize records.
5. `true`, `"true"`, and `"1"` are count mode. String comparison ignores
   case and surrounding spaces. `false`, `"false"`, `"0"`, a blank string,
   and `nil` return the list. Any other value raises
   `RecordingStudioApi::InvalidActionInputError` with the message
   `count must be true or false`, which the API renders as `422`
   `invalid_input`.
6. Nested `total_count` counts `child_scope` before per-child authorize
   hooks. Count mode does not call those hooks. Parent authorization still
   runs.
7. When two registered templates match one path, the template whose first
   differing segment is a literal wins. A host path `foo/metrics` beats
   `:resource/metrics` regardless of registration order. Equal specificity
   keeps registration order. Before `0.8.0`, the first registered template
   won.
8. A resource-first metrics URL is served only when the first segment is
   not a recordable on that API. `GET /folders/metrics` stays on the folder
   routes when `folders` is a recordable. `GET /api_requests/metrics` is
   the metrics catalog when `api_requests` is not a recordable.
9. `from` folds to `start` and `to` folds to `end`. For the start of the
   window, the first present name wins among `start`, `start_at`, and
   `from`. For the end, the order is `end`, `end_at`, then `to`. `from`
   and `to` are dropped before the metrics handler runs, so they are not
   passed into `RecordingStudioMetrics.execute`.
10. `group_by` stays on the params hash. `recording_studio_metrics` 0.2.2
    `ExecuteHandler` ignores it and does not pass it to `execute`.
    Undeclared `filters` are still `422`. When that handler starts passing
    `group_by` into `execute`, bump this gem's pin on
    `recording_studio_metrics`.

## Upgrading to 0.7.0

`0.7.0` routes trash and keep checks through Recording Studio Trashable's
query-only sibling API. Update the host dependency to
`recording_studio_api`, `~> 0.7.0`.

1. No migrations in this gem.
2. Add `recording_studio_trashable` `~> 0.10` (GitHub tag `v0.10.0`).
   Prefer `require "recording_studio_trashable/query"` (Gemfile
   `require: false` plus that require) so the Trashable engine,
   importmap, capability, CopyHelper, and `trash.*` metrics stay out of
   this gem's boot path.
3. Predicates use `recording_studio_trashable_kept?` /
   `recording_studio_trashable_trashed?`. Relation filters and CTE/SQL
   fragments that used `where(trashed_at: nil)` /
   `trashed_at IS NULL` use additive
   `where(recording_studio_trashable_kept_sql(...))` /
   `kept_sql(table)`. This gem does **not** chain
   `recording_studio_trashable_active` (that scope unscopes `trashed_at`
   first). Outcomes match `0.6.16`.
4. This gem does not soft-void recordings with
   `RecordingStudioTrashable.void_recording!`. Keep using Oauth (or
   Trashable trash) for grant voids and user-facing trash.
5. Hosts that want the full trash UI keep requiring the Trashable
   engine as before. Prefer predicates / `kept_sql` for new checks next
   to this gem's paths.

If you are still on `0.6.16` or older, complete
[Upgrading to 0.6.16](#upgrading-to-0616) first.

## Upgrading to 0.6.16

`0.6.16` makes `api_requests.errors_over_time` follow the same window as
`api_requests.over_time`. Update the host dependency to
`recording_studio_api`, `~> 0.6.16`.

1. No migrations.
2. Require `recording_studio_metrics` `>= 0.2.2` (GitHub tag `v0.2.2`).
   Development and dummy Gemfiles pin that tag.
3. `api_requests.errors_over_time` sums `client_error_count +
   server_error_count` on `metric_date`. It uses the requested interval,
   timezone, and window, and fills missing days with `0`. The default
   window is about the last 30 days and includes today.
4. A caller that previously received every stored day, including days
   outside that window, should pass `start_at` and `end_at`.

If you are still on `0.6.15` or older, complete
[Upgrading to 0.6.15](#upgrading-to-0615) first.

## Upgrading to 0.6.15

`0.6.15` lets site admins read operations API usage metrics before the
Admin API record exists. Update the host dependency to
`recording_studio_api`, `~> 0.6.15`.

1. No migrations.
2. `:api_requests` and `:api_keys` authorize
   `access_management_view_role` on the site admin root. Set
   `RecordingStudioAdmin.configuration.site_admin_recording_resolver`
   (or `access_recording_resolver`) to that root. A resolver that raises
   hides the metrics.
3. Workspace admins do not receive these site-wide metrics.

If you are still on `0.6.14` or older, complete
[Upgrading to 0.6.14](#upgrading-to-0614) first.

## Upgrading to 0.6.14

`0.6.14` registers API usage metrics for the operations API. Update the
host dependency to `recording_studio_api`, `~> 0.6.14`.

1. No migrations. Existing request logging and daily metric tables stay
   the same.
2. Add `recording_studio_metrics` at tag `v0.2.0`.
3. This gem only registers metric definitions. The host registers the
   Metrics endpoints once:

   ```ruby
   RecordingStudioMetrics::Api.register!(api: :operations)
   ```

4. Authorization reuses `RecordingStudioApi::Admin::ApiAuthorization`
   with the access-management view role. Do not add a second ACL.

If you are still on `0.6.13` or older, complete
[Upgrading to 0.6.11](#upgrading-to-0611) first.

## Upgrading to 0.6.11

`0.6.11` lets an endpoint or capability action name a widget id. Update the
host dependency to `recording_studio_api`, `~> 0.6.11`.

1. No migrations. Existing registrations stay the same when you omit `ui:`.
2. Pass a string widget id if MCP Apps should find the action:

   ```ruby
   RecordingStudioApi.register_endpoint(
     "presskits.edit",
     http_verb: :patch,
     path: "presskits/:id",
     handler: Presskits::Edit,
     ui: "presskits.editor"
   )

   RecordingStudioApi.register_capability_action(
     :update_presskit,
     capability: :presskits,
     handler: Presskits::Update,
     ui: "presskits.editor"
   )
   ```

3. Look the string up with the same named API and version profile as other
   action lookups:

   ```ruby
   RecordingStudioApi.ui_for("presskits.edit", api: :public, version: "v1")
   RecordingStudioApi.actions_for_ui("presskits.editor", api: :public, version: "v1")
   ```

4. Do not put widget HTML or component classes in this gem.

If you are still on `0.6.9` or older, complete
[Upgrading to 0.6.9](#upgrading-to-069) first.

## Upgrading to 0.6.9

`0.6.9` skips this gem's scoped record lookup when a per-type handler is
registered. Update the host dependency to `recording_studio_api`, `~> 0.6.9`.

1. No migrations. Types and routes without a handler keep today's lookup
   and still 404 outside the client's tree.
2. A registered handler must find the record and check access. Member
   routes pass `context.id`. Nested routes pass `context.parent_id` and
   `context.relationship_id`. Member actions such as `move` pass
   `context.id` and `context.recordable_type` on `ActionContext`.
   `context.recording` and `context.parent_recording` are unset.
3. Use `context.api_client`, `context.access_grant`, and `context.actor`
   with the owning gem's existing access checks.
4. Do not expect this gem to authorize the parent on a nested handler
   route.

If you are still on `0.6.8` or older, complete
[Upgrading to 0.6.8](#upgrading-to-068) first.

## Upgrading to 0.6.8

`0.6.8` runs a registered per-type resource handler on nested relationship
routes as well as collection and member routes. Update the host dependency
to `recording_studio_api`, `~> 0.6.8`.

1. No migrations. Nested routes without a handler keep today's shared
   `ResourceOperations` path and inline nested index/show.
2. The same registration covers nested children:

   ```ruby
   RecordingStudioApi.register_resource_handler(
     "SupportPage",
     :create,
     api: :operations,
     handler: SupportPages::Api::Create
   )
   ```

   Nested `POST /sections/:parent_id/pages` calls that handler. From
   `0.6.9` the nested route passes raw ids instead of a preloaded
   `parent_recording`. `index`, `show`, `update`, and `destroy` on the
   nested route do the same.
3. The handler owns access checks. This gem does not run the nested
   parent role check first. The nested relationship must still list the
   action in `endpoints`, and the child type must still enable the
   operation.
4. Collection and member dispatch is unchanged from `0.6.7`.

If you are still on `0.6.7` or older, complete
[Upgrading to 0.6.7](#upgrading-to-067) first.

## Upgrading to 0.6.7

`0.6.7` lets a gem register a handler for one recordable type and action.
Types without a handler keep the shared handlers. Nested relationship
routes were not included until `0.6.8`. Update the host dependency to
`recording_studio_api`, `~> 0.6.7`.

If you are still on `0.6.5` or older, complete
[Upgrading to 0.6.5](#upgrading-to-065) first.

## Upgrading to 0.6.6

`0.6.6` lets a gem register a handler for one recordable type and action.
Types without a handler keep today's shared handlers. Update the host
dependency to `recording_studio_api`, `~> 0.6.6`.

1. No migrations. Paths, tokens, OpenAPI for unregistered types, and the
   built-in resource and move handlers stay as they are.
2. Register the handler next to the capability action. Pass the recordable
   type, the action, the API, and a callable:

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

   Actions are `index`, `show`, `create`, `update`, `destroy`, or a
   capability action such as `move`. `api:` defaults to `:public`.
3. The handler receives the same context the shared handler receives.
   Resource actions get a `ResourceOperationContext`. Capability actions get
   an `ActionContext`. Return `{ json:, status: }`. Route keys (`api_key`,
   `api_version`, `member_action`) are left out of that context's params
   before the action's input contract runs, so the handler sees the action
   input.
4. The handler owns access checks for that type and action. This gem does
   not run the shared member-action role check first, and it does not add
   permission, search, or other business rules. The action must still be
   enabled on that type, the same way it is today.
5. A handler registered for one type or API does not run for another type
   or API. Lookup returns `nil` when nothing is registered, and dispatch
   uses the shared handler.

If you are still on `0.6.5` or older, complete
[Upgrading to 0.6.5](#upgrading-to-065) first.

## Upgrading to 0.6.5

`0.6.5` dispatches `register_endpoint` routes on path and HTTP verb. Update
the host dependency to `recording_studio_api`, `~> 0.6.5`.

1. No migrations. Keep passing `http_verb` on `register_endpoint`. Recordable
   CRUD and capability actions do not change verbs.
2. `GET` and `POST` on the same collection path (and `GET` and `PATCH` on the
   same member path) now run the matching handler on the public API and on a
   named API such as `:operations`.
3. A registered path with no handler for the request verb returns 405 Method
   Not Allowed and an `Allow` header. It no longer returns 422
   `unsupported_action` or the wrong handler.
4. Hosts that already registered one verb per path keep working. A client that
   called the wrong verb and expected 422 should handle 405.

If you are still on `0.6.2` or older, complete
[Upgrading to 0.6.4](#upgrading-to-064) first.

## Upgrading to 0.6.4

`0.6.4` lets the new API key form open from an admin root on the public API.
Update the host dependency to `recording_studio_api`, `~> 0.6.4`.

1. No migrations. The access point must still be a type that API allows, and
   the person must be allowed to manage it.
2. When an admin root has no access point for the selected API, the form
   lists manageable roots that do. A public key opened from an admin root is
   created on the chosen workspace. It is not nested under the admin root.
3. A workspace opening the public API, and an admin root opening operations,
   still use the access point already in that tree.

If you are still on `0.6.1` or older, complete
[Upgrading to 0.6.2](#upgrading-to-062) first.

## Upgrading to 0.6.2

`0.6.2` bumps companion RecordingStudio pins only. Update the host dependency
to `recording_studio_api`, `~> 0.6.2`.

1. Companion pins: Admin `v2.0.4`, Moveable `v3.0.3`, Root Switchable
   `v0.5.3`. Recording Studio stays `~> 4.2` / `v4.2.2`, Accessible `~> 0.11`
   / `v0.11.1`, FlatPack `v0.1.143`, and Oauth `~> 0.2.2` / `v0.2.2` when the
   host uses Connect.
2. No migrations. No Accessible, auth, or registration changes in this gem.

If you are still on Accessible 0.9 or this gem before `0.6.1`, complete
[Upgrading to 0.6.1](#upgrading-to-061) first.

---

## Upgrading to 0.6.1

`0.6.1` ranks Accessible roles with `RecordingStudio::AccessRoles`. It does
not call `RecordingStudio::Access.roles`. Update the host dependency to
`recording_studio_api`, `~> 0.6.1`.

1. Upgrade Accessible to `0.11.0` or newer (`~> 0.11`) before this gem.
   Matching dummy/dev tag is `v0.11.1`. Recording Studio stays `~> 4.2` /
   `v4.2.2`. Admin `2.0.1`, Moveable `3.0.0`, Root Switchable `v0.5.0`,
   FlatPack `v0.1.143`, and Oauth `~> 0.2.2` / `v0.2.2` when the host uses
   Connect.
2. Run Accessible's migrations, then `bin/rails db:migrate`:

   ```bash
   bin/rails generate recording_studio_accessible:migrations
   bin/rails db:migrate
   ```

   `recording_studio_accesses.role` becomes a string (`view`, `edit`,
   `admin`, or a custom name). Accessible 0.10 also adds invitations.
3. Delete any `RecordingStudio::Access.define_singleton_method(:roles)` (or
   similar) shim. Do not restore `Access.roles` in the host.
4. If the host ranked roles with `RecordingStudioApi::Configuration::ACCESS_ROLE_RANKS`,
   switch to `RecordingStudio::AccessRoles::ORDER`, `value_for`,
   `satisfies?`, and `names_at_or_above`.
5. No migrations in this gem. REST, auth, and registration are unchanged.
   This gem's fallback `RecordingStudio::Access` no longer declares
   `enum :role`. Accessible owns that model in a host app.

If you are still on Accessible 0.9 or Recording Studio 4.1, complete
[Upgrading to 0.6.0](#upgrading-to-060) first.

---

## Upgrading to 0.6.0

`0.6.0` adds an optional progress reporter on handler contexts. REST request
handling is unchanged. Update the host dependency to
`recording_studio_api`, `~> 0.6.0`.

1. Companion pins are unchanged from `0.5.6`. Recording Studio `~> 4.2` /
   `v4.2.2`, Accessible `~> 0.9` / `v0.9.0`, Admin `2.0.1`, Moveable `3.0.0`,
   Root Switchable `v0.5.0`, FlatPack `v0.1.143`, and Oauth `~> 0.2.2` /
   `v0.2.2` when the host uses Connect.
2. No new migrations. No new grant hooks or token authenticators in this gem.
3. Capability, resource, and named-endpoint handlers may call
   `context.progress(current:, total:, message:)` and `context.cancelled?`.
   REST still builds contexts with `progress_reporter: nil`, so those calls
   no-op and `cancelled?` is `false`.
4. A reporter is any object that responds to `progress(current:, total:,
   message:)` and `cancelled?`. Do not pass MCP, SSE, or JSON-RPC types into
   this gem except as that duck type. Callers that construct a context
   outside REST (for example RecordingStudio MCP) pass the reporter in.

If you are still on Accessible 0.7 or Recording Studio 4.1, complete
[Upgrading to 0.5.6](#upgrading-to-056) first.

---

## Upgrading to 0.5.6

`0.5.6` accepts a public Oauth client's delegated bearer on a named API
resource path. Machine `client_credentials` clients stay bound to one API.
Update the host dependency to `recording_studio_api`, `~> 0.5.6`.

1. Companion pins are unchanged from `0.5.5`, except Oauth. Recording Studio
   `~> 4.2` / `v4.2.0`, Accessible `~> 0.9` / `v0.9.0`, Admin `2.0.1`,
   Moveable `3.0.0`, Root Switchable `v0.5.0`, FlatPack `v0.1.143`, and Oauth
   `~> 0.2.2` / `v0.2.2` when the host uses Connect.
2. No new migrations. No new grant hooks or token authenticators in this gem.
3. Keep public Registered Apps on `api_key=public`. Do not force the client
   onto the named API key. Oauth `0.2.2` mints the token. This gem accepts
   that bearer when `api_client.registered_for_api?` says the client is
   registered for the request API.
4. Confidential clients and `client_credentials` API-key clients still need
   an exact `api_key` match.

If you are still on Accessible 0.7 or Recording Studio 4.1, complete
[Upgrading to 0.5.5](#upgrading-to-055) first.

---

## Upgrading to 0.5.5

`0.5.5` routes `GET` member capability actions through the existing
`…/:id/actions/:action_name` and short `…/:id/:action_name` paths on public
and named APIs. Update the host dependency to `recording_studio_api`,
`~> 0.5.5`.

1. Companion pins are unchanged from `0.5.4`. Recording Studio `~> 4.2` /
   `v4.2.0`, Accessible `~> 0.9` / `v0.9.0`, Admin `2.0.1`, Moveable `3.0.0`,
   Root Switchable `v0.5.0`, and FlatPack `v0.1.143`.
2. No new migrations. No new capability registrations in this gem.
3. Keep `http_verb: :get` on the action registration that owns the read
   payload. Allowlist the action in `capability_actions` on the recordable
   type API. Do not add a parallel GET-only controller.
4. Mutating member actions stay verb-checked. `GET` against a `POST`-only
   action still returns `unsupported_action`.

If you are still on Accessible 0.7 or Recording Studio 4.1, complete
[Upgrading to 0.5.4](#upgrading-to-054) first.

---

## Upgrading to 0.5.4

`0.5.4` adds `RecordingStudioApi.register_endpoint` for JSON endpoints that are not
a recordable. Tree CRUD, capability actions, and OAuth Connect are unchanged.
Update the host dependency to `recording_studio_api`, `~> 0.5.4`.

1. Companion pins are unchanged from `0.5.3`. Recording Studio `~> 4.2` /
   `v4.2.0`, Accessible `~> 0.9` / `v0.9.0`, Admin `2.0.1`, Moveable `3.0.0`,
   Root Switchable `v0.5.0`, and FlatPack `v0.1.143`.
2. No new migrations. No Connect screens, token-endpoint, or grant-hook
   changes in this gem.
3. Register a named endpoint from an initializer when the host needs a path that
   is not a tree collection. Use the same mount and version prefix as the rest
   of that API. A public client still cannot call an operations-only endpoint.

   ```ruby
   RecordingStudioApi.register_endpoint(
     :ping,
     api: :public,
     http_verb: :get,
     path: "ping",
     handler: ->(_context) { { ok: true } }
   )
   ```

4. Handlers receive `RecordingStudioApi::RegisteredEndpointContext`. That context
   has the client, credential, access recording, access grant, root, and
   params. It does not have `recording`. Authorize against the client's access
   recording inside the handler when you need Accessible. The gem does not
   require a recording for these endpoints.
5. OpenAPI and Scalar list these routes under the `Endpoints` tag. They are not
   documented as a fake recordable type.

If you are still on Accessible 0.7 or Recording Studio 4.1, complete
[Upgrading to 0.5.3](#upgrading-to-053) first.

---

## Upgrading to 0.5.3

`0.5.3` adds Cloud Agent boot files so Builds fetch Cursor skills and plugin
rules. Product, OAuth Connect, token URLs, and the API surface are unchanged.
Update the host dependency to `recording_studio_api`, `~> 0.5.3`.

1. Companion pins are unchanged from `0.5.2`. Recording Studio `~> 4.2` /
   `v4.2.0`, Accessible `~> 0.9` / `v0.9.0`, Admin `2.0.1`, Moveable `3.0.0`,
   Root Switchable `v0.5.0`, and FlatPack `v0.1.143`.
2. No new migrations. No Connect screens, token-endpoint, or grant-hook
   changes in this gem.
3. Rebuild the Cloud Agent environment with Draft off so Build runs
   `.cursor/install.sh` and loads the skill pack. See
   [docs/cursor-skills.md](docs/cursor-skills.md).

If you are still on Accessible 0.7 or Recording Studio 4.1, complete
[Upgrading to 0.5.2](#upgrading-to-052) first.

---

## Upgrading to 0.5.2

`0.5.2` keeps this gem the resource server. It adds a grant hook so `recording_studio_oauth`
can plug `authorization_code` and `refresh_token` into the existing token endpoints.
Update the host dependency to `recording_studio_api`, `~> 0.5.2`.

1. Companion pins are unchanged from `0.5.1`. Recording Studio `~> 4.2` / `v4.2.0`,
   Accessible `~> 0.9` / `v0.9.0`, Admin `2.0.1`, Moveable `3.0.0`, Root Switchable
   `v0.5.0`, and FlatPack `v0.1.143`.
2. `POST /recording_studio_api/oauth/token` and
   `POST /recording_studio_api/apis/<api-name>/oauth/token` still issue
   `client_credentials` when the Oauth gem is absent. No host change is required for
   machine clients.
3. If another gem registers a grant, call
   `RecordingStudioApi.register_oauth_grant(grant_type, handler:)` at boot. List
   registered grants with `RecordingStudioApi.oauth_grants`. You cannot replace
   `client_credentials` through this hook.
4. Unknown `grant_type` values now return `invalid_grant` instead of
   `unsupported_grant_type`. Update clients that matched the old error code.
5. No new migrations. No OauthClient tables, consent views, or Connect screens in
   this gem.

If you are still on Accessible 0.7 or Recording Studio 4.1, complete
[Upgrading to 0.5.1](#upgrading-to-051) first.

---

## Upgrading to 0.5.1

`0.5.1` keeps Recording Studio `~> 4.2` and raises Accessible to `~> 0.9`. Update the host
dependency to `recording_studio_api`, `~> 0.5.1`, then apply the steps below.

1. Upgrade Accessible to `0.9.0` or newer (`~> 0.9`) before installing this gem. Matching
   dummy/dev tags are RecordingStudio `v4.2.0`, Accessible `v0.9.0`, Admin `2.0.1`,
   Moveable `3.0.0`, Root Switchable `v0.5.0`, and FlatPack `v0.1.143`.
2. If the host is still on Accessible 0.7, run
   `bin/rails generate recording_studio_accessible:migrations` and `bin/rails db:migrate`
   so `recording_studio_accesses.depends_on_recording_id` exists (added in Accessible 0.8).
   This gem has no new migrations of its own.
3. Independent grants are unchanged. Dependent grants (`depends_on:`) now void when the
   manager Access recording is moved; they stay at the old node and do not follow the move.
   Role-weaken via revise, trash, and destroy already voided dependents in Accessible 0.8.
4. `authorized?` still fail-closes off-root/weaker. No API surface, OAuth, or UI changes
   in this gem.

If you are still on Recording Studio 4.1 or Accessible 0.6, complete
[Upgrading to 0.5.0](#upgrading-to-050) first.

---

## Upgrading to 0.5.0

`0.5.0` pins this engine onto Recording Studio 4.2 and Accessible 0.7. Update the host
dependency to `recording_studio_api`, `~> 0.5.0`, then apply the steps below.

1. Upgrade RecordingStudio to `4.2.0` or newer (`~> 4.2`) and Accessible to `0.7.0` or newer
   (`~> 0.7`) before installing this gem. Matching dummy/dev tags are RecordingStudio
   `v4.2.0`, Accessible `v0.7.0`, Admin `2.0.1`, Moveable `3.0.0`, Root Switchable
   `v0.5.0`, and FlatPack `v0.1.143`.
2. Run the Recording Studio 4.0 harden indexes migration in the host
   (`rails g recording_studio:migrations` or copy
   `harden_recording_studio_indexes_and_constraints`) and `bin/rails db:migrate`.
3. Enable Accessible with `RecordingStudio.enable_capability(:accessible, on: Type)` on
   each recordable that should hold grants. Do not include
   `AllowsAccessibleChildren` / `recording_studio_accessible_children`.
4. Include `RecordingStudio::UsesDefaultLayout` on authenticated host controllers (or keep
   `config.layout_name = "recording_studio/default_layout"`). Recording Studio 4.2 applies
   `data-theme="rounded"` on `body`; hosts that still key FlatPack off `html` can stamp
   `html data-theme="rounded"` without copying the layout. Do not vendor
   `recording_studio/default_layout`.
5. First owner grants: `RecordingStudioAccessible.bootstrap_owner_access!` on an empty
   owned root. Later members: `grant_access`. Set `access_actor_types` so User and
   `RecordingStudioApi::ApiClient` can hold grants.
6. FlatPack 0.1.143 buttons use `href:` (not `url:`). Sidebar items use `text:` (not
   `label:`).
7. Run `bin/rails generate recording_studio_api:migrations` and `bin/rails db:migrate`.
   `0.5.0` allows `access_recording_id` to be null on API clients so Accessible 0.7 can
   persist the client before `grant_access` (actors must be persisted). Provision still
   assigns the access recording in the same transaction.

If you are still on a pre-`0.4.0` digest/rate-limit default, complete
[Upgrading to 0.4.0](#upgrading-to-040) first.

---

## Upgrading to 0.4.0

`0.4.0` is a pre-production breaking release focused on safer defaults and operational hardening.
Update the host dependency to `recording_studio_api`, `~> 0.4.0`, then apply the steps below.

If you are still on a pre-`0.3.0` flat-contract API, complete [Upgrading to 0.3.0](#upgrading-to-030)
first.

No database migration is required for `0.4.0`.

### 1. Token digests

1. Ensure `Rails.application.secret_key_base` is set, or set
   `RECORDING_STUDIO_API_TOKEN_DIGEST_PEPPER` / `config.token_digest_pepper`. There is no hardcoded
   digest pepper fallback.
2. `token_digest_legacy_verify` now defaults to `false`. If you still have unsalted SHA256 digests
   in the database, temporarily set `config.token_digest_legacy_verify = true`, rotate or allow
   rehash-on-login, then turn it back off.

### 2. Rate limits and named API defaults

1. Authenticated API rate limiting is on by default (`rate_limit_api_enabled = true`). Disable
   explicitly in non-production hosts if needed.
2. Fail-closed buckets default to `%w[oauth api_pre_auth api]`. Ensure Redis is reachable in
   production or tune `rate_limit_fail_closed_buckets`.
3. Named APIs default to `default_access: :read_only`. Register write operations explicitly or set
   `api.default_access = :read_write`.

### 3. Deletes, admin revoke, and mobile OAuth migrations

1. Resource `DELETE` hard-deletes the recording/recordable. Recording Studio no longer exposes a
   shared trash workflow through this gem; do not expect soft-delete/`trashed_at` behavior from
   destroy endpoints.
2. Admin credential revoke under AdminRoot is intentionally named-API scoped (not limited to the
   currently selected workspace root). Workspace operators continue to revoke via API client screens
   that are tenancy-scoped.
3. Historical mobile OAuth create/drop migrations in the dummy app remain as historical artifacts.
   Do not rewrite old migrations; hosts that never ran them can ignore
   `remove_mobile_oauth_from_recording_studio_api`.

### 4. Client features

1. Send `Idempotency-Key` on creates when retries are possible. Responses are cached in Redis for 24
   hours per API + client + key when Redis is available.
2. Collection indexes accept `filter[attribute]=value` (exact) and `q` (ILIKE across filterable
   attributes). OpenAPI documents the allowed filter attributes per resource.
3. After regenerating install artifacts, run
   `bin/rails flat_pack:prepare_tailwind_assets tailwindcss:build` so FlatPack Grid utilities scan
   correctly. Gitignore `tmp/tailwind_scan/` and `app/assets/tailwind/gem_sources.css`.

---

# Upgrading to 0.3.0

`0.3.0` is a pre-production breaking release. Upgrade API clients, recordable registrations, and
OpenAPI snapshots together; do not expect the previous response structure to remain available.

## 1. Update the gem and regenerate API artifacts

Update the host application's dependency to `recording_studio_api`, `~> 0.3.0` (or `~> 0.4.0` if
continuing through the current release). Restart the application after updating registrations, then
regenerate or re-export any OpenAPI documents, generated clients, fixtures, and contract snapshots.

No database migration is required for this release.

## 2. Update client response handling

Resource responses are now flat. Read serializer fields directly from the record and read expanded
relationships directly from their registered name.

```json
{
  "id": "workspace-1",
  "type": "Workspace",
  "root_id": "workspace-1",
  "parent_id": null,
  "created_at": "2026-08-14T00:00:00Z",
  "updated_at": "2026-08-14T00:00:00Z",
  "name": "Editorial",
  "pages": [
    { "id": "page-1", "type": "Page", "title": "Welcome" }
  ]
}
```

Replace `response.attributes.name` with `response.name` and replace
`response.relationships.pages.data` with `response.pages`. The `actions` key is removed. Standard
collection endpoints return their records in `records` and pagination details in `meta`; a limited
collection relationship reports its `limit` and `has_more` under `_meta.<relationship>`.

## 3. Update recordable registrations

Registrations must explicitly declare the keys that each serializer is allowed to emit. Replace
implicit serializer output and child-only relationship declarations with `output_keys`, `fields`,
and named `relationships`.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  serializer: ->(workspace, **) { { name: workspace.name } },
  output_keys: %i[name],
  writable_attributes: %i[name],
  fields: {
    cover_image_url: {
      resolver: ->(context) { context.recordable.cover_image_url },
      include: :request
    }
  },
  relationships: {
    pages: {
      source: :children,
      child_type: "Page",
      many: true,
      include: :request,
      serializer: ->(page, **) { { title: page.title } },
      output_keys: %i[title],
      limit: 20,
      endpoints: %i[index show]
    }
  }
)
```

Use `source: :children` for a real Recording Studio child edge. Use `source: :custom` with a
`resolver:` for application-defined related records; custom relationships are read-only through
the engine. A relationship serializer and `output_keys` are required, preventing accidental
serialization of arbitrary model attributes.

## 4. Request additional fields and relationships explicitly

Set `include: true` to always return a registered field or relationship. Set `include: :request`
to return it only when the client selects it:

```text
GET /recording_studio_api/api/v1/workspaces/workspace-1?include=cover_image_url,pages
```

Only registered request-enabled names may be selected. Wildcards, nested include paths, and
`include=true` are not supported. For a registered `children` relationship, clients can also
browse related records through its named endpoint, such as
`GET /recording_studio_api/api/v1/workspaces/workspace-1/pages`.

## 5. Send flat write bodies

Create and update requests send registered writable fields at the request body root:

```json
{ "name": "Editorial" }
```

Use `parent_id` only for a top-level create that chooses a parent Recording Studio record. Nested
creates obtain the parent from the route, and updates cannot change `parent_id`; use a registered
move action to change a record's parent.

`0.3.0` rejects the former `{ "attributes": { ... } }` request envelope. Send writable fields at
the request body root. The legacy response shape is not available.

## 6. Update API error handling

Resource API errors now use a nested object:

```json
{
  "error": {
    "code": "not_found",
    "message": "Resource was not found in this API scope"
  }
}
```

Read `error.code` and `error.message`. Validation failures use `code: "validation_failed"` and may
include `error.details`. OAuth token/revoke endpoints keep the OAuth wire format
`{ "error": "...", "error_description": "..." }`.
