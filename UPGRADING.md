# Upgrading RecordingStudioApi

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
   `config.layout_name = "recording_studio/default_layout"`). Set `html data-theme="rounded"`.
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
