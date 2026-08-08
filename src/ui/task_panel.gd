class_name TaskPanel
extends PanelContainer

signal headquarters_settings_changed

@onready var title_label: Label = $Margin/Layout/Intel/Title
@onready var mission_label: Label = $Margin/Layout/Intel/Mission
@onready var selection_title_label: Label = $Margin/Layout/Intel/SelectionTitle
@onready var selection_label: Label = $Margin/Layout/Intel/Selection
@onready var task_label: Label = $Margin/Layout/Intel/TaskStatus
@onready var strategic_title_label: Label = $Margin/Layout/Strategic/Title
@onready var headquarters_directive_label: Label = $Margin/Layout/Strategic/DirectiveLabel
@onready var headquarters_directive_selector: OptionButton = $Margin/Layout/Strategic/Directive
@onready var operations_title_label: Label = $Margin/Layout/Operations/Title
@onready var production_title_label: Label = $Margin/Layout/ProductionSection/Title
@onready var production_queue_label: Label = $Margin/Layout/ProductionSection/Queue
@onready var develop_button: Button = $Margin/Layout/Strategic/Commands/Develop
@onready var defend_button: Button = $Margin/Layout/Strategic/Commands/Defend
@onready var scout_button: Button = $Margin/Layout/Strategic/Commands/Scout
@onready var attack_button: Button = $Margin/Layout/Strategic/Commands/Attack
@onready var build_factory_button: Button = $Margin/Layout/Operations/Grid/BuildFactory
@onready var build_support_button: Button = $Margin/Layout/Operations/Grid/BuildSupport
@onready var repair_button: Button = $Margin/Layout/Operations/Grid/Repair
@onready var pause_button: Button = $Margin/Layout/Operations/Grid/Pause
@onready var resume_button: Button = $Margin/Layout/Operations/Grid/Resume
@onready var cancel_button: Button = $Margin/Layout/Operations/Grid/Cancel
@onready var harvest_button: Button = $Margin/Layout/Operations/Grid/Harvest
@onready var cancel_production_button: Button = $Margin/Layout/ProductionSection/Controls/CancelProduction
@onready var rally_button: Button = $Margin/Layout/ProductionSection/Controls/Rally
@onready var production_buttons: Array[Button] = [
	$Margin/Layout/ProductionSection/Grid/Harvester,
	$Margin/Layout/ProductionSection/Grid/Engineer,
	$Margin/Layout/ProductionSection/Grid/Scout,
	$Margin/Layout/ProductionSection/Grid/Assault,
	$Margin/Layout/ProductionSection/Grid/Missile,
]

const PRODUCTION_DEFINITIONS: Array[StringName] = [
	&"harvester", &"engineer_vehicle", &"scout_vehicle", &"assault_vehicle", &"missile_vehicle",
]

var simulation_host: SimulationHost
var input_controller: InputController
var current_task_id: int = 0
var last_status: String = "No active assignment"
var _signals_connected: bool = false


func _ready() -> void:
	if _signals_connected:
		refresh_locale()
		return
	_signals_connected = true
	develop_button.pressed.connect(_submit_develop)
	defend_button.pressed.connect(_submit_defend)
	scout_button.pressed.connect(_submit_scout)
	attack_button.pressed.connect(_submit_attack)
	headquarters_directive_selector.item_selected.connect(_select_headquarters_directive)
	build_factory_button.pressed.connect(_begin_build.bind(&"automated_factory"))
	build_support_button.pressed.connect(_begin_build.bind(&"forward_support_station"))
	repair_button.pressed.connect(_begin_repair)
	pause_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.PAUSE))
	resume_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.RESUME))
	cancel_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.CANCEL))
	harvest_button.pressed.connect(_begin_harvest)
	cancel_production_button.pressed.connect(_cancel_production)
	rally_button.pressed.connect(_begin_rally)
	for index in range(production_buttons.size()):
		production_buttons[index].pressed.connect(_produce.bind(PRODUCTION_DEFINITIONS[index]))
	refresh_locale()


