#requires -Version 5.1

<#
.SYNOPSIS
Backs up, verifies, cleans, and restores selected Codex data on Windows.

.DESCRIPTION
Preserves active and archived chats, associated media, task databases, skills,
memories, and config.toml. Authentication, plugins, caches, logs, sandbox binaries,
installation identity, and global UI state are intentionally not restored.

Backup and restore require Codex to be completely stopped. Clean also requires
the OpenAI.Codex Windows package to have been uninstalled. Every destructive
mode verifies the external backup first and requires an explicit token.
Run without arguments to open the guided terminal interface.

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Status

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Backup -BackupRoot 'E:\CodexBackups'

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Verify `
    -BackupPath 'E:\CodexBackups\Codex-preserved-20260824-090000'

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Clean `
    -BackupPath 'E:\CodexBackups\Codex-preserved-20260824-090000' `
    -WhatIf

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Clean `
    -BackupPath 'E:\CodexBackups\Codex-preserved-20260824-090000' `
    -Confirmation WIPE-CODEX-LOCAL-DATA

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Restore `
    -BackupPath 'E:\CodexBackups\Codex-preserved-20260824-090000' `
    -WhatIf

.EXAMPLE
.\Codex-Reinstall.ps1 -Mode Restore `
    -BackupPath 'E:\CodexBackups\Codex-preserved-20260824-090000' `
    -Confirmation RESTORE-CODEX-PRESERVED-DATA
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Interactive', 'Status', 'Backup', 'Verify', 'Clean', 'Restore')]
    [string] $Mode = 'Interactive',

    [string] $BackupRoot,

    [string] $BackupPath,

    [string] $Confirmation,

    [switch] $IncludeInstallers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SchemaVersion = 3
$script:ToolId = 'OpenAI-Codex-Reinstall-Toolkit'
$script:CodexHome = Join-Path $env:USERPROFILE '.codex'
$script:PackageFamily = 'OpenAI.Codex_2p2nqsd0c76g0'
$script:ManifestName = 'codex-preserved-manifest.json'
$script:BackupPrefix = 'Codex-preserved-'
$script:BackupRoot = $BackupRoot
$script:BackupPath = $BackupPath
$script:Confirmation = $Confirmation
$script:IncludeInstallers = $IncludeInstallers
$script:UiLayoutKeys = @(
    'pinned-thread-ids',
    'pinned-project-ids',
    'local-projects',
    'project-order',
    'sidebar-project-thread-orders',
    'thread-project-assignments'
)

function Write-Message {
    param([Parameter(Mandatory)][string] $Message)

    Write-Information $Message -InformationAction Continue
}

function Write-Step {
    param([Parameter(Mandatory)][string] $Message)

    Write-Message "`n==> $Message"
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string] $Path)

    $full = [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    )
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        return $full.TrimEnd('\', '/')
    }
    return $full
}

