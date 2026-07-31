Test authentication was installed for <%= name %>.

- The helper is available only when `Rails.env.local?` is true by default.
- Generated credentials are real, scoped credentials and are audited normally.
- Issuing a replacement credential revokes the prior session credential.
- Customize `scalar_test_auth_enabled?` and `scalar_test_auth_actor` in the generated concern when the host application uses different environment or authentication policies.
- Keep the generated create and revoke actions protected. Never expose test credential issuance publicly.
- Run the generator with the same NAME, `--mount-path`, `--controller`, and `--api-surface` using `--revoke` to remove it.