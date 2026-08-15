# Upgrading to 0.3.0

`0.3.0` is a pre-production breaking release. Upgrade API clients, recordable registrations, and
OpenAPI snapshots together; do not expect the previous response structure to remain available.

## 1. Update the gem and regenerate API artifacts

Update the host application's dependency to `recording_studio_api`, `~> 0.3.0`. Restart the
application after updating registrations, then regenerate or re-export any OpenAPI documents,
generated clients, fixtures, and contract snapshots.

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