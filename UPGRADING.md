# Upgrading RecordingStudioApi

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
