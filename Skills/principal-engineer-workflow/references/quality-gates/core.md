# Mandatory Quality Gates

Use this policy while planning and verifying a development change. Map the
gates before editing, then enforce them after a coherent change batch. The
applicable technology baselines are the invariant minimum; risk determines
additional evidence beyond that floor.

## Load Applicable Baselines

Always read this file, then read each reference whose scope was affected:

- [Python](./python.md) for Python source, tests, or Python tool configuration.
- [PowerShell](./powershell.md) for `.ps1`, `.psm1`, or `.psd1` files.
- [JavaScript and TypeScript](./javascript-typescript.md) for JavaScript,
  TypeScript, frontend, Electron, or Node changes.
- [Shell and Rust](./shell-rust.md) for shell scripts or Rust code.
- [Infrastructure](./infrastructure.md) for markup, configuration, containers,
  Windows batch files, workflows, migrations, or service configuration.
- [Security](./security.md) when the canonical gate includes security checks or
  the change affects a security-sensitive boundary described there.

Read multiple references for cross-technology changes. Do not read unrelated
technology references merely because they exist.

The [behavior scenarios](./scenarios.md) are maintenance acceptance criteria
for this skill. Read them when reviewing or changing the quality-gate policy,
not during ordinary implementation work.

## Plan Before Editing

For every implementation request:

1. Detect affected technologies from the expected files, manifests,
   configuration, and documented development commands.
2. Inspect the canonical repository gate. Map which mandatory checks it covers
   and whether it can autofix, generate files, install or upgrade tools, modify
   dependencies or lockfiles, access the network, migrate data, deploy, restart
   services, or cause other material effects.
3. Select focused iteration checks, omitted mandatory checks, and the final
   native-gate mode. Resolve missing tools or authorization gaps before relying
   on the planned verdict.

## Enforcement Order

1. During implementation, iterate with the narrowest relevant analyzer,
   focused test, or build slice. Do not repeatedly invoke the full native gate
   when a faster scoped check provides the needed feedback.
2. Run a repository-supported fix-only phase only when its task-owned
   mutations are authorized and no equivalent non-mutating route can prepare
   or validate the required final state. Run it before omitted mandatory
   checks, then inspect the task-owned diff.
3. Run every applicable mandatory check the native verdict omits. If there is
   no canonical gate, run the complete mandatory baseline directly.
4. Use a check-only native mode when it provides equivalent integrated
   coverage. Do not invoke the mutating workflow in that case. Normally run the
   final native verdict once after omitted checks are green.
5. If no non-mutating mode provides equivalent integrated coverage and the
   required native workflow mutates files, record the task-owned diff before
   and after it and ensure unrelated files did not change. Rerun only omitted
   mandatory checks applicable to files it changed. Determine whether the
   native gate validated the post-mutation tree; if not, run any available
   non-mutating validation mode against the final tree. If no post-mutation
   verdict is possible, report verification as incomplete. Do not blindly
   repeat the full mutating workflow.
6. If the native gate fails, use focused checks while fixing the cause. Re-run
   it only after a relevant code, test, configuration, or generated-artifact
   change makes a different verdict plausible. Never repeat an unchanged
   expensive gate merely to see whether it passes this time.
7. Run focused behavioral tests earlier when they shorten feedback, but finish
   this sequence against the final tree before declaring the work done.

## Side Effects and Authorization

- Diagnose and Review modes are read-only. Do not run a native gate that
  autofixes, generates tracked files, installs tools, changes dependencies, or
  causes operational effects. Use check-only commands and disposable or
  disabled caches where practical.
- Implement mode does not authorize tool installation, upgrades, dependency or
  lockfile changes, live service operations, migrations, or deployment. Ask
  before invoking a gate known to perform any such action.
- Running a familiar repository gate is not implicit permission for its hidden
  installer or operational phases. Inspect it first and select a safe mode.
- When no safe non-mutating verdict exists for Review or Diagnose, report the
  verification gap instead of executing the gate.

## Verdict Integrity

- A mandatory check is satisfied only when it runs successfully against the
  intended project root and relevant source set. An absent configuration, empty
  collection, or wrong environment is not success.
- Mark a mandatory gate `N/A` only when its technology, target, or supported
  first-party file set is genuinely absent. Record the exact reason. A missing
  executable or configuration, empty test collection, or inconvenient
  environment is incomplete or blocked, never `N/A`.
- For example, Prettier is `N/A` in a Python repository only when no supported
  first-party files exist. If supported files exist, it remains mandatory even
  though it must not parse `.py` files.
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
