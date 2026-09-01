# App Access Roadmap

RecordingStudioApi now issues both machine `client_credentials` tokens and delegated
authorization-code tokens for third-party apps. This note records the remaining boundary.

## Current State

- Machine clients still use `ApiClient` / `ApiCredential` under a Recording Studio Access, and
  `POST /recording_studio_api/oauth/token` with `grant_type=client_credentials`.
- Delegated apps use `OauthClient` (not a recordable) plus one `OauthAuthorization` per connect.
- Each approval creates its own Accessible Access, capped by the manager Access recording
  (`depends_on`). The token does not act as the user.
- Consent uses host authentication. Dummy Devise covers sign-in in this repository; Google login
  stays in Users.
- Bearer authentication still resolves either an issued API access token or a token from
  `RecordingStudioApi.register_token_authenticator`.
- Discovery is generic RFC 8414 + RFC 9728. PKCE S256 is required for public clients.

## Intended Boundary

- RecordingStudioApi owns API resource authorization, named APIs, AccessGrant, machine keys, and
  this delegated OAuth grant.
- User identity (Google login and similar) stays in the Users gem / host.
- External auth gems can still integrate through the public surface:
  - token authenticators
  - authorization-header authentication helpers
  - access-grant construction
  - actor access-recording resolution
  - OAuth-style error payload/status helpers

## Non-Goals For This Gem

- MCP transport and MCP-branded UI
- OIDC, SAML, and Dynamic Client Registration
- Invented OAuth scopes (Accessible roles only: view / edit / admin)
- Binding a delegated token to the manager's Access
- Doorkeeper or another OAuth gem
