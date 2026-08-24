#requires -Version 7.0

<#
.SYNOPSIS
Downloads, verifies, and installs the latest Codex Desktop package for Windows.

.DESCRIPTION
Resolves the current Codex Desktop release from Microsoft's package services,
downloads the package for the selected architecture, and validates its product
identity, manifest publisher, SHA-256 hash, and Authenticode signature before
installation.

The Microsoft Store application and WinGet are not required. When a proxy is
configured through HTTPS_PROXY, HTTP_PROXY, or ALL_PROXY, Microsoft catalog and
download requests automatically use it. Temporary name-resolution failures are
retried up to three times.

Resolver source files are taken from an immutable Git commit and checked against
pinned hashes before execution. Unexpected resolver changes are never trusted
automatically.

.PARAMETER Architecture
Selects the package architecture. Valid values are x64 and arm64. The default is
arm64 when PROCESSOR_ARCHITECTURE is ARM64; otherwise, it is x64.

.PARAMETER OutputDirectory
Specifies where newly downloaded packages and their manifest are stored. The
default is a timestamped CodexDesktopOffline directory under the current user's
Downloads directory.

.PARAMETER ExistingPackageDirectory
Skips downloading and validates packages already present in this directory.
The directory must include the package-manifest.json created by this script.

.PARAMETER DownloadOnly
Downloads and verifies the package without installing or launching Codex.

.PARAMETER NoLaunch
Installs the verified package but does not launch Codex afterward.

.EXAMPLE
PS> .\Download-Install-CodexDesktop.ps1

Downloads the latest package, verifies it, installs it, and launches Codex.

.EXAMPLE
PS> .\Download-Install-CodexDesktop.ps1 -DownloadOnly

Downloads and verifies the latest package without installing it.

.EXAMPLE
PS> .\Download-Install-CodexDesktop.ps1 -Architecture arm64 -NoLaunch

Downloads and installs the latest ARM64 package without launching Codex.

