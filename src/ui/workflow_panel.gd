class_name WorkflowPanel
extends PanelContainer

@onready var title_label: Label = $Margin/Layout/Title
@onready var unit_flows_label: Label = $Margin/Layout/UnitFlows
@onready var tasks_title_label: Label = $Margin/Layout/TasksTitle
@onready var tasks_label: Label = $Margin/Layout/Tasks

var simulation_host: SimulationHost


func _ready() -> void:
	refresh_locale()


func refresh_locale() -> void:
	for control in [title_label, unit_flows_label, tasks_title_label, tasks_label]:
		(control as Control).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = GameText.t(&"WORKFLOW_TITLE")
	tasks_title_label.text = GameText.t(&"WORKFLOW_TASKS")


func update_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null:
		return
	var mining := 0
	var constructing := 0
	var repairing := 0
	var scouting := 0
	for unit in snapshot.units:
		if not unit.enabled or unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		if unit.harvest_ore_field_entity_id != 0:
			mining += 1
		if unit.work_kind == UnitState.WorkKind.CONSTRUCT:
			constructing += 1
		elif unit.work_kind == UnitState.WorkKind.REPAIR:
			repairing += 1
		if unit.definition_id == &"scout_vehicle" and unit.assigned_task_id == 0 and unit.is_moving:
			scouting += 1
	var defending := 0
	var attacking := 0
	var task_lines: PackedStringArray = []
	for task in snapshot.tasks:
		if task.faction_id != SimulationWorld.LOCAL_PLAYER_ID or task.kind == TaskState.Kind.FORMATION_MOVE_TEST or task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			continue
		if task.kind == TaskState.Kind.DEFEND_AREA:
			defending += task.get_participant_count()
		elif task.kind == TaskState.Kind.ATTACK_TARGET:
			attacking += task.get_participant_count()
		elif task.kind == TaskState.Kind.SCOUT_AREA:
			scouting += task.get_participant_count()
		task_lines.append(GameText.t(&"WORKFLOW_TASK_LINE") % [
			task.task_id,
			GameText.enum_name("TASK_KIND", TaskState.Kind.keys()[task.kind]),
			GameText.enum_name("TASK_PHASE", TaskState.Phase.keys()[task.phase]),
			task.get_participant_count(),
		])
	unit_flows_label.text = "\n".join([
		GameText.t(&"WORKFLOW_COUNT") % [GameText.t(&"WORKFLOW_MINING"), mining],
		GameText.t(&"WORKFLOW_COUNT") % [GameText.t(&"WORKFLOW_CONSTRUCTION"), constructing],
		GameText.t(&"WORKFLOW_COUNT") % [GameText.t(&"WORKFLOW_REPAIR"), repairing],
		GameText.t(&"WORKFLOW_COUNT") % [GameText.t(&"WORKFLOW_SCOUTING"), scouting],
		GameText.t(&"WORKFLOW_COUNT") % [GameText.t(&"WORKFLOW_DEFENSE"), defending],
		GameText.t(&"WORKFLOW_COUNT") % [GameText.t(&"WORKFLOW_ATTACK"), attacking],
	])
	var authorization_line := ""
	var recommendation_line := ""
	var headquarters_line := ""
	var headquarters_budget_line := ""
	if simulation_host != null:
		authorization_line = GameText.t(&"WORKFLOW_AI_STATUS") % [
			GameText.enum_name("AI_AUTH", AgentPolicy.Authorization.keys()[simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID)]),
			GameText.enum_name("AI_AUTH", AgentPolicy.Authorization.keys()[simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)]),
		]
		recommendation_line = GameText.t(&"WORKFLOW_AI_RECOMMENDATIONS") % [
			GameText.t(simulation_host.get_agent_recommendation_key(StrategicTaskSystem.INDUSTRIAL_AGENT_ID)),
			GameText.t(simulation_host.get_agent_recommendation_key(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)),
		]
		headquarters_line = GameText.t(&"WORKFLOW_HEADQUARTERS") % GameText.t(simulation_host.get_headquarters_decision_key())
		var budget := simulation_host.get_headquarters_budget_snapshot()
		headquarters_budget_line = GameText.t(&"WORKFLOW_HEADQUARTERS_BUDGET") % [int(budget["pending"]), int(budget["reserved"]), int(budget["available"])]
	var task_text := GameText.t(&"WORKFLOW_NONE") if task_lines.is_empty() else "\n".join(task_lines)
	tasks_label.text = "%s\n%s\n%s\n%s\n%s" % [authorization_line, headquarters_line, headquarters_budget_line, recommendation_line, task_text] if not authorization_line.is_empty() else task_text
