#requires -Version 5.1

Set-StrictMode -Version Latest

if (-not (Get-Command Invoke-Backup -ErrorAction SilentlyContinue)) {
    throw 'Run Codex-Reinstall.ps1; the UI component is not a standalone entry point.'
}

$script:UiStatePath = Join-Path $PSScriptRoot 'codex-reinstall-ui.json'

function Write-UiText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [ConsoleColor] $Color = [ConsoleColor]::Gray
    )

    if ([Console]::IsOutputRedirected) {
        Write-Information $Text -InformationAction Continue
        return
    }
    $originalColor = [Console]::ForegroundColor
    try {
        [Console]::ForegroundColor = $Color
        Write-Information $Text -InformationAction Continue
    }
    finally {
        [Console]::ForegroundColor = $originalColor
    }
}

function Show-UiHeader {
    Clear-Host
    Write-UiText '============================================================' DarkCyan
    Write-UiText '               CODEX CLEAN REINSTALL TOOLKIT' Cyan
    Write-UiText '============================================================' DarkCyan
    $preservedText =
        'Preserves chats, pins/projects, databases, skills, memories, and config.toml.'
    Write-UiText $preservedText DarkGray
    Write-UiText ''
}

function Read-UiValue {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [string] $Default
    )

    $label = $Prompt
    if (-not [string]::IsNullOrWhiteSpace($Default)) {
        $label = "$Prompt [$Default]"
    }
    $value = Read-Host $label
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value.Trim().Trim('"')
}

function Read-UiChoice {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [Parameter(Mandatory)][string[]] $Allowed,
        [string] $Default
    )

    while ($true) {
        $rawValue = Read-UiValue -Prompt $Prompt -Default $Default
        $value = if ($null -eq $rawValue) {
            ''
        }
        else {
            $rawValue.ToUpperInvariant()
        }
        if ($Allowed -contains $value) {
            return $value
        }
        Write-UiText "Choose one of: $($Allowed -join ', ')" Yellow
    }
}

function Wait-Ui {
    Read-Host 'Press Enter to continue' | Out-Null
}

function Get-UiState {
    $script:UiStateWarning = ''
    $state = [ordered]@{
        LastBackupRoot = ''
        LastBackupPath = ''
        LastCompletedAction = ''
        UpdatedUtc = ''
    }
    if (-not (Test-Path -LiteralPath $script:UiStatePath)) {
        return $state
    }

    try {
        $saved = Get-Content -LiteralPath $script:UiStatePath -Raw |
            ConvertFrom-Json
        foreach ($key in @($state.Keys)) {
            if ($null -ne $saved.PSObject.Properties[$key]) {
                $state[$key] = [string] $saved.$key
            }
        }
    }
    catch {
        $script:UiStateWarning = `
            'The saved UI state is unreadable; safe defaults are in use.'
    }

    return $state
}

function Save-UiStateSafely {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)
    try { Save-UiState -State $State }
    catch {
        Write-UiText (
            'The action completed, but UI state could not be saved: ' +
            $_.Exception.Message
        ) Yellow
    }
}

function Get-LocalBackupDrive {
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        try {
            if ($drive.IsReady -and $drive.DriveType -in @(
                [IO.DriveType]::Fixed, [IO.DriveType]::Removable
            )) {
                [pscustomobject]@{
                    Name = $drive.Name.TrimEnd('\').TrimEnd(':')
                    Root = $drive.RootDirectory.FullName
                    Free = [long] $drive.AvailableFreeSpace
                }
            }
        }
        catch { continue }
    }
}

function Save-UiState {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    $State['UpdatedUtc'] = [DateTime]::UtcNow.ToString('o')
    $temporaryPath = "$script:UiStatePath.tmp"
    $json = $State | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $temporaryPath -Destination $script:UiStatePath -Force
}

function Get-RecommendedBackupRoot {
    $requiredBytes = [long] 0
    try {
        $requiredBytes = [long](Get-PreservedItem | ForEach-Object {
            (Get-Item -LiteralPath $_.Source -Force).Length
        } | Measure-Object -Sum).Sum
    }
    catch { $requiredBytes = 20GB }
    $minimumFree = [long][math]::Ceiling($requiredBytes * 1.10)
    $systemDrive = $env:SystemDrive.TrimEnd(':')
    $drives = @(Get-LocalBackupDrive |
        Where-Object {
            $_.Free -gt $minimumFree -and
            $_.Name -ne $systemDrive -and
            $_.Name -ne 'Temp'
        } |
        Sort-Object Free -Descending)
    if ($drives.Count -gt 0) {
        return Join-Path $drives[0].Root 'CodexBackups'
    }

    return Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CodexBackups'
}

function Get-KnownBackup {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    $paths = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($State.LastBackupPath)) {
        $paths.Add($State.LastBackupPath)
    }

    $roots = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($State.LastBackupRoot)) {
        $roots.Add($State.LastBackupRoot)
    }
    foreach ($drive in Get-LocalBackupDrive) {
        $roots.Add((Join-Path $drive.Root 'CodexBackups'))
    }

    foreach ($root in @($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        $directories = Get-ChildItem -LiteralPath $root -Directory -Force `
            -ErrorAction SilentlyContinue |
            Where-Object Name -Like 'Codex-preserved-*'
        foreach ($directory in $directories) {
            $manifest = Join-Path $directory.FullName $script:ManifestName
            if (Test-Path -LiteralPath $manifest) {
                $paths.Add($directory.FullName)
            }
        }
    }

    $rows = foreach ($path in @($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            continue
        }
        $manifest = Join-Path $path $script:ManifestName
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            continue
        }
        $item = Get-Item -LiteralPath $manifest
        [pscustomobject]@{
            Path = Get-NormalizedPath $path
            Updated = $item.LastWriteTime
        }
    }

    return @($rows | Sort-Object Updated -Descending)
}