function Test-PathInside {
    param(
        [Parameter(Mandatory)][string] $Candidate,
        [Parameter(Mandatory)][string] $Parent
    )

    $candidatePath = Get-NormalizedPath $Candidate
    $parentPath = Get-NormalizedPath $Parent
    $prefix = $parentPath.TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar

    return $candidatePath.Equals(
        $parentPath,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -or $candidatePath.StartsWith(
        $prefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-IsCodexProcess {
    param([Parameter(Mandatory)][object] $Process)

    $path = $null
    try { $path = $Process.Path } catch { $path = $null }
    return (
        $Process.ProcessName -match '(?i)^codex(?:$|-)' -or
        ($Process.ProcessName -eq 'ChatGPT' -and -not $path) -or
        ($path -and $path -match '(?i)[\\/]OpenAI\.Codex_[^\\/]+[\\/]') -or
        ($path -and $path -match '(?i)[\\/]OpenAI[\\/]Codex[\\/]')
    )
}

function Get-CodexProcess {
    $processes = Get-Process -ErrorAction SilentlyContinue
    $processMatches = foreach ($process in $processes) {
        if (Test-IsCodexProcess $process) {
            $process
        }
    }

    return @($processMatches)
}

function Assert-CodexStopped {
    $processes = @(Get-CodexProcess)
    if ($processes.Count -eq 0) {
        return
    }

    $details = $processes | ForEach-Object {
        "{0} (PID {1})" -f $_.ProcessName, $_.Id
    }
    throw (
        "Codex is still running: {0}. Close Codex completely and retry." -f
        ($details -join ', ')
    )
}

function Get-CodexPackage {
    return Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
}

function Get-CleanupTarget {
    $targets = [System.Collections.Generic.List[string]]::new()
    $targets.Add($script:CodexHome)
    $targets.Add((Join-Path $env:APPDATA 'Codex'))
    $targets.Add((Join-Path $env:LOCALAPPDATA 'Codex'))
    $targets.Add((Join-Path $env:LOCALAPPDATA 'OpenAI\Codex'))
    $extensionRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\extension'
    $targets.Add((Join-Path $extensionRoot 'com.openai.codexextension.json'))
    if (Test-Path -LiteralPath $extensionRoot -PathType Container) {
        foreach ($hostFile in Get-ChildItem -LiteralPath $extensionRoot -File `
            -Force -ErrorAction SilentlyContinue | Where-Object Name -Like `
            'com.openai.codexextension*.json') {
            $targets.Add($hostFile.FullName)
        }
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        $packageData = Get-ChildItem -LiteralPath $packagesRoot -Directory -Force |
            Where-Object Name -Like 'OpenAI.Codex_*'
        foreach ($directory in $packageData) {
            $targets.Add($directory.FullName)
        }
    }

    return @($targets | Select-Object -Unique)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $Boundary
    )

    $current = Get-NormalizedPath $Path
    $stop = if ($Boundary) { Get-NormalizedPath $Boundary } else { $null }
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not allowed in protected paths: $current"
            }
        }
        if ($stop -and $current.Equals($stop, 'OrdinalIgnoreCase')) { break }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Get-SafeTreeFile {
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch] $RejectReparsePoint
    )

    $files = [Collections.Generic.List[object]]::new()
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push((Get-NormalizedPath $Path))
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in Get-ChildItem -LiteralPath $directory -Force `
            -ErrorAction Stop) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                if ($RejectReparsePoint) {
                    throw "Protected tree contains a reparse point: $($child.FullName)"
                }
                continue
            }
            if ($child.PSIsContainer) { $pending.Push($child.FullName) }
            else { $files.Add($child) }
        }
    }
    return @($files)
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory)][string] $Path)

    if (
        [string]::IsNullOrWhiteSpace($Path) -or
        [IO.Path]::IsPathRooted($Path) -or
        $Path -match ':'
    ) {
        throw "Unsafe relative path: $Path"
    }
    $normalized = $Path.Replace('/', '\')
    $segments = @($normalized -split '\\')
    if ($segments | Where-Object {
        $_ -in @('', '.', '..') -or $_ -ne $_.TrimEnd(' ', '.')
    }) {
        throw "Unsafe relative path: $Path"
    }
    return $normalized
}

function Assert-SafeExternalPath {
    param([Parameter(Mandatory)][string] $Path)

    $normalized = Get-NormalizedPath $Path
    Assert-NoReparsePoint -Path $normalized
    foreach ($target in Get-CleanupTarget) {
        if (
            (Test-PathInside -Candidate $normalized -Parent $target) -or
            (Test-PathInside -Candidate $target -Parent $normalized)
        ) {
            throw "Backup path overlaps cleanup target: $target"
        }
    }

    $scriptPath = Get-NormalizedPath $PSCommandPath
    if (Test-PathInside -Candidate $scriptPath -Parent $normalized) {
        Write-Warning 'The script is inside the backup tree; keep another script copy too.'
    }
}

function Get-AppVersionText {
    $package = Get-CodexPackage | Select-Object -First 1
    if ($null -eq $package) {
        return $null
    }

    return [string] $package.Version
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory)][string] $BasePath,
        [Parameter(Mandatory)][string] $ChildPath
    )

    $base = Get-NormalizedPath $BasePath
    $child = Get-NormalizedPath $ChildPath
    if (-not (Test-PathInside -Candidate $child -Parent $base)) {
        throw "Path is outside expected root: $child"
    }

    if ($child.Length -eq $base.Length) {
        return ''
    }

    return $child.Substring($base.Length + 1)
}

function Add-DirectoryFile {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $Items,

        [Parameter(Mandatory)][string] $RelativeDirectory,

        [Parameter(Mandatory)][string] $BackupPrefix
    )

    $sourceDirectory = Join-Path $script:CodexHome $RelativeDirectory
    if (-not (Test-Path -LiteralPath $sourceDirectory)) {
        return
    }

    Assert-NoReparsePoint -Path $sourceDirectory -Boundary $script:CodexHome
    $files = Get-SafeTreeFile -Path $sourceDirectory -RejectReparsePoint
    foreach ($file in $files) {
        $relative = Get-RelativePathCompat `
            -BasePath $script:CodexHome `
            -ChildPath $file.FullName
        $Items.Add([pscustomobject]@{
            Source = $file.FullName
            Relative = Join-Path $BackupPrefix $relative
            RestoreRelative = $relative
            Restore = $true
        })
    }
}

function Add-MatchingRootFile {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $Items,

        [Parameter(Mandatory)][string] $Pattern,

        [Parameter(Mandatory)][string] $BackupPrefix,

        [bool] $Restore
    )

    if (-not (Test-Path -LiteralPath $script:CodexHome)) {
        return
    }

    $files = Get-ChildItem -LiteralPath $script:CodexHome -File -Force |
        Where-Object Name -Match $Pattern
    foreach ($file in $files) {
        $Items.Add([pscustomobject]@{
            Source = $file.FullName
            Relative = Join-Path $BackupPrefix $file.Name
            RestoreRelative = $file.Name
            Restore = $Restore
        })
    }
}

function Get-PreservedItem {
    if (-not (Test-Path -LiteralPath $script:CodexHome)) {
        throw "Codex data directory does not exist: $script:CodexHome"
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $directories = @(
        'sessions',
        'archived_sessions',
        'attachments',
        'generated_images',
        'visualizations',
        'skills',
        'memories'
    )
    foreach ($directory in $directories) {
        Add-DirectoryFile `
            -Items $items `
            -RelativeDirectory $directory `
            -BackupPrefix 'payload'
    }

    $singleFiles = @('session_index.jsonl', 'config.toml')
    foreach ($name in $singleFiles) {
        $source = Join-Path $script:CodexHome $name
        if (Test-Path -LiteralPath $source) {
            $items.Add([pscustomobject]@{
                Source = $source
                Relative = Join-Path 'payload' $name
                RestoreRelative = $name
                Restore = $true
            })
        }
    }

    # Preserve every root task database as a restorable family, including WAL/SHM.
    Add-MatchingRootFile `
        -Items $items `
        -Pattern '^(?!logs(?:_|\.|\d)).*\.(sqlite|sqlite3|db)(?:-wal)?$' `
        -BackupPrefix 'payload' `
        -Restore $true

    $sqliteDirectory = Join-Path $script:CodexHome 'sqlite'
    if (Test-Path -LiteralPath $sqliteDirectory) {
        Assert-NoReparsePoint -Path $sqliteDirectory -Boundary $script:CodexHome
        $databaseFiles = Get-SafeTreeFile -Path $sqliteDirectory `
            -RejectReparsePoint | Where-Object {
                $_.Name -match '\.(sqlite|sqlite3|db)(?:-wal)?$' -and
                $_.Name -notmatch '^logs(?:_|\.|\d)'
            }
        foreach ($file in $databaseFiles) {
            $relative = Get-RelativePathCompat -BasePath $sqliteDirectory `
                -ChildPath $file.FullName
            $items.Add([pscustomobject]@{
                Source = $file.FullName
                Relative = Join-Path 'payload\sqlite' $relative
                RestoreRelative = Join-Path 'sqlite' $relative
                Restore = $true
            })
        }
    }

    Add-MatchingRootFile `
        -Items $items `
        -Pattern '\.(sqlite|sqlite3|db)(?:-wal)?$' `
        -BackupPrefix 'database-insurance\root' `
        -Restore $false

    if (Test-Path -LiteralPath $sqliteDirectory) {
        $databaseFiles = Get-SafeTreeFile -Path $sqliteDirectory `
            -RejectReparsePoint |
            Where-Object Name -Match '\.(sqlite|sqlite3|db)(?:-wal)?$'
        foreach ($file in $databaseFiles) {
            $relative = Get-RelativePathCompat `
                -BasePath $sqliteDirectory `
                -ChildPath $file.FullName
            $items.Add([pscustomobject]@{
                Source = $file.FullName
                Relative = Join-Path 'database-insurance\sqlite' $relative
                RestoreRelative = $null
                Restore = $false
            })
        }
    }

    return @($items | Sort-Object Relative -Unique)
}

function Get-FreeByte {
    param([Parameter(Mandatory)][string] $Path)

    $normalized = Get-NormalizedPath $Path
    if ($normalized.StartsWith('\\')) {
        throw 'UNC backup roots are not supported because free space cannot be verified reliably.'
    }
    $root = [System.IO.Path]::GetPathRoot($normalized)
    try {
        $drive = [System.IO.DriveInfo]::new($root)
        if (-not $drive.IsReady) { throw "Drive is not ready: $root" }
        return $drive.AvailableFreeSpace
    }
    catch {
        throw "Could not determine free space for $root`: $($_.Exception.Message)"
    }
}

