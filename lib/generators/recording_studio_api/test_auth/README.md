The optional API test-token page was installed for <%= name %>.

- The token controls are rendered on a standalone page, never inside the Scalar documentation.
- The page and its create/revoke actions are available only when `Rails.env.local?` is true by default.
- Requests fail closed with `404` when disabled, `401` without an actor, and `403` without manageable API access.
- Generated credentials are real, scoped credentials and are audited normally.
- Issuing a replacement credential revokes the prior session credential.
- Customize `scalar_test_auth_enabled?` and `scalar_test_auth_actor` in the generated concern when the host application uses different environment or authentication policies.
- Never link to or enable test credential issuance publicly.
- Run the generator with the same NAME, `--mount-path`, `--controller`, and `--api-surface` using `--revoke` to remove it.