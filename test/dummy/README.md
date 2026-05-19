# Dummy App

This Rails app exists to validate the RecordingStudio API integration surface and docs handoff in a real host application.

## What It Covers

- Devise authentication with a seeded admin user
- `Current.actor` wiring for Recording Studio events
- Root workspace plus seeded folder and page recordables
- FlatPack layout integration and Tailwind source scanning
- Mounted `RecordingStudio::Engine` route behavior inside a host app
- A sidebar menu and companion docs pages for the renamed RecordingStudio API install and configuration flow

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
- `/recording_studio_api` - mounted RecordingStudio API engine prefix; JSON API endpoints (including `/oauth/token`) live under this mount, and no browser root page is shipped
- `/users/sign_in` - Devise sign-in page
- `/docs/install`, `/docs/config`, `/docs/api`, `/docs/api_routes`, `/docs/auth`, `/docs/add_capability`, `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views`, `/docs/methods` - sidebar pages that capture the completed architecture handoff
- `/up` - Rails health check

## Why This App Exists

Use this app to verify the renamed engine integration and OAuth2 API flow in a host app. If a layout, route, asset source, token exchange, or Recording Studio initializer change breaks here, the RecordingStudio API scaffold needs adjustment before deeper feature work.

The authenticated layout in `app/views/layouts/flat_pack_sidebar.html.erb` and sidebar menu in `app/views/layouts/flat_pack/_sidebar.html.erb` now document the RecordingStudio API concepts that were missing from the previous agent's work. Extend them only when the real HTTP surface exists.

Likewise, the home page in `app/views/home/index.html.erb` stays intentionally small. Use the dedicated sidebar pages for deeper install, config, auth, and API route notes.
