[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-Assessment {
    param(
        [string]$SessionId,
        [string]$ScenarioId,
        [long]$Started,
        [long]$Assessed,
        [string]$GateStatus,
        [string]$EnemyExplanation,
        [double]$FirstCommand
    )

    return [ordered]@{
        schema_version = 2
        scenario_id = $ScenarioId
        playtest_session_id = $SessionId
        source_record = "C:\records\$SessionId.json"
        assessed_unix_time = $Assessed
        observer_id = "observer-a"
        session_context = [ordered]@{
            display_resolution = "1280x720"
            input_device = "mouse"
            interface_language = "zh_CN"
            participant_group = $SessionId
        }
        gate_status = $GateStatus
        automatic_checks = [ordered]@{
            battle_completed = [ordered]@{ result = "pass" }
            first_effective_command_within_30_seconds = [ordered]@{ result = "pass" }
        }
        observer_checks = [ordered]@{
            card_entity_recognition = [ordered]@{ result = "pass" }
            commander_behavior_explanation = [ordered]@{ result = "pass" }
            enemy_reaction_explanation = [ordered]@{ result = $EnemyExplanation }
            second_battle_intent = [ordered]@{ result = "pass" }
            operation_rule_explanation = [ordered]@{ result = $(if ($ScenarioId -eq "grey_ridge") { "not_applicable" } else { "pass" }) }
        }
        failed_checks = @()
        missing_checks = @()
        session = [ordered]@{
            playtest_session_id = $SessionId
            scenario_id = $ScenarioId
            started_unix_time = $Started
            battle_number = 1
            opening_plan_id = "central_assault"
            result = "defeat"
            requested_second_battle = $false
            first_commander_command_seconds = $FirstCommand
            first_unit_card_command_seconds = -1.0
            prebattle_duration_seconds = 10.0
            replans_per_minute = 1.0
            average_intel_action_delay_seconds = 2.0
            direct_control_ratio = 0.5
        }
    }
}

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$toolPath = Join-Path $repositoryRoot "tools\summarize_playtest_cohort.ps1"
$token = [Guid]::NewGuid().ToString("N")
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "warseed-cohort-smoke-$token"))
$tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $temporaryRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Temporary path escaped system temp." }
$reportsDirectory = Join-Path $temporaryRoot "reports"
$outputDirectory = Join-Path $temporaryRoot "output"
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)

try {
    [IO.Directory]::CreateDirectory($reportsDirectory) | Out-Null
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    $fixtures = [ordered]@{
        "session-a-old_assessment.json" = New-Assessment "session-a" "grey_ridge" 1000 100 "fail" "fail" 28.0
        "session-a-new_assessment.json" = New-Assessment "session-a" "grey_ridge" 1000 200 "pass" "pass" 10.0
        "session-a-broken-bridge_assessment.json" = New-Assessment "session-a" "broken_bridge" 1000 300 "fail" "fail" 20.0
    }
    $sourceHashes = @{}
    foreach ($name in $fixtures.Keys) {
        $path = Join-Path $reportsDirectory $name
        [IO.File]::WriteAllText($path, ($fixtures[$name] | ConvertTo-Json -Depth 30), $utf8WithoutBom)
        $sourceHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }

    $firstOutput = Join-Path $outputDirectory "cohort.json"
    $result = & $toolPath -InputDirectory $reportsDirectory -OutputPath $firstOutput
    $summary = Get-Content -Raw -Encoding UTF8 -LiteralPath $result.JsonPath | ConvertFrom-Json
    Assert-True ($summary.cohort_status -eq "needs_attention") "A selected failed session should require attention."
    Assert-True ([int]$summary.total_assessment_files -eq 3 -and [int]$summary.unique_sessions -eq 2 -and [int]$summary.duplicate_assessments_ignored -eq 1) "The cohort should keep the newest assessment for one duplicated operation session without merging another operation."
    Assert-True ([int]$summary.gate_status_counts.pass -eq 1 -and [int]$summary.gate_status_counts.fail -eq 1) "Gate counts should describe unique sessions only."
    Assert-True ([double]$summary.metrics.first_effective_command_seconds.median -eq 15.0) "Cohort metrics should use deduplicated sessions."
    Assert-True ([int]$summary.scenario_counts.grey_ridge -eq 1 -and [int]$summary.scenario_counts.broken_bridge -eq 1) "Cohort output should expose per-operation assessment coverage."
    Assert-True ([int]$summary.session_context_counts.display_resolution."1280x720" -eq 2 -and [int]$summary.session_context_counts.input_device.mouse -eq 2) "Cohort output should expose structured environment coverage."
    Assert-True (@($summary.priority_issues | Where-Object { $_.check -eq "enemy_reaction_explanation" }).Count -eq 1) "Repeated check failures should be exposed as priority issues."
    Assert-True ([IO.File]::Exists($result.MarkdownPath)) "The cohort tool should create a human-readable Markdown summary."

    $legacyContextPath = Join-Path $reportsDirectory "legacy-missing-context_assessment.json"
    $legacyContextFixture = New-Assessment "session-c" "grey_ridge" 3000 400 "pass" "pass" 12.0
    $legacyContextFixture.Remove("session_context")
    [IO.File]::WriteAllText($legacyContextPath, ($legacyContextFixture | ConvertTo-Json -Depth 30), $utf8WithoutBom)
    $sourceHashes[$legacyContextPath] = (Get-FileHash -LiteralPath $legacyContextPath -Algorithm SHA256).Hash
    $contextOutput = Join-Path $outputDirectory "cohort-missing-context.json"
    $contextResult = & $toolPath -InputDirectory $reportsDirectory -OutputPath $contextOutput
    $contextSummary = Get-Content -Raw -Encoding UTF8 -LiteralPath $contextResult.JsonPath | ConvertFrom-Json
    Assert-True ([int]$contextSummary.missing_session_context_count -eq 1) "Missing structured environment evidence should be counted."
    Assert-True (@($contextSummary.priority_issues | Where-Object { $_.check -eq "session_context" -and [int]$_.missing -eq 1 }).Count -eq 1) "Missing session context should be exposed as a priority issue."

    $invalidPath = Join-Path $reportsDirectory "broken_assessment.json"
    [IO.File]::WriteAllText($invalidPath, "{broken", $utf8WithoutBom)
    $secondOutput = Join-Path $outputDirectory "cohort-invalid.json"
    $invalidResult = & $toolPath -InputDirectory $reportsDirectory -OutputPath $secondOutput
    $invalidSummary = Get-Content -Raw -Encoding UTF8 -LiteralPath $invalidResult.JsonPath | ConvertFrom-Json
    Assert-True ($invalidSummary.cohort_status -eq "invalid_reports" -and @($invalidSummary.invalid_reports).Count -eq 1) "Malformed assessment files should prevent a clean cohort status without erasing valid sessions."

    foreach ($path in $sourceHashes.Keys) {
        Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $sourceHashes[$path]) "Cohort generation must not modify assessment sources."
    }
    Write-Host "WARSEED playtest cohort smoke passed: operation-aware dedupe, coverage, metrics, priority issues, invalid report, immutable sources"
}
finally {
    if ([IO.Directory]::Exists($temporaryRoot) -and $temporaryRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($temporaryRoot, $true)
    }
}
