[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8765,
    [string]$DataDirectory = "",
    [switch]$Lan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$serverScript = Join-Path $PSScriptRoot "feedback_server.py"
if (-not [IO.File]::Exists($serverScript)) {
    throw "Feedback server script not found: $serverScript"
}

if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $localApplicationData = [Environment]::GetFolderPath("LocalApplicationData")
    $DataDirectory = Join-Path $localApplicationData "WARSEED\feedback-server"
}
elseif (-not [IO.Path]::IsPathRooted($DataDirectory)) {
    $DataDirectory = Join-Path $repositoryRoot $DataDirectory
}
$resolvedDataDirectory = [IO.Path]::GetFullPath($DataDirectory)
[IO.Directory]::CreateDirectory($resolvedDataDirectory) | Out-Null

$pythonCommand = Get-Command "py.exe" -ErrorAction SilentlyContinue
$pythonArguments = @()
if ($null -ne $pythonCommand) {
    $pythonArguments += "-3"
}
else {
    $pythonCommand = Get-Command "python.exe" -ErrorAction SilentlyContinue
}
if ($null -eq $pythonCommand) {
    throw "Python 3 was not found. Install Python 3 or run tools\feedback_server.py with another Python 3 interpreter."
}

$hostAddress = "127.0.0.1"
if ($Lan) {
    $hostAddress = "0.0.0.0"
}
$pythonArguments += @($serverScript, "--host", $hostAddress, "--port", [string]$Port, "--data-directory", $resolvedDataDirectory)

Write-Host "WARSEED feedback data: $resolvedDataDirectory"
if ($Lan) {
    $addresses = @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.AddressState -eq "Preferred" } |
            Select-Object -ExpandProperty IPAddress -Unique
    )
    Write-Host "LAN mode is enabled. Allow Python through Windows Firewall only for Private networks."
    foreach ($address in $addresses) {
        Write-Host "Player feedback URL: http://${address}:$Port/feedback"
        Write-Host "Dashboard:          http://${address}:$Port/dashboard"
    }
}
else {
    Write-Host "Player feedback URL: http://127.0.0.1:$Port/feedback"
    Write-Host "Dashboard:          http://127.0.0.1:$Port/dashboard"
}

& $pythonCommand.Source @pythonArguments
exit $LASTEXITCODE
