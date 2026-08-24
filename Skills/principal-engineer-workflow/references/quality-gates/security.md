# Security Quality Gates

Read this reference when the canonical repository gate includes security checks
or a change affects dependencies, authentication, authorization, secrets,
untrusted input, network boundaries, command execution, persistence, or
deployment.

## Mandatory Baseline

Run every applicable repository-configured scanner and native security check.
Preserve configured severity thresholds, exclusions, and blocking behavior.

If a security-sensitive change has no applicable configured scanner or native
security check, security verification starts incomplete. Select every fallback
below that applies to the changed boundary. Use an already available
project-local tool when possible, and ask before installing anything.

The fallback satisfies this security gate only when every applicable fallback
runs successfully and adequately covers the changed boundary. If a required
fallback is unavailable, fails, or cannot provide that coverage, verification
remains incomplete and the change must not be reported as fully verified.

- Python: Bandit; add pip-audit or the repository dependency audit when Python
  dependencies or lockfiles changed.
- JavaScript or TypeScript: the package-manager-native npm, pnpm, or Yarn audit
  when dependencies or lockfiles changed.
- Rust: `cargo audit` when available or configured. If it is missing, report
  the gap and ask before installation.
- Containers: Trivy image, filesystem, or secret scanning as appropriate to
  the changed boundary.
- Secret-bearing source or configuration: detect-secrets or Gitleaks.
- Cross-language rules: Semgrep when repository configuration exists or the
  user authorizes it as the fallback.

Do not substitute an unrelated scanner merely to produce a green result. A
missing fallback tool is incomplete or blocked, not `N/A`. Report which
fallbacks satisfied the gate and why they were applicable.

Do not make a previously blocking security verdict advisory. Do not change a
dependency or lockfile solely to silence an audit without validating compatibility
and receiving any authorization required for that scope expansion.

This is a post-implementation gate, not a replacement for the dedicated
security workflow required by an explicitly security-focused assessment.