func refresh_locale() -> void:
	for control in [title_label, mission_label, selection_title_label, selection_label, task_label, strategic_title_label, headquarters_directive_label, headquarters_directive_selector, operations_title_label, production_title_label, production_queue_label, develop_button, defend_button, scout_button, attack_button, build_factory_button, build_support_button, repair_button, pause_button, resume_button, cancel_button, harvest_button, cancel_production_button, rally_button]:
		(control as Control).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for button in production_buttons:
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = GameText.t(&"HUD_TITLE")
	selection_title_label.text = GameText.t(&"HUD_SELECTION")
	strategic_title_label.text = GameText.t(&"HUD_HEADQUARTERS")
	headquarters_directive_label.text = GameText.t(&"HQ_DIRECTIVE_LABEL")
	_populate_headquarters_directives()
	operations_title_label.text = GameText.t(&"HUD_OPERATIONS")
	production_title_label.text = GameText.t(&"HUD_PRODUCTION")
	develop_button.text = GameText.t(&"ORDER_DEVELOP")
	defend_button.text = GameText.t(&"ORDER_DEFEND")
	scout_button.text = GameText.t(&"ORDER_SCOUT")
	attack_button.text = GameText.t(&"ORDER_ATTACK")
	build_factory_button.text = _building_button_text(&"automated_factory", &"BUILD_FACTORY")
	build_support_button.text = _building_button_text(&"forward_support_station", &"BUILD_SUPPORT")
	repair_button.text = GameText.t(&"REPAIR_BUILDING")
	pause_button.text = GameText.t(&"TASK_PAUSE")
	resume_button.text = GameText.t(&"TASK_RESUME")
	cancel_button.text = GameText.t(&"TASK_CANCEL")
	harvest_button.text = GameText.t(&"ORDER_HARVEST")
	cancel_production_button.text = GameText.t(&"CANCEL_PRODUCTION")
	rally_button.text = GameText.t(&"SET_RALLY_POINT")
	for index in range(production_buttons.size()):
		production_buttons[index].text = _production_button_text(PRODUCTION_DEFINITIONS[index])
	if current_task_id == 0:
		last_status = GameText.t(&"TASK_NONE")


