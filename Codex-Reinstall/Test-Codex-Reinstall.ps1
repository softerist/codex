#requires -Version 5.1
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Codex-Reinstall.ps1')
. (Join-Path $PSScriptRoot 'Codex-Reinstall.UI.ps1')

$testRoot = Join-Path $env:TEMP ('codex-reinstall-test-' + [guid]::NewGuid().ToString('N'))
$sourceHome = Join-Path $testRoot 'source\.codex'
$backupRoot = Join-Path $testRoot 'backups'
$restoreHome = Join-Path $testRoot 'restore\.codex'
$outside = Join-Path $testRoot 'outside'
$results = [ordered]@{}
$savedUserProfile = $env:USERPROFILE
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
function Assert-Test([string] $Name, [bool] $Passed) { $script:results[$Name] = $Passed }
function Edit-TestManifest([string] $Backup, [scriptblock] $Change) {
    $path = Join-Path $Backup $script:ManifestName
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    & $Change $data
    [IO.File]::WriteAllText(
        $path,
        ($data | ConvertTo-Json -Depth 10),
        [Text.UTF8Encoding]::new($false)
    )
}
function Test-BackupFile([object] $Backup, [string] $RelativePath) {
    return Test-Path -LiteralPath (Join-Path $Backup.Directory $RelativePath)
}

