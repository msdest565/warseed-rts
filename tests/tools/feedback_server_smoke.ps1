[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$serverScript = Join-Path $repositoryRoot "tools\feedback_server.py"
$python = Get-Command "python.exe" -ErrorAction SilentlyContinue
$pythonArguments = @()
if ($null -eq $python) {
    $python = Get-Command "py.exe" -ErrorAction Stop
    $pythonArguments += "-3"
}
$token = [Guid]::NewGuid().ToString("N")
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "warseed-feedback-server-smoke-$token"))
$systemTempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $temporaryRoot.StartsWith($systemTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary feedback smoke path escaped the system temporary directory."
}
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
$baseUrl = "http://127.0.0.1:$port"
$pythonArguments += @($serverScript, "--host", "127.0.0.1", "--port", [string]$port, "--data-directory", $temporaryRoot)
$process = $null

try {
    $process = Start-Process -FilePath $python.Source -ArgumentList $pythonArguments -WindowStyle Hidden -PassThru
    $healthy = $false
    for ($attempt = 0; $attempt -lt 30; $attempt += 1) {
        try {
            $health = Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 1
            if ($health.status -eq "ok") {
                $healthy = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 100
        }
    }
    Assert-True $healthy "Feedback server should become healthy on loopback."

    $payload = [ordered]@{
        format_version = 1
        feedback_id = "smoke-$token"
        submitted_utc = [DateTimeOffset]::UtcNow.ToString("o")
        build_id = "smoke"
        anonymous_session_id = "smoke"
        scenario_id = "grey_ridge"
        outcome = "victory"
        battle_count = 1
        locale = "en"
        viewport = @{ width = 1280; height = 720 }
        responses = [ordered]@{
            overall_rating = 4
            objective_clarity = 4
            controls_clarity = 3
            agent_usefulness = 4
            priority_area = "maps"
            best_part = "Command flow"
            biggest_problem = "Map navigation"
            suggestions = "Improve landmarks"
            encountered_bug = $false
            bug_details = ""
        }
    }
    $body = $payload | ConvertTo-Json -Depth 10
    $created = Invoke-RestMethod -Method Post -Uri "$baseUrl/feedback" -ContentType "application/json; charset=utf-8" -Body $body
    Assert-True ($created.status -eq "stored") "First feedback submission should be stored."
    $duplicate = Invoke-RestMethod -Method Post -Uri "$baseUrl/feedback" -ContentType "application/json; charset=utf-8" -Body $body
    Assert-True ($duplicate.status -eq "duplicate") "Repeated feedback id should be idempotent."
    $summary = Invoke-RestMethod -Uri "$baseUrl/api/summary"
    Assert-True ([int]$summary.submission_count -eq 1 -and [double]$summary.average_overall_rating -eq 4.0) "Summary should include the stored response exactly once."
    $csv = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/export.csv"
    Assert-True ($csv.Content.Contains("smoke-$token") -and $csv.Content.Contains("Map navigation")) "CSV export should preserve stable ids and open feedback."

    $invalidRejected = $false
    try {
        Invoke-RestMethod -Method Post -Uri "$baseUrl/feedback" -ContentType "application/json" -Body '{"format_version":1}' | Out-Null
    }
    catch {
        $invalidRejected = [int]$_.Exception.Response.StatusCode -eq 422
    }
    Assert-True $invalidRejected "Invalid feedback should be rejected with HTTP 422."
    Write-Host "WARSEED feedback server smoke passed: health, persistence, idempotency, validation, summary, and CSV"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
    if ([IO.Directory]::Exists($temporaryRoot) -and $temporaryRoot.StartsWith($systemTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($temporaryRoot, $true)
    }
}
