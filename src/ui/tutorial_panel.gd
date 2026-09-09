class_name TutorialPanel
extends VBoxContainer

enum Step {
	COMMANDER_OBJECTIVE,
	AIR_RECON,
	RESERVE_DEPLOYMENT,
	FORMATION_ROUTE,
	RETURN_TO_COMMANDER,
	BATTLE_DEBRIEF,
	COMPLETE,
}

const STEP_COUNT := 6
const STEP_FACTS := [
	&"commander_objective",
	&"air_recon",
	&"reserve_deployment",
	&"formation_route",
	&"return_to_commander",
	&"battle_debrief",
]
const BLACK_WELL_STEP_FACTS := [
	&"black_well_lu_objective",
	&"black_well_second_axis",
	&"black_well_reinforcement",
	&"black_well_withdrawal",
	&"battle_debrief",
	&"black_well_continuity",
]

@onready var title_label: Label = $Header/Title
@onready var skip_button: Button = $Header/Skip
@onready var progress_bar: ProgressBar = $Progress
@onready var step_title_label: Label = $StepTitle
@onready var step_body_label: Label = $StepBody
@onready var condition_label: Label = $Condition

var simulation_host: SimulationHost
var current_step: Step = Step.COMMANDER_OBJECTIVE
var persistence_enabled := true
var _facts: Dictionary = {}
var _pending_facts: Dictionary = {}
var _initial_reserve_cards: Dictionary = {}
var _observed_override_cards: Dictionary = {}
var _initial_intel_report_count := -1
var _last_rejection_reason := -1
var _active := false


func _ready() -> void:
	progress_bar.max_value = STEP_COUNT
	progress_bar.show_percentage = false
	if not skip_button.pressed.is_connected(skip):
		skip_button.pressed.connect(skip)
	visible = false
	refresh_locale()


func configure(host: SimulationHost) -> void:
	simulation_host = host
	if simulation_host == null:
		visible = false
		return
	if not simulation_host.grey_ridge_battle_started.is_connected(_on_battle_started):
		simulation_host.grey_ridge_battle_started.connect(_on_battle_started)
	if not simulation_host.grey_ridge_prebattle_opened.is_connected(_on_prebattle_opened):
		simulation_host.grey_ridge_prebattle_opened.connect(_on_prebattle_opened)
	if not simulation_host.player_action_recorded.is_connected(observe_player_action):
		simulation_host.player_action_recorded.connect(observe_player_action)
	if not simulation_host.command_evaluated.is_connected(observe_command_result):
		simulation_host.command_evaluated.connect(observe_command_result)
	if not simulation_host.campaign_concluded.is_connected(_on_campaign_concluded):
		simulation_host.campaign_concluded.connect(_on_campaign_concluded)
	if simulation_host.is_grey_ridge_battle_started():
		begin_from_preference()


func begin_from_preference() -> void:
	var scenario_id := _scenario_id()
	if persistence_enabled and not TutorialProgressStore.is_scenario_enabled(scenario_id):
		_active = false
		visible = false
		return
	if persistence_enabled:
		TutorialProgressStore.begin_scenario(scenario_id)
	begin()


func begin() -> void:
	_facts.clear()
	_pending_facts.clear()
	_initial_reserve_cards.clear()
	_observed_override_cards.clear()
	_initial_intel_report_count = -1
	_last_rejection_reason = -1
	current_step = Step.COMMANDER_OBJECTIVE
	_active = true
	visible = true
	refresh_locale()


func skip() -> void:
	if not _active:
		return
	if simulation_host != null:
		simulation_host.record_playtest_ui_event("tutorial_skipped", _step_facts()[int(current_step)])
	if persistence_enabled:
		TutorialProgressStore.mark_scenario_skipped(_scenario_id())
	_active = false
	visible = false


