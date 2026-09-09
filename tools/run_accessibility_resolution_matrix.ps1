param(
    [Parameter(Mandatory = $true)]
    [string]$GodotConsolePath,
    [string]$ProfileRoot = ""
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$godot = (Resolve-Path -LiteralPath $GodotConsolePath).Path
if ([string]::IsNullOrWhiteSpace($ProfileRoot)) {
    $ProfileRoot = Join-Path $repositoryRoot ".test-profile"
}
$profileRootPath = [System.IO.Path]::GetFullPath($ProfileRoot)
$roamingPath = Join-Path $profileRootPath "AppData\Roaming"
$localPath = Join-Path $profileRootPath "AppData\Local"
New-Item -ItemType Directory -Force -Path $roamingPath | Out-Null
New-Item -ItemType Directory -Force -Path $localPath | Out-Null

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$resolutions = @("1280x720", "1920x1080", "2560x1600", "640x800", "480x800")
try {
    $env:APPDATA = $roamingPath
    $env:LOCALAPPDATA = $localPath
    foreach ($resolution in $resolutions) {
        Write-Host "WARSEED accessibility matrix: $resolution"
        & $godot --path $repositoryRoot --script res://tests/tools/accessibility_resolution_matrix.gd -- "--matrix-resolution=$resolution"
        if ($LASTEXITCODE -ne 0) {
            throw "Accessibility matrix failed at $resolution with exit code $LASTEXITCODE."
        }
    }
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}

$reportPath = Join-Path $repositoryRoot "artifacts\accessibility_resolution_matrix.json"
$report = Get-Content -Raw -Encoding UTF8 -LiteralPath $reportPath | ConvertFrom-Json
if ($report.resolution_count -ne $resolutions.Count) {
    throw "Accessibility report contains $($report.resolution_count) resolutions instead of $($resolutions.Count)."
}
Write-Host "WARSEED accessibility matrix passed: $($report.resolution_count) resolutions"
