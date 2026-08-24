# JavaScript and TypeScript Quality Gates

Read this reference for every completed JavaScript, TypeScript, frontend,
Electron, or Node change.

## Mandatory Baseline

1. ESLint with warnings treated as failures.
2. Prettier in check mode.
3. The repository's test runner, such as Vitest, Jest, or its declared custom
   Node test harness.
4. TypeScript compilation or `tsc --noEmit` for TypeScript projects.
5. The production build for frontend, Electron, library, or packaged executable
   changes.
6. `node --check` for maintained plain-JavaScript entrypoints when no compiler
   parses them.

Run browser or Playwright tests when the changed behavior crosses a browser,
renderer, or end-to-end boundary. Preserve repository package-manager scripts,
lockfiles, configuration, and pinned tool versions.
