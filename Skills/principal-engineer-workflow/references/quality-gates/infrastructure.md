# Infrastructure and Configuration Quality Gates

Read this reference when a change affects markup, configuration, containers,
workflows, database migrations, or service configuration.

## Mandatory Baselines

Apply each gate whose file type or operational boundary was affected:

- Markdown: MarkdownLint and Prettier check.
- JSON, YAML, TOML, and supported configuration: Prettier check plus the
  repository's parser or schema validation.
- CSS: Prettier check, Stylelint when configured, and the production frontend
  build when the stylesheet participates in one.
- HTML: Prettier check plus the repository's HTML validator or production
  build. Run HTMLHint when configured.
- XML: a well-formedness parser plus schema or domain-native validation when
  available. Validate service or virtualization XML without applying it live.
- Windows batch (`.cmd` and `.bat`): use the repository test harness or a safe
  no-op, help, or test entrypoint through `cmd /d /c`. `cmd.exe` parses while
  executing, so there is no reliable parse-only guarantee. Never execute an
  operational or destructive batch file merely to syntax-check it; report the
  direct-verification gap when no safe path exists.
- Dockerfiles: Hadolint and a Docker build for the affected image.
- Docker Compose: configuration rendering or validation and the relevant smoke
  test when safe.
- GitHub Actions: actionlint plus repository-specific workflow integrity checks.
- Database migrations: apply migrations in a disposable test environment and
  run the repository's drift or consistency check.
- systemd, nginx, nftables, or service configuration: use the native syntax or
  validation command in a safe environment.

Do not reload live services, apply production migrations, deploy, or mutate live
infrastructure without explicit authorization.
