class_name FormationMovementSystem
extends RefCounted

const ARRIVAL_TOLERANCE := 6.0
const ANCHOR_LAG_LIMIT := 120.0
const COLUMN_SPACING := 42.0
const PREFERRED_SEPARATION := 34.0
const HARD_SEPARATION := 24.0
const STUCK_TICK_LIMIT := 10
const CLEAR_CORRIDOR_TICKS := 5
const NARROW_CORRIDOR_WIDTH := 3
const MAX_RECOVERY_ATTEMPTS := 3
const LAGGED_ANCHOR_SPEED_SCALE := 0.25
const HISTORY_MARGIN := 36.0

var logic_grid: LogicGrid
var pathfinder: GridPathfinder


func _init(new_logic_grid: LogicGrid, new_pathfinder: GridPathfinder) -> void:
	logic_grid = new_logic_grid
	pathfinder = new_pathfinder


func advance(formations: Dictionary, units: Dictionary, events: Array[SimulationEvent], current_tick: int) -> void:
	var formation_ids := formations.keys()
	formation_ids.sort()
	for formation_id in formation_ids:
		var formation := formations[formation_id] as FormationState
		if formation.is_moving:
			_advance_formation(formation, units, events, current_tick)


func _advance_formation(
	formation: FormationState,
	units: Dictionary,
	events: Array[SimulationEvent],
	current_tick: int
) -> void:
	_update_mode(formation)
	var tangent := _get_tangent(formation)
	var desired_positions := _create_desired_positions(formation, tangent)
	var all_close := true
	for entity_id in formation.member_entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.enabled:
			continue
		unit.desired_position = desired_positions[entity_id]
		if unit.following_formation and unit.position.distance_to(unit.desired_position) > ANCHOR_LAG_LIMIT:
			all_close = false
	var speed_scale := 1.0 if all_close else LAGGED_ANCHOR_SPEED_SCALE
	_advance_anchor(formation, speed_scale)
	tangent = _get_tangent(formation)
	desired_positions = _create_desired_positions(formation, tangent)

	var start_positions: Dictionary = {}
	for entity_id in formation.member_entity_ids:
		start_positions[entity_id] = (units[entity_id] as UnitState).position
	var committed_positions: Dictionary = {}
	for entity_id in formation.member_entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.enabled or not unit.following_formation:
			continue
		unit.desired_position = desired_positions[entity_id]
		var before := unit.position
		var proposed := _propose_position(unit, formation, start_positions)
		proposed = _enforce_hard_separation(entity_id, proposed, committed_positions)
		if not logic_grid.is_segment_walkable(before, proposed):
			proposed = _seek_position(before, unit.desired_position, unit.move_speed * SimulationWorld.TICK_SECONDS)
			if not logic_grid.is_segment_walkable(before, proposed):
				proposed = before
		unit.position = proposed
		committed_positions[entity_id] = proposed
		_update_stuck_state(unit, formation, before, events, current_tick)

	var members_arrived := formation.path_index >= formation.path.size()
	if members_arrived:
		formation.mode = FormationState.MovementMode.WIDE
		for entity_id in formation.member_entity_ids:
			var unit := units[entity_id] as UnitState
			if unit.enabled and unit.following_formation and unit.position.distance_to(unit.desired_position) > ARRIVAL_TOLERANCE:
				members_arrived = false
				break
	if members_arrived:
		formation.is_moving = false
		formation.path = PackedVector2Array()
		for entity_id in formation.member_entity_ids:
			var unit := units[entity_id] as UnitState
			if unit.enabled and unit.following_formation:
				unit.position = unit.desired_position
				unit.has_move_target = false
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_ARRIVED, entity_id))


func _advance_anchor(formation: FormationState, speed_scale: float = 1.0) -> void:
	if formation.path_index >= formation.path.size():
		return
	var travel_remaining := 180.0 * SimulationWorld.TICK_SECONDS * speed_scale
	var retained_distance := COLUMN_SPACING * (formation.member_entity_ids.size() - 1) + HISTORY_MARGIN
	while travel_remaining > 0.0 and formation.path_index < formation.path.size():
		var waypoint := formation.path[formation.path_index]
		var offset := waypoint - formation.anchor_position
		if offset.length() <= travel_remaining:
			formation.anchor_position = waypoint
			formation.append_anchor_history(formation.anchor_position, retained_distance)
			travel_remaining -= offset.length()
			formation.path_index += 1
		else:
			formation.anchor_position += offset.normalized() * travel_remaining
			formation.append_anchor_history(formation.anchor_position, retained_distance)
			travel_remaining = 0.0


func _update_mode(formation: FormationState) -> void:
	var narrow_ahead := formation.forced_column_ticks > 0
	if formation.forced_column_ticks > 0:
		formation.forced_column_ticks -= 1
	var previous_cell := logic_grid.world_to_cell(formation.anchor_position)
	for index in range(formation.path_index, mini(formation.path_index + 4, formation.path.size())):
		var cell := logic_grid.world_to_cell(formation.path[index])
		var delta := cell - previous_cell
		var direction := Vector2i(signi(delta.x), signi(delta.y))
		if direction == Vector2i.ZERO:
			direction = Vector2i.RIGHT
		if logic_grid.get_corridor_width(cell, direction) < NARROW_CORRIDOR_WIDTH:
			narrow_ahead = true
			break
		previous_cell = cell
	if narrow_ahead:
		formation.mode = FormationState.MovementMode.COLUMN
		formation.clear_corridor_ticks = 0
	elif formation.mode == FormationState.MovementMode.COLUMN:
		formation.clear_corridor_ticks += 1
		if formation.clear_corridor_ticks >= CLEAR_CORRIDOR_TICKS:
			formation.mode = FormationState.MovementMode.WIDE


