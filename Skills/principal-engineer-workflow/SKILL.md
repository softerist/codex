---
name: principal-engineer-workflow
description: >-
  Use when a user explicitly wants principal-level engineering rigor, or when
  software work has meaningful architectural, cross-file, operational, data,
  security, or rollback risk. Covers evidence-led diagnosis, scoped
  implementation, and severity-first review. Do not use for routine isolated
  edits or ordinary technical questions.
---

# Principal Engineer Workflow

Handle consequential engineering work with high rigor and low ceremony. Scale
the process to the actual risk, preserve the user's scope, and prefer evidence
over speculation.

## Choose the Operating Mode

Determine which mode the user authorized before acting:

- **Diagnose:** Investigate and explain the root cause. Do not implement a fix
  unless the user also requested one.
- **Implement:** Make the smallest correct change within the requested scope,
  then verify it.
- **Review:** Inspect and report severity-ranked findings. Treat review as
  read-only unless the user explicitly asks for fixes.

Combine modes only when the request clearly authorizes each one. Self-review
and correction are part of an authorized implementation; they do not turn a
review-only request into permission to edit.

## Core Rules

1. Preserve user intent, authorization boundaries, and unrelated work.
2. Prefer root-cause fixes and minimal blast radius over compensating patches
   or cleanup.
3. Follow repository conventions unless they are unsafe or directly
   responsible for the problem.
4. Ask questions only when ambiguity materially changes behavior, risk, or
   irreversible effects.
5. Re-plan when new evidence invalidates the current approach.
6. Do not claim completion without verification proportional to the risk.

## Workflow

1. **Triage:** Identify the operating mode, affected behavior, failure modes,
   and rollback cost.
2. **Inspect:** Read the relevant repository instructions, code paths, tests,
   configuration, and current state before proposing a significant change.
3. **Plan proportionally:** For non-trivial work, keep a short plan in the
   conversation. Use repository planning files only when they already exist or
   the user requests them.
4. **Act within scope:** Diagnose, implement, or review according to the
   authorized mode.
5. **Verify behavior:** Use the repository's declared tooling and the narrowest
   meaningful checks first, broadening as risk warrants. After an
   implementation, read and apply the mandatory technology baselines in the
   [quality-gate policy][quality-gates].
6. **Report the outcome:** State what changed or was found, what was verified,
   and any residual risk or untested area.

Do not install tools or dependencies without authorization. Run checks after a
coherent edit batch rather than mechanically after every file, unless the
repository's own workflow requires otherwise.

Treat line length, file size, and similar metrics as maintainability signals,
not universal laws. Repository rules take precedence; do not split cohesive
code merely to satisfy an arbitrary limit.

## Verification

Match evidence to the changed or investigated behavior. Useful evidence can
include targeted tests, safe reproductions, logs or traces, type and lint
checks, and before/after comparisons.

When practical, exercise the behavior directly through an existing test, a
repository-supported harness, or a disposable probe. Choose a method
appropriate to the language and architecture. Do not invoke code in a way that
can mutate production data, contact live services, or trigger other material
side effects without authorization. Passing static analysis or an unrelated
test suite is not proof that the target behavior works.

If an important check cannot run, explain why and reduce the confidence of the
conclusion accordingly.

## Review Output

Lead with actionable findings, ordered by severity and user impact. Prioritize:

1. Security and privacy
2. Data correctness and durability
3. Business logic and state transitions
4. Reliability and operability
5. User experience and presentation

For each finding, identify the affected location, explain the concrete failure
mode, and state why it matters. Prefer fewer high-confidence findings over
speculative nits. Call out missing tests only when the gap materially affects
confidence.

If there are no findings, say `No issues found` explicitly, then note residual
risks or review gaps. For an explicitly security-focused assessment, use the
relevant security workflow rather than stretching this general engineering
skill.

## Detailed Guidance

For non-trivial diagnosis, implementation, or review, read the
[detailed principal-engineer guidelines][guidelines].

For every completed implementation, read the [quality-gate policy][quality-gates]
and run the baselines for every technology affected by the change. Reviews and
diagnosis remain read-only, but the same policy can guide non-mutating verification.

[guidelines]: ./references/principal-engineer-guidelines.md
[quality-gates]: ./references/quality-gates/core.md
