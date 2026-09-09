[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$builderPath = Join-Path $repositoryRoot "tools\build_playtest_kit.ps1"
$token = [Guid]::NewGuid().ToString("N")
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "warseed-playtest-kit-smoke-$token"))
$systemTempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $temporaryRoot.StartsWith($systemTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary smoke-test path escaped the system temporary directory."
}
$packageName = "WARSEED-Smoke-$token"
$outputDirectory = Join-Path $temporaryRoot "output"
$expandedDirectory = Join-Path $temporaryRoot "expanded"

try {
    $result = & $builderPath -OutputDirectory $outputDirectory -PackageName $packageName
    Assert-True ([IO.File]::Exists($result.ArchivePath)) "The playtest kit archive should be created."
    Assert-True ([IO.File]::Exists($result.ManifestPath)) "The unpacked kit should contain a manifest."

    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $result.ManifestPath | ConvertFrom-Json
    $requiredPaths = @(
        "build/windows/warseed-debug.exe",
        "build/windows/warseed-debug.pck",
        "tools/start_isolated_playtest.ps1",
        "tools/complete_playtest_report.ps1",
        "tools/summarize_playtest_cohort.ps1",
        "tools/feedback_server.py",
        "tools/start_feedback_server.ps1",
        "PLAYTEST_PROTOCOL.md",
        "P6_7_PLAYTEST_COHORT_PLAN.md",
        "README_PLAYTEST.md",
        "START_WARSEED_PLAYTEST.cmd",
        "START_GREY_RIDGE_PLAYTEST.cmd",
        "START_WARSEED_FEEDBACK_SERVER.cmd",
        "feedback_server_url.txt",
        "FEEDBACK_SERVER_GUIDE.md",
        "CURRENT_PLAYTEST_FEEDBACK_FOCUS.md"
    )
    $manifestPaths = @($manifest.files | ForEach-Object { $_.path })
    foreach ($requiredPath in $requiredPaths) {
        Assert-True ($manifestPaths -contains $requiredPath) "Manifest is missing required file: $requiredPath"
    }
    Assert-True ([int]$manifest.file_count -eq @($manifest.files).Count) "Manifest file count should match its file list."
    Assert-True ($manifest.entrypoint -eq "START_WARSEED_PLAYTEST.cmd") "The four-operation launcher should be the package entrypoint."
    Assert-True ($manifest.feedback_server_entrypoint -eq "START_WARSEED_FEEDBACK_SERVER.cmd" -and [int]$manifest.feedback_schema_version -eq 1) "The manifest should declare the feedback collector contract."
    Assert-True (@($manifest.scenario_ids).Count -eq 4 -and @($manifest.scenario_ids) -contains "black_well") "The manifest should declare all four operation ids."

    Expand-Archive -LiteralPath $result.ArchivePath -DestinationPath $expandedDirectory
    $expandedPackage = Join-Path $expandedDirectory $packageName
    $expandedManifestPath = Join-Path $expandedPackage "MANIFEST.json"
    Assert-True ([IO.File]::Exists($expandedManifestPath)) "The ZIP should preserve the package root and manifest."
    $expandedManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $expandedManifestPath | ConvertFrom-Json
    foreach ($entry in $expandedManifest.files) {
        $expandedFilePath = Join-Path $expandedPackage ([string]$entry.path).Replace("/", "\")
        Assert-True ([IO.File]::Exists($expandedFilePath)) "Expanded kit is missing manifest file: $($entry.path)"
        Assert-True ((Get-FileHash -LiteralPath $expandedFilePath -Algorithm SHA256).Hash -eq [string]$entry.sha256) "Expanded file hash mismatch: $($entry.path)"
    }

    Write-Host "WARSEED playtest kit smoke passed: package, ZIP layout, manifest, and file hashes"
}
finally {
    if ([IO.Directory]::Exists($temporaryRoot) -and $temporaryRoot.StartsWith($systemTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($temporaryRoot, $true)
    }
}
