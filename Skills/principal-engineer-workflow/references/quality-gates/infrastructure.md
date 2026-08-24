# Infrastructure and Configuration Quality Gates

Read this reference when a change affects markup, configuration, containers,
workflows, database migrations, or service configuration.

## Mandatory Baselines

Apply each gate whose file type or operational boundary was affected:

- Markdown: MarkdownLint and Prettier check.
- JSON, YAML, TOML, CSS, and supported configuration: Prettier check plus the
  repository's parser or schema validation.
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
