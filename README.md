# RecordingStudio API

Mountable Rails engine scaffold for a future programmable Recording Studio API.

This repository now completes the last unfinished agent pass by renaming the live engine surfaces to `recording_studio_api` / `RecordingStudioApi` and replacing the placeholder docs with the original architecture handoff for the API gem.

## Current Scope

- renamed engine, generators, migrations, and tests under `RecordingStudioApi`
- dummy app for auth, FlatPack, Recording Studio wiring, and docs review
- documented design for programmable API surfaces, nested resources, and access management
- preserved template reference material in `docs/gem_template/`

The current codebase still ships the template engine mechanics (configuration, hooks, install generator, sample service objects). The HTTP API described below is the intended next implementation phase, not a finished endpoint set in this branch.

## Proposed API Architecture

### Core registries

`RecordingStudioApi` is intended to expose explicit registration layers for:

- API surfaces
- resources
- nested resources
- actions backed by Recording Studio capabilities

Each action should declare its verb, scope, capability mapping, handler, and serializer so the API surface is opt-in and boot-time validated.

### Routing model

- top-level resources represent recordable roots or directly addressable records
- nested resources mirror the real recording tree, not ad hoc controller structure
- capability actions sit beside resources as explicit member or collection endpoints

### Access model

- authorization should flow through accessible records and Recording Studio access boundaries
- `ApiClient` is the acting API principal
- each accessible record should own at most one active API credential record
- raw secrets should only be revealed at creation or rotation time

### Boot validation

The eventual runtime should fail fast when:

- an API action points at a capability that is not enabled
- a resource registration conflicts with another route or serializer contract
- nested resource declarations contradict the recording hierarchy
- required handlers or serializers are missing

## Current Ruby Surface

The renamed engine currently exposes the same basic Ruby integration points as the template:

```ruby
RecordingStudioApi.configure do |config|
  config.api_key = ENV["RECORDING_STUDIO_API_KEY"]
  config.enable_feature_x = false
  config.timeout = 5
end

RecordingStudioApi.configuration
RecordingStudioApi::Hooks.run(:before_initialize)
```

These APIs keep the engine loadable while the future HTTP-specific DSL is designed on top of them.

## Dummy App

Use `test/dummy/` as the review surface for the completed handoff:

- `/docs/install` documents the renamed install and migration flow
- `/docs/config` records the current config API plus the planned registry constraints
- `/docs/methods` documents the live Ruby entrypoints
- `/docs/recordable_types`, `/docs/recordings_tree`, and `/docs/gem_views` verify Recording Studio wiring and engine assets

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
