[CmdletBinding()]
param(
    [string]$RecordPath = "",
    [ValidateSet("grey_ridge", "broken_bridge", "fog_forest", "black_well")]
    [string]$ScenarioId = "grey_ridge",
    [string]$OutputPath = "",
    [string]$ObserverId = "",
    [string]$CardEntityRecognition = "",
    [string]$CardEntityRecognitionNote = "",
    [string]$CommanderBehaviorExplanation = "",
    [string]$CommanderBehaviorExplanationNote = "",
    [string]$EnemyReactionExplanation = "",
    [string]$EnemyReactionExplanationNote = "",
    [string]$SecondBattleIntent = "",
    [string]$SecondBattleIntentNote = "",
    [string]$OperationRuleExplanation = "",
    [string]$OperationRuleExplanationNote = "",
    [string]$DisplayResolution = "",
    [string]$InputDevice = "",
    [string]$InterfaceLanguage = "",
    [string]$ParticipantGroup = "",
    [string]$Notes = "",
    [switch]$RequireContext,
    [switch]$RequirePass
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$supportedScenarioIds = @("grey_ridge", "broken_bridge", "fog_forest", "black_well")

function Get-RecordValue {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$DefaultValue
    )

    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }
    return $property.Value
}

function Get-ObserverCheck {
    param(
        [string]$Value,
        [string]$Note,
        [string]$Prompt
    )

    $wasInteractive = [string]::IsNullOrWhiteSpace($Value)
    while ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = Read-Host "$Prompt [pass/fail/not_observed]"
    }
    $Value = $Value.Trim().ToLowerInvariant()
    if ($Value -notin @("pass", "fail", "not_observed")) {
        throw "Invalid observer result '$Value'. Use pass, fail, or not_observed."
    }
    if ($wasInteractive -and [string]::IsNullOrWhiteSpace($Note)) {
        $Note = Read-Host "Evidence or player quote (optional)"
    }
    return [ordered]@{
        result = $Value
        evidence = $Note.Trim()
    }
}

function New-AutomaticCheck {
    param(
        [bool]$Passed,
        [object]$Evidence
    )

    return [ordered]@{
        result = $(if ($Passed) { "pass" } else { "fail" })
        evidence = $Evidence
    }
}

function Get-SessionContextValue {
    param(
        [string]$Value,
        [string]$Prompt,
        [string[]]$AllowedValues,
        [string]$Pattern,
        [bool]$Required
    )

    if ([string]::IsNullOrWhiteSpace($Value) -and $Required) {
        $Value = Read-Host $Prompt
    }
    $Value = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    if ($AllowedValues.Count -gt 0) {
        $match = @($AllowedValues | Where-Object { $_.Equals($Value, [StringComparison]::OrdinalIgnoreCase) })
        if ($match.Count -eq 0) {
            throw "Invalid $Prompt '$Value'. Allowed values: $($AllowedValues -join ', ')."
        }
        return [string]$match[0]
    }
    if (-not [string]::IsNullOrWhiteSpace($Pattern) -and $Value -notmatch $Pattern) {
        throw "Invalid $Prompt '$Value'."
    }
    return $Value
}

if ([string]::IsNullOrWhiteSpace($RecordPath)) {
    $applicationData = [Environment]::GetFolderPath("ApplicationData")
    $RecordPath = Join-Path $applicationData ("Godot\app_userdata\WARSEED\playtests\latest_{0}.json" -f $ScenarioId)
}
if (-not (Test-Path -LiteralPath $RecordPath -PathType Leaf)) {
    throw "Playtest record not found: $RecordPath"
}

$sourcePath = (Resolve-Path -LiteralPath $RecordPath).Path
$recordText = [IO.File]::ReadAllText($sourcePath, [Text.Encoding]::UTF8)
$record = $recordText | ConvertFrom-Json
if ($null -eq $record) {
    throw "Playtest record is not valid JSON: $sourcePath"
}
$recordScenarioId = [string](Get-RecordValue $record "scenario_id" "")
if ($recordScenarioId -notin $supportedScenarioIds) {
    throw "Unsupported WARSEED playtest scenario '$recordScenarioId'."
}

$DisplayResolution = Get-SessionContextValue $DisplayResolution "display resolution (for example 1280x720)" @() "^[0-9]{3,5}x[0-9]{3,5}$" ([bool]$RequireContext)
$InputDevice = Get-SessionContextValue $InputDevice "primary pointer device [mouse/touchpad/other]" @("mouse", "touchpad", "other") "" ([bool]$RequireContext)
$InterfaceLanguage = Get-SessionContextValue $InterfaceLanguage "interface language [zh_CN/en]" @("zh_CN", "en") "" ([bool]$RequireContext)
$ParticipantGroup = Get-SessionContextValue $ParticipantGroup "pre-registered participant id (for example p67-01)" @() "^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$" ([bool]$RequireContext)

$commandTimes = @(
    @(
        [double](Get-RecordValue $record "first_commander_command_seconds" -1.0),
        [double](Get-RecordValue $record "first_unit_card_command_seconds" -1.0)
    ) | Where-Object { $_ -ge 0.0 }
)
$firstEffectiveCommandSeconds = -1.0
if ($commandTimes.Count -gt 0) {
    $firstEffectiveCommandSeconds = [double](($commandTimes | Measure-Object -Minimum).Minimum)
}