func update_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null:
		return
	var industrial_authorization := simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID)
	var battlefield_authorization := simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
	headquarters_directive_selector.select(simulation_host.get_headquarters_directive())
	strategic_title_label.text = GameText.t(&"HUD_HEADQUARTERS_AUTH") % [
		GameText.t(StringName("AI_AUTH_SHORT_%s" % AgentPolicy.Authorization.keys()[industrial_authorization])),
		GameText.t(StringName("AI_AUTH_SHORT_%s" % AgentPolicy.Authorization.keys()[battlefield_authorization])),
	]
	var active_task: TaskSnapshot
	var latest_task: TaskSnapshot
	var industrial_open := false
	var battlefield_open := false
	for task in snapshot.tasks:
		if task.kind == TaskState.Kind.FORMATION_MOVE_TEST:
			continue
		if latest_task == null or task.task_id > latest_task.task_id:
			latest_task = task
		if task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			continue
		if active_task == null or task.task_id > active_task.task_id:
			active_task = task
		if task.kind == TaskState.Kind.DEVELOP_RESOURCE:
			industrial_open = true
		else:
			battlefield_open = true
	if active_task == null:
		active_task = latest_task
	current_task_id = active_task.task_id if active_task != null else 0
	var has_open_task := active_task != null and active_task.lifecycle not in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]
	develop_button.disabled = industrial_open or industrial_authorization < AgentPolicy.Authorization.ASSISTED
	var selected_combat := input_controller != null and not input_controller._selected_strategic_unit_ids(false).is_empty()
	var selected_scout := input_controller != null and not input_controller._selected_strategic_unit_ids(true).is_empty()
	defend_button.disabled = battlefield_open or battlefield_authorization < AgentPolicy.Authorization.ASSISTED or not selected_combat
	scout_button.disabled = battlefield_open or battlefield_authorization < AgentPolicy.Authorization.ASSISTED or not selected_scout
	var default_enemy := snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID)
	attack_button.disabled = battlefield_open or battlefield_authorization < AgentPolicy.Authorization.ASSISTED or not selected_combat or default_enemy == null or not default_enemy.enabled or not default_enemy.is_visible_to_local_player
	pause_button.disabled = active_task == null or active_task.lifecycle != TaskState.Lifecycle.EXECUTING
	resume_button.disabled = active_task == null or active_task.lifecycle not in [TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]
	cancel_button.disabled = not has_open_task
	var engineer_available := _has_available_engineer(snapshot)
	var faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var available_ore := faction.ore if faction != null else 0
	build_factory_button.disabled = not engineer_available or available_ore < _building_cost(&"automated_factory")
	build_support_button.disabled = not engineer_available or available_ore < _building_cost(&"forward_support_station")
	repair_button.disabled = not engineer_available
	var selected_factory := snapshot.get_building(input_controller.selected_building_id) if input_controller != null else null
	var building_definition := SimulationWorld.BUILDING_CATALOG.get_building(selected_factory.definition_id) if selected_factory != null else null
	var factory_available := selected_factory != null and selected_factory.enabled and selected_factory.operational and building_definition != null and not building_definition.production_catalog.is_empty() and selected_factory.production_queue.size() + int(not selected_factory.production_definition_id.is_empty()) < BuildingState.MAX_PRODUCTION_QUEUE_SIZE
	for index in range(production_buttons.size()):
		production_buttons[index].disabled = not factory_available or not building_definition.can_produce(PRODUCTION_DEFINITIONS[index]) or available_ore < _unit_cost(PRODUCTION_DEFINITIONS[index])
	var production_count := selected_factory.production_queue.size() + int(not selected_factory.production_definition_id.is_empty()) if selected_factory != null else 0
	cancel_production_button.disabled = production_count == 0
	rally_button.disabled = selected_factory == null or not selected_factory.enabled or not selected_factory.operational or building_definition == null or building_definition.production_catalog.is_empty()
	production_queue_label.text = GameText.t(&"PRODUCTION_QUEUE") % [production_count, BuildingState.MAX_PRODUCTION_QUEUE_SIZE]
	harvest_button.disabled = input_controller == null or input_controller._selected_harvester_id() == 0
	_update_mission(snapshot.mission)
	_update_selection(snapshot)
	_update_task(active_task)


func _update_mission(mission: MissionSnapshot) -> void:
	if mission == null:
		mission_label.text = GameText.t(&"HUD_MISSION_WAITING")
		return
	mission_label.text = GameText.t(&"MISSION_TEMPLATE") % [
		GameText.t(&"MISSION_COMPLETE") if mission.completed else GameText.t(&"MISSION_ACTIVE"),
		_mark(mission.developed_resource),
		_mark(mission.defended_area),
		_mark(mission.attacked_target),
		_mark(mission.missile_taken_over),
		_mark(mission.missile_returned),
	]


func _update_task(task: TaskSnapshot) -> void:
	if task == null:
		task_label.text = input_controller.last_command_status if input_controller != null and not input_controller.last_command_status.is_empty() else last_status
		return
	task_label.text = GameText.t(&"TASK_COMPACT") % [
		task.task_id,
		GameText.enum_name("TASK_KIND", TaskState.Kind.keys()[task.kind]),
		GameText.enum_name("TASK_LIFECYCLE", TaskState.Lifecycle.keys()[task.lifecycle]),
		GameText.enum_name("TASK_PHASE", TaskState.Phase.keys()[task.phase]),
		task.progress_current,
		task.progress_target,
	]
	if task.lifecycle == TaskState.Lifecycle.BLOCKED:
		task_label.text += "\n" + GameText.t(&"TASK_BLOCKED") % [
			GameText.enum_name("TASK_BLOCKED", TaskState.BlockedReason.keys()[task.blocked_reason]),
			task.blocked_detail,
		]
	if task.kind == TaskState.Kind.SCOUT_AREA:
		task_label.text += "\n" + GameText.t(&"SCOUT_INTEL_REPORT") % task.discovered_contact_count


