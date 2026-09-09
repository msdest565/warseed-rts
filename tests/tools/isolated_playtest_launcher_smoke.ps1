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
$launcherPath = Join-Path $repositoryRoot "tools\start_isolated_playtest.ps1"
$token = [Guid]::NewGuid().ToString("N")
$feedbackUrl = "http://192.0.2.10:8765/feedback"
$launch = & $launcherPath -SessionId "Observer 01 ../ $token" -ExecutablePath ".\not-used-in-dry-run.exe" -FeedbackUrl $feedbackUrl -DryRun
$expectedSessionId = ("observer_01_$token").Substring(0, 40).TrimEnd([char[]]@("_", "-"))

Assert-True ($launch.SessionId -eq $expectedSessionId) "The launcher should normalize and bound the anonymous id exactly like the game."
Assert-True ($launch.Arguments.Count -eq 3 -and $launch.Arguments[0] -eq "--" -and $launch.Arguments[1] -eq "--playtest-session=$($launch.SessionId)" -and $launch.Arguments[2] -eq "--feedback-url=$feedbackUrl") "The launcher should pass the isolated session id and validated feedback URL as user arguments."
Assert-True ($launch.FeedbackUrl -eq $feedbackUrl) "The launch description should expose the selected feedback endpoint."
Assert-True ($launch.RosterPath.EndsWith("playtest_runs\$($launch.SessionId)\grey_ridge_roster.json")) "The campaign roster should be isolated per session."
Assert-True ($launch.RecordPath.EndsWith("playtest_runs\$($launch.SessionId)\playtests\latest_grey_ridge.json")) "The raw playtest record should be isolated per session."
Assert-True ($launch.RecordPaths.Count -eq 4) "The launcher should expose all four operation record paths."
Assert-True ([string]$launch.RecordPaths["broken_bridge"] -like "*playtest_runs\$($launch.SessionId)\playtests\latest_broken_bridge.json") "Broken Bridge should use its own isolated latest record."
Assert-True ([string]$launch.RecordPaths["fog_forest"] -like "*playtest_runs\$($launch.SessionId)\playtests\latest_fog_forest.json") "Fog Forest should use its own isolated latest record."
Assert-True ([string]$launch.RecordPaths["black_well"] -like "*playtest_runs\$($launch.SessionId)\playtests\latest_black_well.json") "Black Well should use its own isolated latest record."
Assert-True (-not $launch.ExistingData -and -not $launch.Resume) "A unique dry-run session should start clean."

$invalidRejected = $false
try {
    & $launcherPath -SessionId "..." -DryRun | Out-Null
}
catch {
    $invalidRejected = $_.Exception.Message.Contains("ASCII letter or digit")
}
Assert-True $invalidRejected "A path-only or punctuation-only session id must be rejected."

Write-Host "WARSEED isolated playtest launcher smoke passed: normalized id, four isolated operation paths, invalid id rejected"
