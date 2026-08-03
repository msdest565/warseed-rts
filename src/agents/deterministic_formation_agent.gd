class_name DeterministicFormationAgent
extends RefCounted

var agent_id: int
var task_id: int
var formation_id: int
var target_position: Vector2
var command_issued: bool = false

func _init(new_agent_id: int, new_task_id: int, new_formation_id: int, new_target_position: Vector2) -> void:
	agent_id = new_agent_id
	task_id = new_task_id
	formation_id = new_formation_id
	target_position = new_target_position

func advance(world: SimulationWorld) -> void:
	if command_issued or not world.tasks.has(task_id) or not world.formations.has(formation_id):
		return
	var task := world.tasks[task_id] as TaskState
	if task.lifecycle != TaskState.Lifecycle.EXECUTING:
		return
	var formation := world.formations[formation_id] as FormationState
	var command := FormationMoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		formation.leader_entity_id,
		formation_id,
		target_position
	)
	command.agent_id = agent_id
	command.task_id = task_id
	command_formation(command, world)

func command_formation(command: FormationMoveCommand, world: SimulationWorld) -> void:
	var result := world.submit_command(command)
	if result.is_accepted():
		command_issued = true
