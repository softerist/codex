# Shell and Rust Quality Gates

Read only the section matching the affected technology. Read both for a
cross-technology change.

## Shell Baseline

For every completed Bash or POSIX shell change:

1. Run the appropriate parser check, such as `bash -n` for Bash.
2. Run ShellCheck using repository directives and configuration.
3. Run repository shell tests or a safe focused invocation of the affected
   behavior when available.

Use `shfmt --diff` only when the repository already declares its formatting
style. Do not introduce a shell formatting policy implicitly.

## Rust Baseline

For every completed Rust change:

1. Run `cargo fmt --check`.
2. Run `cargo clippy` across applicable targets and features, with warnings
   denied unless repository policy is stricter.
3. Run focused tests followed by the repository's required `cargo test` scope.
4. Run `cargo check` or the repository's production build for affected targets.

Specialized parity, compatibility, baseline, or intentional-failure tests remain
mandatory when the changed code is in their scope.
