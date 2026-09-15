class_name CommanderTaskGraphPresenter
extends RefCounted


static func describe(snapshot: WorldSnapshot, graph: CommanderTaskGraphSnapshot) -> String:
	var lines: PackedStringArray = []
	for card_id in _card_ids(graph):
		var chosen: CommanderTaskNodeSnapshot
		for node in graph.nodes:
			if node.card_id != card_id or node.phase == CommanderTaskStageDefinition.Phase.RETREAT and not graph.retreat_requested:
				continue
			if graph.retreat_requested and node.phase != CommanderTaskStageDefinition.Phase.RETREAT:
				continue
			if chosen == null or _priority(node) > _priority(chosen) or _priority(node) == _priority(chosen) and (node.phase > chosen.phase if node.is_satisfied() else node.phase < chosen.phase):
				chosen = node
		if chosen == null:
			continue
		var card := snapshot.get_unit_card(card_id)
		lines.append("%s · %s · %s" % [GameText.t(card.display_name_key) if card != null else String(card_id),
			GameText.t(StringName("COMMANDER_GRAPH_PHASE_%d" % chosen.phase)), GameText.t(chosen.reason_key)])
	return "\n".join(lines)


static func summary(graph: CommanderTaskGraphSnapshot) -> String:
	var active := 0
	var waiting := 0
	var complete := 0
	for card_id in _card_ids(graph):
		var has_active := false
		var all_complete := true
		for node in graph.nodes:
			if node.card_id != card_id or node.phase == CommanderTaskStageDefinition.Phase.RETREAT and not graph.retreat_requested:
				continue
			if graph.retreat_requested and node.phase != CommanderTaskStageDefinition.Phase.RETREAT:
				continue
			has_active = has_active or node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.ACTIVE
			all_complete = all_complete and node.is_satisfied()
		if all_complete:
			complete += 1
		elif has_active:
			active += 1
		else:
			waiting += 1
	var text := GameText.t(&"COMMANDER_GRAPH_SUMMARY") % [active, waiting, complete]
	if not graph.last_adaptation_reason.is_empty():
		text += " · " + GameText.t(graph.last_adaptation_reason)
	return text


static func _priority(node: CommanderTaskNodeSnapshot) -> int:
	match node.lifecycle:
		CommanderTaskNodeSnapshot.Lifecycle.ACTIVE: return 6
		CommanderTaskNodeSnapshot.Lifecycle.PAUSED: return 5
		CommanderTaskNodeSnapshot.Lifecycle.BLOCKED, CommanderTaskNodeSnapshot.Lifecycle.FAILED: return 4
		CommanderTaskNodeSnapshot.Lifecycle.WAITING: return 3
		CommanderTaskNodeSnapshot.Lifecycle.COMPLETED: return 2
	return 1


static func _card_ids(graph: CommanderTaskGraphSnapshot) -> Array[StringName]:
	var ids: Array[StringName] = []
	for node in graph.nodes:
		if not ids.has(node.card_id):
			ids.append(node.card_id)
	ids.sort()
	return ids
