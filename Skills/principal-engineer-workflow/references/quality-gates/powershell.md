# PowerShell Quality Gates

Read this reference for every completed change affecting `.ps1`, `.psm1`, or
`.psd1` files.

## Mandatory Baseline

1. Parse every affected PowerShell file with the PowerShell parser and fail on
   every parse error.
2. Run PSScriptAnalyzer using the repository's settings when present and fail on
   every configured error or warning.
3. Run the relevant Pester suite when tests exist. Otherwise, perform a safe,
   focused behavioral probe when practical. If no safe probe exists, report
   the verification gap without executing an operational script.
4. For modules, validate the module manifest, import the module, and smoke-test
   the affected exported commands or aliases when applicable.

Parsing is not a substitute for PSScriptAnalyzer, and PSScriptAnalyzer is not a
substitute for behavioral verification.

## Direct Command Shapes

A direct parser probe should call
`[System.Management.Automation.Language.Parser]::ParseFile()` for each affected
file and fail if the returned parse-error collection is non-empty.

A typical analyzer invocation is:

```powershell
Invoke-ScriptAnalyzer -Path <scope> -Recurse
```

Add the repository's settings file when present. Use its Pester, manifest, and
module-import commands rather than inventing replacements.