func observe_player_action(descriptor: Dictionary) -> void:
	if not _active or descriptor.is_empty():
		return
	var category := String(descriptor.get("category", ""))
	var action := String(descriptor.get("action", ""))
	if _is_black_well():
		if category == "unit_card" and action == "deploy":
			_facts[&"black_well_reinforcement"] = true
		elif category == "growth" and action == "apply":
			_facts[&"black_well_growth_selected"] = true
			if persistence_enabled:
				TutorialProgressStore.mark_black_well_growth_pending(
					StringName(descriptor.get("subject", "")),
					StringName(descriptor.get("growth_id", ""))
				)
		_advance_satisfied_steps()
		return
	var subject := StringName(descriptor.get("subject", ""))
	if category == "commander" and action in ["objective", "intent"]:
		_pending_facts[&"commander_objective"] = subject
	elif category == "support" and action == "air_recon":
		_pending_facts[&"air_recon"] = true
	elif category == "unit_card" and action == "deploy":
		_pending_facts[&"reserve_deployment"] = subject
	elif category == "unit_card" and bool(descriptor.get("route_planned", false)):
		_pending_facts[&"formation_route"] = subject
	elif category == "unit_card" and action == "return_to_commander":
		_pending_facts[&"return_to_commander"] = subject
	refresh_locale()


func observe_snapshot(snapshot: WorldSnapshot) -> void:
	if not _active or snapshot == null:
		return
	if _initial_intel_report_count < 0:
		_initialize_snapshot_baseline(snapshot)
	if not _is_black_well():
		_observe_standard_snapshot(snapshot)
		_advance_satisfied_steps()
		return
	var lu := snapshot.get_commander(&"lu_zheng")
	var gu := snapshot.get_commander(&"gu_hanxing")
	if lu != null and lu.target_region_id == &"black_well_core":
		_facts[&"black_well_lu_objective"] = true
	if lu != null and gu != null and not gu.target_region_id.is_empty() \
			and gu.target_region_id != lu.target_region_id:
		_facts[&"black_well_second_axis"] = true
	for task in snapshot.tasks:
		if task.faction_id == SimulationWorld.LOCAL_PLAYER_ID and task.reinforcement_committed:
			_facts[&"black_well_reinforcement"] = true
			break
	for card in snapshot.unit_cards:
		if card.faction_id == SimulationWorld.LOCAL_PLAYER_ID \
				and card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
			_facts[&"black_well_withdrawal"] = true
			break
	_advance_satisfied_steps()


func observe_command_result(result: CommandValidationResult) -> void:
	if not _active or result == null:
		return
	_last_rejection_reason = -1 if result.is_accepted() else int(result.reason)
	refresh_locale()


func is_active() -> bool:
	return _active


func has_completed_fact(fact_id: StringName) -> bool:
	return bool(_facts.get(fact_id, false))


func refresh_locale() -> void:
	if title_label == null:
		return
	if current_step >= Step.COMPLETE:
		title_label.text = GameText.t(&"TUTORIAL_COMPLETE_TITLE")
		step_title_label.text = GameText.t(&"TUTORIAL_COMPLETE_STEP")
		step_body_label.text = GameText.t(&"TUTORIAL_COMPLETE_BODY")
		condition_label.text = ""
		progress_bar.value = STEP_COUNT
	else:
		var display_index := int(current_step) + 1
		title_label.text = GameText.t(&"TUTORIAL_TITLE") % [display_index, STEP_COUNT]
		var key_prefix := "TUTORIAL_STEP_%d" % display_index
		if simulation_host != null:
			if simulation_host.get_scenario_id() == &"broken_bridge" and current_step == Step.FORMATION_ROUTE:
				key_prefix = "BROKEN_BRIDGE_TUTORIAL_ROUTE"
			elif simulation_host.get_scenario_id() == &"fog_forest":
				key_prefix = "FOG_FOREST_TUTORIAL_STEP_%d" % display_index
			elif simulation_host.get_scenario_id() == &"black_well":
				key_prefix = "BLACK_WELL_TUTORIAL_STEP_%d" % display_index
		step_title_label.text = GameText.t(StringName(key_prefix + "_TITLE"))
		step_body_label.text = GameText.t(StringName(key_prefix + "_BODY"))
		condition_label.text = GameText.t(StringName(key_prefix + "_CONDITION"))
		if _last_rejection_reason >= 0:
			var rejection := CommandValidationResult.new(CommandValidationResult.Status.REJECTED, _last_rejection_reason)
			condition_label.text += "\n" + GameText.t(&"TUTORIAL_REJECTION_HINT") % GameText.command_result(rejection)
		elif _has_pending_fact(_step_facts()[int(current_step)]):
			condition_label.text += "\n" + GameText.t(&"TUTORIAL_WAITING_CONFIRMATION")
		progress_bar.value = int(current_step)
	skip_button.text = GameText.t(&"TUTORIAL_SKIP")
	skip_button.tooltip_text = GameText.t(&"TUTORIAL_SKIP_TOOLTIP")