$automaticChecks = [ordered]@{
    battle_completed = New-AutomaticCheck ([bool](Get-RecordValue $record "completed" $false)) ([ordered]@{
        completed = [bool](Get-RecordValue $record "completed" $false)
        result = [string](Get-RecordValue $record "result" "unknown")
    })
    first_effective_command_within_30_seconds = New-AutomaticCheck ($firstEffectiveCommandSeconds -ge 0.0 -and $firstEffectiveCommandSeconds -le 30.0) ([ordered]@{
        seconds = $firstEffectiveCommandSeconds
        threshold_seconds = 30.0
    })
    intel_followed_by_player_action = New-AutomaticCheck ([int](Get-RecordValue $record "intel_actions_measured" 0) -ge 1) ([ordered]@{
        measured_actions = [int](Get-RecordValue $record "intel_actions_measured" 0)
        average_delay_seconds = [double](Get-RecordValue $record "average_intel_action_delay_seconds" -1.0)
    })
    whole_card_takeover_and_return = New-AutomaticCheck (
        [int](Get-RecordValue $record "takeovers" 0) -ge 1 -and
        [int](Get-RecordValue $record "returns_to_commander" 0) -ge 1
    ) ([ordered]@{
        takeovers = [int](Get-RecordValue $record "takeovers" 0)
        returns_to_commander = [int](Get-RecordValue $record "returns_to_commander" 0)
    })
    no_individual_diagnostic_attempt = New-AutomaticCheck ([int](Get-RecordValue $record "diagnostic_individual_mode_activations" 0) -eq 0) ([ordered]@{
        diagnostic_individual_mode_activations = [int](Get-RecordValue $record "diagnostic_individual_mode_activations" 0)
    })
    no_agent_override_conflict = New-AutomaticCheck ([int](Get-RecordValue $record "agent_override_rejections" 0) -eq 0) ([ordered]@{
        agent_override_rejections = [int](Get-RecordValue $record "agent_override_rejections" 0)
    })
}

$observerChecks = [ordered]@{
    card_entity_recognition = Get-ObserverCheck $CardEntityRecognition $CardEntityRecognitionNote "Player correctly explained how a unit card maps to battlefield entities"
    commander_behavior_explanation = Get-ObserverCheck $CommanderBehaviorExplanation $CommanderBehaviorExplanationNote "Player explained why one commander advanced, stopped, withdrew, or requested support"
    enemy_reaction_explanation = Get-ObserverCheck $EnemyReactionExplanation $EnemyReactionExplanationNote "Player understood one enemy reaction as a locked-plan or legal-intelligence response"
    second_battle_intent = Get-ObserverCheck $SecondBattleIntent $SecondBattleIntentNote "Player wanted to try a different composition, doctrine, route, or main effort"
    operation_rule_explanation = $(if ($recordScenarioId -eq "grey_ridge") {
        [ordered]@{ result = "not_applicable"; evidence = "Base onboarding operation" }
    }
    else {
        Get-ObserverCheck $OperationRuleExplanation $OperationRuleExplanationNote "Player explained how this operation's new rule changed a decision"
    })
}

$failedChecks = [Collections.Generic.List[string]]::new()
$missingChecks = [Collections.Generic.List[string]]::new()
foreach ($entry in $automaticChecks.GetEnumerator()) {
    if ($entry.Value.result -eq "fail") {
        $failedChecks.Add("automatic:$($entry.Key)")
    }
}
foreach ($entry in $observerChecks.GetEnumerator()) {
    if ($entry.Value.result -eq "fail") {
        $failedChecks.Add("observer:$($entry.Key)")
    }
    elseif ($entry.Value.result -eq "not_observed") {
        $missingChecks.Add("observer:$($entry.Key)")
    }
}

$gateStatus = "pass"
if ($failedChecks.Count -gt 0) {
    $gateStatus = "fail"
}
elseif ($missingChecks.Count -gt 0) {
    $gateStatus = "incomplete"
}

$report = [ordered]@{
    schema_version = 2
    scenario_id = $recordScenarioId
    playtest_session_id = [string](Get-RecordValue $record "playtest_session_id" "")
    source_record = $sourcePath
    assessed_unix_time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    observer_id = $ObserverId.Trim()
    session_context = [ordered]@{
        display_resolution = $DisplayResolution
        input_device = $InputDevice
        interface_language = $InterfaceLanguage
        participant_group = $ParticipantGroup
    }
    gate_status = $gateStatus
    automatic_checks = $automaticChecks
    observer_checks = $observerChecks
    failed_checks = @($failedChecks)
    missing_checks = @($missingChecks)
    notes = $Notes.Trim()
    session = $record
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $battleNumber = [int](Get-RecordValue $record "battle_number" 1)
    $startedUnixTime = [long](Get-RecordValue $record "started_unix_time" 0)
    $fileName = "{0}_b{1:d3}_{2}_assessment.json" -f $recordScenarioId, $battleNumber, $startedUnixTime
    $OutputPath = Join-Path ([IO.Path]::GetDirectoryName($sourcePath)) $fileName
}
elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path $OutputPath
}
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ([StringComparer]::OrdinalIgnoreCase.Equals($resolvedOutputPath, [IO.Path]::GetFullPath($sourcePath))) {
    throw "Assessment output must not overwrite the raw playtest record."
}
$outputDirectory = [IO.Path]::GetDirectoryName($resolvedOutputPath)
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($resolvedOutputPath, ($report | ConvertTo-Json -Depth 100), $utf8WithoutBom)

Write-Host "WARSEED $recordScenarioId playtest gate: $($gateStatus.ToUpperInvariant())"
foreach ($entry in $automaticChecks.GetEnumerator()) {
    Write-Host ("  automatic {0}: {1}" -f $entry.Key, $entry.Value.result)
}
foreach ($entry in $observerChecks.GetEnumerator()) {
    Write-Host ("  observer  {0}: {1}" -f $entry.Key, $entry.Value.result)
}
Write-Host "Assessment report: $resolvedOutputPath"

if ($RequirePass -and $gateStatus -ne "pass") {
    exit 2
}
