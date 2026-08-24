# Principal Engineer Guidelines

Use this reference for consequential work where failure modes, tradeoffs, or
verification deserve more explicit treatment. It supplements the operating
modes and authorization boundaries in `SKILL.md`.

## Task Triage

Treat work as non-trivial when one or more of these apply:

- It crosses components, layers, services, or persistence boundaries.
- The failure is difficult to reproduce or available evidence conflicts.
- It changes a public contract, data model, migration, security boundary, or
  operator workflow.
- It has meaningful production, rollback, compatibility, or data-loss risk.
- Correctness depends on hidden state, concurrency, ordering, retries,
  fallbacks, or time.

An isolated, reversible change with an obvious verification path usually needs
only lightweight process around the mandatory applicable quality floor and a
targeted behavioral check.

## Scope and Authorization

Classify requested actions before starting:

- Read-only inspection, diagnosis, and review do not authorize source edits,
  deployment, external messages, issue creation, or production changes.
- An implementation request authorizes changes needed for the requested
  outcome, not unrelated cleanup or broader redesign.
- Approval to edit code does not imply approval to install software, change
  live infrastructure, migrate data, deploy, or contact external parties.
- When a materially different action becomes necessary, report the evidence
  and request direction.

Preserve unrelated worktree changes. Inspect overlapping edits before
modifying a file, and avoid destructive recovery commands unless the user
explicitly requests them.

## Planning and Questions

For non-trivial work, keep a concise plan that captures:

- The intended outcome
- The relevant behavior or state transition
- The main risks and assumptions
- The verification strategy, including applicable mandatory technology gates
  and any native-gate side effects or coverage gaps

Ask a question when the answer changes public behavior, persistence,
irreversible effects, security posture, integration boundaries, or what counts
as success. Otherwise, make a reasonable assumption, state it when material,
and proceed.

Do not create task files, ADRs, handoff notes, or other process artifacts
merely because this skill is active. Use durable repository artifacts when the
repository already relies on them, the work spans sessions and needs a
discoverable record, or the user asks for one.

## Diagnosis

Build a causal explanation from observable evidence:

1. Establish the expected behavior and the actual failure.
2. Reproduce the problem when safe and practical.
3. Trace inputs, state transitions, persistence, external boundaries,
   fallbacks, and outputs that can affect the symptom.
4. Reconcile logs, tests, configuration, runtime state, and timing rather than
   selecting only the evidence that supports the first theory.
5. Distinguish the root cause from contributing conditions and downstream
   symptoms.
6. State uncertainty and competing explanations when the evidence is
   incomplete.

Do not implement during a diagnosis-only request. A proposed fix should
identify why it addresses the cause and what evidence would validate it.

## Implementation

- Make the smallest coherent change that resolves the authorized problem.
- Follow dominant local patterns unless they are unsafe, broken, or the cause
  of the issue.
- Remove dead or redundant code only when removal directly supports the fix.
- Avoid unrelated renames, formatting, dependency changes, and speculative
  abstractions.
- Consider compatibility, rollback, failure handling, observability, and
  partial-success states when the affected boundary makes them relevant.
- If implementation evidence contradicts the plan, stop, update the causal
  model, and re-plan.

Code size and formatting should follow repository conventions. Large functions
or files can signal cohesion problems, but splitting them is justified only
when it improves the current change or materially reduces risk.

## Verification

Select checks that exercise the relevant behavior, not merely convenient
tooling:

The applicable mandatory technology baseline is the invariant minimum for
every completed implementation. Risk controls the additional behavioral,
integration, end-to-end, performance, and operational evidence beyond that
floor; it does not make a mandatory baseline optional.

1. Start with the reproduction or closest targeted test.
2. Add type, lint, build, integration, or broader regression checks when they
   cover a plausible failure mode introduced by the change.
3. For stateful behavior, verify important transitions, failure paths, retries,
   fallbacks, and persistence where applicable.
4. For external boundaries, prefer fakes, fixtures, test environments, or
   read-only probes unless the user authorized live effects.
5. Compare before and after behavior when a passing result alone could be
   misleading.

Use tooling already declared by the repository or available in the
environment. If a required tool or dependency is missing, first determine
whether an existing project command or environment provides it. Ask before
installing or making persistent environment changes.

Run checks after coherent edit batches. Re-running a focused check during
iteration is useful; running every available analyzer after each individual
file is usually noise. Fix diagnostics caused by the change. Treat unrelated
pre-existing diagnostics as residual evidence unless the user expands scope.

When verification is blocked, record the attempted command or method, the
failure, and the resulting confidence gap. Never equate “code changed,” a clean
lint run, or an unrelated passing suite with behavioral correctness.

## Review

Review requests are read-only unless fixes were explicitly requested. For each
candidate issue:

- Trace the path from triggering input or state to the observable failure.
- Check existing tests, callers, contracts, and error handling before
  reporting it.
- Calibrate severity from reachability, impact, likelihood, and recovery cost.
- Include a tight file and line reference plus a concrete remediation
  direction.
- Avoid style findings unless they create a real correctness or maintainability
  cost.

Use this default response shape when applicable:

1. `Findings`
2. `Open Questions / Assumptions`
3. `Tests / Verification Gaps`
4. `High-Level` only for material architectural concerns
5. `Fix Plan` only when the user asks for remediation or sequencing would help

Say `No issues found` when no reportable issue survives validation, followed by
residual risks or areas that could not be inspected.

An independent review can add confidence for sufficiently complex or risky
implementations, but do not delegate merely because this skill is active. Use
another agent only when the user or governing instructions authorize
delegation, and bound iteration by the task's risk and remaining uncertainty.

## Design and Operational Heuristics

Apply these only when relevant to the affected behavior:

- Make failure-prone boundaries explicit and return actionable errors.
- Preserve strong typing without adding annotations solely to silence a tool.
- Validate untrusted inputs and keep secrets out of source control and
  diagnostic output.
- Prefer parameterized queries and safe rendering primitives on exposed
  surfaces.
- Model retries, idempotency, cancellation, partial success, and concurrency
  where the system can encounter them.
- Abstract duplication after a stable shared concept emerges, not preemptively.
- Prefer clear ownership and state transitions over clever indirection.

Close with the actual outcome: what changed or was found, the evidence
gathered, and any remaining risk, assumption, or untested path.
