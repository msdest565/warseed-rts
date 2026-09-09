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
$toolPath = Join-Path $repositoryRoot "tools\complete_playtest_report.ps1"
$token = [Guid]::NewGuid().ToString("N")
$temporaryDirectory = [IO.Path]::GetTempPath()
$sourcePath = Join-Path $temporaryDirectory "warseed-playtest-source-$token.json"
$passPath = Join-Path $temporaryDirectory "warseed-playtest-pass-$token.json"
$failPath = Join-Path $temporaryDirectory "warseed-playtest-fail-$token.json"
$incompletePath = Join-Path $temporaryDirectory "warseed-playtest-incomplete-$token.json"
$brokenBridgeSourcePath = Join-Path $temporaryDirectory "warseed-playtest-broken-bridge-source-$token.json"
$brokenBridgeReportPath = Join-Path $temporaryDirectory "warseed-playtest-broken-bridge-report-$token.json"
$unsupportedSourcePath = Join-Path $temporaryDirectory "warseed-playtest-unsupported-source-$token.json"
$temporaryPaths = @($sourcePath, $passPath, $failPath, $incompletePath, $brokenBridgeSourcePath, $brokenBridgeReportPath, $unsupportedSourcePath)

try {
    $fixture = [ordered]@{
        format_version = 2
        scenario_id = "grey_ridge"
        battle_number = 1
        opening_plan_id = "central_assault"
        started_unix_time = 1234567890
        completed = $true
        result = "defeat"
        first_commander_command_seconds = 12.0
        first_unit_card_command_seconds = -1.0
        intel_actions_measured = 1
        average_intel_action_delay_seconds = 3.0
        takeovers = 1
        returns_to_commander = 1
        diagnostic_individual_mode_activations = 0
        agent_override_rejections = 0
        events = @()
    }
    $utf8WithoutBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($sourcePath, ($fixture | ConvertTo-Json -Depth 20), $utf8WithoutBom)
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash

    & $toolPath -RecordPath $sourcePath -OutputPath $passPath `
        -CardEntityRecognition pass `
        -CommanderBehaviorExplanation pass `
        -EnemyReactionExplanation pass `
        -SecondBattleIntent pass `
        -DisplayResolution 1280x720 `
        -InputDevice touchpad `
        -InterfaceLanguage zh_CN `
        -ParticipantGroup p67-01 `
        -RequireContext | Out-Null
    $passReport = Get-Content -Raw -Encoding UTF8 -LiteralPath $passPath | ConvertFrom-Json
    Assert-True ($passReport.gate_status -eq "pass") "All satisfied checks should pass the playtest gate."
    Assert-True (@($passReport.automatic_checks.PSObject.Properties).Count -eq 6) "The report should contain all six automatic checks."
    Assert-True (@($passReport.observer_checks.PSObject.Properties).Count -eq 5) "The report should contain four core observer checks plus the operation-rule check."
    Assert-True ($passReport.observer_checks.operation_rule_explanation.result -eq "not_applicable") "The base onboarding operation should not require a separate new-rule explanation."
    Assert-True ($passReport.session_context.display_resolution -eq "1280x720" -and $passReport.session_context.input_device -eq "touchpad") "Required session context should be structured in the assessment."

    & $toolPath -RecordPath $sourcePath -OutputPath $failPath `
        -CardEntityRecognition pass `
        -CommanderBehaviorExplanation pass `
        -EnemyReactionExplanation fail `
        -SecondBattleIntent pass | Out-Null
    $failReport = Get-Content -Raw -Encoding UTF8 -LiteralPath $failPath | ConvertFrom-Json
    Assert-True ($failReport.gate_status -eq "fail") "One explicit observer failure should fail the playtest gate."
    Assert-True (@($failReport.failed_checks).Count -eq 1) "The failed check should be preserved in the report."

    & $toolPath -RecordPath $sourcePath -OutputPath $incompletePath `
        -CardEntityRecognition not_observed `
        -CommanderBehaviorExplanation pass `
        -EnemyReactionExplanation pass `
        -SecondBattleIntent pass | Out-Null
    $incompleteReport = Get-Content -Raw -Encoding UTF8 -LiteralPath $incompletePath | ConvertFrom-Json
    Assert-True ($incompleteReport.gate_status -eq "incomplete") "Missing observer evidence should remain incomplete."
    Assert-True (@($incompleteReport.missing_checks).Count -eq 1) "The missing check should be preserved in the report."
    Assert-True ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -eq $sourceHash) "Assessment generation must not modify the raw playtest record."

    $overwriteRejected = $false
    try {
        & $toolPath -RecordPath $sourcePath -OutputPath $sourcePath `
            -CardEntityRecognition pass `
            -CommanderBehaviorExplanation pass `
            -EnemyReactionExplanation pass `
            -SecondBattleIntent pass | Out-Null
    }
    catch {
        $overwriteRejected = $_.Exception.Message.Contains("must not overwrite")
    }
    Assert-True $overwriteRejected "The tool must reject an assessment path that equals the raw record path."
    Assert-True ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -eq $sourceHash) "Rejected overwrite attempts must leave the raw record unchanged."

    $brokenBridgeFixture = [ordered]@{}
    foreach ($key in $fixture.Keys) {
        $brokenBridgeFixture[$key] = $fixture[$key]
    }
    $brokenBridgeFixture.scenario_id = "broken_bridge"
    [IO.File]::WriteAllText($brokenBridgeSourcePath, ($brokenBridgeFixture | ConvertTo-Json -Depth 20), $utf8WithoutBom)
    & $toolPath -RecordPath $brokenBridgeSourcePath -OutputPath $brokenBridgeReportPath `
        -CardEntityRecognition pass `
        -CommanderBehaviorExplanation pass `
        -EnemyReactionExplanation pass `
        -SecondBattleIntent pass `
        -OperationRuleExplanation pass | Out-Null
    $brokenBridgeReport = Get-Content -Raw -Encoding UTF8 -LiteralPath $brokenBridgeReportPath | ConvertFrom-Json
    Assert-True ($brokenBridgeReport.scenario_id -eq "broken_bridge" -and $brokenBridgeReport.gate_status -eq "pass") "A supported non-Grey-Ridge operation should preserve its scenario id and pass."
    Assert-True ($brokenBridgeReport.observer_checks.operation_rule_explanation.result -eq "pass") "A later operation should require its new-rule explanation."

    $unsupportedFixture = [ordered]@{}
    foreach ($key in $fixture.Keys) {
        $unsupportedFixture[$key] = $fixture[$key]
    }
    $unsupportedFixture.scenario_id = "unknown_operation"
    [IO.File]::WriteAllText($unsupportedSourcePath, ($unsupportedFixture | ConvertTo-Json -Depth 20), $utf8WithoutBom)
    $unsupportedRejected = $false
    try {
        & $toolPath -RecordPath $unsupportedSourcePath -OutputPath $brokenBridgeReportPath `
            -CardEntityRecognition pass `
            -CommanderBehaviorExplanation pass `
            -EnemyReactionExplanation pass `
            -SecondBattleIntent pass | Out-Null
    }
    catch {
        $unsupportedRejected = $_.Exception.Message.Contains("Unsupported WARSEED playtest scenario")
    }
    Assert-True $unsupportedRejected "Unknown operation ids must not enter the human evidence pipeline."

    Write-Host "WARSEED playtest report tool smoke passed: four-operation schema, pass/fail/incomplete, immutable source, invalid operation rejected"
}
finally {
    foreach ($path in $temporaryPaths) {
        if ([IO.File]::Exists($path)) {
            [IO.File]::Delete($path)
        }
    }
}
