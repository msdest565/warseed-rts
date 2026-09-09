[CmdletBinding()]
param(
    [string]$InputDirectory = "",
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$supportedScenarioIds = @("grey_ridge", "broken_bridge", "fog_forest", "black_well")

function Get-Value {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }
    return $property.Value
}

function Add-Count {
    param(
        [System.Collections.IDictionary]$Counts,
        [string]$Key
    )

    if (-not $Counts.Contains($Key)) {
        $Counts[$Key] = 0
    }
    $Counts[$Key] = [int]$Counts[$Key] + 1
}

function Add-CheckResult {
    param(
        [System.Collections.IDictionary]$Aggregate,
        [string]$CheckName,
        [string]$Result,
        [string[]]$AllowedResults
    )

    if (-not $Aggregate.Contains($CheckName)) {
        $Aggregate[$CheckName] = [ordered]@{}
        foreach ($allowed in $AllowedResults) {
            $Aggregate[$CheckName][$allowed] = 0
        }
        $Aggregate[$CheckName]["missing"] = 0
    }
    $normalizedResult = $Result.Trim().ToLowerInvariant()
    if ($normalizedResult -notin $AllowedResults) {
        $normalizedResult = "missing"
    }
    $Aggregate[$CheckName][$normalizedResult] = [int]$Aggregate[$CheckName][$normalizedResult] + 1
}

function Get-FirstEffectiveCommandSeconds {
    param([object]$Session)

    $values = @(
        @(
            [double](Get-Value $Session "first_commander_command_seconds" -1.0),
            [double](Get-Value $Session "first_unit_card_command_seconds" -1.0)
        ) | Where-Object { $_ -ge 0.0 }
    )
    if ($values.Count -eq 0) {
        return -1.0
    }
    return [double](($values | Measure-Object -Minimum).Minimum)
}

function Get-MetricSummary {
    param([System.Collections.Generic.List[double]]$Values)

    if ($Values.Count -eq 0) {
        return [ordered]@{ count = 0; average = $null; median = $null }
    }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2.0)
    $median = if ($sorted.Count % 2 -eq 0) {
        ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
    }
    else {
        [double]$sorted[$middle]
    }
    return [ordered]@{
        count = $Values.Count
        average = [double](($Values | Measure-Object -Average).Average)
        median = $median
    }
}

if ([string]::IsNullOrWhiteSpace($InputDirectory)) {
    $applicationData = [Environment]::GetFolderPath("ApplicationData")
    $InputDirectory = Join-Path $applicationData "Godot\app_userdata\WARSEED\playtest_runs"
}
if (-not [IO.Directory]::Exists($InputDirectory)) {
    throw "Playtest assessment directory not found: $InputDirectory"
}
$resolvedInputDirectory = [IO.Path]::GetFullPath($InputDirectory)

$assessmentFiles = @(Get-ChildItem -LiteralPath $resolvedInputDirectory -Recurse -File -Filter "*_assessment.json" | Sort-Object FullName)
$selectedReports = @{}
$invalidReports = [Collections.Generic.List[object]]::new()
$duplicateAssessmentsIgnored = 0

