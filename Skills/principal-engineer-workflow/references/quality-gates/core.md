# Mandatory Quality Gates

Use this policy after completing a coherent development change. It defines the
shared enforcement order and routes to only the baselines relevant to the
technologies affected by the change.

## Load Applicable Baselines

Always read this file, then read each reference whose scope was affected:

- [Python](./python.md) for Python source, tests, or Python tool configuration.
- [PowerShell](./powershell.md) for `.ps1`, `.psm1`, or `.psd1` files.
- [JavaScript and TypeScript](./javascript-typescript.md) for JavaScript,
  TypeScript, frontend, Electron, or Node changes.
- [Shell and Rust](./shell-rust.md) for shell scripts or Rust code.
- [Infrastructure](./infrastructure.md) for markup, configuration, containers,
  workflows, migrations, or service configuration.
- [Security](./security.md) when the canonical gate includes security checks or
  the change affects a security-sensitive boundary described there.

Read multiple references for cross-technology changes. Do not read unrelated
technology references merely because they exist.

## Enforcement Order

1. Detect every affected technology from the edited files and the repository's
   manifests, configuration, and documented development commands.
2. Inspect the repository's canonical quality-gate command before running it and
   map its coverage against every applicable mandatory baseline.
3. Run every applicable mandatory check that the canonical gate omits. If the
   repository has no canonical gate, run the complete mandatory baseline directly.
4. After the omitted mandatory checks are green, run the repository-native
   quality gate as the expensive final integrated verdict. Normally run it once.
5. During implementation, iterate with the narrowest relevant analyzer, focused
   test, or build slice. Do not repeatedly invoke the full native gate for
   feedback that a faster scoped check can provide.
6. If the native gate fails, use focused checks while fixing the cause. Re-run the
   native gate only after a relevant code, test, configuration, or generated
   artifact change makes a different verdict plausible. Never repeat an unchanged
   expensive gate merely to see whether it passes this time.
7. Run focused behavioral tests earlier when they shorten the feedback loop, but
   still complete this ordered gate sequence before declaring the work done.

## Verdict Integrity

- A mandatory check is satisfied only when it runs successfully against the
  intended project root and relevant source set. An absent configuration, empty
  collection, or wrong environment is not success.
- Prefer project-local environments and pinned commands such as Poetry, a virtual
  environment, npm scripts, or Cargo.
- Never install or upgrade tools, modify lockfiles, or make persistent environment
  changes without user authorization.
- If a mandatory tool is unavailable, try an existing repository-provided
  equivalent entrypoint. If none exists, report verification as incomplete and
  request permission before installing it.
- Apply tools only to supported file types. Prettier and MarkdownLint can validate
  supported files around Python code, but never Python source. Never run
  MarkdownLint on `.py` files.
- Do not suppress diagnostics, weaken rules, add blanket exclusions, or add ignore
  annotations merely to make a gate pass. Fix change-caused findings at their
  root and report unrelated pre-existing findings separately.
- Re-run a failed check after an organic fix. Stop after the complete applicable
  baseline is green or a concrete blocker is established.

## Output Discipline

- Use compact, quiet, or summary output modes when they preserve the complete
  verdict and actionable failure evidence.
- Report successful checks as short command-and-result summaries. Do not paste
  repetitive success logs into the conversation.
- On failure, retain the exact command, exit code, affected locations, and
  actionable diagnostics. Collapse duplicate findings reported by multiple tools
  while preserving which tools failed.
- For large logs, keep the full output in an existing repository-supported
  artifact or bounded tool result and summarize the relevant sections. Do not hide
  a failure through truncation.
- Security scanners may produce structured reports; summarize the blocking
  findings and reference the artifact instead of reproducing the entire report.

## Completion Report

Report the canonical gate and individual mandatory checks that ran, their
results, and any checks that could not run. Separate focused behavioral evidence
from static analysis, tests, builds, and security gates. Do not call the change
fully verified while an applicable mandatory check is missing or failing.
