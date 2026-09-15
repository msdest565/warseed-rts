[CmdletBinding()]
param(
    [string]$GodotConsolePath = "",
    [string]$ExportPath = "",
    [string]$SessionId = "",
    [switch]$EnforcePerformance
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:LASTEXITCODE = 0

function Resolve-Executable {
    param(
        [string]$RequestedPath,
        [string[]]$FallbackNames
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if ([IO.File]::Exists($RequestedPath)) {
            $resolvedPath = [IO.Path]::GetFullPath($RequestedPath)
            if ([IO.Path]::GetExtension($resolvedPath) -ieq ".exe" -and -not $resolvedPath.EndsWith("_console.exe", [StringComparison]::OrdinalIgnoreCase)) {
                $consoleCompanion = $resolvedPath.Substring(0, $resolvedPath.Length - 4) + "_console.exe"
                if ([IO.File]::Exists($consoleCompanion)) {
                    return $consoleCompanion
                }
            }
            return $resolvedPath
        }
        $requestedCommand = Get-Command $RequestedPath -ErrorAction SilentlyContinue
        if ($null -ne $requestedCommand) {
            return $requestedCommand.Source
        }
        throw "Executable not found: $RequestedPath"
    }

    foreach ($name in $FallbackNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }
    throw "Godot executable not found. Pass -GodotConsolePath or set WARSEED_GODOT_CONSOLE."
}

function Invoke-ExternalStep {
    param(
        [string]$Name,
        [string]$Executable,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "=== $Name ==="
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $global:LASTEXITCODE = 0
    & $Executable @Arguments
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode after $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds."
    }
    Write-Host "$Name passed in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds."
}

function Invoke-UnfilteredFullMatchMatrix {
    param(
        [string]$GodotExecutable,
        [string]$RepositoryRoot
    )

    $filterKeys = @("WARSEED_PLAN_FILTER", "WARSEED_STRATEGY_FILTER", "WARSEED_REPEAT_COUNT")
    $previousValues = @{}
    foreach ($key in $filterKeys) {
        $previousValues[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, $null, "Process")
    }
    try {
        Invoke-ExternalStep "Grey Ridge full-match quality matrix" $GodotExecutable @(
            "--headless", "--path", $RepositoryRoot,
            "--script", "res://tests/scenarios/grey_ridge_full_match_baseline.gd"
        )
    }
    finally {
        foreach ($key in $filterKeys) {
            [Environment]::SetEnvironmentVariable($key, $previousValues[$key], "Process")
        }
    }
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$verificationProfile = Join-Path $repositoryRoot "artifacts\verification-profile"
$verificationRoaming = Join-Path $verificationProfile "AppData\Roaming"
$verificationLocal = Join-Path $verificationProfile "AppData\Local"
[IO.Directory]::CreateDirectory($verificationRoaming) | Out-Null
[IO.Directory]::CreateDirectory($verificationLocal) | Out-Null
# Keep Godot's user:// and editor caches inside the writable workspace during CI/headless runs.
$env:APPDATA = $verificationRoaming
$env:LOCALAPPDATA = $verificationLocal
$requestedGodot = $GodotConsolePath
if ([string]::IsNullOrWhiteSpace($requestedGodot)) {
    $requestedGodot = [Environment]::GetEnvironmentVariable("WARSEED_GODOT_CONSOLE")
}
$godot = Resolve-Executable $requestedGodot @("godot", "godot4")
$powershell = (Get-Command "powershell.exe" -ErrorAction Stop).Source

if ([string]::IsNullOrWhiteSpace($ExportPath)) {
    $ExportPath = Join-Path $repositoryRoot "build\windows\warseed-debug.exe"
}
elseif (-not [IO.Path]::IsPathRooted($ExportPath)) {
    $ExportPath = Join-Path $repositoryRoot $ExportPath
}
$resolvedExportPath = [IO.Path]::GetFullPath($ExportPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedExportPath)) | Out-Null

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = "verification-{0}-{1}" -f [Diagnostics.Process]::GetCurrentProcess().Id, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}
if ($SessionId -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") {
    throw "SessionId must contain 1-64 ASCII letters, digits, dots, underscores, or hyphens."
}

$global:LASTEXITCODE = 0
$godotVersion = & $godot --version
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read Godot version from $godot."
}
if ([string]$godotVersion -notmatch "^4\.6\.3\.stable\.mono") {
    throw "WARSEED verification requires Godot 4.6.3 stable mono; found '$godotVersion'."
}