foreach ($file in $assessmentFiles) {
    try {
        $report = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
        $scenarioId = [string](Get-Value $report "scenario_id" "")
        $schemaVersion = [int](Get-Value $report "schema_version" 0)
        if ($null -eq $report -or $schemaVersion -notin @(1, 2) -or $scenarioId -notin $supportedScenarioIds) {
            throw "Unsupported WARSEED operation assessment schema."
        }
        $gateStatus = [string](Get-Value $report "gate_status" "")
        if ($gateStatus -notin @("pass", "fail", "incomplete")) {
            throw "Unknown gate_status '$gateStatus'."
        }
        $session = Get-Value $report "session" $null
        if ($null -eq $session) {
            throw "Assessment does not contain its raw session summary."
        }
        $sessionId = [string](Get-Value $report "playtest_session_id" (Get-Value $session "playtest_session_id" ""))
        $startedUnixTime = [long](Get-Value $session "started_unix_time" 0)
        $battleNumber = [int](Get-Value $session "battle_number" 0)
        $sourceRecord = [string](Get-Value $report "source_record" "")
        $dedupeKey = if (-not [string]::IsNullOrWhiteSpace($sessionId) -or $startedUnixTime -gt 0 -or $battleNumber -gt 0) {
            "session|$sessionId|$scenarioId|$startedUnixTime|$battleNumber"
        }
        else {
            "source|$sourceRecord"
        }
        $candidate = [pscustomobject]@{
            Path = $file.FullName
            Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            AssessedUnixTime = [long](Get-Value $report "assessed_unix_time" 0)
            DedupeKey = $dedupeKey
            Report = $report
        }
        if ($selectedReports.ContainsKey($dedupeKey)) {
            $duplicateAssessmentsIgnored += 1
            if ($candidate.AssessedUnixTime -gt $selectedReports[$dedupeKey].AssessedUnixTime) {
                $selectedReports[$dedupeKey] = $candidate
            }
        }
        else {
            $selectedReports[$dedupeKey] = $candidate
        }
    }
    catch {
        $invalidReports.Add([ordered]@{
            file = $file.FullName.Substring($resolvedInputDirectory.Length).TrimStart([IO.Path]::DirectorySeparatorChar).Replace("\", "/")
            error = $_.Exception.Message
        })
    }
}

$gateStatusCounts = [ordered]@{ pass = 0; fail = 0; incomplete = 0 }
$automaticChecks = [ordered]@{}
$observerChecks = [ordered]@{}
$openingPlans = [ordered]@{}
$battleResults = [ordered]@{}
$scenarioCounts = [ordered]@{}
$resolutionCounts = [ordered]@{}
$inputDeviceCounts = [ordered]@{}
$languageCounts = [ordered]@{}
$participantGroupCounts = [ordered]@{}
$observerIds = @{}
$sessionRows = [Collections.Generic.List[object]]::new()
$firstCommandSeconds = [Collections.Generic.List[double]]::new()
$prebattleSeconds = [Collections.Generic.List[double]]::new()
$replansPerMinute = [Collections.Generic.List[double]]::new()
$intelDelaySeconds = [Collections.Generic.List[double]]::new()
$directControlRatios = [Collections.Generic.List[double]]::new()
$requestedSecondBattleCount = 0
$missingSessionContextCount = 0

foreach ($item in @($selectedReports.Values | Sort-Object AssessedUnixTime, Path)) {
    $report = $item.Report
    $session = $report.session
    $scenarioId = [string](Get-Value $report "scenario_id" (Get-Value $session "scenario_id" "unknown"))
    $gateStatus = [string]$report.gate_status
    Add-Count $gateStatusCounts $gateStatus
    Add-Count $scenarioCounts $scenarioId
    $sessionContext = Get-Value $report "session_context" $null
    $displayResolution = [string](Get-Value $sessionContext "display_resolution" "missing")
    $inputDevice = [string](Get-Value $sessionContext "input_device" "missing")
    $interfaceLanguage = [string](Get-Value $sessionContext "interface_language" "missing")
    $participantGroup = [string](Get-Value $sessionContext "participant_group" "missing")
    if ([string]::IsNullOrWhiteSpace($displayResolution)) { $displayResolution = "missing" }
    if ([string]::IsNullOrWhiteSpace($inputDevice)) { $inputDevice = "missing" }
    if ([string]::IsNullOrWhiteSpace($interfaceLanguage)) { $interfaceLanguage = "missing" }
    if ([string]::IsNullOrWhiteSpace($participantGroup)) { $participantGroup = "missing" }
    if ($displayResolution -eq "missing" -or $inputDevice -eq "missing" -or $interfaceLanguage -eq "missing" -or $participantGroup -eq "missing") {
        $missingSessionContextCount += 1
    }
    Add-Count $resolutionCounts $displayResolution
    Add-Count $inputDeviceCounts $inputDevice
    Add-Count $languageCounts $interfaceLanguage
    Add-Count $participantGroupCounts $participantGroup

    foreach ($property in $report.automatic_checks.PSObject.Properties) {
        Add-CheckResult $automaticChecks $property.Name ([string](Get-Value $property.Value "result" "missing")) @("pass", "fail")
    }
    foreach ($property in $report.observer_checks.PSObject.Properties) {
        Add-CheckResult $observerChecks $property.Name ([string](Get-Value $property.Value "result" "missing")) @("pass", "fail", "not_observed", "not_applicable")
    }

    $openingPlan = [string](Get-Value $session "opening_plan_id" "unknown")
    $battleResult = [string](Get-Value $session "result" "unknown")
    Add-Count $openingPlans $openingPlan
    Add-Count $battleResults $battleResult
    $observerId = [string](Get-Value $report "observer_id" "")
    if (-not [string]::IsNullOrWhiteSpace($observerId)) {
        $observerIds[$observerId] = $true
    }

    $firstCommand = Get-FirstEffectiveCommandSeconds $session
    if ($firstCommand -ge 0.0) { $firstCommandSeconds.Add($firstCommand) }
    $prebattle = [double](Get-Value $session "prebattle_duration_seconds" -1.0)
    if ($prebattle -ge 0.0) { $prebattleSeconds.Add($prebattle) }
    $replans = [double](Get-Value $session "replans_per_minute" -1.0)
    if ($replans -ge 0.0) { $replansPerMinute.Add($replans) }
    $intelDelay = [double](Get-Value $session "average_intel_action_delay_seconds" -1.0)
    if ($intelDelay -ge 0.0) { $intelDelaySeconds.Add($intelDelay) }
    $directRatio = [double](Get-Value $session "direct_control_ratio" -1.0)
    if ($directRatio -ge 0.0) { $directControlRatios.Add($directRatio) }
    if ([bool](Get-Value $session "requested_second_battle" $false)) {
        $requestedSecondBattleCount += 1
    }

    $sessionRows.Add([ordered]@{
        playtest_session_id = [string](Get-Value $report "playtest_session_id" (Get-Value $session "playtest_session_id" ""))
        scenario_id = $scenarioId
        battle_number = [int](Get-Value $session "battle_number" 0)
        started_unix_time = [long](Get-Value $session "started_unix_time" 0)
        assessed_unix_time = [long](Get-Value $report "assessed_unix_time" 0)
        gate_status = $gateStatus
        opening_plan_id = $openingPlan
        battle_result = $battleResult
        observer_id = $observerId
        display_resolution = $displayResolution
        input_device = $inputDevice
        interface_language = $interfaceLanguage
        participant_group = $participantGroup
        report_file = $item.Path.Substring($resolvedInputDirectory.Length).TrimStart([IO.Path]::DirectorySeparatorChar).Replace("\", "/")
        report_sha256 = $item.Hash
    })
}

$priorityIssues = [Collections.Generic.List[object]]::new()
foreach ($key in $automaticChecks.Keys) {
    $counts = $automaticChecks[$key]
    if ([int]$counts.fail -gt 0 -or [int]$counts.missing -gt 0) {
        $priorityIssues.Add([ordered]@{ kind = "automatic"; check = $key; failures = [int]$counts.fail; missing = [int]$counts.missing })
    }
}
foreach ($key in $observerChecks.Keys) {
    $counts = $observerChecks[$key]
    $missing = [int]$counts.not_observed + [int]$counts.missing
    if ([int]$counts.fail -gt 0 -or $missing -gt 0) {
        $priorityIssues.Add([ordered]@{ kind = "observer"; check = $key; failures = [int]$counts.fail; missing = $missing })
    }
}
if ($missingSessionContextCount -gt 0) {
    $priorityIssues.Add([ordered]@{ kind = "context"; check = "session_context"; failures = 0; missing = $missingSessionContextCount })
}
$priorityIssues = @($priorityIssues | Sort-Object @{ Expression = { $_.failures }; Descending = $true }, @{ Expression = { $_.missing }; Descending = $true }, check)

$cohortStatus = "all_sessions_pass"
if ($assessmentFiles.Count -eq 0) {
    $cohortStatus = "no_data"
}
elseif ($invalidReports.Count -gt 0 -or $selectedReports.Count -eq 0) {
    $cohortStatus = "invalid_reports"
}
elseif ([int]$gateStatusCounts.fail -gt 0) {
    $cohortStatus = "needs_attention"
}
elseif ([int]$gateStatusCounts.incomplete -gt 0) {
    $cohortStatus = "incomplete"
}
elseif ($missingSessionContextCount -gt 0) {
    $cohortStatus = "incomplete"
}

$summary = [ordered]@{
    schema_version = 2
    scenario_ids = $supportedScenarioIds
    generated_utc = [DateTimeOffset]::UtcNow.ToString("o")
    source_directory = $resolvedInputDirectory
    cohort_status = $cohortStatus
    mvp_gate_claimed = $false
    sample_threshold_defined = $false
    total_assessment_files = $assessmentFiles.Count
    unique_sessions = $selectedReports.Count
    duplicate_assessments_ignored = $duplicateAssessmentsIgnored
    invalid_reports = @($invalidReports)
    gate_status_counts = $gateStatusCounts
    observer_id_count = $observerIds.Count
    missing_session_context_count = $missingSessionContextCount
    scenario_counts = $scenarioCounts
    session_context_counts = [ordered]@{
        display_resolution = $resolutionCounts
        input_device = $inputDeviceCounts
        interface_language = $languageCounts
        participant_group = $participantGroupCounts
    }
    opening_plan_counts = $openingPlans
    battle_result_counts = $battleResults
    requested_second_battle_count = $requestedSecondBattleCount
    automatic_checks = $automaticChecks
    observer_checks = $observerChecks
    metrics = [ordered]@{
        first_effective_command_seconds = Get-MetricSummary $firstCommandSeconds
        prebattle_duration_seconds = Get-MetricSummary $prebattleSeconds
        replans_per_minute = Get-MetricSummary $replansPerMinute
        average_intel_action_delay_seconds = Get-MetricSummary $intelDelaySeconds
        direct_control_ratio = Get-MetricSummary $directControlRatios
    }
    priority_issues = $priorityIssues
    sessions = @($sessionRows)
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $resolvedInputDirectory ("warseed_operation_cohort_{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}
elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path $OutputPath
}
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$markdownPath = [IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
if ([IO.File]::Exists($resolvedOutputPath) -or [IO.File]::Exists($markdownPath)) {
    throw "Cohort output already exists: $resolvedOutputPath"
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutputPath)) | Out-Null
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($resolvedOutputPath, ($summary | ConvertTo-Json -Depth 100), $utf8WithoutBom)

$markdown = [Text.StringBuilder]::new()
[void]$markdown.AppendLine("# WARSEED Operation Playtest Cohort")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("- Status: **$cohortStatus**")
[void]$markdown.AppendLine("- Unique sessions: $($selectedReports.Count)")
[void]$markdown.AppendLine("- Assessment files: $($assessmentFiles.Count)")
[void]$markdown.AppendLine("- Duplicate assessments ignored: $duplicateAssessmentsIgnored")
[void]$markdown.AppendLine("- Invalid reports: $($invalidReports.Count)")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("> This report describes the collected sample only. It does not claim the MVP gate has passed and does not define a required sample size.")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("## Gate Status")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("| Pass | Fail | Incomplete |")
[void]$markdown.AppendLine("|---:|---:|---:|")
[void]$markdown.AppendLine("| $($gateStatusCounts.pass) | $($gateStatusCounts.fail) | $($gateStatusCounts.incomplete) |")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("## Operation Coverage")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("| Operation | Assessments |")
[void]$markdown.AppendLine("|---|---:|")
foreach ($scenarioId in $supportedScenarioIds) {
    $scenarioCount = if ($scenarioCounts.Contains($scenarioId)) { [int]$scenarioCounts[$scenarioId] } else { 0 }
    [void]$markdown.AppendLine("| $scenarioId | $scenarioCount |")
}
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("## Session Context")
[void]$markdown.AppendLine("")
$resolutionSummary = @($resolutionCounts.Keys | ForEach-Object { "{0}={1}" -f $_, $resolutionCounts[$_] }) -join ", "
$inputDeviceSummary = @($inputDeviceCounts.Keys | ForEach-Object { "{0}={1}" -f $_, $inputDeviceCounts[$_] }) -join ", "
$languageSummary = @($languageCounts.Keys | ForEach-Object { "{0}={1}" -f $_, $languageCounts[$_] }) -join ", "
[void]$markdown.AppendLine("- Display resolutions: $resolutionSummary")
[void]$markdown.AppendLine("- Pointer devices: $inputDeviceSummary")
[void]$markdown.AppendLine("- Interface languages: $languageSummary")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("## Priority Issues")
[void]$markdown.AppendLine("")
if ($priorityIssues.Count -eq 0) {
    [void]$markdown.AppendLine("No failed or missing checks in the selected sessions.")
}
else {
    [void]$markdown.AppendLine("| Kind | Check | Failures | Missing |")
    [void]$markdown.AppendLine("|---|---|---:|---:|")
    foreach ($issue in $priorityIssues) {
        [void]$markdown.AppendLine("| $($issue.kind) | $($issue.check) | $($issue.failures) | $($issue.missing) |")
    }
}
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("## Metrics")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("| Metric | Samples | Average | Median |")
[void]$markdown.AppendLine("|---|---:|---:|---:|")
foreach ($property in $summary.metrics.GetEnumerator()) {
    $metric = $property.Value
    $average = if ($null -eq $metric.average) { "n/a" } else { "{0:F3}" -f [double]$metric.average }
    $median = if ($null -eq $metric.median) { "n/a" } else { "{0:F3}" -f [double]$metric.median }
    [void]$markdown.AppendLine("| $($property.Key) | $($metric.count) | $average | $median |")
}
[IO.File]::WriteAllText($markdownPath, $markdown.ToString(), $utf8WithoutBom)

Write-Host "WARSEED operation cohort summary: $cohortStatus ($($selectedReports.Count) unique operation sessions)"
Write-Host "JSON: $resolvedOutputPath"
Write-Host "Markdown: $markdownPath"
[pscustomobject]@{
    CohortStatus = $cohortStatus
    UniqueSessions = $selectedReports.Count
    JsonPath = $resolvedOutputPath
    MarkdownPath = $markdownPath
    JsonSHA256 = (Get-FileHash -LiteralPath $resolvedOutputPath -Algorithm SHA256).Hash
}