.EXAMPLE
PS> .\Download-Install-CodexDesktop.ps1 `
>>   -ExistingPackageDirectory 'C:\Packages\Codex' -DownloadOnly

Validates a package set previously downloaded by this script without installing
or launching it.

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. Progress and verification details are written to the information stream.

.NOTES
Requires PowerShell 7 or later. Package installation uses Add-AppxPackage and
may be restricted by organizational Windows application policies.

Use Get-Help .\Download-Install-CodexDesktop.ps1 -Full for complete help.
#>

[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = $(
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    ),
    [string]$OutputDirectory = $(
        Join-Path $env:USERPROFILE (
            'Downloads\CodexDesktopOffline-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        )
    ),
    [string]$ExistingPackageDirectory,
    [switch]$DownloadOnly,
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$productId = '9PLM9XGG6VKS'
$expectedIdentityName = 'OpenAI.Codex'
$resolverRepository = 'hanyu1212/microsoft-store-package-downloader-skill'
$resolverCommit = 'd1c508cc458223ec7ae684e685625c5b7cb62286'
$patchedResolverHash = '89C30F84119FD691E67518264EB1437FFEF3866CBC07D626BF8CA636B95C328F'

$resolverFiles = [ordered]@{
    'scripts/download-store-package.ps1' =
        'FAD16430BFC802258DA33F354432D6E4E3D1843033253FC7213EE10D6B94B977'
    'scripts/storelib-xml/GetCookie.xml' =
        '6CEEB91A37805CFDADD66DF99FF4EF3859DFC3EAF372ADD0FD9AD2D3BBFDB009'
    'scripts/storelib-xml/WUIDRequest.xml' =
        '2B01A7B98E92EAF39F23E5EF161613278220C913E678F024DCEBB3867831B97E'
    'scripts/storelib-xml/FE3FileUrl.xml' =
        'C813845BD22A441C84120A308EE2C47F921ABBCB3FD4FD54DE9208CEF1F5BB4B'
    'references/storelib/FE3Handler.cs' =
        '9D910F22CF8B55246CE8EB420B3EE876AA5A8C6016C1B7F7328195FC7396E54E'
    'references/storelib/LICENSE' =
        '4B89D4518BD135AB4EE154A7BCE722246B57A98C3D7EFC1A09409898160C2BD1'
}

function Test-ChildPath {
    param(
        [Parameter(Mandatory)]
        [string]$Parent,
        [Parameter(Mandatory)]
        [string]$Child
    )

    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $childPath = [IO.Path]::GetFullPath($Child)
    $prefix = $parentPath + [IO.Path]::DirectorySeparatorChar
    return $childPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Write-Status {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)

    Write-Information $Message -InformationAction Continue
}

function Save-VerifiedResolverFile {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [Parameter(Mandatory)]
        [string]$ExpectedHash,
        [Parameter(Mandatory)]
        [string]$ResolverRoot
    )

    $relativeUri = $RelativePath.Replace('\', '/')
    $uri = 'https://raw.githubusercontent.com/{0}/{1}/{2}' -f @(
        $resolverRepository,
        $resolverCommit,
        $relativeUri
    )
    $destination = Join-Path $ResolverRoot $RelativePath
    if (-not (Test-ChildPath -Parent $ResolverRoot -Child $destination)) {
        throw "Refusing resolver path outside temporary root: $destination"
    }

    $directory = Split-Path -Parent $destination
    [IO.Directory]::CreateDirectory($directory) | Out-Null

    $actualHash = $null
    foreach ($attempt in 1..3) {
        & curl.exe @(
            '--fail',
            '--location',
            '--silent',
            '--show-error',
            '--ssl-no-revoke',
            '--retry', '3',
            '--connect-timeout', '20',
            '--max-time', '120',
            '--remove-on-error',
            '--output', $destination,
            $uri
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download pinned resolver file: $RelativePath"
        }

        $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($actualHash -eq $ExpectedHash) {
            return
        }

        if ($attempt -lt 3) {
            Write-Status "Checksum mismatch for $RelativePath; downloading it again ($attempt/3)."
        }
    }

    throw @"
Resolver integrity check failed after 3 downloads.
File:     $RelativePath
Commit:   $resolverCommit
Expected: $ExpectedHash
Actual:   $actualHash
The pinned commit is immutable, so do not automatically trust the changed bytes.
"@
}

function ConvertTo-CompatibleResolver {
    param([Parameter(Mandatory)][string]$Path)

    $content = Get-Content -Raw -LiteralPath $Path
    $replacements = [ordered]@{
        '([string]$head.Headers["Content-Disposition"])' =
            '([string]($head.Headers["Content-Disposition"] | Select-Object -First 1))'
        '[long]$head.Headers["Content-Length"]' =
            '[long]($head.Headers["Content-Length"] | Select-Object -First 1)'
    }

    foreach ($entry in $replacements.GetEnumerator()) {
        if (-not $content.Contains($entry.Key)) {
            throw "Pinned resolver no longer contains an expected compatibility target."
        }
        $content = $content.Replace($entry.Key, $entry.Value)
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8 -NoNewline
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $patchedResolverHash) {
        throw 'Patched resolver hash did not match the reviewed implementation.'
    }
}

function Invoke-StoreResolver {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Architecture,
        [Parameter(Mandatory)]
        [string]$OutputDirectory
    )

    $proxyUri = @(
        $env:HTTPS_PROXY
        $env:HTTP_PROXY
        $env:ALL_PROXY
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1

    if ($null -ne $proxyUri) {
        $parsedProxy = $null
        if (-not [uri]::TryCreate($proxyUri, [UriKind]::Absolute, [ref]$parsedProxy)) {
            throw "The configured proxy URI is invalid: $proxyUri"
        }
        if ($parsedProxy.Scheme -notin @('http', 'https')) {
            throw "The configured proxy must use HTTP or HTTPS: $proxyUri"
        }

        $PSDefaultParameterValues['Invoke-RestMethod:Proxy'] = $parsedProxy
        $PSDefaultParameterValues['Invoke-WebRequest:Proxy'] = $parsedProxy
        $PSDefaultParameterValues[
            'Invoke-RestMethod:ProxyUseDefaultCredentials'
        ] = $true
        $PSDefaultParameterValues[
            'Invoke-WebRequest:ProxyUseDefaultCredentials'
        ] = $true
        Write-Status "Using configured OS proxy: $($parsedProxy.Authority)"
    }

    foreach ($attempt in 1..3) {
        try {
            & $Path `
                -ProductId $productId `
                -Architecture $Architecture `
                -Market 'US' `
                -Language 'en' `
                -OutputDirectory $OutputDirectory
            return
        } catch {
            $isNameResolutionFailure = $_.Exception.ToString() -match @(
                'No such host'
                'Name or service not known'
                'Temporary failure in name resolution'
            ) -join '|'

            if (-not $isNameResolutionFailure -or $attempt -eq 3) {
                throw
            }

            Write-Status (
                "Microsoft endpoint name resolution failed; retrying ($attempt/3)."
            )
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Get-PackageIdentity {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if ($null -eq $entry) {
            throw "Package has no AppxManifest.xml: $Path"
        }

        $reader = [IO.StreamReader]::new($entry.Open())
        try {
            [xml]$manifest = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }

        $namespace = [Xml.XmlNamespaceManager]::new($manifest.NameTable)
        $namespace.AddNamespace(
            'appx',
            'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
        )
        $identity = $manifest.SelectSingleNode(
            '/appx:Package/appx:Identity',
            $namespace
        )
        if ($null -eq $identity) {
            throw "Package identity is missing: $Path"
        }

        return [pscustomobject]@{
            Name = [string]$identity.Name
            Publisher = [string]$identity.Publisher
            Version = [version]$identity.Version
            Architecture = [string]$identity.ProcessorArchitecture
        }
    } finally {
        $archive.Dispose()
    }
}

