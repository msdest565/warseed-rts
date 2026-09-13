[CmdletBinding()]
param([string]$PackageName = "WARSEED-Playable-20260914")

$ErrorActionPreference = "Stop"
if ($PackageName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') {
    throw "Invalid package name."
}
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$packagePath = Join-Path $repositoryRoot "build\playable\$PackageName"
$archivePath = "$packagePath.zip"
if ((Test-Path -LiteralPath $packagePath) -or (Test-Path -LiteralPath $archivePath)) {
    throw "Package already exists: $PackageName"
}
New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repositoryRoot "build\windows\warseed-debug.exe") -Destination (Join-Path $packagePath "WARSEED.exe")
Copy-Item -LiteralPath (Join-Path $repositoryRoot "build\windows\warseed-debug.pck") -Destination (Join-Path $packagePath "WARSEED.pck")
Copy-Item -LiteralPath (Join-Path $repositoryRoot "docs\PLAYABLE_20260914.md") -Destination (Join-Path $packagePath "README.md")
$entries = @(Get-ChildItem -LiteralPath $packagePath -File | Sort-Object Name | ForEach-Object {
    [ordered]@{name=$_.Name; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
[ordered]@{schema_version=1; package=$PackageName; evidence="SIMULATED"; files=$entries} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packagePath "manifest.json") -Encoding UTF8
Compress-Archive -Path (Join-Path $packagePath '*') -DestinationPath $archivePath -CompressionLevel Optimal
Write-Output "PLAYABLE_PACKAGE=$packagePath"
Write-Output "PLAYABLE_ARCHIVE=$archivePath"
Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
