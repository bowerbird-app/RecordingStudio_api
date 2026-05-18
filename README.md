# RecordingStudio API

 Mountable Rails engine for a programmable Recording Studio API.

This repository now completes the last unfinished agent pass by renaming the live engine surfaces to `recording_studio_api` / `RecordingStudioApi` and replacing the placeholder docs with the original architecture handoff for the API gem.

## Current Scope

- bearer-token API authentication backed by `RecordingStudioApi::ApiClient` and `ApiCredential`
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

- authorization should flow through accessible records and Recording Studio access boundaries
- `ApiClient` is the acting API principal
- each access recording owns at most one active API credential record
- raw secrets should only be revealed at creation or rotation time

`ApiClient` is an immutable Recording Studio recordable. It is recorded as a child of a `RecordingStudio::Access` recording, while the mutable bearer-token state lives in `ApiCredential` with a digest, rotation, revocation, and last-used tracking.

### Boot validation

The eventual runtime should fail fast when:

- an API action points at a capability that is not enabled
- duplicate action names are registered
- required handlers or serializers are missing

## Current Ruby Surface

The renamed engine currently exposes the same basic Ruby integration points as the template:

```ruby
RecordingStudioApi.configure do |config|
  # Optional placeholder for an outbound API integration you add later.
  # config.api_key = ENV["RECORDING_STUDIO_API_KEY"]
  config.enable_feature_x = false
  config.timeout = 5
end

RecordingStudioApi.configuration
RecordingStudioApi::Hooks.run(:before_initialize)
```

`api_key` remains available for host-managed outbound integrations, but inbound API authentication now uses provisioned bearer tokens stored in `ApiCredential`.

### Provisioning and authentication

Provision a token from an existing `RecordingStudio::Access` recording:

```ruby
result = RecordingStudioApi::Services::ProvisionApiClient.call(
  access_recording: access_recording,
  name: "Primary token"
)

token = result.value.fetch(:token)
```

Authenticate requests with:

```http
Authorization: Bearer rsapi_<public_id>.<secret>
```

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

- `GET /recording_studio_api/api/v1` — list available API resources
- `GET /recording_studio_api/api/v1/:resource` — list recordings of a resource type inside the authenticated root
- `GET /recording_studio_api/api/v1/:resource/:id` — show one recording
- `GET /recording_studio_api/api/v1/:resource/:id/actions` — list enabled capability actions
- `POST /recording_studio_api/api/v1/:resource/:id/actions/:action_name` — execute a capability-backed action

## Dummy App

Use `test/dummy/` as the review surface for the completed handoff:

- `/docs/install` documents the renamed install and migration flow
- `/docs/config` records the current config API plus the capability action registry
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
| RecordingStudio | v0.1.0-alpha (pinned in `test/dummy/Gemfile`) |
| FlatPack        | v0.1.33 (pinned in `test/dummy/Gemfile`) |
| Devise          | latest  |

## Documentation

The original gem template documentation is preserved in this repository under `docs/gem_template/` as architectural reference material. Those files are for contributors reviewing the repo, not packaged gem docs; the README and dummy app are now the source of truth for the Recording Studio API design handoff.
