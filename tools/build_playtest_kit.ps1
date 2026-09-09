[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [string]$PackageName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot "build\playtest-kits"
}
elseif (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location).Path $OutputDirectory
}
$resolvedOutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = "WARSEED-Four-Operations-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")
}
if ($PackageName -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$") {
    throw "PackageName must contain 1-80 ASCII letters, digits, dots, underscores, or hyphens."
}

$packageDirectory = [IO.Path]::GetFullPath((Join-Path $resolvedOutputDirectory $PackageName))
$archivePath = [IO.Path]::GetFullPath((Join-Path $resolvedOutputDirectory "$PackageName.zip"))
$outputPrefix = $resolvedOutputDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $packageDirectory.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Package directory must remain inside the requested output directory."
}
if ([IO.Directory]::Exists($packageDirectory) -or [IO.File]::Exists($archivePath)) {
    throw "Package output already exists: $PackageName"
}

$files = @(
    [ordered]@{ source = "build\windows\warseed-debug.exe"; destination = "build\windows\warseed-debug.exe"; required = $true },
    [ordered]@{ source = "build\windows\warseed-debug.pck"; destination = "build\windows\warseed-debug.pck"; required = $true },
    [ordered]@{ source = "build\windows\warseed-debug.console.exe"; destination = "build\windows\warseed-debug.console.exe"; required = $false },
    [ordered]@{ source = "tools\start_isolated_playtest.ps1"; destination = "tools\start_isolated_playtest.ps1"; required = $true },
    [ordered]@{ source = "tools\complete_playtest_report.ps1"; destination = "tools\complete_playtest_report.ps1"; required = $true },
    [ordered]@{ source = "tools\summarize_playtest_cohort.ps1"; destination = "tools\summarize_playtest_cohort.ps1"; required = $true },
    [ordered]@{ source = "tools\feedback_server.py"; destination = "tools\feedback_server.py"; required = $true },
    [ordered]@{ source = "tools\start_feedback_server.ps1"; destination = "tools\start_feedback_server.ps1"; required = $true },
    [ordered]@{ source = "docs\PLAYTEST_PROTOCOL.md"; destination = "PLAYTEST_PROTOCOL.md"; required = $true },
    [ordered]@{ source = "docs\P6_7_PLAYTEST_COHORT_PLAN.md"; destination = "P6_7_PLAYTEST_COHORT_PLAN.md"; required = $true },
    [ordered]@{ source = "docs\PLAYTEST_PACKAGE_README.md"; destination = "README_PLAYTEST.md"; required = $true },
    [ordered]@{ source = "START_WARSEED_PLAYTEST.cmd"; destination = "START_WARSEED_PLAYTEST.cmd"; required = $true },
    [ordered]@{ source = "START_GREY_RIDGE_PLAYTEST.cmd"; destination = "START_GREY_RIDGE_PLAYTEST.cmd"; required = $true },
    [ordered]@{ source = "START_WARSEED_FEEDBACK_SERVER.cmd"; destination = "START_WARSEED_FEEDBACK_SERVER.cmd"; required = $true },
    [ordered]@{ source = "feedback_server_url.txt"; destination = "feedback_server_url.txt"; required = $true },
    [ordered]@{ source = "docs\FEEDBACK_SERVER_GUIDE.md"; destination = "FEEDBACK_SERVER_GUIDE.md"; required = $true },
    [ordered]@{ source = "docs\CURRENT_PLAYTEST_FEEDBACK_FOCUS.md"; destination = "CURRENT_PLAYTEST_FEEDBACK_FOCUS.md"; required = $true }
)

foreach ($entry in $files) {
    $sourcePath = Join-Path $repositoryRoot $entry.source
    if ($entry.required -and -not [IO.File]::Exists($sourcePath)) {
        throw "Required playtest-kit file not found: $sourcePath"
    }
}

$createdPackageDirectory = $false
try {
    [IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
    [IO.Directory]::CreateDirectory($packageDirectory) | Out-Null
    $createdPackageDirectory = $true
    foreach ($entry in $files) {
        $sourcePath = Join-Path $repositoryRoot $entry.source
        if (-not [IO.File]::Exists($sourcePath)) {
            continue
        }
        $destinationPath = Join-Path $packageDirectory $entry.destination
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath)) | Out-Null
        [IO.File]::Copy($sourcePath, $destinationPath, $false)
    }

    $manifestFiles = @()
    foreach ($filePath in [IO.Directory]::GetFiles($packageDirectory, "*", [IO.SearchOption]::AllDirectories) | Sort-Object) {
        $relativePath = $filePath.Substring($packageDirectory.Length).TrimStart([IO.Path]::DirectorySeparatorChar).Replace("\", "/")
        $fileInfo = Get-Item -LiteralPath $filePath
        $manifestFiles += [ordered]@{
            path = $relativePath
            bytes = [long]$fileInfo.Length
            sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        }
    }
    $manifest = [ordered]@{
        schema_version = 3
        package_name = $PackageName
        scenario_ids = @("grey_ridge", "broken_bridge", "fog_forest", "black_well")
        created_utc = [DateTimeOffset]::UtcNow.ToString("o")
        entrypoint = "START_WARSEED_PLAYTEST.cmd"
        feedback_server_entrypoint = "START_WARSEED_FEEDBACK_SERVER.cmd"
        feedback_schema_version = 1
        file_count = $manifestFiles.Count
        files = $manifestFiles
    }
    $manifestPath = Join-Path $packageDirectory "MANIFEST.json"
    $utf8WithoutBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 20), $utf8WithoutBom)

    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $archivePath -CompressionLevel Optimal
    $result = [pscustomobject]@{
        PackageName = $PackageName
        PackageDirectory = $packageDirectory
        ArchivePath = $archivePath
        ArchiveBytes = (Get-Item -LiteralPath $archivePath).Length
        ArchiveSHA256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        ManifestPath = $manifestPath
        ManifestFileCount = $manifestFiles.Count
    }
    Write-Host "WARSEED four-operation playtest kit created: $archivePath"
    $result
}
catch {
    if ([IO.File]::Exists($archivePath) -and $archivePath.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.File]::Delete($archivePath)
    }
    if ($createdPackageDirectory -and [IO.Directory]::Exists($packageDirectory) -and $packageDirectory.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($packageDirectory, $true)
    }
    throw
}