function Format-ByteSize {
    param([Parameter(Mandatory)][long] $Bytes)

    if ($Bytes -ge 1TB) {
        return '{0:N2} TiB' -f ($Bytes / 1TB)
    }
    if ($Bytes -ge 1GB) {
        return '{0:N2} GiB' -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB) {
        return '{0:N2} MiB' -f ($Bytes / 1MB)
    }
    return "$Bytes bytes"
}

function Copy-PreservedItem {
    param(
        [Parameter(Mandatory)][object[]] $Items,
        [Parameter(Mandatory)][string] $Destination
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $count = $Items.Count
    for ($index = 0; $index -lt $count; $index++) {
        $item = $Items[$index]
        Assert-NoReparsePoint -Path $item.Source -Boundary $script:CodexHome
        $sourceBefore = Get-Item -LiteralPath $item.Source -Force
        $sourceLength = [long] $sourceBefore.Length
        $sourceWriteTime = $sourceBefore.LastWriteTimeUtc
        $sourceHashBefore = (Get-FileHash -LiteralPath $item.Source `
            -Algorithm SHA256).Hash
        $percent = [math]::Floor((($index + 1) / $count) * 100)
        Write-Progress `
            -Activity 'Copying preserved Codex data' `
            -Status $item.Relative `
            -PercentComplete $percent

        $destinationFile = Join-Path $Destination $item.Relative
        $destinationDirectory = Split-Path -Parent $destinationFile
        [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
        [System.IO.File]::Copy($item.Source, $destinationFile, $true)

        $copied = Get-Item -LiteralPath $destinationFile -Force
        $sourceAfter = Get-Item -LiteralPath $item.Source -Force
        $sourceHashAfter = (Get-FileHash -LiteralPath $item.Source `
            -Algorithm SHA256).Hash
        if (
            $copied.Length -ne $sourceLength -or
            $sourceAfter.Length -ne $sourceLength -or
            $sourceAfter.LastWriteTimeUtc -ne $sourceWriteTime -or
            -not $sourceHashAfter.Equals($sourceHashBefore, 'OrdinalIgnoreCase')
        ) {
            throw "Source changed while being backed up: $($item.Source)"
        }

        $hash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash
        if (-not $hash.Equals($sourceHashBefore, 'OrdinalIgnoreCase')) {
            throw "Copied file hash mismatch: $($item.Relative)"
        }
        $results.Add([pscustomobject]@{
            relative_path = $item.Relative.Replace('\', '/')
            restore_relative_path = if ($item.RestoreRelative) {
                $item.RestoreRelative.Replace('\', '/')
            }
            else {
                $null
            }
            restore = [bool] $item.Restore
            bytes = [long] $copied.Length
            sha256 = $hash
        })
    }
    Write-Progress -Activity 'Copying preserved Codex data' -Completed

    return @($results)
}

function Assert-PreservedSnapshotStable {
    param(
        [Parameter(Mandatory)][object[]] $Items,
        [Parameter(Mandatory)][object[]] $CopiedFiles
    )

    $copiedByRelative = @{}
    foreach ($file in $CopiedFiles) {
        $copiedByRelative[[string] $file.relative_path] = [string] $file.sha256
    }
    foreach ($sourceGroup in $Items | Group-Object Source) {
        $currentHash = (Get-FileHash -LiteralPath $sourceGroup.Name `
            -Algorithm SHA256).Hash
        foreach ($item in $sourceGroup.Group) {
            $relative = $item.Relative.Replace('\', '/')
            $expectedHash = $copiedByRelative[$relative]
            if (-not $currentHash.Equals($expectedHash, 'OrdinalIgnoreCase')) {
                throw "Source changed during the backup snapshot: $($sourceGroup.Name)"
            }
        }
    }
}

function Add-SanitizedUiLayoutBackup {
    param([Parameter(Mandatory)][string] $Destination)

    $source = Join-Path $script:CodexHome '.codex-global-state.json'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return $null }
    Assert-NoReparsePoint -Path $source -Boundary $script:CodexHome
    $globalState = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
    $layout = [ordered]@{}
    foreach ($key in $script:UiLayoutKeys) {
        $property = $globalState.PSObject.Properties[$key]
        if ($null -ne $property) { $layout[$key] = $property.Value }
    }
    if ($layout.Count -eq 0) { return $null }

    $relative = 'payload\ui-layout.json'
    $path = Join-Path $Destination $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, ($layout | ConvertTo-Json -Depth 20),
        [Text.UTF8Encoding]::new($false))
    $file = Get-Item -LiteralPath $path -Force
    return [pscustomobject]@{
        relative_path = $relative.Replace('\', '/')
        restore_relative_path = '.codex-global-state.json'
        restore = $true
        restore_strategy = 'merge-ui-layout'
        bytes = [long] $file.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
}

function Invoke-SqliteCheck {
    param([Parameter(Mandatory)][string] $DatabasePath)

    $sqlite = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($null -eq $sqlite) {
        $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
    }
    if ($null -eq $sqlite) {
        throw 'sqlite3 is required to validate the preserved databases.'
    }

    $sharedMemory = "$DatabasePath-shm"
    try {
        $output = & $sqlite.Source -readonly $DatabasePath `
            'PRAGMA integrity_check;' 2>&1
        if ($LASTEXITCODE -ne 0 -or ($output -join '').Trim() -ne 'ok') {
            throw "SQLite integrity check failed for $DatabasePath`: $output"
        }
    }
    finally {
        # SQLite may create or rewrite this volatile WAL index even in readonly mode.
        if (Test-Path -LiteralPath $sharedMemory -PathType Leaf) {
            Remove-Item -LiteralPath $sharedMemory -Force
        }
    }

    return 'ok'
}

function Get-IntegrityDatabasePath {
    param([Parameter(Mandatory)][string] $BackupDirectory)

    $databases = foreach ($file in Get-SafeTreeFile -Path $BackupDirectory `
        -RejectReparsePoint) {
        if ($file.Name -notmatch '\.(sqlite|sqlite3|db)$') { continue }
        $relative = (Get-RelativePathCompat -BasePath $BackupDirectory `
            -ChildPath $file.FullName).Replace('/', '\')
        if (
            $relative -match '^payload\\[^\\]+\.(sqlite|sqlite3|db)$' -or
            $relative -match '^payload\\sqlite\\.+\.(sqlite|sqlite3|db)$' -or
            $relative -match '^database-insurance\\(root|sqlite)\\.+\.(sqlite|sqlite3|db)$'
        ) {
            $file.FullName
        }
    }
    return @($databases | Select-Object -Unique)
}

function Write-Manifest {
    param(
        [Parameter(Mandatory)][string] $BackupDirectory,
        [Parameter(Mandatory)][object[]] $Files,
        [Parameter(Mandatory)][object[]] $DatabaseChecks
    )

    $manifest = [ordered]@{
        tool_id = $script:ToolId
        schema_version = $script:SchemaVersion
        scope = 'codex-preserved-profile-v3'
        created_utc = [DateTime]::UtcNow.ToString('o')
        source_computer = $env:COMPUTERNAME
        source_user = $env:USERNAME
        source_codex_home = $script:CodexHome
        codex_app_version = Get-AppVersionText
        file_count = $Files.Count
        total_bytes = [long](($Files | Measure-Object bytes -Sum).Sum)
        preserved = @(
            'active and archived chats and media',
            'task and history databases',
            'database insurance copy',
            'skills',
            'memories',
            'config.toml'
        )
        intentionally_excluded = @(
            'auth.json',
            'global UI state except pinned/project sidebar layout',
            'plugins',
            'caches and restorable logs (log databases remain insurance-only)',
            'sandbox and runtime binaries',
            'installation identity'
        )
        coverage = [ordered]@{
            config = @($Files | Where-Object relative_path -EQ `
                'payload/config.toml').Count
            active_chats = @($Files | Where-Object relative_path -Match `
                '^payload/sessions/').Count
            archived_chats = @($Files | Where-Object relative_path -Match `
                '^payload/archived_sessions/').Count
            skills = @($Files | Where-Object relative_path -Match `
                '^payload/skills/(?!\.system(?:/|$))').Count
            memories = @($Files | Where-Object relative_path -Match `
                '^payload/memories/').Count
            restorable_databases = @($Files | Where-Object {
                $_.restore -and $_.relative_path -match `
                    '\.(sqlite|sqlite3|db)(?:-wal)?$'
            }).Count
            ui_layout = @($Files | Where-Object {
                $_.PSObject.Properties['restore_strategy'] -and
                $_.restore_strategy -eq 'merge-ui-layout'
            }).Count
        }
        database_integrity = $DatabaseChecks
        files = $Files
    }

    $manifestPath = Join-Path $BackupDirectory $script:ManifestName
    $temporaryPath = "$manifestPath.tmp"
    $json = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
}

function Resolve-BackupDirectory {
    param([Parameter(Mandatory)][string] $Path)

    $normalized = Get-NormalizedPath $Path
    $manifest = Join-Path $normalized $script:ManifestName
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "Backup manifest not found: $manifest"
    }

    return $normalized
}

function Test-BackupManifest {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [switch] $Quiet
    )

    $backupDirectory = Resolve-BackupDirectory $Directory
    Assert-SafeExternalPath $backupDirectory
    $manifestPath = Join-Path $backupDirectory $script:ManifestName
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    $requiredProperties = @(
        'tool_id', 'schema_version', 'scope', 'created_utc', 'file_count',
        'total_bytes', 'coverage', 'database_integrity', 'files'
    )
    foreach ($property in $requiredProperties) {
        if (-not $manifest.PSObject.Properties[$property]) {
            throw "Manifest is missing required property: $property"
        }
    }
    if ($manifest.tool_id -ne $script:ToolId -or
        $manifest.scope -ne 'codex-preserved-profile-v3') {
        throw 'Manifest was not generated for this preservation scope.'
    }

    if ([int] $manifest.schema_version -ne $script:SchemaVersion) {
        throw "Unsupported backup schema version: $($manifest.schema_version)"
    }

    $files = @($manifest.files)
    if ($files.Count -eq 0 -or [long] $manifest.total_bytes -le 0) {
        throw 'Manifest contains no preserved data.'
    }
    if ($files.Count -ne [int] $manifest.file_count) {
        throw 'Manifest file count is inconsistent.'
    }

    $expectedCoverage = [ordered]@{
        config = @($files | Where-Object relative_path -EQ `
            'payload/config.toml').Count
        active_chats = @($files | Where-Object relative_path -Match `
            '^payload/sessions/').Count
        archived_chats = @($files | Where-Object relative_path -Match `
            '^payload/archived_sessions/').Count
        skills = @($files | Where-Object relative_path -Match `
            '^payload/skills/(?!\.system(?:/|$))').Count
        memories = @($files | Where-Object relative_path -Match `
            '^payload/memories/').Count
        restorable_databases = @($files | Where-Object {
            $_.restore -and $_.relative_path -match `
                '\.(sqlite|sqlite3|db)(?:-wal)?$'
        }).Count
        ui_layout = @($files | Where-Object {
            $_.PSObject.Properties['restore_strategy'] -and
            $_.restore_strategy -eq 'merge-ui-layout'
        }).Count
    }
    foreach ($category in $expectedCoverage.Keys) {
        $value = $manifest.coverage.PSObject.Properties[$category]
        if ($null -eq $value -or
            [int] $value.Value -ne [int] $expectedCoverage[$category]) {
            throw "Manifest coverage is inconsistent: $category"
        }
    }
    if ([int] $expectedCoverage.restorable_databases -lt 1) {
        throw 'Manifest contains no restorable task database.'
    }
    if (([int] $expectedCoverage.active_chats +
        [int] $expectedCoverage.archived_chats) -lt 1) {
        throw 'Manifest contains no active or archived chat data.'
    }

    $seenRelative = @{}
    $seenRestore = @{}
    $checkedBytes = [long] 0
    for ($index = 0; $index -lt $files.Count; $index++) {
        $entry = $files[$index]
        foreach ($field in @('relative_path', 'restore', 'bytes', 'sha256')) {
            if (-not $entry.PSObject.Properties[$field]) {
                throw "Manifest file entry is missing $field."
            }
        }
        $relative = Assert-SafeRelativePath ([string] $entry.relative_path)
        if ($seenRelative.ContainsKey($relative)) {
            throw "Duplicate manifest path: $relative"
        }
        $seenRelative[$relative] = $true
        if ([long] $entry.bytes -lt 0 -or
            [string] $entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "Invalid manifest metadata: $relative"
        }
        if ([bool] $entry.restore) {
            if (-not $entry.PSObject.Properties['restore_relative_path']) {
                throw "Restorable entry has no destination: $relative"
            }
            $restorePath = Assert-SafeRelativePath `
                ([string] $entry.restore_relative_path)
            if ($seenRestore.ContainsKey($restorePath)) {
                throw "Duplicate restore destination: $restorePath"
            }
            $seenRestore[$restorePath] = $true
            if ($entry.PSObject.Properties['restore_strategy'] -and
                $entry.restore_strategy -notin @('copy', 'merge-ui-layout')) {
                throw "Unsupported restore strategy: $($entry.restore_strategy)"
            }
        }
        $path = Get-NormalizedPath (Join-Path $backupDirectory $relative)
        if (-not (Test-PathInside -Candidate $path -Parent $backupDirectory)) {
            throw "Unsafe path in manifest: $relative"
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Backup file is missing: $relative"
        }
        Assert-NoReparsePoint -Path $path -Boundary $backupDirectory

        $file = Get-Item -LiteralPath $path -Force
        if ($file.Length -ne [long] $entry.bytes) {
            throw "Backup file size mismatch: $relative"
        }

        if (-not $Quiet) {
            $percent = [math]::Floor((($index + 1) / $files.Count) * 100)
            Write-Progress `
                -Activity 'Verifying backup hashes' `
                -Status $relative `
                -PercentComplete $percent
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if (-not $hash.Equals([string] $entry.sha256, 'OrdinalIgnoreCase')) {
            throw "Backup hash mismatch: $relative"
        }
        $checkedBytes += $file.Length
    }
    Write-Progress -Activity 'Verifying backup hashes' -Completed

    if ($checkedBytes -ne [long] $manifest.total_bytes) {
        throw 'Manifest byte total is inconsistent.'
    }

    $actualDatabases = @(Get-IntegrityDatabasePath $backupDirectory)
    $volatileSidecars = @{}
    foreach ($database in $actualDatabases) {
        $volatileSidecars[(Get-NormalizedPath "$database-shm")] = $true
    }
    $actualBackupFiles = @(Get-SafeTreeFile -Path $backupDirectory `
        -RejectReparsePoint | Where-Object {
            $_.FullName -ne $manifestPath -and
            -not $volatileSidecars.ContainsKey((Get-NormalizedPath $_.FullName))
        })
    if ($actualBackupFiles.Count -ne $files.Count) {
        throw 'Backup contains undeclared or missing files.'
    }

    $declaredChecks = @($manifest.database_integrity)
    if ($declaredChecks.Count -ne $actualDatabases.Count) {
        throw 'Manifest database integrity inventory is inconsistent.'
    }
    $declaredDatabasePaths = @{}
    foreach ($check in $declaredChecks) {
        if (-not $check.PSObject.Properties['relative_path'] -or
            [string] $check.result -ne 'ok') {
            throw 'Manifest contains invalid database integrity metadata.'
        }
        $checkRelative = Assert-SafeRelativePath ([string] $check.relative_path)
        if ($declaredDatabasePaths.ContainsKey($checkRelative)) {
            throw "Duplicate database integrity path: $checkRelative"
        }
        $declaredDatabasePaths[$checkRelative] = $true
    }
    foreach ($database in $actualDatabases) {
        $databaseRelative = Get-RelativePathCompat -BasePath $backupDirectory `
            -ChildPath $database
        if (-not $declaredDatabasePaths.ContainsKey($databaseRelative)) {
            throw "Database is missing declared integrity result: $databaseRelative"
        }
        Invoke-SqliteCheck -DatabasePath $database | Out-Null
    }

    return [pscustomobject]@{
        Directory = $backupDirectory
        Manifest = $manifest
        Files = $files.Count
        Bytes = $checkedBytes
    }
}

$operationsPath = Join-Path $PSScriptRoot 'Codex-Reinstall.Operations.ps1'
if (-not (Test-Path -LiteralPath $operationsPath -PathType Leaf)) {
    throw "Operations component is missing: $operationsPath"
}
. $operationsPath
if ($MyInvocation.InvocationName -ne '.') {
    switch ($Mode) {
        'Interactive' {
            $uiPath = Join-Path $PSScriptRoot 'Codex-Reinstall.UI.ps1'
            if (-not (Test-Path -LiteralPath $uiPath)) {
                throw "Interactive UI component is missing: $uiPath"
            }
            . $uiPath
            Show-InteractiveUi
        }
        'Status' { Show-Status }
        'Backup' { Invoke-Backup }
        'Verify' { Invoke-Verify }
        'Clean' { Invoke-Clean }
        'Restore' { Invoke-Restore }
    }
}
