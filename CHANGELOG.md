# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-15

### Added
- OAuth2 `client_credentials` authentication with Recording Studio-backed API clients, credentials, and access tokens
- OAuth2 Authorization Code with PKCE, refresh-token rotation, and token revocation for public mobile clients
- Capability-backed API action registration, versioned contribution contracts, and access-grant authorization
- Recordable resource lookup, nested resource routing, structured action input contracts, and OpenAPI documentation
- Configurable API version profiles and runtime dispatch to the newest compatible contribution contract
- Configurable pre-auth IP rate limiting for `/api/v1` requests
- FlatPack-based administration screens for API clients, OAuth clients, credentials, access tokens, grants, and request logs
- Install generator, Rails engine configuration, hooks, and a Minitest-covered dummy application integration

### Changed
- Renamed live engine surfaces from `gem_template` to `recording_studio_api`
- Replaced placeholder documentation with the RecordingStudio API architecture and integration guide

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_api/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_api/releases/tag/v0.1.0