function Get-VerifiedPackageSet {
    param([Parameter(Mandatory)][string]$PackageDirectory)

    $root = [IO.Path]::GetFullPath($PackageDirectory)
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Package manifest was not found: $manifestPath"
    }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.ProductId -ne $productId) {
        throw "Unexpected Store Product ID: $($manifest.ProductId)"
    }
    if ($manifest.PackageIdentityName -ne $expectedIdentityName) {
        throw "Unexpected package identity: $($manifest.PackageIdentityName)"
    }

    $verified = foreach ($record in @($manifest.Packages)) {
        $path = Join-Path $root ([string]$record.FileName)
        if (-not (Test-ChildPath -Parent $root -Child $path)) {
            throw "Package path escaped the output directory: $path"
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Downloaded package is missing: $path"
        }

        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne [string]$record.Sha256) {
            throw "Package SHA-256 mismatch: $path"
        }

        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid') {
            throw "Package signature is not valid: $path"
        }

        $identity = Get-PackageIdentity -Path $path
        if ($identity.Publisher -ne $signature.SignerCertificate.Subject) {
            throw "Manifest publisher does not match the package signer: $path"
        }

        [pscustomobject]@{
            Path = $path
            Sha256 = $hash
            Signature = [string]$signature.Status
            Signer = $signature.SignerCertificate.Subject
            Identity = $identity
        }
    }

    $mainPackages = @(
        $verified | Where-Object { $_.Identity.Name -eq $expectedIdentityName }
    )
    if ($mainPackages.Count -ne 1) {
        throw "Expected one Codex package; found $($mainPackages.Count)."
    }

    return [pscustomobject]@{
        Manifest = $manifest
        Main = $mainPackages[0]
        Dependencies = @(
            $verified | Where-Object Path -ne $mainPackages[0].Path
        )
        Packages = @($verified)
    }
}

$resolverRoot = $null
try {
    if ([string]::IsNullOrWhiteSpace($ExistingPackageDirectory)) {
        $resolverRoot = Join-Path $env:TEMP (
            'CodexStoreResolver-' + [guid]::NewGuid().ToString('N')
        )
        [IO.Directory]::CreateDirectory($resolverRoot) | Out-Null

        foreach ($entry in $resolverFiles.GetEnumerator()) {
            Save-VerifiedResolverFile `
                -RelativePath $entry.Key `
                -ExpectedHash $entry.Value `
                -ResolverRoot $resolverRoot
        }

        $resolverPath = Join-Path $resolverRoot 'scripts\download-store-package.ps1'
        ConvertTo-CompatibleResolver -Path $resolverPath

        Invoke-StoreResolver `
            -Path $resolverPath `
            -Architecture $Architecture `
            -OutputDirectory $OutputDirectory

        $packageRoot = [IO.Path]::GetFullPath($OutputDirectory)
    } else {
        $packageRoot = [IO.Path]::GetFullPath($ExistingPackageDirectory)
    }

    $result = Get-VerifiedPackageSet -PackageDirectory $packageRoot
    $main = $result.Main

    Write-Status ''
    Write-Status "Verified Codex Desktop $($main.Identity.Version)"
    Write-Status "Package: $($main.Path)"
    Write-Status "SHA-256: $($main.Sha256)"
    Write-Status "Signer: $($main.Signer)"

    if ($DownloadOnly) {
        Write-Status 'Download and verification completed. Installation was skipped.'
        return
    }

    $addParameters = @{ Path = $main.Path; ErrorAction = 'Stop' }
    if ($result.Dependencies.Count -gt 0) {
        $addParameters.DependencyPath = $result.Dependencies.Path
    }
    Add-AppxPackage @addParameters

    $installed = Get-AppxPackage -Name $expectedIdentityName |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $installed -or [version]$installed.Version -lt $main.Identity.Version) {
        throw 'Codex Desktop did not register at the downloaded version.'
    }

    Write-Status "Installed Codex Desktop $($installed.Version) successfully."

    if (-not $NoLaunch) {
        Start-Process 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
        Write-Status 'Launched ChatGPT. Select Codex inside the desktop app.'
    }
} finally {
    if ($null -ne $resolverRoot -and (Test-Path -LiteralPath $resolverRoot)) {
        $tempRoot = [IO.Path]::GetFullPath($env:TEMP)
        if (-not (Test-ChildPath -Parent $tempRoot -Child $resolverRoot)) {
            throw "Refusing to remove unexpected temporary path: $resolverRoot"
        }
        Remove-Item -LiteralPath $resolverRoot -Recurse -Force
    }
}
