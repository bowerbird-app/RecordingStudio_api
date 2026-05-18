RecordingStudioApi install complete.

Next steps:

1. Review config/initializers/recording_studio_api.rb and set any required options.
2. If you use environment-specific settings, create config/recording_studio_api.yml.
3. Ensure the host app already loads the shared `flat_pack` gem and styles used by the engine views.
4. Install the engine migrations with `bin/rails generate recording_studio_api:migrations`.
5. Apply the migrations with `bin/rails db:migrate`.
6. Run `bin/rails tailwindcss:build` if you use Tailwind CSS.
7. Mount routes are added at the configured mount path. Adjust auth, layout, and current actor integration to match your host app.
