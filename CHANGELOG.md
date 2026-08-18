# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-08-18

### Changed
- Runtime Redis dependency is now `~> 6.0` (was `~> 5.3`)
- Dummy and development pins move onto RecordingStudio `v3.0.3`, Accessible `v0.5.0`, Admin `1.2.0`, Moveable `2.1.1`, Root Switchable `v0.3.5`, and FlatPack `v0.1.129`
- Dummy Accessible setup configures `access_actor_types` and drops legacy `AllowsAccessibleChildren` usage

### Upgrade notes
- See [UPGRADING.md](UPGRADING.md) for Redis 6 and Accessible 0.5 host steps
- RecordingStudio `4.0.0` remains deferred until sibling gems allow `recording_studio ~> 4.0`

## [0.4.0] - 2026-08-15

### Added
- Optional `Idempotency-Key` header on resource creates (Redis-backed, scoped per API client)
- Collection index `filter[...]` exact-match filters and `q` substring search over sortable/writable attributes
- Install generator ships `lib/tasks/flat_pack_tailwind_assets.rake` plus `gem_sources.css` / Grid utility safelist guidance for host Tailwind builds

### Changed
- **Breaking (pre-production):** `token_digest_legacy_verify` defaults to `false`; enable temporarily while rehashing pre-pepper digests
- **Breaking (pre-production):** `token_digest_pepper` no longer falls back to a hardcoded string; set `RECORDING_STUDIO_API_TOKEN_DIGEST_PEPPER`, `config.token_digest_pepper`, or rely on `Rails.application.secret_key_base`
- **Breaking (pre-production):** authenticated API rate limiting defaults to enabled; `rate_limit_fail_closed_buckets` includes `api`
- Named API `default_access` defaults to `:read_only` (opt into writes via registration/`read_write`)
- Credential rotation locks the API client and active credential rows and treats uniqueness races as retryable failures
- Accessible recording authorization uses SQL `EXISTS` / subquery membership instead of materializing full id arrays for every check
- OpenAPI documents hard-delete semantics, collection filters/search, and `Idempotency-Key`
- Admin credential revoke remains intentionally AdminRoot / named-API scoped (not limited to the selected workspace root)

### Removed
- Placeholder `RecordingStudioApi::Services::ExampleService` and its tests

### Fixed
- Dummy/host Tailwind scanning for FlatPack Grid (`md:grid-cols-*`, `lg:grid-cols-*`) and icon sizing utilities when gems live outside vendor Docker paths

See [UPGRADING.md](UPGRADING.md) for digest, rate-limit, delete, and client migration steps.

## [0.3.0] - 2026-08-14

### Changed
- **Breaking (pre-production):** API responses now use the flat recording contract. Former
  `attributes` values are top-level, relationship values have no `relationships` or `data` wrapper,
  and `actions` is removed. Upgrade consumer snapshots, fixtures, and tests; no runtime legacy
  response compatibility is provided.
- Replaced recordable serializers and the child-only relationship DSL with explicit `output_keys`,
  `fields`, and named `children`/`custom` relationship sources
- Flattened API record responses and generated OpenAPI schemas; timestamps are now canonical
  response keys and collection entries are exposed as `records`
- Added generic named relationship endpoints and request-driven relationship expansion

See [UPGRADING.md](UPGRADING.md) for the required registration, client-response, request-body, and
relationship migration steps.

## [0.2.0] - 2026-08-03

### Added
- Configurable Scalar API documentation generator with named API support, customizable OpenAPI paths, and optional test-auth pages
- API client management policies and administration controls for API credentials and client access
- API settings, request context, and route helpers for isolated named API deployments
- Recording-level API-key support and access-control helpers for protected API resources

### Changed
- Hardened API documentation and test-credential workflows, including credential issuance and rotation
- Expanded OpenAPI documentation and API resource behavior for named APIs and access requests

## [0.1.0] - 2026-07-15

### Added
- OAuth2 `client_credentials` authentication with Recording Studio-backed API clients, credentials, and access tokens
- Capability-backed API action registration, versioned contribution contracts, and access-grant authorization
- Recordable resource lookup, nested resource routing, structured action input contracts, and OpenAPI documentation
- Configurable API version profiles and runtime dispatch to the newest compatible contribution contract
- Configurable pre-auth IP rate limiting for `/api/v1` requests
- FlatPack-based administration screens for API clients, credentials, access tokens, and request logs
- Install generator, Rails engine configuration, hooks, and a Minitest-covered dummy application integration

### Changed
- Renamed live engine surfaces from `gem_template` to `recording_studio_api`
- Replaced placeholder documentation with the RecordingStudio API architecture and integration guide

### Removed
- Built-in mobile OAuth authorization-code, PKCE, and refresh-token support; host applications can integrate external bearer-token authenticators instead

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_api/releases/tag/v0.1.0