try {
    $fixtureDirectories = @(
        'sessions\2026\08\24',
        'archived_sessions',
        'attachments',
        'skills\personal',
        'skills\.system',
        'memories',
        'sqlite'
    )
    foreach ($directory in $fixtureDirectories) {
        [IO.Directory]::CreateDirectory((Join-Path $sourceHome $directory)) | Out-Null
    }
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    [IO.File]::WriteAllText((Join-Path $sourceHome 'config.toml'), 'model="test"')
    [IO.File]::WriteAllText(
        (Join-Path $sourceHome 'sessions\2026\08\24\active.jsonl'),
        '{"active":true}'
    )
    [IO.File]::WriteAllText(
        (Join-Path $sourceHome 'archived_sessions\archived.jsonl'),
        '{"archived":true}'
    )
    [IO.File]::WriteAllText((Join-Path $sourceHome 'skills\personal\SKILL.md'), '# personal')
    [IO.File]::WriteAllText((Join-Path $sourceHome 'skills\.system\SKILL.md'), '# built-in')
    [IO.File]::WriteAllText((Join-Path $sourceHome 'memories\MEMORY.md'), '# memory')
    [IO.File]::WriteAllText(
        (Join-Path $sourceHome 'attachments\example.sqlite'),
        'attachment, not database'
    )
    [IO.File]::WriteAllText((Join-Path $sourceHome '.codex-global-state.json'), @'
{"pinned-thread-ids":["thread-1"],"project-order":["project-1"],"auth-token":"must-not-back-up"}
'@)
    $database = Join-Path $sourceHome 'state_5.sqlite'
    $query = @'
CREATE TABLE test_data(id INTEGER PRIMARY KEY, value TEXT);
INSERT INTO test_data(value) VALUES('verified');
'@
    & sqlite3.exe $database $query
    if ($LASTEXITCODE -ne 0) { throw 'Could not create SQLite fixture.' }
    Copy-Item $database (Join-Path $sourceHome 'sqlite\goals.sqlite')
    Copy-Item $database (Join-Path $sourceHome 'logs_2.sqlite')
    [IO.File]::WriteAllText((Join-Path $sourceHome 'state_5.sqlite-shm'),
        'volatile shared memory')
    [IO.File]::WriteAllText((Join-Path $sourceHome 'sqlite\goals.sqlite-shm'),
        'volatile shared memory')

    $script:CodexHome = $sourceHome
    $script:BackupRoot = $backupRoot
    $script:UiStatePath = Join-Path $testRoot 'ui-state.json'
    function Get-CodexProcess { return @() }
    function Get-CodexPackage {
        [pscustomobject]@{ Version = '99.0.0.0'; PackageFullName = 'fixture' }
    }

    $backup = Invoke-Backup
    Assert-Test ExactBackupResultReturned ($backup.Directory -like "$backupRoot*")
    Assert-Test ActiveChatPreserved (
        Test-BackupFile $backup 'payload\sessions\2026\08\24\active.jsonl'
    )
    Assert-Test ArchivedChatPreserved (
        Test-BackupFile $backup 'payload\archived_sessions\archived.jsonl'
    )
    Assert-Test ConfigPreserved (Test-Path (Join-Path $backup.Directory 'payload\config.toml'))
    Assert-Test SkillsPreserved (
        Test-BackupFile $backup 'payload\skills\personal\SKILL.md'
    )
    Assert-Test MemoriesPreserved (
        Test-BackupFile $backup 'payload\memories\MEMORY.md'
    )
    Assert-Test DatabaseNamedAttachmentPreserved (
        Test-BackupFile $backup 'payload\attachments\example.sqlite'
    )
    $layoutBackup = Get-Content (Join-Path $backup.Directory 'payload\ui-layout.json') -Raw
    Assert-Test SidebarLayoutPreserved ($layoutBackup -match 'thread-1')
    Assert-Test GlobalIdentityExcluded ($layoutBackup -notmatch 'auth-token|must-not-back-up')
    Assert-Test GoalsDatabaseRestorable (
        Test-BackupFile $backup 'payload\sqlite\goals.sqlite'
    )
    Assert-Test LogsExcludedFromRestore (-not (
        Test-BackupFile $backup 'payload\logs_2.sqlite'
    ))
    Assert-Test LogsRetainedAsInsurance (
        Test-BackupFile $backup 'database-insurance\root\logs_2.sqlite'
    )
    Assert-Test SharedMemoryExcludedFromPayload (-not (Test-Path `
        (Join-Path $backup.Directory 'payload\state_5.sqlite-shm')))
    Assert-Test SharedMemoryExcludedFromInsurance (-not (Test-Path `
        (Join-Path $backup.Directory 'database-insurance\sqlite\goals.sqlite-shm')))
    $verified = Test-BackupManifest -Directory $backup.Directory -Quiet
    Assert-Test ValidManifestPassed ($verified.Files -gt 0)
    $generatedSidecar = Join-Path $backup.Directory `
        'payload\state_5.sqlite-shm'
    [IO.File]::WriteAllBytes($generatedSidecar, [byte[]]::new(32768))
    $verifiedAgain = Test-BackupManifest -Directory $backup.Directory -Quiet
    Assert-Test RepeatedVerificationPassed ($verifiedAgain.Files -gt 0)
    Assert-Test GeneratedSharedMemoryRemoved (-not (
        Test-Path -LiteralPath $generatedSidecar
    ))

    Remove-Item -LiteralPath (Join-Path $sourceHome 'config.toml') -Force
    Remove-Item -LiteralPath (Join-Path $sourceHome 'archived_sessions') -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $sourceHome 'skills\personal') -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $sourceHome 'memories') -Recurse -Force
    $sparseRoot = Join-Path $testRoot 'sparse-backups'
    [IO.Directory]::CreateDirectory($sparseRoot) | Out-Null
    $script:BackupRoot = $sparseRoot
    $sparseBackup = Invoke-Backup
    $sparseVerified = Test-BackupManifest $sparseBackup.Directory -Quiet
    Assert-Test SparseProfileBackupPassed ($sparseVerified.Files -gt 0)
    $script:BackupRoot = $backupRoot

    $copyRoot = Join-Path $testRoot 'tamper-empty'; Copy-Item $backup.Directory $copyRoot -Recurse
    Edit-TestManifest $copyRoot { param($m) $m.file_count = 0; $m.total_bytes = 0; $m.files = @() }
    $caught = $false
    try { Test-BackupManifest $copyRoot -Quiet | Out-Null }
    catch { $caught = $_.Exception.Message -match 'no preserved data|file count' }
    Assert-Test EmptyManifestRejected $caught

    $copyRoot = Join-Path $testRoot 'tamper-path'; Copy-Item $backup.Directory $copyRoot -Recurse
    Edit-TestManifest $copyRoot { param($m) $m.files[0].relative_path = '../escape.txt' }
    $caught = $false
    try { Test-BackupManifest $copyRoot -Quiet | Out-Null }
    catch { $caught = $_.Exception.Message -match 'Unsafe relative path' }
    Assert-Test TraversalRejected $caught

    $copyRoot = Join-Path $testRoot 'tamper-duplicate'
    Copy-Item $backup.Directory $copyRoot -Recurse
    Edit-TestManifest $copyRoot { param($m) $m.files[1].relative_path = $m.files[0].relative_path }
    $caught = $false
    try { Test-BackupManifest $copyRoot -Quiet | Out-Null }
    catch { $caught = $_.Exception.Message -match 'Duplicate manifest path' }
    Assert-Test DuplicateManifestPathRejected $caught

    $copyRoot = Join-Path $testRoot 'tamper-extra'; Copy-Item $backup.Directory $copyRoot -Recurse
    [IO.File]::WriteAllText((Join-Path $copyRoot 'payload\undeclared.txt'), 'extra')
    $caught = $false
    try { Test-BackupManifest $copyRoot -Quiet | Out-Null }
    catch { $caught = $_.Exception.Message -match 'undeclared' }
    Assert-Test UndeclaredBackupFileRejected $caught

    $copyRoot = Join-Path $testRoot 'tamper-coverage'
    Copy-Item $backup.Directory $copyRoot -Recurse
    Edit-TestManifest $copyRoot { param($m) $m.coverage.active_chats = 999 }
    $caught = $false
    try { Test-BackupManifest $copyRoot -Quiet | Out-Null }
    catch { $caught = $_.Exception.Message -match 'coverage is inconsistent' }
    Assert-Test ForgedCoverageRejected $caught

    Assert-Test DriveRootPreserved ((Get-NormalizedPath 'C:\') -eq 'C:\')
    $fakeHelper = [pscustomobject]@{
        ProcessName = 'codex-code-mode-host'
        Path = 'C:\Program Files\WindowsApps\OpenAI.Codex_1_x64__id\app\helper.exe'
    }
    $fakeUi = [pscustomobject]@{
        ProcessName = 'ChatGPT'
        Path = 'C:\Program Files\WindowsApps\OpenAI.Codex_1_x64__id\app\ChatGPT.exe'
    }
    Assert-Test HelperProcessDetected (Test-IsCodexProcess $fakeHelper)
    Assert-Test PackageUiProcessDetected (Test-IsCodexProcess $fakeUi)
    Assert-Test InaccessiblePackageUiDetected (Test-IsCodexProcess `
        ([pscustomobject]@{ ProcessName = 'ChatGPT'; Path = $null }))
    $caught = $false
    try { Assert-SafeRelativePath 'config.toml.' | Out-Null }
    catch { $caught = $true }
    Assert-Test TrailingDotAliasRejected $caught

    $junction = Join-Path $testRoot 'junction'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    $caught = $false
    try { Assert-SafeExternalPath $junction }
    catch { $caught = $_.Exception.Message -match 'Reparse points' }
    Assert-Test ExternalJunctionRejected $caught
    Remove-SafeTree -Path $junction -Confirm:$false
    Assert-Test JunctionTargetSurvivesRemoval (Test-Path $outside)

    $script:CodexHome = $restoreHome
    $script:BackupPath = $backup.Directory
    $script:Confirmation = 'RESTORE-CODEX-PRESERVED-DATA'
    Invoke-Restore -WhatIf
    Assert-Test RestoreWhatIfHasNoSideEffects (-not (Test-Path $restoreHome))
    [IO.Directory]::CreateDirectory($restoreHome) | Out-Null
    [IO.File]::WriteAllText((Join-Path $restoreHome '.codex-global-state.json'),
        '{"auth-token":"fresh-install"}')
    Invoke-Restore -Confirm:$false
    Assert-Test ActiveChatRestored (
        Test-Path (Join-Path $restoreHome 'sessions\2026\08\24\active.jsonl')
    )
    $restoredConfig = Get-Content (Join-Path $restoreHome 'config.toml') -Raw
    Assert-Test ConfigRestored ($restoredConfig -eq 'model="test"')
    Assert-Test FreshSystemSkillWins (-not (
        Test-Path (Join-Path $restoreHome 'skills\.system\SKILL.md')
    ))
    $restoredGlobal = Get-Content (Join-Path $restoreHome '.codex-global-state.json') -Raw
    Assert-Test SidebarLayoutRestored ($restoredGlobal -match 'thread-1')
    Assert-Test FreshGlobalIdentityPreserved (
        $restoredGlobal -match 'fresh-install' -and
        $restoredGlobal -notmatch 'must-not-back-up'
    )
    $staleWal = Join-Path $restoreHome 'state_5.sqlite-wal'
    $staleShm = Join-Path $restoreHome 'state_5.sqlite-shm'
    [IO.File]::WriteAllText($staleWal, 'stale')
    [IO.File]::WriteAllText($staleShm, 'stale')
    Invoke-Restore -Confirm:$false
    Assert-Test StaleWalRemoved (-not (Test-Path $staleWal))
    Assert-Test StaleSharedMemoryRemoved (-not (Test-Path $staleShm))

    [IO.File]::WriteAllText((Join-Path $restoreHome 'config.toml'), 'fresh-before-failure')
    Remove-Item -LiteralPath (Join-Path $restoreHome 'memories') -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $restoreHome 'memories'), 'blocking file')
    $caught = $false
    try { Invoke-Restore -Confirm:$false }
    catch { $caught = $_.Exception.Message -match 'rolled back' }
    Assert-Test RestoreFailureDetected $caught
    $recoveredConfig = Get-Content (Join-Path $restoreHome 'config.toml') -Raw
    Assert-Test RestoreRollbackRecoveredConfig (
        $recoveredConfig -eq 'fresh-before-failure'
    )

    $fakeProfile = Join-Path $testRoot 'cleanup-profile'
    $env:USERPROFILE = $fakeProfile
    $env:APPDATA = Join-Path $fakeProfile 'AppData\Roaming'
    $env:LOCALAPPDATA = Join-Path $fakeProfile 'AppData\Local'
    $script:CodexHome = Join-Path $fakeProfile '.codex'
    [IO.Directory]::CreateDirectory($script:CodexHome) | Out-Null
    [IO.File]::WriteAllText((Join-Path $script:CodexHome 'old.txt'), 'old')
    $extensionDir = Join-Path $env:LOCALAPPDATA 'OpenAI\extension'
    [IO.Directory]::CreateDirectory($extensionDir) | Out-Null
    [IO.File]::WriteAllText((Join-Path $extensionDir 'com.openai.codexextension.backup.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $extensionDir 'unrelated.json'), '{}')
    $downloads = Join-Path $fakeProfile 'Downloads'
    [IO.Directory]::CreateDirectory($downloads) | Out-Null
    [IO.File]::WriteAllText((Join-Path $downloads 'CodexSetup.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $downloads 'OpenAI-Codex-Installer.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $downloads 'OpenAISetup.exe'), 'fixture')
    function Get-CodexPackage { return $null }
    $script:BackupPath = $backup.Directory
    $script:Confirmation = 'WIPE-CODEX-LOCAL-DATA'
    $script:IncludeInstallers = $true
    Invoke-Clean -Confirm:$false
    Assert-Test CleanupRemovedCodexHome (-not (Test-Path $script:CodexHome))
    Assert-Test CleanupRemovedVersionedHost (-not (
        Test-Path (Join-Path $extensionDir `
            'com.openai.codexextension.backup.json')
    ))
    Assert-Test CleanupPreservedUnrelatedHost (Test-Path (Join-Path $extensionDir 'unrelated.json'))
    Assert-Test CleanupRemovedCodexInstaller (-not (
        Test-Path (Join-Path $downloads 'CodexSetup.exe')
    ))
    Assert-Test CleanupRemovedPrefixedCodexInstaller (-not (
        Test-Path (Join-Path $downloads 'OpenAI-Codex-Installer.exe')
    ))
    Assert-Test CleanupPreservedOpenAIInstaller (Test-Path (Join-Path $downloads 'OpenAISetup.exe'))

    $whatIfRejected = $false; $script:CodexHome = $sourceHome
    try { Invoke-Backup -WhatIf }
    catch {
        $whatIfRejected = $_.Exception.Message -match 'does not support -WhatIf'
    }
    Assert-Test BackupWhatIfExplicitlyRejected $whatIfRejected
    $state = Get-UiState
    $state.LastBackupRoot = $backupRoot
    $state.LastBackupPath = $backup.Directory
    $state.LastCompletedAction = 'Backup'
    Save-UiState -State $state
    Assert-Test UiStateRoundTrip ((Get-UiState).LastBackupPath -eq $backup.Directory)

    [pscustomobject] $results | Format-List
    $failed = @($results.GetEnumerator() | Where-Object Value -NE $true)
    if ($failed.Count -gt 0) { throw "Self-test failures: $(($failed.Name) -join ', ')" }
}
finally {
    $env:USERPROFILE = $savedUserProfile
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTest = Get-NormalizedPath $testRoot; $resolvedTemp = Get-NormalizedPath $env:TEMP
        $safeName = (Split-Path -Leaf $resolvedTest) -like `
            'codex-reinstall-test-*'
        if ($safeName -and (Test-PathInside $resolvedTest $resolvedTemp)) {
            Remove-Item -LiteralPath $resolvedTest -Recurse -Force
        }
    }
}
