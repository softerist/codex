# Python Quality Gates

Read this reference for every completed change affecting Python source, tests,
or Python tool configuration.

## Mandatory Baseline

All of these checks are mandatory:

1. MyPy through `dmypy`; if the daemon fails or cannot provide a trustworthy
   verdict, run cold MyPy as the fallback.
2. Pyright.
3. BasedPyright.
4. pytest, including the focused affected tests and the repository's required
   regression scope.
5. Pylint.
6. Ruff lint.
7. Pyrefly.
8. Prettier in check mode for the repository's supported non-Python files. It
   remains part of the Python-repository gate even though it must not parse
   Python source. Apply the `N/A` rule in `core.md`: it is `N/A` only when no
   supported first-party files exist, and the completion report must say why.

Also run Python byte compilation and Ruff formatting verification when the
repository declares them. Use the configured project or backend root and the
project's supported interpreter environment for every analyzer.

Do not substitute one required type checker for another: MyPy, Pyright,
BasedPyright, and Pyrefly provide independent mandatory verdicts.

## Direct Command Shapes

Use these only when no canonical repository wrapper provides the check:

```text
dmypy run -- <configured source and test roots>
mypy <configured source and test roots>          # cold fallback only
pyright
basedpyright
pytest <focused tests, then required regression scope>
pylint <configured source and test roots>
ruff check <configured source and test roots>
pyrefly check <configured source and test roots>
prettier --check <supported repository files>
```

Resolve executables through the project environment. Preserve repository-specific
configuration, plugins, arguments, and wrapper scripts instead of copying these
templates literally.