func _get_tangent(formation: FormationState) -> Vector2:
	if formation.path_index < formation.path.size():
		var offset := formation.path[formation.path_index] - formation.anchor_position
		if not offset.is_zero_approx():
			return offset.normalized()
	if formation.path.size() >= 2:
		return (formation.path[-1] - formation.path[-2]).normalized()
	return Vector2.RIGHT


func _create_desired_positions(formation: FormationState, tangent: Vector2) -> Dictionary:
	var desired: Dictionary = {}
	var lateral := Vector2(-tangent.y, tangent.x)
	for entity_id in formation.member_entity_ids:
		var slot_id := formation.get_slot_id(entity_id)
		if formation.mode == FormationState.MovementMode.COLUMN:
			var history_position := formation.sample_anchor_history(COLUMN_SPACING * slot_id)
			desired[entity_id] = _get_walkable_history_position(formation, history_position, slot_id)
		else:
			var offset := formation.get_wide_offset(slot_id)
			desired[entity_id] = formation.anchor_position + tangent * offset.x + lateral * offset.y
	return desired


func _get_walkable_history_position(
	formation: FormationState,
	preferred_position: Vector2,
	slot_id: int
) -> Vector2:
	if logic_grid.is_world_position_walkable(preferred_position):
		return preferred_position
	var fallback_distance := COLUMN_SPACING * slot_id
	var step_count := ceili(fallback_distance / 12.0)
	for step in range(step_count + 1):
		var candidate := formation.sample_anchor_history(maxf(0.0, fallback_distance - step * 12.0))
		if logic_grid.is_world_position_walkable(candidate):
			return candidate
	return formation.anchor_position


func _propose_position(unit: UnitState, formation: FormationState, positions: Dictionary) -> Vector2:
	if unit.is_recovering and unit.recovery_path_index < unit.recovery_path.size():
		var recovery_target := unit.recovery_path[unit.recovery_path_index]
		var recovery_position := _seek_position(unit.position, recovery_target, unit.move_speed * SimulationWorld.TICK_SECONDS)
		if recovery_position.distance_to(recovery_target) <= ARRIVAL_TOLERANCE:
			unit.recovery_path_index += 1
			if unit.recovery_path_index >= unit.recovery_path.size():
				unit.is_recovering = false
				unit.recovery_path = PackedVector2Array()
				unit.recovery_path_index = 0
				unit.recovery_attempts = 0
		return recovery_position

	var seek := unit.desired_position - unit.position
	var steering := seek.normalized() if not seek.is_zero_approx() else Vector2.ZERO
	for other_id in formation.member_entity_ids:
		if other_id == unit.entity_id:
			continue
		var offset := unit.position - (positions[other_id] as Vector2)
		var distance := offset.length()
		if distance < PREFERRED_SEPARATION:
			if distance <= 0.001:
				offset = Vector2.RIGHT.rotated(float((unit.entity_id * 17 + other_id * 31) % 8) * PI / 4.0)
				distance = 1.0
			steering += offset.normalized() * (PREFERRED_SEPARATION - distance) / PREFERRED_SEPARATION * 0.45
	if steering.is_zero_approx():
		return unit.position
	var max_travel := unit.move_speed * SimulationWorld.TICK_SECONDS
	return unit.position + steering.normalized() * minf(max_travel, unit.position.distance_to(unit.desired_position))


func _seek_position(from_position: Vector2, target_position: Vector2, max_travel: float) -> Vector2:
	var offset := target_position - from_position
	if offset.length() <= max_travel:
		return target_position
	return from_position + offset.normalized() * max_travel


func _enforce_hard_separation(entity_id: int, proposed: Vector2, committed: Dictionary) -> Vector2:
	for other_id in committed.keys():
		var other_position := committed[other_id] as Vector2
		if proposed.distance_to(other_position) < HARD_SEPARATION:
			var offset := proposed - other_position
			if offset.is_zero_approx():
				offset = Vector2.RIGHT if entity_id > int(other_id) else Vector2.LEFT
			return other_position + offset.normalized() * HARD_SEPARATION
	return proposed


func _update_stuck_state(
	unit: UnitState,
	formation: FormationState,
	before: Vector2,
	events: Array[SimulationEvent],
	current_tick: int
) -> void:
	if unit.position.distance_to(unit.desired_position) <= ARRIVAL_TOLERANCE:
		unit.ticks_without_progress = 0
		return
	if unit.position.distance_to(before) >= 0.5:
		unit.ticks_without_progress = 0
		if not unit.is_recovering:
			unit.recovery_attempts = 0
		return
	unit.ticks_without_progress += 1
	if unit.ticks_without_progress < STUCK_TICK_LIMIT:
		return
	unit.ticks_without_progress = 0
	unit.recovery_attempts += 1
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_STUCK, unit.entity_id))
	if unit.recovery_attempts <= MAX_RECOVERY_ATTEMPTS:
		var fallback_positions := PackedVector2Array()
		for index in range(formation.anchor_history.size() - 1, -1, -1):
			fallback_positions.append(formation.anchor_history[index])
		var recovery_path := pathfinder.find_path_to_first_reachable(
			unit.position,
			unit.desired_position,
			fallback_positions
		)
		if not recovery_path.is_empty():
			unit.recovery_path = recovery_path
			unit.recovery_path_index = 1
			unit.is_recovering = unit.recovery_path.size() > 1
	formation.forced_column_ticks = CLEAR_CORRIDOR_TICKS * 2
