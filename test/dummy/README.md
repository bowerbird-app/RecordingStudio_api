# Dummy App

This Rails app exists to validate the RecordingStudio API integration surface and docs handoff in a real host application.

## What It Covers

- Devise authentication with a seeded admin user
- `Current.actor` wiring for Recording Studio events
- A dedicated admin root rendered through the host app root page
- `RecordingStudioRootSwitchable` mounted root chooser for switching between admin and standard roots
- RecordingStudio 4.2 hierarchy declarations for root-capable `Workspace`/`Folder`, child-only `Page`, API-owned recordables, and accessible parent grants
- `RecordingStudio::UsesDefaultLayout` from the Recording Studio gem (rounded theme on `html` / `body`; no vendored layout copy)
- Root workspace plus seeded folder and page recordables
- FlatPack layout integration and Tailwind source scanning
- Mounted `RecordingStudio::Engine` route behavior inside a host app
- Mounted `RecordingStudioAccessible` and `RecordingStudioRootSwitchable` engines
- Companion docs pages with in-page documentation links (install, config, Scalar, auth) for the renamed RecordingStudio API install and configuration flow
- API credential authentication that resolves a `RecordingStudioApi::AccessGrant`
- Delegated OAuth consent (`/recording_studio_api/oauth/authorize`) and a dummy connected-apps list; Accessible 0.8 dependent grants (`depends_on_recording_id`) cap each connect by the manager Access recording
- Capability-owned authorization examples that use the access grant with Recording Studio Accessible

## Quick Start

```bash
cd test/dummy
bundle install
bin/rails db:setup
bin/dev
```

Run the commands above from the dummy app directory, not the repository root.

Then open the app and sign in with:

- Email: `admin@admin.com`
- Password: `Password`

## Useful Routes

- `/` - dummy app home page and RecordingStudio API design guidance
- `/recording_studio` - redirects to `/` while the mounted Recording Studio engine stays available under that prefix for non-root routes
- `/recording_studio_accessible` - mounted shared access-management engine used by the admin experience
- `/recording_studio_root_switchable/v1/root_switch?scope=all_roots` - root switcher used by the top-nav root switch button
- `/connected_apps` - dummy list of apps the signed-in user has connected, with remove access
- `/recording_studio_api` - mounted RecordingStudio API engine prefix; JSON API endpoints (including `/oauth/token` and `/oauth/authorize`) live under this mount, and no browser root page is shipped
- `/users/sign_in` - Devise sign-in page
- `/docs/install`, `/docs/config`, `/docs/api_routes`, `/docs/scalar`, `/docs/auth`, `/docs/add_capability`, `/docs/methods`, `/docs/api_hierarchy`, `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views` - documentation pages that capture the completed architecture handoff
- `/up` - Rails health check

## Relationship Expansion Demo

The seeded `Studio Workspace` has direct Folder and Page children. After obtaining a bearer token, use its recording ID to compare these API responses:

- `GET /recording_studio_api/api/v1/workspaces/:id` includes `folders` automatically
- `GET /recording_studio_api/api/v1/workspaces/:id?include=pages` adds the request-selected `pages`
- `GET /recording_studio_api/api/v1/workspaces/:id?include=featured_folder` adds the request-selected custom `featured_folder`
- `GET /recording_studio_api/api/v1/workspaces/:id?include=pages,featured_folder` adds both request-selected relationships
- `GET /recording_studio_api/api/v1/workspaces/:id/folders` lists the direct Folder children
- `GET /recording_studio_api/api/v1/workspaces/:id/pages` lists the direct Page children

The custom `featured_folder` relationship is embed-only; it intentionally has no nested relationship route.

## Why This App Exists

Use this app to verify the renamed engine integration, the admin-root flow, the API-key OAuth2 client credentials flow, and delegated OAuth consent in a host app. If a layout, route, asset source, token exchange, access-grant dispatch, root switch, or Recording Studio initializer change breaks here, the RecordingStudio API scaffold needs adjustment before deeper feature work.

Authenticated pages include `RecordingStudio::UsesDefaultLayout` and render the gem's `recording_studio/default_layout` (theme `rounded` on `body`; dummy also stamps `data-theme="rounded"` on `html`). API-key, consent, and connected-apps screens do not render the root-switch dropdown in the page-nav slot. Consent and connected apps sit in the first cell of a two-column Flatpack Grid. Consent is a connect screen: title `Connect {app}`; one workspace is Continue / Cancel only; several workspaces use a Flatpack Select, with permission only when more than View is available (default View), and stacked Continue / Cancel. Connected apps uses a Flatpack List inside a Card. The home page in `app/views/home/standard_root.html.erb` stays intentionally small and links into this gem's API key screens and connected apps. Seeds include a second workspace, a public OAuth app (`rsapi_oc_seed_demo_app`), and one connect. Use the dedicated docs pages for deeper install, config, auth, and API route notes.
