class_name TaskPanel
extends PanelContainer

@onready var title_label: Label = $Layout/Title
@onready var mission_label: Label = $Layout/Mission
@onready var task_label: Label = $Layout/TaskStatus
@onready var develop_button: Button = $Layout/Orders/Develop
@onready var defend_button: Button = $Layout/Orders/Defend
@onready var attack_button: Button = $Layout/Orders/Attack
@onready var build_factory_button: Button = $Layout/Orders/BuildFactory
@onready var build_support_button: Button = $Layout/Orders/BuildSupport
@onready var repair_button: Button = $Layout/Orders/Repair
@onready var pause_button: Button = $Layout/Orders/Pause
@onready var resume_button: Button = $Layout/Orders/Resume
@onready var cancel_button: Button = $Layout/Orders/Cancel
@onready var harvest_button: Button = $Layout/Production/Harvest
@onready var production_buttons: Array[Button] = [
	$Layout/Production/Harvester,
	$Layout/Production/Engineer,
	$Layout/Production/Scout,
	$Layout/Production/Assault,
	$Layout/Production/Missile,
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
	attack_button.pressed.connect(_submit_attack)
	build_factory_button.pressed.connect(_begin_build.bind(&"automated_factory"))
	build_support_button.pressed.connect(_begin_build.bind(&"forward_support_station"))
	repair_button.pressed.connect(_begin_repair)
	pause_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.PAUSE))
	resume_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.RESUME))
	cancel_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.CANCEL))
	harvest_button.pressed.connect(_begin_harvest)
	for index in range(production_buttons.size()):
		production_buttons[index].pressed.connect(_produce.bind(PRODUCTION_DEFINITIONS[index]))
	refresh_locale()


func refresh_locale() -> void:
	for control in [title_label, mission_label, task_label, develop_button, defend_button, attack_button, build_factory_button, build_support_button, repair_button, pause_button, resume_button, cancel_button, harvest_button]:
		(control as Control).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for button in production_buttons:
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = GameText.t(&"HUD_TITLE")
	develop_button.text = GameText.t(&"ORDER_DEVELOP")
	defend_button.text = GameText.t(&"ORDER_DEFEND")
	attack_button.text = GameText.t(&"ORDER_ATTACK")
	build_factory_button.text = GameText.t(&"BUILD_FACTORY")
	build_support_button.text = GameText.t(&"BUILD_SUPPORT")
	repair_button.text = GameText.t(&"REPAIR_BUILDING")
	pause_button.text = GameText.t(&"TASK_PAUSE")
	resume_button.text = GameText.t(&"TASK_RESUME")
	cancel_button.text = GameText.t(&"TASK_CANCEL")
	harvest_button.text = GameText.t(&"ORDER_HARVEST")
	for index in range(production_buttons.size()):
		production_buttons[index].text = GameText.unit_name(PRODUCTION_DEFINITIONS[index])
	if current_task_id == 0:
		last_status = GameText.t(&"TASK_NONE")


func update_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null:
		return
	var active_task: TaskSnapshot
	for task in snapshot.tasks:
		if task.kind == TaskState.Kind.FORMATION_MOVE_TEST:
			continue
		if active_task == null or task.task_id > active_task.task_id:
			active_task = task
	current_task_id = active_task.task_id if active_task != null else 0
	var has_open_task := active_task != null and active_task.lifecycle not in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]
	develop_button.disabled = has_open_task
	defend_button.disabled = has_open_task
	attack_button.disabled = has_open_task or snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID) == null or not snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID).enabled
	pause_button.disabled = active_task == null or active_task.lifecycle != TaskState.Lifecycle.EXECUTING
	resume_button.disabled = active_task == null or active_task.lifecycle not in [TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]
	cancel_button.disabled = not has_open_task
	var engineer_available := _has_available_engineer(snapshot)
	build_factory_button.disabled = not engineer_available
	build_support_button.disabled = not engineer_available
	repair_button.disabled = not engineer_available
	var selected_factory := snapshot.get_building(input_controller.selected_building_id) if input_controller != null else null
	var factory_available := selected_factory != null and selected_factory.enabled and selected_factory.operational and selected_factory.definition_id == &"automated_factory" and selected_factory.production_definition_id.is_empty()
	for button in production_buttons:
		button.disabled = not factory_available
	harvest_button.disabled = input_controller == null or input_controller._selected_harvester_id() == 0
	_update_mission(snapshot.mission)
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
		task_label.text = last_status
		return
	var route_text := GameText.t(&"TASK_ROUTE") % task.route.size()
	var blocked_text := ""
	if task.lifecycle == TaskState.Lifecycle.BLOCKED:
		blocked_text = "\n" + GameText.t(&"TASK_BLOCKED") % [
			GameText.enum_name("TASK_BLOCKED", TaskState.BlockedReason.keys()[task.blocked_reason]),
			TranslationServer.translate(task.blocked_detail),
		]
	task_label.text = GameText.t(&"TASK_TEMPLATE") % [
		task.task_id,
		GameText.enum_name("TASK_KIND", TaskState.Kind.keys()[task.kind]),
		GameText.enum_name("TASK_LIFECYCLE", TaskState.Lifecycle.keys()[task.lifecycle]),
		GameText.enum_name("TASK_PHASE", TaskState.Phase.keys()[task.phase]),
		task.target_position.x,
		task.target_position.y,
		task.target_radius,
		route_text,
		str(task.participant_entity_ids),
		task.progress_current,
		task.progress_target,
		TranslationServer.translate(task.last_detail),
		blocked_text,
	]


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


func _submit_defend() -> void:
	if input_controller != null:
		input_controller.begin_defend_targeting()


func _submit_attack() -> void:
	var snapshot := simulation_host.current_snapshot
	var formation := snapshot.get_formation(SimulationWorld.DEFAULT_FORMATION_ID)
	var enemy := snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID)
	if formation == null or enemy == null or not enemy.is_visible_to_local_player:
		last_status = GameText.t(&"ATTACK_NO_TARGET")
		return
	_submit(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.ATTACK_TARGET,
		formation.formation_id,
		enemy.entity_id,
		enemy.position
	))


func _begin_build(definition_id: StringName) -> void:
	if input_controller != null:
		input_controller.begin_build_targeting(definition_id)


func _begin_repair() -> void:
	if input_controller != null:
		input_controller.begin_repair_targeting()


func _begin_harvest() -> void:
	if input_controller != null:
		input_controller.harvest_with_selected()


func _produce(definition_id: StringName) -> void:
	if input_controller != null:
		input_controller.produce_unit(definition_id)


func _has_available_engineer(snapshot: WorldSnapshot) -> bool:
	for unit in snapshot.units:
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == &"engineer_vehicle" and unit.work_kind == UnitState.WorkKind.NONE:
			return true
	return false


func _control_task(action: TaskControlCommand.Action) -> void:
	if current_task_id == 0:
		return
	_submit(simulation_host.create_task_control_command(current_task_id, action))


func _submit(command: GameCommand) -> void:
	var result := simulation_host.submit_command(command)
	last_status = GameText.command_result(result)


func _mark(done: bool) -> String:
	return "[x]" if done else "[ ]"
