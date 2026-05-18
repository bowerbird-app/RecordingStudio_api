RecordingStudioApi install complete.

Next steps:

1. Review `config/initializers/recording_studio_api.rb` and set any required options.
2. If you use environment-specific settings, create `config/recording_studio_api.yml`.
3. Ensure the host app already loads Recording Studio and the shared `flat_pack` gem used by the engine views.
4. Install the engine migrations with `bin/rails generate recording_studio_api:migrations`.
5. Apply the migrations with `bin/rails db:migrate`.
6. Run `bin/rails tailwindcss:build` if you use Tailwind CSS.
7. Provision bearer credentials from an existing `RecordingStudio::Access` recording:

   ```ruby
   result = RecordingStudioApi::Services::ProvisionApiClient.call(
     access_recording: access_recording,
     name: "Primary API token"
   )

   result.value.fetch(:token)
   ```

8. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
9. Add addon gems that enable Recording Studio capabilities, then register the related API action once with `RecordingStudioApi.register_capability_action`.
