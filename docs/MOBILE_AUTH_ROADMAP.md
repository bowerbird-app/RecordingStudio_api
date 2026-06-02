# Mobile Auth Roadmap

This document describes the mobile auth shape for RecordingStudioApi while keeping all auth artifacts inside the Recording Studio recording/recordable model.

## Current State

- Grant types: `client_credentials`, `authorization_code` with PKCE, and `refresh_token`
- Machine token chain in recording tree: Access -> ApiClient -> ApiCredential -> ApiAccessToken
- Mobile token chain in recording tree: Access -> OauthGrantSession -> OauthSessionAccessToken and OauthRefreshToken
- Machine access-token TTL follows `RecordingStudioApi.configuration.token_ttl`
- Mobile access tokens are short-lived and refresh tokens rotate on use
- Every accepted bearer token resolves to a `RecordingStudioApi::AccessGrant` before API dispatch

## Target State

- Mobile users authenticate with user-delegated OAuth when direct mobile access is required
- Workspace/root scope remains explicit and auditable
- No parallel auth subsystem outside Recording Studio recording topology
- Capability handlers authorize behavior through the resolved access grant and Recording Studio Accessible

## Stage 0: Alignment

Goals:

- Choose primary integration mode: backend-for-frontend now vs direct mobile OAuth now
- Define security and UX requirements (login frequency, revocation behavior, scope model)
- Define tenant/root scoping policy for multi-workspace users

Deliverables:

- Decision record for auth mode
- Scope matrix by resource and workspace/root

## Stage 1: Harden Current Baseline

Goals:

- Keep current credential/token chain stable
- Confirm admin visibility expectations for workspace-scoped API artifacts
- Document lifecycle: provision, issue token, revoke, expire

Deliverables:

- Admin/operator runbook
- Updated integration docs and examples

## Stage 2: Mobile Docs and Contracts

Goals:

- Publish clear mobile integration guide
- Define API error contract for expired/invalid/scope errors
- Define client renewal and retry guidance

Deliverables:

- Mobile sequence diagrams
- Error and retry contract
- Multi-root scoping examples

## Stage 3A: Backend-for-Frontend Path (Recommended First)

Goals:

- Keep API secrets server-side
- Use existing client_credentials flow from backend only
- Expose mobile-safe backend endpoints for app clients

Deliverables:

- Backend integration reference implementation
- Operational policy for credential rotation/revocation

Notes:

- This stage enables mobile product delivery with minimal gem auth changes.

## Stage 3B: Direct Mobile OAuth Path

Status: implemented baseline.

Goals:

- Support user-delegated OAuth for mobile public clients
- Support Authorization Code + PKCE
- Support refresh-token rotation and token-family revocation

Implemented structural pieces:

- Authorization endpoint + token endpoint extensions
- Public client model with exact redirect URI matching and PKCE requirement
- Grant/session recordables under access recording scope
- Refresh-token model with rotation and revocation controls

Remaining product decisions:

- Scope and consent persistence by workspace/root
- Mobile client registration UI and operator runbooks
- User-facing copy for multi-access selection

Delivered baseline:

- OAuth endpoints and services
- Grant/session/refresh recordables and migrations
- Tests for login, access selection, token exchange, refresh, and revocation

## Stage 4: Security Hardening

Goals:

- Shorten access-token TTL for mobile user flows
- Add refresh-token misuse detection
- Add rate limits and anomaly controls

Deliverables:

- Security policy defaults
- Alerting and incident playbook

## Stage 5: Governance and Admin UX

Goals:

- Give workspace admins clear visibility into app usage
- Support rapid revocation and investigation

Deliverables:

- Workspace-level auth artifact views
- Last-used and scope visibility
- Admin kill-switch and audit actions

## Suggested Delivery Order

1. Stage 0
2. Stage 1
3. Stage 2
4. Stage 3A (ship quickly)
5. Stage 3B (if direct mobile auth is required)
6. Stage 4
7. Stage 5