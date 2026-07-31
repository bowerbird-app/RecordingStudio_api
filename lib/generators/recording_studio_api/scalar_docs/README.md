Scalar documentation was installed for <%= name %>.

- Visit `<%= mount_path %>/<%= default_api_version %>`.
- The generated OpenAPI endpoint is `<%= mount_path %>/<%= default_api_version %>/openapi.json`.
- The versioned page helper is `<%= route_key %>_scalar_docs_version_path`.
- Configure another provider with `--openapi-provider=YourOpenapiProvider`; it must respond to
  `call(version:, mount_path:, api_mount_path:)`.
- The generated templates use only Rails and browser APIs. They do not require FlatPack, Tailwind,
  or the dummy application.
- Implement `authorize_scalar_documentation!` in the generated controller using the host
  application's policy. Leaving the hook unchanged makes this installation deliberately public.
- Use `--scalar-integrity=sha384-...` for a CDN script's SRI hash; this also emits
  `crossorigin="anonymous"`. Integrity defaults are applied only when a verified hash is shipped
  for the exact default Scalar source. A custom `--scalar-source` never inherits a default hash,
  so provide its verified SRI value explicitly. For strict CSP, self-host Scalar or authorize the
  scripts with a nonce or hash. Do not add `unsafe-inline`.
- Revoke removes the marked route block using NAME only. If `--controller` was customized, pass
  the same option again to remove that custom controller and its views.
<% if options[:test_auth] -%>
- Optional local test authentication was also installed. Its generated credentials are real,
  scoped credentials. Review the generated concern and controller before enabling it outside
  local environments.
<% end -%>
