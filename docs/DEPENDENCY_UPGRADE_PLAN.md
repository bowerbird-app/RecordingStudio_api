# Dependency upgrade plan

Snapshot date: **18 August 2026**.

> Status: Phase 1–3 compatible bumps are implemented on
> `cursor/update-compatible-gems-dbac` (gem `0.5.0`). Studio **4.0.0** remains
> deferred until sibling gemspecs allow it.

This is a review plan, not an executed upgrade. It inventories every gem declared by
`recording_studio_api` and the dummy app, compares them with the latest published
versions, and recommends a phased update order.

Do not treat `UPDATE_SUMMARY.md` as current; that file is an archival snapshot from
February 2026.

## Recheck verdict (17 Aug 2026)

**RecordingStudio v4.0.0 is now a published GitHub Release**
([release](https://github.com/bowerbird-app/RecordingStudio/releases/tag/v4.0.0),
published 17 Aug 2026). It is still **not installable** in this repo: Accessible,
Moveable, Admin, and Root Switchable gemspecs all require `recording_studio ~> 3.0`.

Sibling upgrade work is converging on the **3.0.3** stack, not 4.0:

| Sibling | Open work | Studio pin |
| --- | --- | --- |
| Accessible | PR [#12](https://github.com/bowerbird-app/RecordingStudio_accessible/pull/12) → `0.5.1` | Explicitly stays on **v3.0.3**; defers 4.0 |
| Moveable | PR [#11](https://github.com/bowerbird-app/RecordingStudio_moveable/pull/11) → `2.1.2` | Stays on **v3.0.3**; Accessible only to **0.3.2** (conservative) |
| Root Switchable | main already **0.3.5**; Dependabot PRs for Rails/Puma/etc. | Still `recording_studio ~> 3.0` |
| Admin | no open upgrade PR | Gemfile still on Studio **v3.0.2** / Accessible **0.3.2** |

**Take now:** Studio **v3.0.3** + Accessible **v0.5.0** (or wait for 0.5.1) + Admin
**1.2.0** + Moveable **2.1.1** (or 2.1.2 when merged) + Root Switchable **v0.3.5** +
FlatPack **v0.1.129** + Rails **8.1.3.1**.

**Still blocked:** Studio **4.0.0**, Pagy **43**, FlatPack-driven ViewComponent majors
(none), dummy `image_processing` **2.x** (optional).

## How dependencies are split

There are three layers. They must stay in sync where they overlap.

| Layer | File | Purpose |
| --- | --- | --- |
| Runtime (hosts) | `recording_studio_api.gemspec` | Constraints hosts inherit: Rails, RecordingStudio, Accessible, Redis |
| Gem development | `Gemfile` + `Gemfile.lock` | Dummy-adjacent GitHub pins, plus RuboCop / SimpleCov / Puma used from the gem root |
| Dummy host | `test/dummy/Gemfile` + `test/dummy/Gemfile.lock` | Full Rails 8.1 host: Solid adapters, Tailwind, Kamal, Brakeman, image processing |

GitHub-sourced Recording Studio / FlatPack gems are declared in **both** Gemfiles today.
Those two files have already drifted (see lockfile drift below). Any upgrade should
change both Gemfiles and regenerate both lockfiles in the same PR.

Ruby is `3.3.6` (`.ruby-version`). Latest 3.3 patch is `3.3.12`. That is optional and
independent of gem updates. Bundler is `4.0.0` in both lockfiles.

## Current vs latest

### Runtime (gemspec)

| Gem | Constraint | Locked | Latest | Action |
| --- | --- | --- | --- | --- |
| `rails` | `~> 8.1.0` | 8.1.3 | **8.1.3.1** | Take the patch. Constraint already allows it. |
| `recording_studio` | `~> 3.0` | tag `v3.0.2` resolving as **3.0.1** at SHA `3369c49` | **4.0.0 released**; latest compatible **v3.0.3** | Phase 1: `v3.0.3`. Phase 4 (blocked): `v4.0.0`. |
| `recording_studio_accessible` | `~> 0.3` | branch `copilot/upgrade-recordingstudio-3-0-0` at **0.3.1** | **v0.5.0** (0.5.1 pending in Accessible PR #12) | Leave the stale copilot branch. Pin `tag: "v0.5.0"` (or `0.5.1` once tagged). Dummy config required. |
| `redis` | `~> 5.3` | 5.4.1 | **6.0.0** | Widen the gemspec (`>= 5.3`, `< 7` or `~> 6.0`) then bump. This gem only uses INCR/TTL/EXPIRE/EVAL/GET/SET/DEL. |

Note: `~> 0.3` already allows Accessible 0.4/0.5 (`>= 0.3`, `< 1.0`). Bundler is not
the reason Moveable's PR stays on 0.3.2 — that is a behavioral / coordination choice
(`access_actor_types` fail-closed in 0.5.0).

### GitHub ecosystem gems (both Gemfiles)

These are not on RubyGems. Pin by **tag**, not by copilot branch or raw SHA, unless a
tag does not exist.

| Gem | Current pin | Locked version | Latest | Action |
| --- | --- | --- | --- | --- |
| `recording_studio` | `tag: "v3.0.2"` | 3.0.1 (stale SHA vs current `v3.0.2`) | **4.0.0 released**; compatible target **v3.0.3** | Pin `v3.0.3` now. 4.0 waits on sibling gemspecs. |
| `recording_studio_accessible` | **branch** `copilot/upgrade-recordingstudio-3-0-0` | 0.3.1 | **v0.5.0** (+ 0.5.1 in flight) | Highest-risk compatible bump. Breaking actor-type default. |
| `recording_studio_admin` | `tag: "1.1.0"` | 1.1.0 | **1.2.0** | Additive (widget info tooltips). Safe with Accessible 0.5 (`~> 0.3` still). |
| `recording_studio_icons` | unpinned GitHub HEAD | 0.1.0 @ `7c32c08` | same SHA, no tags | Already latest. Optionally add a tag pin once Icons ships one. |
| `recording_studio_moveable` | **branch** `copilot/update-access-api-in-moveable` | **0.1.0** | **2.1.1** (2.1.2 pending in Moveable PR #11) | Largest dummy-app jump. The copilot branch is obsolete. |
| `recording_studio_root_switchable` | SHA `e684aa3` (commented 0.3.0) | 0.3.0 | **v0.3.5** tag; GitHub *Release* list still tops at v0.3.1 | Pin `tag: "v0.3.5"`. Includes security cookie/redirect changes. |
| `flat_pack` | `tag: "v0.1.124"` | 0.1.124 | **v0.1.129** | Patch-level UI gem. Admin still requires `~> 0.1.124`, which allows 0.1.129. |

`flat_pack` 0.1.129 still depends on `pagy ~> 9.0` and `view_component ~> 4.12.0`.
Pagy 43 exists on RubyGems but **cannot** be taken until FlatPack loosens that constraint.
`view_component` is already on latest 4.12.0.

### Root Gemfile (development)

| Gem | Locked | Latest | Notes |
| --- | --- | --- | --- |
| `devise` | 5.0.1 | **5.0.4** | Patch. Dummy uses Devise heavily. |
| `pg` | 1.6.3 | 1.6.3 | Current. Dummy lock is behind at **1.6.2**. |
| `puma` | 7.1.0 | **8.0.2** | Major. Dummy-only impact (default IPv6 bind). |
| `sprockets-rails` | 3.5.2 | 3.5.2 | Current. Dummy uses Propshaft, not Sprockets. |
| `importmap-rails` | 2.2.3 | 2.2.3 | Current. |
| `turbo-rails` | 2.0.23 | 2.0.23 | Current. Dummy lock is behind at **2.0.20**. |
| `debug` | 1.11.0 | **1.11.1** | Patch. |
| `simplecov` | 0.22.0 | **1.1.1** | Major. Test helper already filters `/test/`. |
| `rubocop` | 1.81.7 | **1.89.0** | Expect new cops / todo churn. |
| `rubocop-rails` | 2.34.2 | **2.37.0** | Pair with RuboCop 1.89. |

### Dummy-only gems

| Gem | Constraint / locked | Latest | Notes |
| --- | --- | --- | --- |
| `rails` | `~> 8.1.1` / 8.1.3 | **8.1.3.1** | Same patch as the gem. |
| `propshaft` | 1.3.1 | **1.3.2** | Patch. |
| `stimulus-rails` | 1.3.4 | 1.3.4 | Current. |
| `jbuilder` | 2.14.1 | **2.15.1** | Minor. |
| `tailwindcss-rails` | 4.6.0 | 4.6.0 | Current (`tailwindcss-ruby` 4.3.3). |
| `solid_cache` | 1.0.10 | 1.0.10 | Current. |
| `solid_queue` | 1.2.4 | **1.6.0** | Fiber execution is opt-in. Check for schema/update task. |
| `solid_cable` | 3.0.12 | **4.0.2** | Major, but mainly Ruby 3.3+ and connection retries. Dummy is already on 3.3. |
| `bootsnap` | 1.19.0 | **1.25.0** | Patch/minor. |
| `kamal` | 2.9.0 | **2.12.0** | Dummy deploy tooling only. |
| `thruster` | 0.1.16 | **0.1.25** | Dummy deploy tooling only. |
| `image_processing` | `~> 1.2` / 1.14.0 | **2.0.3** | Dummy does not use Active Storage variants. Constraint **blocks** 2.x. Prefer stay on 1.14 unless variants are added. |
| `bundler-audit` | 0.9.3 | 0.9.3 | Current. |
| `brakeman` | 7.1.1 | **8.0.6** | Major scanner release. Re-baseline ignores if needed. |
| `rubocop-rails-omakase` | 1.1.0 | 1.1.0 | Current. Will pull newer RuboCop transitively. |
| `web-console` | 4.2.1 | **4.3.0** | Dev-only. |
| `puma` | `>= 5.0` / 7.1.0 | **8.0.2** | Dummy `config/puma.rb` uses `port`, not an explicit bind. |

## Lockfile drift to fix regardless of versions

Root and dummy locks are already inconsistent for the same public gems:

| Gem | Root lock | Dummy lock |
| --- | --- | --- |
| `pg` | 1.6.3 | 1.6.2 |
| `turbo-rails` | 2.0.23 | 2.0.20 |

The RecordingStudio Git pin is also inconsistent with GitHub: both lockfiles claim
`tag: "v3.0.2"` but resolve SHA `3369c49` / gem version **3.0.1**. The current
`v3.0.2` tag is SHA `bcf8e12` and version 3.0.2. Re-pinning to `v3.0.3` (SHA
`8db9ca7`) clears that.

## Blocker: RecordingStudio 4.0.0

`recording_studio` **4.0.0** now has a published GitHub Release (17 Aug 2026). It is
**still not installable** with current sibling gems:

- Accessible 0.5.0 / pending 0.5.1 still have `recording_studio ~> 3.0`
- Admin 1.2.0 still has `recording_studio_accessible ~> 0.3` (fine) but Accessible
  cannot resolve Studio 4
- Moveable 2.1.1 / pending 2.1.2 have `recording_studio ~> 3.0`
- Root Switchable 0.3.5 has `recording_studio ~> 3.0`

Bundler will not resolve Studio 4.0 against those gemspecs. Sibling upgrade PRs
explicitly stay on **v3.0.3** for the same reason.

Studio 4.0 breaking changes that will matter here once unblocked:

- `Recording` loses newest-first `default_scope`; use `.recent` or explicit `order:`
- `RecordingStudio::Event` is append-only (AR update/destroy raise)
- Relation/Arel/proc recordable query escape hatches need an opt-in flag
- New unique root index + harden migration
- Optional `require_actor` / `authorize_write` / `max_metadata_bytes`

This gem does not call `recordings_query` with unsafe scopes. It does use
`Recording.where(...)` in tests, docs helpers, and backfill migrations. Those calls
do not rely on implicit order today, but collection endpoints and admin queries
should be re-checked when 4.0 lands.

**Do not attempt Studio 4.0 in the first upgrade PR.** Track it as a follow-up once
Accessible (at least) publishes a `~> 4.0` or `>= 4.0` constraint, then Moveable /
Root Switchable / this gemspec follow.

## Recommended phases

### Phase 1 — GitHub ecosystem onto current 3.x-compatible tags

Highest value, highest behavioral risk. One PR, both Gemfiles, both lockfiles.

Target pins (17 Aug recheck):

```ruby
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v3.0.3"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.5.0"
# prefer tag "0.5.1" once Accessible PR #12 merges and tags
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "1.2.0"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons" # still untagged
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "2.1.1"
# prefer tag "2.1.2" once Moveable PR #11 merges and tags
gem "recording_studio_root_switchable", github: "bowerbird-app/RecordingStudio_root_switchable", tag: "v0.3.5"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.129"
```

Gemspec: keep `recording_studio ~> 3.0`. Leave `recording_studio_accessible ~> 0.3`
unless this gem starts depending on 0.4/0.5-only APIs (`authorized_through?`,
`access_actor_types`). Hosts on Accessible 0.3.x would then need a matching bump.

Conservative alternative if Accessible 0.5 risk is too high for one PR: pin Accessible
`0.3.2` first (matches Moveable PR #11), then follow with 0.5.x + `access_actor_types`
in a second PR. Prefer going straight to 0.5.x here so we leave the stale copilot
branch and pick up hierarchy / integrity fixes.

Dummy / test changes required for Accessible 0.5.0:

1. Add `test/dummy/config/initializers/recording_studio_accessible.rb` (or extend an
   existing initializer) with an explicit actor allowlist, for example
   `config.access_actor_types = ["User"]`. Blank/`nil` now **rejects every new grant**.
2. Remove `include RecordingStudioAccessible::AllowsAccessibleChildren` and
   `recording_studio_accessible_children :access` from `AdminRoot` and `AdminSection`.
   That API was removed after 0.3.1 in favor of
   `RecordingStudio.enable_capability(:accessible, on: ...)`, which the dummy
   initializer already does for Workspace/Folder/Page/AdminRoot.
3. Confirm `AdminSection` still gets `:accessible` if access children hang off it.
4. Run `bin/rails recording_studio_accessible:access_grants:integrity` against the
   dummy DB after migrate.
5. Re-run seeds; `grant_access` in `test/dummy/db/seeds.rb` and gem tests will fail
   closed without (1).

Moveable 0.1.0 → 2.1.1:

- 2.0.0 already required Studio 3 / Accessible 0.3 (dummy is conceptually there).
- 2.1.0 adds optional `RecordingStudio::Moveable::API` action registration for this
  gem. Decide whether the dummy should enable that action on public/operations APIs
  (Moveable's own dummy does). Not required to boot, but worth a conscious choice.
- Dummy already `enable_capability(:movable, on: "Folder")`.

Root Switchable 0.3.0 → 0.3.5:

- 0.3.2 security defaults: httponly cookies, sanitized `return_to`, anonymous
  selections off, switch rate limiting, cascade-delete selections.
- Dummy initializer already customizes `after_switch_redirect`. Re-read that callback
  against the new sanitization so it does not double-parse or fight the gem.
- 0.3.4/0.3.5 UI copy avoids the word "root" in user-facing labels (`Switch`).
- Importmap must pick up the new Stimulus controller
  `recording-studio-root-switchable--root-switch-dropdown`.

Studio v3.0.3 is a version/docs bump over 3.0.2, not a behavior release. Still
regenerate dummy migrations if the install generator copies anything new.

FlatPack 0.1.129 is UI (notifications, focus rings). Rebuild dummy Tailwind and
screenshot admin + Scalar + root switcher.

### Phase 2 — Runtime public gems

Same PR as Phase 1 if resolution is clean; otherwise a fast follow.

- `bundle update rails` → 8.1.3.1 in both locks.
- Change gemspec Redis from `~> 5.3` to `~> 6.0` (or `>= 5.3, < 7` if hosts should
  stay on 5.x). This gem's Lua INCR/EXPIRE script and idempotency GET/SET should be
  drop-in under RESP3. Rate-limit tests stub Redis; add one live ping test if Redis
  is available in CI.
- `devise` 5.0.4.

If the gemspec Redis constraint changes, bump `RecordingStudioApi::VERSION` once on
the implementation branch (currently `0.4.0` → `0.5.0`) and add `CHANGELOG.md` /
`UPGRADING.md` notes for hosts.

### Phase 3 — Dummy and development tooling

Lower product risk. Can be a second PR.

Take now:

- `propshaft` 1.3.2, `jbuilder` 2.15.1, `bootsnap` 1.25.0, `debug` 1.11.1
- `web-console` 4.3.0, `kamal` 2.12.0, `thruster` 0.1.25
- `solid_queue` 1.6.0 (fiber mode opt-in; keep thread workers unless we want it)
- `solid_cable` 4.0.2
- `brakeman` 8.0.6
- Align dummy `pg` / `turbo-rails` with the root lock

Take with eyes open:

- **Puma 8.0.2** — default production bind becomes IPv6 `::` when a non-loopback IPv6
  interface exists. Dummy `config/puma.rb` only sets `port`. For Codespaces / Docker
  IPv4-only, set `port ENV.fetch("PORT", 3000), "0.0.0.0"` if bind fails.
- **SimpleCov 1.1.1** — 1.0 filters `test/` by default; this repo already does.
  Coverage percentage may move. `simplecov-html` is vendored into 1.x; no Gemfile
  change beyond the gem itself.
- **RuboCop 1.89 + rubocop-rails 2.37** — regenerate `.rubocop_todo.yml` rather than
  hand-fighting new cops in the same PR as behavioral gem bumps if the diff explodes.

Defer:

- **image_processing 2.x** — constraint `~> 1.2` is intentional for a host that does
  not process variants. 2.0 makes `mini_magick` / `ruby-vips` soft dependencies.
  Leave at 1.14.0 unless Active Storage variants are introduced.
- **pagy 43** — blocked by FlatPack `pagy ~> 9.0`.
- **Ruby 3.3.12** — optional patch; not required for these gems.

### Phase 4 — RecordingStudio 4.0.0 (blocked until siblings move)

When Accessible, Moveable, Admin, and Root Switchable publish Studio 4-compatible
releases:

1. Pin `recording_studio` to `tag: "v4.0.0"`.
2. Widen this gemspec to `recording_studio ~> 4.0` (breaking for hosts on 3.x).
3. Run `rails g recording_studio:migrations` and migrate the dummy (unique root
   index / harden constraints).
4. Audit `Recording` queries for implicit order; add `.recent` where newest-first
   is required.
5. Confirm no code path updates/destroys `RecordingStudio::Event` via ActiveRecord
   (backfills already use `delete_all`).
6. Consider `config.require_actor = true` in the dummy.

## Suggested implementation order inside Phase 1

1. Replace copilot branches and the Root Switchable SHA with tags (Gemfiles only).
2. `bundle update` at repo root **and** in `test/dummy`.
3. Fix dummy Accessible config / remove `AllowsAccessibleChildren`.
4. `cd test/dummy && bundle exec rails db:prepare` (and seeds).
5. `bundle exec rubocop` then `bundle exec rake app:test`.
6. Boot dummy (`bin/dev`), confirm CSS (Tailwind rebuild), screenshot:
   sign-in, home, root switcher, admin API screens, Scalar docs.
7. Update README Tech Stack pins, `CHANGELOG.md`, `UPGRADING.md` if gemspec
   constraints or host setup steps change.

## Verification checklist

- Both lockfiles resolve the same GitHub SHAs for Studio / Accessible / Admin /
  Moveable / Root Switchable / FlatPack / Icons
- Dummy boots; seeds grant User access without Accessible 0.5 fail-closed errors
- Rate limit + idempotency tests still pass (Redis 5 or 6)
- Moveable capability on Folder still works in the dummy tree
- Root switcher label updates without a full page reload (0.3.5 Stimulus)
- CI `.github/workflows/ci.yml` still installs dummy then `rake app:test`

## Out of scope for the first upgrade PR

- RecordingStudio 4.0.0 (released, but sibling gemspecs still `~> 3.0`)
- Pagy 43 / ViewComponent major (none available)
- Publishing this gem to RubyGems
- Replacing GitHub source gems with RubyGems.org (they are still GitHub-only)
- Dummy `image_processing` 2.x
