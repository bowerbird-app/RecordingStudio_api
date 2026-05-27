# Mobile Auth Roadmap

This document describes a staged path from current machine-to-machine auth to mobile-ready user-delegated OAuth while keeping all auth artifacts inside the Recording Studio recording/recordable model.

## Current State

- Grant type: `client_credentials`
- Token chain in recording tree: Access -> ApiClient -> ApiCredential -> ApiAccessToken
- Access-token TTL default: 30 days
- Best-fit use case: server-to-server and backend-for-frontend integration

## Target State

- Mobile users authenticate with user-delegated OAuth
- Workspace/root scope remains explicit and auditable
- No parallel auth subsystem outside Recording Studio recording topology

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

## Stage 3B: Direct Mobile OAuth Path (If Required)

Goals:

- Add user-delegated OAuth support for mobile public clients
- Support Authorization Code + PKCE
- Add refresh-token lifecycle

Structural gem changes:

- Authorization endpoint + token endpoint extensions
- Public client registration (redirect URIs, PKCE required)
- New grant/session recordables under access recording scope
- Refresh-token model with rotation and revocation controls
- Scope/consent persistence by workspace/root

Deliverables:

- OAuth endpoints and services
- Grant/session/refresh recordables and migrations
- Tests for login, consent, token exchange, refresh, revocation

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