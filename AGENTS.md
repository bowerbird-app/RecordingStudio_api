# AGENTS.md

## Cursor Cloud specific instructions

This is a mountable Rails 8.1 engine (`recording_studio_api`). The product is exercised through the
dummy host app at `test/dummy` (Puma on port 3000). Ruby is **3.3.6** managed by **rbenv**
(`rbenv init` is in `~/.bashrc`, so interactive shells have `ruby`/`gem`/`bundle`; for
non-interactive contexts use the shims at `~/.rbenv/shims/`). Bundler is pinned to **4.0.0**.

### Start PostgreSQL before anything (it does NOT auto-start on VM boot)

Tests and the app need PostgreSQL 16 running on `127.0.0.1:5432` (role `postgres` / password `postgres`).
The snapshot keeps the cluster's data (databases + seed data persist) but the server process is not
started automatically. Start it once per session:

```bash
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf" -l /tmp/pg.log start
```

`pg_isready -h 127.0.0.1 -U postgres` should then succeed. Redis is optional (rate limiting is off
outside `production`), so you normally don't need it.

### Tailwind CSS / dummy app gems must use `vendor/bundle`

The dummy app's Tailwind entry (`test/dummy/app/assets/tailwind/application.css`) scans engine
component sources via `@source` globs under `test/dummy/vendor/bundle/**` and `/usr/local/bundle/**`
(matching GitHub Codespaces). If the dummy app gems are installed only in the rbenv global path,
Tailwind will miss classes such as `lg:grid-cols-3` from FlatPack's grid component and admin pages
will look unstyled (widgets stack one-per-row instead of a 3-column grid).

The startup update script installs dummy-app gems into `vendor/bundle`. After gem or view changes,
rebuild CSS: `cd test/dummy && bundle exec rails tailwindcss:build` (or rely on `bin/dev`'s watcher).

Quick sanity check: `grep -c 'lg\\\\:grid-cols-3' test/dummy/app/assets/builds/tailwind.css` should
be **> 0**.

### Run the app

```bash
cd test/dummy && bin/dev      # Puma on 0.0.0.0:3000 + Tailwind watcher (see Procfile.dev)
```

Seeded dev data (from `db:seed`): admin login `admin@admin.com` / `Password`, plus a demo OAuth
`client_credentials` client whose id/secret/bearer token are printed by the seed. The engine mounts
the API at `/recording_studio_api`; get a token via `POST /recording_studio_api/oauth/token`
(`grant_type=client_credentials`) and call `GET/POST /recording_studio_api/api/v1/...`. The admin
monitoring UI is at `/admin/api`.

### Lint / test / build

- Lint: `bundle exec rubocop` (run from repo root).
- Tests: `bundle exec rake` from the repo root (default task; runs the Minitest suite against the
  `*_test` databases). Single file: `bundle exec rake test TEST=path/to/file_test.rb`.
- Assets: `cd test/dummy && bundle exec rails tailwindcss:build` (only needed if not using `bin/dev`).

### Known caveat: order-dependent test flakiness (not an environment problem)

The suite (~540 tests) has **pre-existing, order-dependent flakiness** — roughly 3-4 failures per
run drawn from a small set (`recording_studio_admin_api_logs_screen_test`, `openapi_document_test`,
`admin_dashboards_controller_test`). The failing set changes with Minitest's random seed and each
affected file passes when run in isolation, because some tests leak global in-memory registration
state (OpenAPI / contribution-contract / admin-API registries). This is unrelated to the environment
(it includes DB-independent pure-Ruby tests) and CI on `main` passes with random ordering. Do not
treat these as environment breakage, and do not "fix" them as part of setup work.

### After pulling new code

If a pull adds migrations, run `cd test/dummy && bundle exec rails db:prepare` (kept out of the
startup update script on purpose). Gem changes are handled by the update script (`bundle install`).
