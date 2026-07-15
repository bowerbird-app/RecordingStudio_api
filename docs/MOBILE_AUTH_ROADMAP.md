# Mobile Auth Roadmap

This document is retained as an architectural note after the built-in mobile OAuth implementation was removed from RecordingStudioApi.

## Current State

- RecordingStudioApi now owns API access for machine clients only.
- Supported token issuance in this gem is `client_credentials` through `/recording_studio_api/oauth/token`.
- Bearer token authentication in this gem resolves either:
	- API access tokens issued from `ApiClient` and `ApiCredential`
	- Tokens authenticated by external gems through `RecordingStudioApi.register_token_authenticator`
- User-facing mobile or app OAuth is no longer implemented inside this gem.

## Intended Boundary

- A future app-access gem should own user login, public clients, authorization codes, refresh tokens, consent, and revocation UX.
- RecordingStudioApi should remain the shared API/resource authorization core.
- External auth gems should integrate through the public surface already exposed by RecordingStudioApi:
	- token authenticators
	- authorization-header authentication helpers
	- access-grant construction
	- actor access-recording resolution
	- OAuth-style error payload/status helpers

## Recommended Delivery Path

1. Keep mobile clients behind a backend-for-frontend when possible.
2. If direct mobile auth is required, build it in a dedicated app-access gem.
3. Have that gem register token authenticators against RecordingStudioApi instead of reintroducing mobile OAuth models into this repository.

## Non-Goals For This Gem

- No public OAuth client registry.
- No authorization-code or refresh-token persistence.
- No mobile-session admin UI.
- No mobile-auth-specific recording tree artifacts.