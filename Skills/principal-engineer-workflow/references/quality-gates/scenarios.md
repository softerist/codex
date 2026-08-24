# Quality-Gate Behavior Scenarios

Use these scenarios only when maintaining or reviewing this skill. They are
acceptance criteria for routing and gate decisions, not extra instructions to
load during ordinary implementation.

1. **Routine Python implementation:** Activate the skill, read core and Python,
   and run the mandatory floor.
2. **Non-trivial Python change without a native gate:** Run the complete Python
   baseline directly, plus risk-driven evidence.
3. **Mixed Python and TypeScript with a partial native gate:** Read both
   baselines, run omitted checks, then run the safe native verdict once.
4. **Native gate autofixes files:** Run a supported fix phase first when
   available, inspect the diff, and rerun affected omitted checks.
5. **Native gate installs tools:** Ask before invoking the installing phase;
   gate execution does not imply permission.
6. **Security-sensitive change without a scanner:** Select the minimum
   applicable fallback; if unavailable, report incomplete verification.
7. **Review-only request with a mutating native gate:** Do not run it; use
   non-mutating checks or report the gap.
8. **Mandatory checker is missing:** Use an existing repository entrypoint or
   report incomplete verification and request authorization.
9. **Python repository has no Prettier-supported files:** Mark Prettier `N/A`
   and record the exact absence reason.
10. **Markdown, XML, or Windows batch changes:** Route to infrastructure and
    apply the file-specific safe baseline.
