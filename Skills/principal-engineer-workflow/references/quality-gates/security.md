# Security Quality Gates

Read this reference when the canonical repository gate includes security checks
or a change affects dependencies, authentication, authorization, secrets,
untrusted input, network boundaries, command execution, persistence, or
deployment.

## Mandatory Baseline

Run the applicable repository-configured scanners:

- Bandit for Python security analysis.
- detect-secrets or Gitleaks for secret detection.
- npm audit or the repository's JavaScript dependency audit.
- pip-audit or the repository's Python dependency audit.
- Semgrep and Trivy when configured.

Run other repository-native security checks in scope. Preserve their configured
severity threshold and blocking behavior.

Do not make a previously blocking security verdict advisory. Do not change a
dependency or lockfile solely to silence an audit without validating compatibility
and receiving any authorization required for that scope expansion.
