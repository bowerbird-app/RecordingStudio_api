# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-08-31

### Added
- Delegated OAuth for third-party apps: each approval creates its own Accessible Access (sibling of the manager's), not a token bound to the user
- `authorization_code` and `refresh_token` grant types on the existing `/oauth/token` endpoints; `client_credentials` is unchanged
- Consent and connected-app screens composed from `recording_studio/default_layout` + FlatPack (`UsesDefaultLayout`); host authentication (dummy Devise) owns sign-in. Consent is a connect screen (`Connect {app}`) in the first cell of `FlatPack::Grid` (`cols: 2`): one workspace is title + Continue / Cancel only; several use a Flatpack Workspace Select, with permission only when there is more than View (default `view`), and stacked full-width Continue / Cancel. Connected apps uses a Flatpack List inside a Card.
- RFC 8414 authorization-server metadata and RFC 9728 protected-resource metadata; PKCE S256; optional RFC 8707 `resource`; Client ID Metadata Documents for public clients
- Consent `grant_access` passes `depends_on:` with the manager's Access recording so Accessible 0.8 owns the cap, authorize-time fail-closed, and dependent voiding

### Changed
- Access tokens may belong to either a machine `ApiCredential` or an `OauthAuthorization` (exactly one)
- Delegated `AccessGrant.actor` is the authorization, not the user; handlers keep using `access_grant.authorize!`
- **Breaking dependency floor:** requires RecordingStudio Accessible `~> 0.8` (tested against `0.8.0`) so `depends_on_recording_id` exists. RecordingStudio stays `~> 4.2`

### Removed
- API-side Recording/Access after_commit monkey-patches that voided OAuth grants. Accessible `VoidDependentAccesses` / `authorized?` own that ACL. User Cancel and connected-apps revoke still use `VoidOauthAuthorization`

See [UPGRADING.md](UPGRADING.md) for Accessible 0.8, `depends_on_recording_id`, `access_actor_types`, and token-endpoint changes.

## [0.5.0] - 2026-08-31

### Changed
- **Breaking dependency floor:** requires RecordingStudio `~> 4.2` (tested against `4.2.0`) and RecordingStudio Accessible `~> 0.7` (tested against `0.7.0`)
- Dummy and development Gemfiles pin RecordingStudio `v4.2.0`, Accessible `v0.7.0`, Admin `2.0.1`, Moveable `3.0.0`, Root Switchable `v0.5.0`, and FlatPack `v0.1.143`
- Dummy app uses `RecordingStudio::UsesDefaultLayout` from Recording Studio 4.2 as-is (no vendored `default_layout` copy). Rounded theme is applied on `html` and `body`; API-key pages do not render RootSwitchDropdown
- Dummy seeds bootstrap the first owner with `bootstrap_owner_access!`, then use `grant_access` for later grants
- API client provision persists the client before `grant_access` so Accessible 0.7 actor persistence checks pass (`access_recording_id` may be null until the grant is written)

See [UPGRADING.md](UPGRADING.md) for the Recording Studio 4.2 host pin.

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_api/releases/tag/v0.1.0
