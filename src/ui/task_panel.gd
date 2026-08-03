class_name TaskPanel
extends PanelContainer

@onready var mission_label: Label = $Layout/Mission
@onready var task_label: Label = $Layout/TaskStatus
@onready var develop_button: Button = $Layout/Orders/Develop
@onready var defend_button: Button = $Layout/Orders/Defend
@onready var attack_button: Button = $Layout/Orders/Attack
@onready var pause_button: Button = $Layout/TaskControls/Pause
@onready var resume_button: Button = $Layout/TaskControls/Resume
@onready var cancel_button: Button = $Layout/TaskControls/Cancel

var simulation_host: SimulationHost
var current_task_id: int = 0
var last_status: String = "No active assignment"


func _ready() -> void:
	develop_button.pressed.connect(_submit_develop)
	defend_button.pressed.connect(_submit_defend)
	attack_button.pressed.connect(_submit_attack)
	pause_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.PAUSE))
	resume_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.RESUME))
	cancel_button.pressed.connect(_control_task.bind(TaskControlCommand.Action.CANCEL))


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
	_update_mission(snapshot.mission)
	_update_task(active_task)


func _update_mission(mission: MissionSnapshot) -> void:
	if mission == null:
		mission_label.text = "MISSION / awaiting state"
		return
	mission_label.text = "MISSION %s\n%s Develop resource  %s Hold perimeter  %s Eliminate target\n%s Take missile unit  %s Return missile unit" % [
		"COMPLETE" if mission.completed else "ACTIVE",
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
	var route_text := "%d waypoints" % task.route.size()
	var blocked_text := ""
	if task.lifecycle == TaskState.Lifecycle.BLOCKED:
		blocked_text = "\nBlocked: %s / %s" % [TaskState.BlockedReason.keys()[task.blocked_reason], task.blocked_detail]
	task_label.text = "T%d %s / %s / %s\nTarget: (%.0f, %.0f) r%.0f  Route: %s\nParticipants: %s  Progress: %d/%d\n%s%s" % [
		task.task_id,
		TaskState.Kind.keys()[task.kind],
		TaskState.Lifecycle.keys()[task.lifecycle],
		TaskState.Phase.keys()[task.phase],
		task.target_position.x,
		task.target_position.y,
		task.target_radius,
		route_text,
		str(task.participant_entity_ids),
		task.progress_current,
		task.progress_target,
		task.last_detail,
		blocked_text,
	]


func _submit_develop() -> void:
	var snapshot := simulation_host.current_snapshot
	var ore_field := snapshot.get_ore_field(SimulationWorld.DEFAULT_ORE_FIELD_ID)
	if ore_field == null:
		last_status = "Develop rejected: ore field is not known"
		return
	_submit(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE,
		0,
		ore_field.entity_id,
		ore_field.position
	))


func _submit_defend() -> void:
	var formation := simulation_host.current_snapshot.get_formation(SimulationWorld.DEFAULT_FORMATION_ID)
	if formation == null:
		last_status = "Defense rejected: formation unavailable"
		return
	_submit(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.DEFEND_AREA,
		formation.formation_id,
		0,
		formation.anchor_position,
		40.0
	))


func _submit_attack() -> void:
	var snapshot := simulation_host.current_snapshot
	var formation := snapshot.get_formation(SimulationWorld.DEFAULT_FORMATION_ID)
	var enemy := snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID)
	if formation == null or enemy == null or not enemy.is_visible_to_local_player:
		last_status = "Attack rejected: visible target unavailable"
		return
	_submit(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.ATTACK_TARGET,
		formation.formation_id,
		enemy.entity_id,
		enemy.position
	))


func _control_task(action: TaskControlCommand.Action) -> void:
	if current_task_id == 0:
		return
	_submit(simulation_host.create_task_control_command(current_task_id, action))


func _submit(command: GameCommand) -> void:
	var result := simulation_host.submit_command(command)
	last_status = result.describe()


func _mark(done: bool) -> String:
	return "[x]" if done else "[ ]"