$started = [DateTimeOffset]::UtcNow
Write-Host "WARSEED playable-battles release verification"
Write-Host "Repository: $repositoryRoot"
Write-Host "Godot: $godotVersion"
Write-Host "Session: $SessionId"

Invoke-ExternalStep "Editor import" $godot @("--headless", "--editor", "--path", $repositoryRoot, "--quit")
Invoke-ExternalStep "Godot test suites" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/test_runner.gd")
Invoke-ExternalStep "Godot test suites with isolated session" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/test_runner.gd", "--", "--playtest-session=$SessionId")
Invoke-ExternalStep "Legacy vertical-slice smoke" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/vertical_slice_smoke.gd")
Invoke-ExternalStep "Grey Ridge smoke" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/grey_ridge_smoke.gd")
Invoke-ExternalStep "Grey Ridge decision matrix" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/scenarios/grey_ridge_decision_matrix.gd")
Invoke-UnfilteredFullMatchMatrix $godot $repositoryRoot
Invoke-ExternalStep "Broken Bridge smoke" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/broken_bridge_smoke.gd")
Invoke-ExternalStep "Broken Bridge decision matrix" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/scenarios/broken_bridge_decision_matrix.gd")
Invoke-ExternalStep "Fog Forest smoke" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/fog_forest_smoke.gd")
Invoke-ExternalStep "Fog Forest decision matrix" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/scenarios/fog_forest_decision_matrix.gd")
Invoke-ExternalStep "Black Well smoke" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/black_well_smoke.gd")
Invoke-ExternalStep "Black Well decision matrix" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/scenarios/black_well_decision_matrix.gd")
Invoke-ExternalStep "Four-operation release balance audit" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/scenarios/four_operation_release_balance_audit.gd")
if ($EnforcePerformance) {
    Invoke-ExternalStep "Grey Ridge entity benchmark" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/performance/grey_ridge_entity_benchmark.gd")
} else {
    Write-Host "Performance gate DEFERRED by D-028; no performance PASS is claimed."
}
Invoke-ExternalStep "Feedback UI five-viewport selfplay" $godot @("--headless", "--path", $repositoryRoot, "--script", "res://tests/tools/feedback_ui_selfplay.gd")

$toolSmokes = @(
    "tests\tools\playtest_report_smoke.ps1",
    "tests\tools\isolated_playtest_launcher_smoke.ps1",
    "tests\tools\playtest_cohort_smoke.ps1",
    "tests\tools\feedback_server_smoke.ps1"
)
foreach ($relativePath in $toolSmokes) {
    Invoke-ExternalStep $relativePath $powershell @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $repositoryRoot $relativePath)
    )
}

Invoke-ExternalStep "tests\tools\feedback_delivery_smoke.ps1" $powershell @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $repositoryRoot "tests\tools\feedback_delivery_smoke.ps1"),
    "-GodotConsolePath", $godot
)

Invoke-ExternalStep "Windows debug export" $godot @(
    "--headless",
    "--path", $repositoryRoot,
    "--export-debug", "Windows Desktop", $resolvedExportPath
)

$exportPckPath = [IO.Path]::ChangeExtension($resolvedExportPath, ".pck")
if (-not [IO.File]::Exists($resolvedExportPath) -or -not [IO.File]::Exists($exportPckPath)) {
    throw "Windows export did not produce both EXE and PCK outputs."
}
Invoke-ExternalStep "Exported game isolated headless smoke" $resolvedExportPath @(
    "--headless",
    "--quit-after", "3",
    "--",
    "--playtest-session=$SessionId-export"
)

Invoke-ExternalStep "Playtest kit smoke" $powershell @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $repositoryRoot "tests\tools\playtest_kit_smoke.ps1")
)

$completed = [DateTimeOffset]::UtcNow
$result = [pscustomobject]@{
    Status = "passed"
    GodotVersion = [string]$godotVersion
    StartedUtc = $started.ToString("o")
    CompletedUtc = $completed.ToString("o")
    DurationSeconds = [Math]::Round(($completed - $started).TotalSeconds, 3)
    ExportPath = $resolvedExportPath
    ExportBytes = (Get-Item -LiteralPath $resolvedExportPath).Length
    ExportSHA256 = (Get-FileHash -LiteralPath $resolvedExportPath -Algorithm SHA256).Hash
    PckPath = $exportPckPath
    PckBytes = (Get-Item -LiteralPath $exportPckPath).Length
    PckSHA256 = (Get-FileHash -LiteralPath $exportPckPath -Algorithm SHA256).Hash
}
Write-Host ""
Write-Host "WARSEED playable-battles release verification passed in $($result.DurationSeconds) seconds."
$result