func _update_selection(snapshot: WorldSnapshot) -> void:
	if input_controller == null:
		selection_label.text = GameText.t(&"SELECTION_NONE")
		return
	if input_controller.selected_building_id != 0:
		var building := snapshot.get_building(input_controller.selected_building_id)
		if building != null:
			selection_label.text = GameText.t(&"SELECTION_BUILDING") % [
				GameText.building_name(building.definition_id), building.health, building.max_health,
			]
			selection_label.text += "\n" + GameText.t(&"SELECTION_VALUE") % _building_cost(building.definition_id)
			if not building.production_definition_id.is_empty():
				selection_label.text += "\n" + GameText.t(&"SELECTION_PRODUCING") % [
					GameText.unit_name(building.production_definition_id), building.production_ticks_remaining,
				]
			if not building.production_queue.is_empty():
				var queued_names: Array[String] = []
				for definition_id in building.production_queue:
					queued_names.append(GameText.unit_name(definition_id))
				selection_label.text += "\n" + GameText.t(&"SELECTION_QUEUE") % ", ".join(queued_names)
			return
	if input_controller.selected_entity_ids.is_empty():
		selection_label.text = GameText.t(&"SELECTION_NONE")
		return
	if input_controller.selected_entity_ids.size() == 1:
		var unit := snapshot.get_unit(input_controller.selected_entity_ids[0])
		if unit != null:
			selection_label.text = GameText.t(&"SELECTION_UNIT") % [
				GameText.unit_name(unit.definition_id), unit.entity_id, unit.health, unit.max_health,
			]
			selection_label.text += "\n" + GameText.t(&"SELECTION_VALUE") % _unit_cost(unit.definition_id)
			if unit.can_attack:
				selection_label.text += "  " + GameText.t(&"SELECTION_COMBAT") % [unit.attack_damage, unit.attack_range]
			return
	var combat_count := 0
	var worker_count := 0
	for entity_id in input_controller.selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit == null:
			continue
		if unit.can_harvest or unit.can_construct or unit.can_repair:
			worker_count += 1
		elif unit.can_attack and unit.can_accept_attack_orders:
			combat_count += 1
	selection_label.text = GameText.t(&"SELECTION_GROUP") % [input_controller.selected_entity_ids.size(), combat_count, worker_count]


func _submit_develop() -> void:
	var snapshot := simulation_host.current_snapshot
	var ore_field := snapshot.get_ore_field(SimulationWorld.DEFAULT_ORE_FIELD_ID)
	if ore_field == null:
		last_status = GameText.t(&"DEVELOP_UNKNOWN_ORE")
		return
	_submit(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE,
		0,
		ore_field.entity_id,
		ore_field.position
	))


func _select_headquarters_directive(index: int) -> void:
	if simulation_host == null:
		return
	var directive: StrategicHeadquarters.Directive = int(headquarters_directive_selector.get_item_metadata(index))
	if simulation_host.set_headquarters_directive(directive):
		last_status = GameText.t(&"HQ_DIRECTIVE_APPLIED") % GameText.t(simulation_host.get_headquarters_directive_key())
		headquarters_settings_changed.emit()


func _populate_headquarters_directives() -> void:
	var selected := simulation_host.get_headquarters_directive() if simulation_host != null else StrategicHeadquarters.Directive.NONE
	headquarters_directive_selector.clear()
	for directive_index in range(StrategicHeadquarters.Directive.size()):
		var directive_name: String = StrategicHeadquarters.Directive.keys()[directive_index]
		headquarters_directive_selector.add_item(GameText.t(StringName("HQ_DIRECTIVE_%s" % directive_name)))
		headquarters_directive_selector.set_item_metadata(directive_index, directive_index)
	headquarters_directive_selector.select(selected)