function Select-UiBackup {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    $backups = @(Get-KnownBackup -State $State | Select-Object -First 5)
    if ($backups.Count -eq 0) {
        return Read-UiValue -Prompt 'Enter the full backup path'
    }

    Write-UiText ''
    Write-UiText 'Available backups:' Cyan
    for ($index = 0; $index -lt $backups.Count; $index++) {
        $number = $index + 1
        Write-UiText "  [$number] $($backups[$index].Path)" Gray
    }
    Write-UiText '  [M] Enter another path' Gray
    Write-UiText '  [C] Cancel' DarkGray

    $allowed = @('M', 'C') + @(1..$backups.Count | ForEach-Object { [string] $_ })
    $choice = Read-UiChoice `
        -Prompt 'Select backup' `
        -Allowed $allowed `
        -Default '1'
    if ($choice -eq 'M') {
        return Read-UiValue -Prompt 'Enter the full backup path'
    }
    if ($choice -eq 'C') { return $null }

    return $backups[[int] $choice - 1].Path
}

function Get-UiRecommendation {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    $running = @(Get-CodexProcess).Count -gt 0
    $installed = $null -ne (Get-CodexPackage | Select-Object -First 1)
    $backupAvailable = -not [string]::IsNullOrWhiteSpace($State.LastBackupPath) -and
        (Test-Path -LiteralPath (Join-Path $State.LastBackupPath `
            $script:ManifestName) -PathType Leaf)
    $lastAction = if ($backupAvailable) { $State.LastCompletedAction } else { '' }
    if ($running -and $lastAction -ne 'Restore') {
        return 'Next: close Codex and every helper process before continuing.'
    }
    switch ($lastAction) {
        'Backup' {
            if ($installed) {
                return 'Next: uninstall Codex, restart Windows, then preview cleanup.'
            }
            return 'Next: preview cleanup, then remove the verified local data.'
        }
        'Clean' {
            if (-not $installed) {
                return 'Next: reinstall Codex, launch it once, close it, then restore.'
            }
            return 'Next: close the fresh Codex installation, then preview restore.'
        }
        'Restore' {
            return 'Restore completed. Open Codex and verify several active and archived chats.'
        }
    }

    if ($running) {
        return 'Next: close Codex completely, then create a verified backup.'
    }
    return 'Next: create a verified preservation backup.'
}

function Show-UiSummary {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    $package = Get-CodexPackage | Select-Object -First 1
    $runningCount = @(Get-CodexProcess).Count
    $packageText = if ($null -eq $package) { 'Not installed' } else { [string] $package.Version }
    $processText = if ($runningCount -eq 0) { 'Stopped' } else { "$runningCount running" }
    $backupText = if ([string]::IsNullOrWhiteSpace($State.LastBackupPath)) {
        'None selected'
    }
    else {
        $manifest = Join-Path $State.LastBackupPath $script:ManifestName
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            "$($State.LastBackupPath) (available; verified again before use)"
        }
        else {
            "$($State.LastBackupPath) (missing or unavailable)"
        }
    }

    Write-UiText "Codex package : $packageText" Gray
    Write-UiText "Codex processes: $processText" Gray
    Write-UiText "Last backup   : $backupText" Gray
    Write-UiText "Guidance      : $(Get-UiRecommendation -State $State)" Green
    if ($script:UiStateWarning) { Write-UiText $script:UiStateWarning Yellow }
    Write-UiText ''
}

function Invoke-UiBackup {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    if (@(Get-CodexProcess).Count -gt 0) {
        throw 'Close Codex and all Codex helper processes before starting the backup.'
    }

    $defaultRoot = if ([string]::IsNullOrWhiteSpace($State.LastBackupRoot)) {
        Get-RecommendedBackupRoot
    }
    else {
        $State.LastBackupRoot
    }
    $root = Read-UiValue -Prompt 'Backup parent directory' -Default $defaultRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'A backup parent directory is required.'
    }

    $script:BackupRoot = $root
    $created = Invoke-Backup

    $State.LastBackupRoot = Get-NormalizedPath $root
    $State.LastBackupPath = $created.Directory
    $State.LastCompletedAction = 'Backup'
    Save-UiStateSafely -State $State
    Write-UiText 'Backup saved as the active verified backup.' Green
}

