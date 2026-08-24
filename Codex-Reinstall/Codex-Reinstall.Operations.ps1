#requires -Version 5.1

if (-not (Get-Command Test-BackupManifest -ErrorAction SilentlyContinue)) {
    throw 'Dot-source Codex-Reinstall.ps1 instead of running this component directly.'
}

function Invoke-Backup {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($WhatIfPreference) {
        throw 'Backup does not support -WhatIf; use Status to inspect source scope.'
    }
    if ([string]::IsNullOrWhiteSpace($script:BackupRoot)) {
        throw 'Backup mode requires -BackupRoot on a separate safe location.'
    }

    Assert-CodexStopped
    Assert-NoReparsePoint -Path $script:CodexHome
    $root = Get-NormalizedPath $script:BackupRoot
    Assert-SafeExternalPath $root
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    Assert-NoReparsePoint -Path $root

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $destination = Join-Path $root ($script:BackupPrefix + $timestamp)
    if (Test-Path -LiteralPath $destination) {
        throw "Backup destination already exists: $destination"
    }

    $items = @(Get-PreservedItem)
    if ($items.Count -eq 0) {
        throw 'No preserved Codex files were found.'
    }
    $requiredBytes = [long](($items | ForEach-Object {
        (Get-Item -LiteralPath $_.Source).Length
    } | Measure-Object -Sum).Sum)
    $minimumFree = [long] [math]::Ceiling($requiredBytes * 1.10)
    $freeBytes = Get-FreeByte $root
    if ($freeBytes -lt $minimumFree) {
        throw (
            'Insufficient free space. Need {0}; found {1}.' -f
            (Format-ByteSize $minimumFree),
            (Format-ByteSize $freeBytes)
        )
    }

    Write-Step "Creating backup at $destination"
    [System.IO.Directory]::CreateDirectory($destination) | Out-Null
    try {
        $copiedFiles = @(Copy-PreservedItem `
            -Items $items `
            -Destination $destination)
        $uiLayoutEntry = Add-SanitizedUiLayoutBackup -Destination $destination
        if ($null -ne $uiLayoutEntry) {
            $copiedFiles = @($copiedFiles) + @($uiLayoutEntry)
        }

        Write-Step 'Confirming the complete source snapshot stayed unchanged'
        Assert-PreservedSnapshotStable -Items $items -CopiedFiles $copiedFiles

        # Catch helpers that started or became detectable during the copy.
        Assert-CodexStopped

        Write-Step 'Validating copied SQLite databases'
        $databaseChecks = [System.Collections.Generic.List[object]]::new()
        foreach ($database in Get-IntegrityDatabasePath $destination) {
            Invoke-SqliteCheck -DatabasePath $database | Out-Null
            $relative = Get-RelativePathCompat `
                -BasePath $destination `
                -ChildPath $database
            $databaseChecks.Add([pscustomobject]@{
                relative_path = $relative.Replace('\', '/')
                result = 'ok'
            })
        }

        Write-Manifest `
            -BackupDirectory $destination `
            -Files $copiedFiles `
            -DatabaseChecks @($databaseChecks)

        Write-Step 'Re-verifying manifest, hashes, and databases'
        $verified = Test-BackupManifest -Directory $destination
        $script:LastBackupResult = $verified
        Write-Message 'Backup completed and verified.'
        Write-Message "Path:  $($verified.Directory)"
        Write-Message "Files: $($verified.Files)"
        Write-Message "Size:  $(Format-ByteSize $verified.Bytes)"
        return $verified
    }
    catch {
        Write-Warning "Incomplete backup retained for diagnosis: $destination"
        throw
    }
}

function Invoke-Verify {
    if ([string]::IsNullOrWhiteSpace($script:BackupPath)) {
        throw 'Verify mode requires -BackupPath.'
    }

    Write-Step 'Verifying backup manifest, hashes, and databases'
    $verified = Test-BackupManifest -Directory $script:BackupPath
    Write-Message 'Backup is valid.'
    Write-Message "Path:  $($verified.Directory)"
    Write-Message "Files: $($verified.Files)"
    Write-Message "Size:  $(Format-ByteSize $verified.Bytes)"
}

function Remove-EmptyOpenAIParent {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $extension = Join-Path $env:LOCALAPPDATA 'OpenAI\extension'
    if (Test-Path -LiteralPath $extension -PathType Container) {
        $extensionChildren = @(Get-ChildItem -LiteralPath $extension -Force)
        if ($extensionChildren.Count -eq 0 -and
            $PSCmdlet.ShouldProcess($extension, 'Remove empty directory')) {
            Remove-Item -LiteralPath $extension -Force
        }
    }

    $parent = Join-Path $env:LOCALAPPDATA 'OpenAI'
    if (-not (Test-Path -LiteralPath $parent)) {
        return
    }

    $children = @(Get-ChildItem -LiteralPath $parent -Force)
    if ($children.Count -eq 0 -and $PSCmdlet.ShouldProcess($parent, 'Remove empty directory')) {
        Remove-Item -LiteralPath $parent -Force
    }
}

function Remove-SafeTree {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string] $Path)

    $normalized = Get-NormalizedPath $Path
    $rootItem = Get-Item -LiteralPath $normalized -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($PSCmdlet.ShouldProcess($normalized, 'Remove reparse point only')) {
            Remove-Item -LiteralPath $normalized -Force
        }
        return
    }
    if (-not $rootItem.PSIsContainer) {
        if ($PSCmdlet.ShouldProcess($normalized, 'Remove file')) {
            Remove-Item -LiteralPath $normalized -Force
        }
        return
    }

    # Walk without following links, then unlink reparse points before recursion.
    $pending = [Collections.Generic.Stack[string]]::new()
    $links = [Collections.Generic.List[string]]::new()
    $pending.Push($normalized)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in Get-ChildItem -LiteralPath $directory -Force) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $links.Add($child.FullName)
            }
            elseif ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
        }
    }
    foreach ($link in $links) {
        if ($PSCmdlet.ShouldProcess($link, 'Remove nested reparse point only')) {
            Remove-Item -LiteralPath $link -Force
        }
    }
    if ($PSCmdlet.ShouldProcess($normalized, 'Remove recursively')) {
        Remove-Item -LiteralPath $normalized -Recurse -Force
    }
}

function Invoke-Clean {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ([string]::IsNullOrWhiteSpace($script:BackupPath)) {
        throw 'Clean mode requires -BackupPath.'
    }

    Assert-CodexStopped
    $package = Get-CodexPackage
    if ($null -ne $package) {
        throw 'Codex is still installed. Uninstall it from Windows Settings first.'
    }

    Write-Step 'Verifying the preservation backup before cleanup'
    $verified = Test-BackupManifest -Directory $script:BackupPath
    $backupDirectory = $verified.Directory
    Assert-SafeExternalPath $backupDirectory

    if (
        -not $WhatIfPreference -and
        $script:Confirmation -ne 'WIPE-CODEX-LOCAL-DATA'
    ) {
        throw (
            'Cleanup requires -Confirmation WIPE-CODEX-LOCAL-DATA. ' +
            'Use -WhatIf first to inspect the targets.'
        )
    }

    Write-Step 'Removing exact Codex data targets'
    foreach ($target in Get-CleanupTarget) {
        $normalized = Get-NormalizedPath $target
        if (Test-PathInside -Candidate $backupDirectory -Parent $normalized) {
            throw "Refusing to delete a target containing the backup: $normalized"
        }
        if (Test-Path -LiteralPath $normalized) {
            Remove-SafeTree -Path $normalized -WhatIf:$WhatIfPreference
        }
    }

    $registryKeys = @(
        'HKCU:\Software\Classes\codex',
        'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension',
        'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.openai.codexextension'
    )
    foreach ($key in $registryKeys) {
        if (Test-Path -LiteralPath $key) {
            if ($PSCmdlet.ShouldProcess($key, 'Remove registry key')) {
                Remove-Item -LiteralPath $key -Recurse -Force
            }
        }
    }

    if ($script:IncludeInstallers) {
        $downloads = Join-Path $env:USERPROFILE 'Downloads'
        $installers = Get-ChildItem -LiteralPath $downloads -File -Force `
            -ErrorAction SilentlyContinue |
            Where-Object Name -Match '(?i)Codex.*\.(exe|msix|appx)(bundle)?$'
        foreach ($installer in $installers) {
            if ($PSCmdlet.ShouldProcess($installer.FullName, 'Remove installer')) {
                Remove-Item -LiteralPath $installer.FullName -Force
            }
        }
    }

    Remove-EmptyOpenAIParent
    if ($WhatIfPreference) {
        Write-Message 'WhatIf completed; nothing was removed.'
    }
    else {
        Write-Message 'Codex local cleanup completed.'
        Write-Message "Verified backup remains at: $backupDirectory"
    }
}

function Compare-AppVersion {
    param(
        [string] $BackupVersion,
        [string] $InstalledVersion
    )

    if (-not $BackupVersion -or -not $InstalledVersion) {
        return
    }

    try {
        if ([version] $InstalledVersion -lt [version] $BackupVersion) {
            throw (
                "Installed Codex $InstalledVersion is older than backup version " +
                "$BackupVersion. Install the same or a newer Codex build."
            )
        }
    }
    catch [System.Management.Automation.RuntimeException] {
        throw
    }
    catch {
        Write-Warning 'Could not compare installed and backup Codex versions.'
    }
}

function Invoke-Restore {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ([string]::IsNullOrWhiteSpace($script:BackupPath)) {
        throw 'Restore mode requires -BackupPath.'
    }

    Assert-CodexStopped
    $package = Get-CodexPackage | Select-Object -First 1
    if ($null -eq $package) {
        throw 'Install and launch Codex once before restoring preserved data.'
    }

    Write-Step 'Verifying backup before restoration'
    $verified = Test-BackupManifest -Directory $script:BackupPath
    Compare-AppVersion `
        -BackupVersion ([string] $verified.Manifest.codex_app_version) `
        -InstalledVersion ([string] $package.Version)

    if (
        -not $WhatIfPreference -and
        $script:Confirmation -ne 'RESTORE-CODEX-PRESERVED-DATA'
    ) {
        throw (
            'Restore requires -Confirmation RESTORE-CODEX-PRESERVED-DATA. ' +
            'Use -WhatIf first to inspect the files.'
        )
    }

    $restoreEntries = @($verified.Manifest.files | Where-Object restore -EQ $true)
    $restorePlan = [Collections.Generic.List[object]]::new()
    foreach ($entry in $restoreEntries) {
        $relative = Assert-SafeRelativePath ([string] $entry.relative_path)
        $restoreRelative = Assert-SafeRelativePath `
            ([string] $entry.restore_relative_path)

        # Fresh built-in system skills should win over backed-up built-ins.
        if ($restoreRelative -match '^skills\\\.system([\\]|$)') {
            continue
        }

        $source = Get-NormalizedPath (Join-Path $verified.Directory $relative)
        $destination = Get-NormalizedPath (Join-Path $script:CodexHome $restoreRelative)
        if (-not (Test-PathInside -Candidate $source -Parent $verified.Directory)) {
            throw "Unsafe restore source: $relative"
        }
        if (-not (Test-PathInside -Candidate $destination -Parent $script:CodexHome)) {
            throw "Unsafe restore destination: $restoreRelative"
        }
        Assert-NoReparsePoint -Path $source -Boundary $verified.Directory
        $existingParent = Split-Path -Parent $destination
        while ($existingParent -and -not (Test-Path -LiteralPath $existingParent)) {
            $existingParent = Split-Path -Parent $existingParent
        }
        if ($existingParent) { Assert-NoReparsePoint -Path $existingParent }
        $restorePlan.Add([pscustomobject]@{
            Source = $source
            Destination = $destination
            RestoreRelative = $restoreRelative
            Bytes = [long] $entry.bytes
            Sha256 = [string] $entry.sha256
            Strategy = if ($entry.PSObject.Properties['restore_strategy']) {
                [string] $entry.restore_strategy
            }
            else { 'copy' }
        })
    }

    if ($WhatIfPreference) {
        $PSCmdlet.ShouldProcess(
            $script:CodexHome,
            "Transactionally restore $($restorePlan.Count) preserved files"
        ) | Out-Null
        Write-Message 'WhatIf completed; nothing was restored.'
        return
    }

    $restoreBytes = [long](($restorePlan | Measure-Object Bytes -Sum).Sum)
    $homeParent = Split-Path -Parent $script:CodexHome
    $preflightTargets = [Collections.Generic.List[string]]::new()
    foreach ($plan in $restorePlan) { $preflightTargets.Add($plan.Destination) }
    foreach ($plan in @($restorePlan | Where-Object {
        $_.Destination -match '\.(sqlite|sqlite3|db)$'
    })) {
        foreach ($suffix in @('-wal', '-shm')) {
            $sidecar = $plan.Destination + $suffix
            if (-not ($preflightTargets -contains $sidecar) -and
                (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
                $preflightTargets.Add($sidecar)
            }
        }
    }
    $existingBytes = [long] 0
    foreach ($target in @($preflightTargets | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Assert-NoReparsePoint -Path $target -Boundary $script:CodexHome
            $existingBytes += [long](Get-Item -LiteralPath $target -Force).Length
        }
    }
    $minimumRestoreFree = [long][math]::Ceiling($restoreBytes * 1.10)
    $minimumRollbackFree = [long][math]::Ceiling($existingBytes * 1.10)
    Assert-NoReparsePoint -Path $env:TEMP
    $homeRoot = [IO.Path]::GetPathRoot((Get-NormalizedPath $homeParent))
    $tempRoot = [IO.Path]::GetPathRoot((Get-NormalizedPath $env:TEMP))
    if ($homeRoot.Equals($tempRoot, 'OrdinalIgnoreCase')) {
        if ((Get-FreeByte $homeParent) -lt `
            ($minimumRestoreFree + $minimumRollbackFree)) {
            throw 'Insufficient shared free space for restore and rollback copies.'
        }
    }
    else {
        if ((Get-FreeByte $homeParent) -lt $minimumRestoreFree) {
            throw 'Insufficient free space on the restore drive.'
        }
        if ((Get-FreeByte $env:TEMP) -lt $minimumRollbackFree) {
            throw 'Insufficient free space for rollback copies on the temporary drive.'
        }
    }
    if (-not $PSCmdlet.ShouldProcess(
        $script:CodexHome,
        "Transactionally restore $($restorePlan.Count) preserved files"
    )) { return }

    Assert-CodexStopped
    $rollbackRoot = Join-Path $env:TEMP `
        ('Codex-Reinstall-Rollback-' + [guid]::NewGuid().ToString('N'))
    $rollbackItems = [Collections.Generic.List[object]]::new()
    $removeRollback = $false
    [IO.Directory]::CreateDirectory($rollbackRoot) | Out-Null
    Assert-NoReparsePoint -Path $rollbackRoot -Boundary $env:TEMP
    try {
        [IO.Directory]::CreateDirectory($script:CodexHome) | Out-Null
        Assert-NoReparsePoint -Path $script:CodexHome

        # A database family is atomic: stale sidecars absent from the backup are removed.
        foreach ($target in @($preflightTargets | Select-Object -Unique)) {
            $relativeTarget = Get-RelativePathCompat `
                -BasePath $script:CodexHome -ChildPath $target
            $rollback = Join-Path $rollbackRoot $relativeTarget
            $existed = Test-Path -LiteralPath $target -PathType Leaf
            if ($existed) {
                Assert-NoReparsePoint -Path $target -Boundary $script:CodexHome
                [IO.Directory]::CreateDirectory((Split-Path -Parent $rollback)) |
                    Out-Null
                [IO.File]::Copy($target, $rollback, $true)
                $originalHash = (Get-FileHash -LiteralPath $target `
                    -Algorithm SHA256).Hash
                $rollbackHash = (Get-FileHash -LiteralPath $rollback `
                    -Algorithm SHA256).Hash
                if (-not $rollbackHash.Equals($originalHash, 'OrdinalIgnoreCase')) {
                    throw "Rollback copy hash mismatch: $relativeTarget"
                }
            }
            $rollbackItems.Add([pscustomobject]@{
                Target = $target; Rollback = $rollback; Existed = $existed
            })
        }

        foreach ($plan in $restorePlan) {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $plan.Destination)) |
                Out-Null
            $expectedHash = $plan.Sha256
            if ($plan.Strategy -eq 'merge-ui-layout') {
                $layout = Get-Content -LiteralPath $plan.Source -Raw |
                    ConvertFrom-Json
                $fresh = if (Test-Path -LiteralPath $plan.Destination -PathType Leaf) {
                    Get-Content -LiteralPath $plan.Destination -Raw | ConvertFrom-Json
                }
                else { [pscustomobject]@{} }
                foreach ($key in $script:UiLayoutKeys) {
                    $property = $layout.PSObject.Properties[$key]
                    if ($null -ne $property) {
                        $fresh | Add-Member -NotePropertyName $key `
                            -NotePropertyValue $property.Value -Force
                    }
                }
                $merged = Join-Path $rollbackRoot `
                    ('merged-' + [guid]::NewGuid().ToString('N') + '.json')
                [IO.File]::WriteAllText($merged, ($fresh | ConvertTo-Json -Depth 20),
                    [Text.UTF8Encoding]::new($false))
                $expectedHash = (Get-FileHash -LiteralPath $merged `
                    -Algorithm SHA256).Hash
                [IO.File]::Copy($merged, $plan.Destination, $true)
            }
            else {
                [IO.File]::Copy($plan.Source, $plan.Destination, $true)
            }
            $restoredHash = (Get-FileHash -LiteralPath $plan.Destination `
                -Algorithm SHA256).Hash
            if (-not $restoredHash.Equals($expectedHash, 'OrdinalIgnoreCase')) {
                throw "Restored file hash mismatch: $($plan.RestoreRelative)"
            }
        }
        foreach ($item in $rollbackItems | Where-Object {
            $_.Existed -and -not ($restorePlan.Destination -contains $_.Target)
        }) {
            Remove-Item -LiteralPath $item.Target -Force
        }
        Assert-CodexStopped
        $removeRollback = $true
    }
    catch {
        $failure = $_
        $rollbackErrors = [Collections.Generic.List[string]]::new()
        foreach ($item in @($rollbackItems) | Sort-Object Target -Descending) {
            try {
                if ($item.Existed) {
                    if (-not (Test-Path -LiteralPath $item.Rollback -PathType Leaf)) {
                        throw "Rollback source is missing: $($item.Rollback)"
                    }
                    [IO.Directory]::CreateDirectory((Split-Path -Parent $item.Target)) |
                        Out-Null
                    [IO.File]::Copy($item.Rollback, $item.Target, $true)
                }
                elseif (Test-Path -LiteralPath $item.Target -PathType Leaf) {
                    Remove-Item -LiteralPath $item.Target -Force
                }
            }
            catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        if ($rollbackErrors.Count -gt 0) {
            throw (
                "Restore failed: $($failure.Exception.Message). Rollback also failed: " +
                "$($rollbackErrors -join '; '). Recovery data remains at $rollbackRoot"
            )
            }
        $removeRollback = $true
        throw "Restore failed and was rolled back: $($failure.Exception.Message)"
    }
    finally {
        if ($removeRollback -and (Test-Path -LiteralPath $rollbackRoot)) {
            try { Remove-Item -LiteralPath $rollbackRoot -Recurse -Force }
            catch { Write-Warning "Temporary rollback data remains at $rollbackRoot" }
        }
    }

    Write-Message 'Preserved Codex data restored and hash-verified.'
    Write-Message 'Start Codex and allow it to migrate the restored databases.'
}

function Show-Status {
    Write-Step 'Codex reinstall status'
    $package = Get-CodexPackage | Select-Object -First 1
    if ($null -eq $package) {
        Write-Message 'Installed package: not found'
    }
    else {
        Write-Message "Installed package: $($package.PackageFullName)"
    }

    $processes = @(Get-CodexProcess)
    if ($processes.Count -eq 0) {
        Write-Message 'Running processes: none'
    }
    else {
        Write-Message 'Running processes:'
        $processes | Select-Object ProcessName, Id, Path | Format-Table -AutoSize
    }

    Write-Message 'Cleanup targets:'
    $rows = foreach ($target in Get-CleanupTarget) {
        $exists = Test-Path -LiteralPath $target
        $bytes = [long] 0
        if ($exists) {
            $item = Get-Item -LiteralPath $target -Force
            if ($item.PSIsContainer) {
                $sum = Get-SafeTreeFile -Path $target |
                    Measure-Object Length -Sum
                if ($null -ne $sum.Sum) {
                    $bytes = [long] $sum.Sum
                }
            }
            else {
                $bytes = $item.Length
            }
        }
        [pscustomobject]@{
            Exists = $exists
            Size = Format-ByteSize $bytes
            Path = $target
        }
    }
    $rows | Format-Table -AutoSize

    Write-Message @'

Workflow:
  1. Close Codex, then run Backup.
  2. Uninstall Codex from Windows Settings and restart Windows.
  3. Run Clean with -WhatIf, then with the cleanup confirmation token.
  4. Reinstall and launch Codex once, then close it.
  5. Run Restore with -WhatIf, then with the restore confirmation token.
'@
}