func _submit_defend() -> void:
	if input_controller != null:
		input_controller.begin_defend_targeting()


func _submit_scout() -> void:
	if input_controller != null:
		input_controller.begin_scout_targeting()


func _submit_attack() -> void:
	var snapshot := simulation_host.current_snapshot
	var enemy := snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID)
	if input_controller == null or enemy == null or not enemy.is_visible_to_local_player:
		last_status = GameText.t(&"ATTACK_NO_TARGET")
		return
	var result := input_controller.attack_selected_strategic_target(enemy.entity_id)
	if result != null:
		last_status = GameText.t(&"STATUS_ATTACK") % GameText.command_result(result)


func _begin_build(definition_id: StringName) -> void:
	if input_controller != null:
		input_controller.begin_build_targeting(definition_id)


func _begin_repair() -> void:
	if input_controller != null:
		input_controller.begin_repair_targeting()


func _begin_harvest() -> void:
	if input_controller != null:
		input_controller.harvest_with_selected()


func _cancel_production() -> void:
	if input_controller == null or input_controller.selected_building_id == 0:
		return
	var building := simulation_host.current_snapshot.get_building(input_controller.selected_building_id)
	if building == null:
		return
	var queue_index := building.production_queue.size()
	var result := simulation_host.submit_command(simulation_host.create_cancel_production_command(building.entity_id, queue_index))
	last_status = GameText.t(&"STATUS_CANCEL_PRODUCTION") % GameText.command_result(result)


func _begin_rally() -> void:
	if input_controller != null:
		input_controller.begin_rally_targeting()


func get_hover_context(screen_position: Vector2) -> Dictionary:
	for index in range(production_buttons.size()):
		if production_buttons[index].get_global_rect().has_point(screen_position):
			var definition_id := PRODUCTION_DEFINITIONS[index]
			return {"key": "unit:%s" % definition_id, "text": GameText.unit_tooltip(definition_id)}
	for entry in [
		[build_factory_button, &"automated_factory"],
		[build_support_button, &"forward_support_station"],
	]:
		var button := entry[0] as Button
		var definition_id := entry[1] as StringName
		if button.get_global_rect().has_point(screen_position):
			return {"key": "building:%s" % definition_id, "text": GameText.building_tooltip(definition_id)}
	return {}


func _produce(definition_id: StringName) -> void:
	if input_controller != null:
		input_controller.produce_unit(definition_id)


func _has_available_engineer(snapshot: WorldSnapshot) -> bool:
	for unit in snapshot.units:
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == &"engineer_vehicle" and unit.work_kind == UnitState.WorkKind.NONE:
			return true
	return false


func _building_button_text(definition_id: StringName, label_key: StringName) -> String:
	return GameText.t(&"COST_BUTTON") % [GameText.t(label_key), _building_cost(definition_id)]


func _production_button_text(definition_id: StringName) -> String:
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	if definition == null:
		return GameText.unit_name(definition_id)
	return GameText.t(&"PRODUCTION_COST_BUTTON") % [GameText.unit_name(definition_id), definition.production_cost, definition.production_ticks * SimulationWorld.TICK_SECONDS]


func _building_cost(definition_id: StringName) -> int:
	var definition := SimulationWorld.BUILDING_CATALOG.get_building(definition_id)
	return definition.build_cost if definition != null else 0


func _unit_cost(definition_id: StringName) -> int:
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	return definition.production_cost if definition != null else 0


func _control_task(action: TaskControlCommand.Action) -> void:
	if current_task_id == 0:
		return
	_submit(simulation_host.create_task_control_command(current_task_id, action))


func _submit(command: GameCommand) -> void:
	var result := simulation_host.submit_command(command)
	last_status = GameText.command_result(result)


func _mark(done: bool) -> String:
	return "[x]" if done else "[ ]"
