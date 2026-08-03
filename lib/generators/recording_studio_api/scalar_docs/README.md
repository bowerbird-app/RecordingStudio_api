Scalar documentation routes and configuration were installed.

- The gem owns the controller and default views, so upgrades apply automatically.
- Documentation access defaults to `authenticated`; use `--access=public` only intentionally.
- Replace the generated access symbol with a callable policy for private API authorization.
- The embedded page uses the API-specific layout override or
  `RecordingStudioApi.configuration.layout_name`.
- Revoke removes only the managed route block and initializer. Legacy customized controller or
  view files are reported but never deleted automatically.