function Invoke-UiVerify {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $State)

    $path = Select-UiBackup -State $State
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-UiText 'Action cancelled.' Yellow
        return
    }
    $script:BackupPath = $path
    Invoke-Verify
    $State.LastBackupPath = Get-NormalizedPath $path
    $State.LastBackupRoot = Split-Path -Parent $State.LastBackupPath
    Save-UiStateSafely -State $State
}

function Invoke-UiClean {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State,
        [switch] $Preview
    )

    $path = Select-UiBackup -State $State
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-UiText 'Action cancelled.' Yellow
        return
    }
    $script:BackupPath = $path
    $removeInstallers = Read-UiChoice `
        -Prompt 'Include downloaded Codex installers? (Y/N)' `
        -Allowed @('Y', 'N') -Default 'N'
    $script:IncludeInstallers = $removeInstallers -eq 'Y'
    if ($Preview) { Invoke-Clean -WhatIf; return }

    Write-UiText ''
    Write-UiText 'This permanently removes the old local Codex profile.' Red
    Write-UiText 'The selected backup will be fully verified first.' Yellow
    $typed = Read-UiValue -Prompt 'Type WIPE-CODEX-LOCAL-DATA to continue'
    if ($typed -ne 'WIPE-CODEX-LOCAL-DATA') {
        throw 'Cleanup cancelled; the confirmation text did not match.'
    }
    $script:Confirmation = $typed
    Invoke-Clean
    $State.LastBackupPath = Get-NormalizedPath $path
    $State.LastCompletedAction = 'Clean'
    Save-UiStateSafely -State $State
}

function Invoke-UiRestore {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $State,
        [switch] $Preview
    )

    $path = Select-UiBackup -State $State
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-UiText 'Action cancelled.' Yellow
        return
    }
    $script:BackupPath = $path
    if ($Preview) {
        Invoke-Restore -WhatIf
        return
    }

    Write-UiText ''
    Write-UiText 'Codex must have been reinstalled, launched once, and closed.' Yellow
    $typed = Read-UiValue -Prompt 'Type RESTORE-CODEX-PRESERVED-DATA to continue'
    if ($typed -ne 'RESTORE-CODEX-PRESERVED-DATA') {
        throw 'Restore cancelled; the confirmation text did not match.'
    }
    $script:Confirmation = $typed
    Invoke-Restore
    $State.LastBackupPath = Get-NormalizedPath $path
    $State.LastCompletedAction = 'Restore'
    Save-UiStateSafely -State $State
}

function Show-UiHelp {
    Write-UiText ''
    Write-UiText 'Safe sequence' Cyan
    Write-UiText '  1. Close Codex and create a verified backup.' Gray
    Write-UiText '  2. Uninstall Codex from Windows Settings and restart.' Gray
    Write-UiText '  3. Preview cleanup, then perform cleanup.' Gray
    Write-UiText '  4. Reinstall Codex, launch it once, and close it.' Gray
    Write-UiText '  5. Preview restore, then restore preserved data.' Gray
    Write-UiText '  6. Inspect active/archived chats, pins, projects, skills, and memories.' Gray
    Write-UiText ''
    Write-UiText 'Preview actions never change files or the registry.' Green
    Write-UiText 'Actual cleanup and restore require exact typed confirmations.' Green
}

function Show-InteractiveUi {
    if ($WhatIfPreference) {
        throw (
            'Interactive mode does not accept top-level -WhatIf. ' +
            'Use the dedicated Preview cleanup/restore menu actions.'
        )
    }
    $state = Get-UiState
    while ($true) {
        Show-UiHeader
        Show-UiSummary -State $state
        Write-UiText '[1] Create and verify backup' White
        Write-UiText '[2] Verify an existing backup' White
        Write-UiText '[3] Preview cleanup (no changes)' White
        Write-UiText '[4] Clean after uninstall' Yellow
        Write-UiText '[5] Preview restore (no changes)' White
        Write-UiText '[6] Restore after reinstall' Yellow
        Write-UiText '[7] Detailed status' White
        Write-UiText '[8] Open Windows Installed Apps' White
        Write-UiText '[9] Help' White
        Write-UiText '[0] Exit' DarkGray
        Write-UiText ''

        $choice = Read-UiChoice `
            -Prompt 'Choose an action' `
            -Allowed @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
        if ($choice -eq '0') {
            return
        }

        try {
            switch ($choice) {
                '1' { Invoke-UiBackup -State $state }
                '2' { Invoke-UiVerify -State $state }
                '3' { Invoke-UiClean -State $state -Preview }
                '4' { Invoke-UiClean -State $state }
                '5' { Invoke-UiRestore -State $state -Preview }
                '6' { Invoke-UiRestore -State $state }
                '7' { Show-Status }
                '8' { Start-Process 'ms-settings:appsfeatures' }
                '9' { Show-UiHelp }
            }
        }
        catch {
            Write-UiText ''
            Write-UiText "Action stopped safely: $($_.Exception.Message)" Red
        }
        Write-UiText ''
        Wait-Ui
        $state = Get-UiState
    }
}
