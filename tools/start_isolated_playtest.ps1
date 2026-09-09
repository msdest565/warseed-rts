[CmdletBinding()]
param(
    [string]$SessionId = "",
    [string]$ExecutablePath = "",
    [string]$FeedbackUrl = "",
    [switch]$Resume,
    [switch]$Evaluate,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-SafeSessionId {
    param([string]$Value)

    $normalized = ""
    $previousWasSeparator = $false
    foreach ($character in $Value.Trim().ToLowerInvariant().ToCharArray()) {
        $text = [string]$character
        if ("abcdefghijklmnopqrstuvwxyz0123456789_-".Contains($text)) {
            $normalized += $text
            $previousWasSeparator = $text -eq "_"
        }
        elseif ($normalized.Length -gt 0 -and -not $previousWasSeparator) {
            $normalized += "_"
            $previousWasSeparator = $true
        }
    }
    $normalized = $normalized.Trim([char[]]@("_", "-"))
    if ($normalized.Length -gt 40) {
        $normalized = $normalized.Substring(0, 40).TrimEnd([char[]]@("_", "-"))
    }
    return $normalized
}

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    if ($DryRun) {
        throw "SessionId is required in dry-run mode."
    }
    $SessionId = Read-Host "Anonymous playtest session id"
}
$safeSessionId = ConvertTo-SafeSessionId $SessionId
if ([string]::IsNullOrWhiteSpace($safeSessionId)) {
    throw "SessionId must contain at least one ASCII letter or digit."
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($FeedbackUrl)) {
    $feedbackConfigPath = Join-Path $repositoryRoot "feedback_server_url.txt"
    if ([IO.File]::Exists($feedbackConfigPath)) {
        $FeedbackUrl = (Get-Content -Raw -Encoding UTF8 -LiteralPath $feedbackConfigPath).Trim()
    }
}
if (-not [string]::IsNullOrWhiteSpace($FeedbackUrl)) {
    $feedbackUri = $null
    if (-not [Uri]::TryCreate($FeedbackUrl, [UriKind]::Absolute, [ref]$feedbackUri) -or $feedbackUri.Scheme -notin @("http", "https")) {
        throw "FeedbackUrl must be an absolute HTTP or HTTPS URL."
    }
    $FeedbackUrl = $feedbackUri.AbsoluteUri.TrimEnd("/")
}
if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $repositoryRoot "build\windows\warseed-debug.exe"
}
elseif (-not [IO.Path]::IsPathRooted($ExecutablePath)) {
    $ExecutablePath = Join-Path (Get-Location).Path $ExecutablePath
}
$resolvedExecutablePath = [IO.Path]::GetFullPath($ExecutablePath)
if (-not $DryRun -and -not [IO.File]::Exists($resolvedExecutablePath)) {
    throw "WARSEED executable not found: $resolvedExecutablePath"
}

$applicationData = [Environment]::GetFolderPath("ApplicationData")
$warseedUserDirectory = Join-Path $applicationData "Godot\app_userdata\WARSEED"
$sessionRoot = Join-Path $warseedUserDirectory ("playtest_runs\{0}" -f $safeSessionId)
$scenarioIds = @("grey_ridge", "broken_bridge", "fog_forest", "black_well")
$recordPaths = [ordered]@{}
foreach ($scenarioId in $scenarioIds) {
    $recordPaths[$scenarioId] = Join-Path $sessionRoot ("playtests\latest_{0}.json" -f $scenarioId)
}
$recordPath = [string]$recordPaths["grey_ridge"]
$rosterPath = Join-Path $sessionRoot "grey_ridge_roster.json"
$hasExistingData = $false
if ([IO.Directory]::Exists($sessionRoot)) {
    foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($sessionRoot)) {
        $hasExistingData = $true
        break
    }
}
if ($hasExistingData -and -not $Resume) {
    throw "Session '$safeSessionId' already has data. Use a new id, or pass -Resume explicitly."
}

$launchArguments = @("--", "--playtest-session=$safeSessionId")
if (-not [string]::IsNullOrWhiteSpace($FeedbackUrl)) {
    $launchArguments += "--feedback-url=$FeedbackUrl"
}
$launch = [pscustomobject]@{
    SessionId = $safeSessionId
    ExecutablePath = $resolvedExecutablePath
    Arguments = $launchArguments
    SessionRoot = $sessionRoot
    RosterPath = $rosterPath
    RecordPath = $recordPath
    RecordPaths = $recordPaths
    ExistingData = $hasExistingData
    Resume = [bool]$Resume
    FeedbackUrl = $FeedbackUrl
}

if ($DryRun) {
    $launch
    return
}

$recordHashesBeforeLaunch = @{}
foreach ($scenarioId in $scenarioIds) {
    $scenarioRecordPath = [string]$recordPaths[$scenarioId]
    if ([IO.File]::Exists($scenarioRecordPath)) {
        $recordHashesBeforeLaunch[$scenarioId] = (Get-FileHash -LiteralPath $scenarioRecordPath -Algorithm SHA256).Hash
    }
}

Write-Host "Starting isolated WARSEED four-operation playtest: $safeSessionId"
Write-Host "Session data: $sessionRoot"
& $resolvedExecutablePath @launchArguments
if ($LASTEXITCODE -ne 0) {
    throw "WARSEED exited with code $LASTEXITCODE."
}

$completedRecordPaths = [Collections.Generic.List[string]]::new()
$evaluatedRecordCount = 0
foreach ($scenarioId in $scenarioIds) {
    $scenarioRecordPath = [string]$recordPaths[$scenarioId]
    if ([IO.File]::Exists($scenarioRecordPath)) {
        $completedRecordPaths.Add($scenarioRecordPath)
        Write-Host "Latest $scenarioId raw playtest record: $scenarioRecordPath"
        $currentHash = (Get-FileHash -LiteralPath $scenarioRecordPath -Algorithm SHA256).Hash
        $recordChanged = -not $recordHashesBeforeLaunch.ContainsKey($scenarioId) -or $recordHashesBeforeLaunch[$scenarioId] -ne $currentHash
        if ($Evaluate -and $recordChanged) {
            $assessmentTool = Join-Path $repositoryRoot "tools\complete_playtest_report.ps1"
            & $assessmentTool -RecordPath $scenarioRecordPath -ObserverId $safeSessionId -RequireContext
            $evaluatedRecordCount += 1
        }
    }
}
if ($completedRecordPaths.Count -eq 0) {
    Write-Warning "No completed WARSEED operation record was found. Finish at least one battle before closing the game."
}
elseif ($Evaluate -and $evaluatedRecordCount -eq 0) {
    Write-Warning "No operation record changed during this launch, so no duplicate assessment was created."
}
