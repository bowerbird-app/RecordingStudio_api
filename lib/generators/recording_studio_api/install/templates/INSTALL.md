RecordingStudioApi install complete.

Next steps:

1. Review `config/initializers/recording_studio_api.rb` and set any required options.
2. If you use environment-specific settings, create `config/recording_studio_api.yml`.
3. Ensure the host app already loads Recording Studio and the shared `flat_pack` gem used by the engine views.
4. Ensure every `RecordingStudio.configuration.recordable_types` entry declares `recording_studio_recordable(...)` for RecordingStudio 4.2:
  - use `root: true` only for recordables that may be created as root recordings
  - provide `allowed_parent_types` for recordables that may be created under other recordings
  - call `RecordingStudio.enable_capability(:accessible, on: "YourRecordable")` for recordables that can own direct access grants
5. Install the engine migrations with `bin/rails generate recording_studio_api:migrations`.
6. Apply the migrations with `bin/rails db:migrate`.
7. Run `bin/rails flat_pack:prepare_tailwind_assets tailwindcss:build` if you use Tailwind CSS.
   The install generator copies `lib/tasks/flat_pack_tailwind_assets.rake`, which mirrors gem
   Engine trees into `tmp/tailwind_scan` (Tailwind does not follow symlinks) and writes
   `app/assets/tailwind/gem_sources.css` with absolute `@source` fallbacks plus a FlatPack Grid
   utility safelist. Add `tmp/tailwind_scan/` and `app/assets/tailwind/gem_sources.css` to
   `.gitignore`.

8. Provision OAuth2 client credentials from an existing `RecordingStudio::Access` recording, then exchange them for an access token:

   ```ruby
   result = RecordingStudioApi::Services::ProvisionApiClient.call(
     access_recording: access_recording,
     name: "Primary OAuth client"
   )

   client_id = result.value.fetch(:credential).oauth_client_id
   client_secret = result.value.fetch(:token)

   oauth = RecordingStudioApi::Services::IssueOauthAccessToken.call(
     grant_type: "client_credentials",
     client_id: client_id,
     client_secret: client_secret
   )

   oauth.value.fetch(:access_token)
   ```

   For third-party apps, register a `RecordingStudioApi::OauthClient` (not an `ApiClient`) and send
   users to `GET /recording_studio_api/oauth/authorize` (or the named-API authorize URL). Include
   `RecordingStudioApi::OauthAuthorization` in Accessible `access_actor_types`. The same token
   endpoint also accepts `authorization_code` and `refresh_token`. Discovery documents are served
   from `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource`.

9. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
10. Add addon gems that enable Recording Studio capabilities, then register the related API action once with `RecordingStudioApi.register_capability_action`.
11. In each custom capability handler, authorize with the passed `context.access_grant` before exposing or mutating Recording Studio data.