func _advance_satisfied_steps() -> void:
	var step_facts := _step_facts()
	while current_step < Step.COMPLETE and bool(_facts.get(step_facts[int(current_step)], false)):
		if simulation_host != null:
			simulation_host.record_playtest_ui_event("tutorial_step_completed", step_facts[int(current_step)])
		current_step = int(current_step) + 1
	if current_step == Step.COMPLETE:
		_complete()
	else:
		refresh_locale()


func _complete() -> void:
	if persistence_enabled:
		TutorialProgressStore.mark_scenario_completed(_scenario_id())
	if simulation_host != null:
		simulation_host.record_playtest_ui_event("tutorial_completed")
	_active = false
	visible = false


func _on_battle_started(_snapshot: WorldSnapshot) -> void:
	begin_from_preference()
	if _active:
		_initialize_snapshot_baseline(_snapshot)


func _on_prebattle_opened(_plan: ArmyPlan) -> void:
	_active = false
	visible = false


func _on_campaign_concluded(_record: Dictionary) -> void:
	if not _active:
		return
	_facts[&"battle_debrief"] = true
	_advance_satisfied_steps()


func _step_facts() -> Array:
	return BLACK_WELL_STEP_FACTS if _is_black_well() else STEP_FACTS


func _is_black_well() -> bool:
	return simulation_host != null and simulation_host.get_scenario_id() == &"black_well"


func _scenario_id() -> StringName:
	return simulation_host.get_scenario_id() if simulation_host != null else &"grey_ridge"


func _initialize_snapshot_baseline(snapshot: WorldSnapshot) -> void:
	_initial_intel_report_count = snapshot.intel_reports.size()
	_initial_reserve_cards.clear()
	for card in snapshot.unit_cards:
		if card.faction_id == SimulationWorld.LOCAL_PLAYER_ID and card.deployment_state == UnitCardState.DeploymentState.RESERVE:
			_initial_reserve_cards[card.definition_id] = true


func _has_pending_fact(fact_id: StringName) -> bool:
	if not _pending_facts.has(fact_id):
		return false
	var value: Variant = _pending_facts[fact_id]
	return value if value is bool else not String(value).is_empty()


func _observe_standard_snapshot(snapshot: WorldSnapshot) -> void:
	var commander_id := StringName(_pending_facts.get(&"commander_objective", &""))
	if not commander_id.is_empty():
		var commander := snapshot.get_commander(commander_id)
		if commander != null and not commander.current_task_ids.is_empty() and not commander.target_region_id.is_empty():
			_facts[&"commander_objective"] = true
	if bool(_pending_facts.get(&"air_recon", false)) and snapshot.intel_reports.size() > _initial_intel_report_count:
		_facts[&"air_recon"] = true
	var deployed_card_id := StringName(_pending_facts.get(&"reserve_deployment", &""))
	if not deployed_card_id.is_empty() and _initial_reserve_cards.has(deployed_card_id):
		var deployed := snapshot.get_unit_card(deployed_card_id)
		if deployed != null and deployed.deployment_state in [UnitCardState.DeploymentState.DEPLOYING, UnitCardState.DeploymentState.DEPLOYED]:
			_facts[&"reserve_deployment"] = true
	var route_card_id := StringName(_pending_facts.get(&"formation_route", &""))
	if not route_card_id.is_empty():
		var routed := snapshot.get_unit_card(route_card_id)
		var route_formation := snapshot.get_formation(routed.formation_id) if routed != null else null
		if routed != null and routed.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.PLAYER_CONTROLLED]:
			_observed_override_cards[route_card_id] = true
			if route_formation != null and (route_formation.is_moving or not route_formation.planned_route.is_empty()):
				_facts[&"formation_route"] = true
	var returning_card_id := StringName(_pending_facts.get(&"return_to_commander", &""))
	if not returning_card_id.is_empty() and _observed_override_cards.has(returning_card_id):
		var returned := snapshot.get_unit_card(returning_card_id)
		if returned != null and returned.control_state in [UnitCardState.ControlState.RETURNING, UnitCardState.ControlState.AGENT_ASSIGNED]:
			_facts[&"return_to_commander"] = true
