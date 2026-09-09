[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotConsolePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$serverScript = Join-Path $repositoryRoot "tools\feedback_server.py"
$godot = [IO.Path]::GetFullPath($GodotConsolePath)
if (-not [IO.File]::Exists($godot)) {
    throw "Godot console executable not found: $godot"
}
$python = Get-Command "python.exe" -ErrorAction SilentlyContinue
$pythonArguments = @()
if ($null -eq $python) {
    $python = Get-Command "py.exe" -ErrorAction Stop
    $pythonArguments += "-3"
}
$token = [Guid]::NewGuid().ToString("N")
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "warseed-feedback-delivery-smoke-$token"))
$systemTempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $temporaryRoot.StartsWith($systemTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary feedback delivery path escaped the system temporary directory."
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
    if (-not $healthy) {
        throw "Temporary feedback server did not become healthy."
    }
    & $godot --headless --path $repositoryRoot --script res://tests/tools/feedback_delivery_selfplay.gd -- "--playtest-session=delivery-$token" "--feedback-url=$baseUrl/feedback"
    if ($LASTEXITCODE -ne 0) {
        throw "Godot feedback delivery selfplay failed with exit code $LASTEXITCODE."
    }
    $summary = Invoke-RestMethod -Uri "$baseUrl/api/summary"
    if ([int]$summary.submission_count -ne 1 -or [double]$summary.average_overall_rating -ne 4.0) {
        throw "Temporary server should contain exactly one delivered Godot feedback response."
    }
    Write-Host "WARSEED feedback delivery smoke passed: Godot local queue -> HTTP server -> sent archive"
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
