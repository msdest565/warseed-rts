class_name BattleFeedbackDirector
extends Node

signal feedback_emitted(message_key: StringName, arguments: Array, severity: int)
signal effect_requested(kind: StringName, position: Vector2, faction_id: int, entity_id: int)

enum Cue {
	NONE,
	ENGAGEMENT,
	VOLLEY,
	IMPACT,
	FOCUS_FIRE,
	UNDER_PRESSURE,
	REINFORCEMENT,
	SCOUT_REPORT,
	DEPLOYMENT,
	SUPPORT,
	ENGINEERING,
	EFFECT_ENDED,
	DOCTRINE,
	REGION,
	HEADQUARTERS_CRITICAL,
	VICTORY,
	DEFEAT,
}

enum Severity {
	INFO,
	WARNING,
	CRITICAL,
}

const MAX_CONCURRENT_VOICES := 3
const FOCUS_WINDOW_TICKS := 12
const FOCUS_SOURCE_THRESHOLD := 3
const DAMAGE_WINDOW_TICKS := 18
const DAMAGE_PRESSURE_THRESHOLD := 18.0

var audio_enabled: bool = true
var play_count: int = 0
var visual_count: int = 0
var dropped_audio_count: int = 0
var preempted_audio_count: int = 0
var peak_concurrent_voice_count: int = 0
var last_cue: Cue = Cue.NONE
var last_message_key: StringName

var _event_cursor: int = 0
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _voice_until_ticks: Array[int] = []
var _voice_priorities: Array[int] = []
var _last_feedback_tick_by_scope: Dictionary = {}
var _focus_windows: Dictionary = {}
var _damage_windows: Dictionary = {}
var _ready_complete: bool = false


func _ready() -> void:
	if _ready_complete:
		return
	_ready_complete = true
	_ensure_audio()


func reset(event_count: int = 0) -> void:
	_event_cursor = maxi(0, event_count)
	_last_feedback_tick_by_scope.clear()
	_focus_windows.clear()
	_damage_windows.clear()
	peak_concurrent_voice_count = 0
	for index in range(_voice_until_ticks.size()):
		_voice_until_ticks[index] = 0
		_voice_priorities[index] = 0


func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	if not enabled:
		for player in _players:
			player.stop()


func process_events(events: Array[SimulationEvent], snapshot: WorldSnapshot) -> void:
	if snapshot == null:
		return
	if events.size() < _event_cursor:
		reset(0)
	while _event_cursor < events.size():
		_process_event(events[_event_cursor], snapshot)
		_event_cursor += 1


func get_active_voice_count(tick: int) -> int:
	var active := 0
	for until_tick in _voice_until_ticks:
		if until_tick > tick:
			active += 1
	return active


func get_feedback_count(cue: Cue) -> int:
	return int(_last_feedback_tick_by_scope.get("count:%d" % cue, 0))


func notify_contact(tick: int) -> void:
	_emit_feedback(Cue.SCOUT_REPORT, &"", [], Severity.INFO, "scout", tick)


func _process_event(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	match event.kind:
		SimulationEvent.Kind.ATTACK_STARTED:
			_process_attack_started(event, snapshot)
		SimulationEvent.Kind.PROJECTILE_FIRED:
			_process_projectile_fired(event, snapshot)
		SimulationEvent.Kind.DAMAGE_APPLIED:
			_process_damage(event, snapshot)
		SimulationEvent.Kind.UNIT_DESTROYED:
			_process_unit_destroyed(event, snapshot)
		SimulationEvent.Kind.UNIT_CARD_DEPLOYMENT_STARTED:
			_process_deployment_started(event, snapshot)
		SimulationEvent.Kind.UNIT_CARD_DEPLOYED:
			_process_card_deployed(event, snapshot)
		SimulationEvent.Kind.UNIT_CARD_REINFORCED:
			_process_reinforcement(event, snapshot)
		SimulationEvent.Kind.SUPPORT_STARTED:
			_process_support_started(event, snapshot)
		SimulationEvent.Kind.SUPPORT_ENDED:
			_process_support_ended(event, snapshot)
		SimulationEvent.Kind.ENGINEERING_ROUTE_OPENED:
			_process_engineering_route_opened(event, snapshot)
		SimulationEvent.Kind.DOCTRINE_EQUIPPED:
			_process_doctrine_equipped(event, snapshot)
		SimulationEvent.Kind.SUPPLY_NODE_ACTIVATED:
			_process_supply_node_activated(event, snapshot)
		SimulationEvent.Kind.REGION_CONTROL_CHANGED:
			_process_region_control_changed(event, snapshot)
		SimulationEvent.Kind.REGION_CAPTURE_STARTED:
			_process_region_capture_started(event, snapshot)
		SimulationEvent.Kind.REGION_CAPTURE_INTERRUPTED:
			_process_region_capture_interrupted(event, snapshot)
		SimulationEvent.Kind.UNIT_CARD_ORGANIZATION_CHANGED:
			_process_organization_changed(event, snapshot)
		SimulationEvent.Kind.UNIT_CARD_WITHDRAWN:
			_process_card_withdrawn(event, snapshot)
		SimulationEvent.Kind.SCOUT_CONTACT_REPORTED:
			_emit_feedback(Cue.SCOUT_REPORT, &"BATTLE_FEEDBACK_SCOUT_REPORT", [], Severity.INFO, "scout", event.tick)
		SimulationEvent.Kind.FACTION_VICTORIOUS:
			if event.entity_id == SimulationWorld.LOCAL_PLAYER_ID:
				_emit_feedback(Cue.VICTORY, &"BATTLE_FEEDBACK_VICTORY", [], Severity.INFO, "outcome", event.tick)
		SimulationEvent.Kind.FACTION_DEFEATED:
			if event.entity_id == SimulationWorld.LOCAL_PLAYER_ID:
				_emit_feedback(Cue.DEFEAT, &"BATTLE_FEEDBACK_DEFEAT", [], Severity.CRITICAL, "outcome", event.tick)
		SimulationEvent.Kind.BATTLE_CONCLUDED:
			if event is BattleConclusionEvent and (event as BattleConclusionEvent).outcome.result == BattleOutcome.Result.ORDERED_WITHDRAWAL:
				_emit_feedback(Cue.DEFEAT, &"BATTLE_FEEDBACK_ORDERED_WITHDRAWAL", [], Severity.INFO, "outcome", event.tick)


func _process_attack_started(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var attacker := snapshot.get_unit(event.entity_id)
	var target_id := _detail_int(event.detail, "target")
	if attacker == null or not _is_relevant_attack(attacker, target_id, snapshot):
		return
	var actor_key := _unit_or_card_display_key(attacker, snapshot)
	var scope := "engagement:%s" % (attacker.unit_card_id if not attacker.unit_card_id.is_empty() else attacker.formation_id)
	if _emit_feedback(Cue.ENGAGEMENT, &"BATTLE_FEEDBACK_ENGAGEMENT", [actor_key], Severity.INFO, scope, event.tick):
		effect_requested.emit(&"engagement", attacker.position, attacker.faction_id, attacker.entity_id)


func _process_projectile_fired(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var attacker := snapshot.get_unit(event.entity_id)
	var target_id := _detail_int(event.detail, "target")
	if attacker == null or not _is_relevant_attack(attacker, target_id, snapshot):
		return
	_emit_feedback(Cue.VOLLEY, &"", [], Severity.INFO, "volley", event.tick)
	_register_focus_fire(event.entity_id, target_id, event.tick, snapshot)


func _process_damage(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var target_id := _detail_int(event.detail, "target")
	var target_unit := snapshot.get_unit(target_id)
	var target_building := snapshot.get_building(target_id)
	if target_unit == null and target_building == null:
		return
	var target_is_local := target_unit != null and target_unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID \
		or target_building != null and target_building.faction_id == SimulationWorld.LOCAL_PLAYER_ID
	var target_visible := target_unit != null and target_unit.is_visible_to_local_player \
		or target_building != null and target_building.is_visible
	if not target_is_local and not target_visible:
		return
	_emit_feedback(Cue.IMPACT, &"", [], Severity.INFO, "impact", event.tick)
	var position := _entity_position(snapshot, target_id)
	if target_id == SimulationWorld.PLAYER_COMMAND_CENTER_ID:
		if _emit_feedback(Cue.HEADQUARTERS_CRITICAL, &"BATTLE_FEEDBACK_HEADQUARTERS_CRITICAL", [], Severity.CRITICAL, "headquarters", event.tick):
			effect_requested.emit(&"headquarters", position, SimulationWorld.LOCAL_PLAYER_ID, target_id)
		return
	if target_unit == null or target_unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	_register_card_damage(target_unit, _detail_float(event.detail, "amount"), event.tick, snapshot)


func _process_unit_destroyed(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var unit := snapshot.get_unit(event.entity_id)
	if unit == null or unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	var card_key := _unit_or_card_display_key(unit, snapshot)
	if _emit_feedback(Cue.UNDER_PRESSURE, &"BATTLE_FEEDBACK_LOSS", [card_key], Severity.WARNING, "loss:%s" % unit.unit_card_id, event.tick):
		effect_requested.emit(&"pressure", unit.position, unit.faction_id, unit.entity_id)


func _process_reinforcement(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var card_id := StringName(_detail_string(event.detail, "card"))
	var card := snapshot.get_unit_card(card_id)
	if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	if _emit_feedback(Cue.REINFORCEMENT, &"BATTLE_FEEDBACK_REINFORCEMENT", [card.display_name_key], Severity.INFO, "reinforcement:%s" % card_id, event.tick):
		effect_requested.emit(&"reinforcement", card.center_position, card.faction_id, event.entity_id)


func _process_deployment_started(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var card := snapshot.get_unit_card(StringName(_detail_string(event.detail, "card")))
	if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	if _emit_feedback(Cue.DEPLOYMENT, &"BATTLE_FEEDBACK_DEPLOYMENT_STARTED", [card.display_name_key], Severity.INFO, "deploy-start:%s" % card.definition_id, event.tick):
		effect_requested.emit(&"deployment_started", _detail_vector2(event.detail, "position"), card.faction_id, event.entity_id)


func _process_card_deployed(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var card := snapshot.get_unit_card(StringName(_detail_string(event.detail, "card")))
	if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	if _emit_feedback(Cue.DEPLOYMENT, &"BATTLE_FEEDBACK_CARD_DEPLOYED", [card.display_name_key], Severity.INFO, "deploy-complete:%s" % card.definition_id, event.tick):
		effect_requested.emit(&"deployment_complete", card.center_position, card.faction_id, event.entity_id)


func _process_support_started(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	if event.entity_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	var air_recon := _detail_string(event.detail, "air_recon")
	if not air_recon.is_empty():
		var region_ids := air_recon.split(",")
		var first := snapshot.get_strategic_region(StringName(region_ids[0])) if not region_ids.is_empty() else null
		var second := snapshot.get_strategic_region(StringName(region_ids[1])) if region_ids.size() > 1 else first
		var arguments: Array = [_region_display_key(first), _region_display_key(second)]
		if _emit_feedback(Cue.SUPPORT, &"BATTLE_FEEDBACK_AIR_RECON_STARTED", arguments, Severity.INFO, "support:recon", event.tick):
			if first != null:
				effect_requested.emit(&"recon_support", first.position, SimulationWorld.LOCAL_PLAYER_ID, event.entity_id)
			if second != null and second != first:
				effect_requested.emit(&"recon_support", second.position, SimulationWorld.LOCAL_PLAYER_ID, event.entity_id)
		return
	for detail_key in ["fortify", "rapid_mobility", "frontline_logistics"]:
		var card_id := StringName(_detail_string(event.detail, detail_key))
		if card_id.is_empty():
			continue
		var card := snapshot.get_unit_card(card_id)
		if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			return
		var message_key := &"BATTLE_FEEDBACK_FORTIFY_STARTED"
		var effect_kind := &"fortify"
		var arguments: Array = [card.display_name_key]
		if detail_key == "rapid_mobility":
			message_key = &"BATTLE_FEEDBACK_MOBILITY_STARTED"
			effect_kind = &"mobility"
		elif detail_key == "frontline_logistics":
			message_key = &"BATTLE_FEEDBACK_LOGISTICS_APPLIED"
			effect_kind = &"logistics"
			arguments.append(_detail_float(event.detail, "restored"))
		if _emit_feedback(Cue.SUPPORT, message_key, arguments, Severity.INFO, "support:%s:%s" % [detail_key, card_id], event.tick):
			effect_requested.emit(effect_kind, card.center_position, card.faction_id, event.entity_id)
		return
	var fire_region_id := StringName(_detail_string(event.detail, "fire_support"))
	if not fire_region_id.is_empty():
		var region := snapshot.get_strategic_region(fire_region_id)
		if region != null and _emit_feedback(Cue.SUPPORT, &"BATTLE_FEEDBACK_FIRE_SUPPORT", [region.display_name_key, _detail_int(event.detail, "hits")], Severity.WARNING, "support:fire:%s" % fire_region_id, event.tick):
			effect_requested.emit(&"fire_support", region.position, SimulationWorld.LOCAL_PLAYER_ID, event.entity_id)


func _process_support_ended(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	if event.entity_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	for detail_key in ["fortify", "rapid_mobility"]:
		var card_id := StringName(_detail_string(event.detail, detail_key))
		if card_id.is_empty():
			continue
		var card := snapshot.get_unit_card(card_id)
		if card != null and _emit_feedback(Cue.EFFECT_ENDED, &"BATTLE_FEEDBACK_CARD_EFFECT_ENDED", [card.display_name_key], Severity.INFO, "support-ended:%s:%s" % [detail_key, card_id], event.tick):
			effect_requested.emit(&"effect_ended", card.center_position, card.faction_id, event.entity_id)
		return
	var recon_region_id := StringName(_detail_string(event.detail, "air_recon"))
	var region := snapshot.get_strategic_region(recon_region_id)
	if region != null and _emit_feedback(Cue.EFFECT_ENDED, &"BATTLE_FEEDBACK_RECON_ENDED", [region.display_name_key], Severity.INFO, "recon-ended:%s" % recon_region_id, event.tick):
		effect_requested.emit(&"effect_ended", region.position, SimulationWorld.LOCAL_PLAYER_ID, event.entity_id)


func _process_engineering_route_opened(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	if event.entity_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	var region := snapshot.get_strategic_region(StringName(_detail_string(event.detail, "region")))
	var position := _detail_vector2(event.detail, "position")
	if position.is_zero_approx() and region != null:
		position = region.position
	if _emit_feedback(Cue.ENGINEERING, &"BATTLE_FEEDBACK_ENGINEERING_OPENED", [_region_display_key(region)], Severity.INFO, "engineering:%s" % _detail_string(event.detail, "route"), event.tick):
		effect_requested.emit(&"engineering_route", position, SimulationWorld.LOCAL_PLAYER_ID, event.entity_id)


func _process_doctrine_equipped(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var commander_id := StringName(_detail_string(event.detail, "commander"))
	var commander := snapshot.get_commander(commander_id)
	if commander == null or commander.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	var doctrine_key := StringName("DOCTRINE_%s" % _detail_string(event.detail, "doctrine").to_upper())
	_emit_feedback(Cue.DOCTRINE, &"BATTLE_FEEDBACK_DOCTRINE_EQUIPPED", [commander.display_name_key, doctrine_key], Severity.INFO, "doctrine:%s" % commander_id, event.tick)


func _process_supply_node_activated(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var card := snapshot.get_unit_card(StringName(_detail_string(event.detail, "card")))
	var region := snapshot.get_strategic_region(StringName(_detail_string(event.detail, "region")))
	if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID or region == null:
		return
	if _emit_feedback(Cue.REGION, &"BATTLE_FEEDBACK_SUPPLY_NODE_ACTIVE", [region.display_name_key], Severity.INFO, "supply-node:%s" % region.region_id, event.tick):
		effect_requested.emit(&"supply_node", region.position, card.faction_id, event.entity_id)


func _process_region_control_changed(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var region := snapshot.get_strategic_region(StringName(_detail_string(event.detail, "region")))
	if region == null:
		return
	var controller := _detail_int(event.detail, "controller")
	var contested := _detail_string(event.detail, "contested") == "true"
	var message_key := &"BATTLE_FEEDBACK_REGION_CONTESTED" if contested else (&"BATTLE_FEEDBACK_REGION_SECURED" if controller == SimulationWorld.LOCAL_PLAYER_ID else &"BATTLE_FEEDBACK_REGION_LOST")
	if _emit_feedback(Cue.REGION, message_key, [region.display_name_key], Severity.INFO, "region:%s:%d:%s" % [region.region_id, controller, contested], event.tick):
		var effect_kind := &"region_contested" if contested else (&"region_secured" if controller == SimulationWorld.LOCAL_PLAYER_ID else &"region_enemy")
		effect_requested.emit(effect_kind, region.position, controller, event.entity_id)


func _process_region_capture_started(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var region := snapshot.get_strategic_region(StringName(_detail_string(event.detail, "region")))
	if region == null:
		return
	var faction_id := _detail_int(event.detail, "faction")
	var message_key := &"BATTLE_FEEDBACK_CAPTURE_STARTED_LOCAL" if faction_id == SimulationWorld.LOCAL_PLAYER_ID else &"BATTLE_FEEDBACK_CAPTURE_STARTED_ENEMY"
	var severity := Severity.INFO if faction_id == SimulationWorld.LOCAL_PLAYER_ID else Severity.WARNING
	if _emit_feedback(Cue.REGION, message_key, [region.display_name_key], severity, "capture-start:%s:%d" % [region.region_id, faction_id], event.tick):
		effect_requested.emit(&"region_capture", region.position, faction_id, event.entity_id)


func _process_region_capture_interrupted(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var region := snapshot.get_strategic_region(StringName(_detail_string(event.detail, "region")))
	if region == null:
		return
	var faction_id := _detail_int(event.detail, "faction")
	var message_key := &"BATTLE_FEEDBACK_CAPTURE_INTERRUPTED_LOCAL" if faction_id == SimulationWorld.LOCAL_PLAYER_ID else &"BATTLE_FEEDBACK_CAPTURE_INTERRUPTED_ENEMY"
	if _emit_feedback(Cue.EFFECT_ENDED, message_key, [region.display_name_key], Severity.INFO, "capture-interrupted:%s:%d" % [region.region_id, faction_id], event.tick):
		effect_requested.emit(&"capture_interrupted", region.position, faction_id, event.entity_id)


func _process_organization_changed(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var card := snapshot.get_unit_card(StringName(_detail_string(event.detail, "card")))
	if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	var band := _detail_int(event.detail, "band")
	var severity := Severity.WARNING if band <= 1 else Severity.INFO
	if _emit_feedback(Cue.REGION, &"BATTLE_FEEDBACK_ORGANIZATION_CHANGED", [card.display_name_key, card.organization_state_key], severity, "organization:%s:%d" % [card.definition_id, band], event.tick):
		effect_requested.emit(&"organization", card.center_position, card.faction_id, event.entity_id)


func _process_card_withdrawn(event: SimulationEvent, snapshot: WorldSnapshot) -> void:
	var card := snapshot.get_unit_card(StringName(_detail_string(event.detail, "card")))
	if card == null or card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		return
	var position := _entity_position(snapshot, event.entity_id)
	if _emit_feedback(Cue.UNDER_PRESSURE, &"BATTLE_FEEDBACK_CARD_WITHDRAWN", [card.display_name_key], Severity.WARNING, "withdrawn:%s" % card.definition_id, event.tick):
		effect_requested.emit(&"withdrawal", position, card.faction_id, event.entity_id)


func _register_focus_fire(source_id: int, target_id: int, tick: int, snapshot: WorldSnapshot) -> void:
	if target_id == 0:
		return
	var window := _focus_windows.get(target_id, {}) as Dictionary
	if window.is_empty() or tick - int(window.get("start_tick", tick)) > FOCUS_WINDOW_TICKS:
		window = {"start_tick": tick, "sources": {}}
	var sources := window.get("sources", {}) as Dictionary
	sources[source_id] = true
	window["sources"] = sources
	_focus_windows[target_id] = window
	if sources.size() < FOCUS_SOURCE_THRESHOLD:
		return
	var target_key := _entity_display_key(snapshot, target_id)
	if _emit_feedback(Cue.FOCUS_FIRE, &"BATTLE_FEEDBACK_FOCUS_FIRE", [target_key], Severity.WARNING, "focus:%d" % target_id, tick):
		var target_faction := _entity_faction(snapshot, target_id)
		effect_requested.emit(&"focus", _entity_position(snapshot, target_id), target_faction, target_id)


func _register_card_damage(unit: UnitSnapshot, amount: float, tick: int, snapshot: WorldSnapshot) -> void:
	var scope_id := unit.unit_card_id if not unit.unit_card_id.is_empty() else StringName("formation_%d" % unit.formation_id)
	var window := _damage_windows.get(scope_id, {}) as Dictionary
	if window.is_empty() or tick - int(window.get("start_tick", tick)) > DAMAGE_WINDOW_TICKS:
		window = {"start_tick": tick, "amount": 0.0}
	window["amount"] = float(window.get("amount", 0.0)) + maxf(1.0, amount)
	_damage_windows[scope_id] = window
	if float(window["amount"]) < DAMAGE_PRESSURE_THRESHOLD:
		return
	var card_key := _unit_or_card_display_key(unit, snapshot)
	if _emit_feedback(Cue.UNDER_PRESSURE, &"BATTLE_FEEDBACK_UNDER_PRESSURE", [card_key], Severity.WARNING, "pressure:%s" % scope_id, tick):
		var card := snapshot.get_unit_card(unit.unit_card_id)
		var position := card.center_position if card != null else unit.position
		effect_requested.emit(&"pressure", position, unit.faction_id, unit.entity_id)
	window["amount"] = 0.0
	window["start_tick"] = tick
	_damage_windows[scope_id] = window


func _emit_feedback(cue: Cue, message_key: StringName, arguments: Array, severity: Severity, scope: String, tick: int) -> bool:
	var cooldown_key := "%d:%s" % [cue, scope]
	var last_tick := int(_last_feedback_tick_by_scope.get(cooldown_key, -1000000))
	if tick - last_tick < _cue_cooldown_ticks(cue):
		return false
	_last_feedback_tick_by_scope[cooldown_key] = tick
	_last_feedback_tick_by_scope["count:%d" % cue] = int(_last_feedback_tick_by_scope.get("count:%d" % cue, 0)) + 1
	last_cue = cue
	if not message_key.is_empty():
		last_message_key = message_key
		visual_count += 1
		feedback_emitted.emit(message_key, arguments.duplicate(), severity)
	_play_audio(cue, severity, tick)
	return true


func _play_audio(cue: Cue, severity: Severity, tick: int) -> void:
	if not audio_enabled or cue == Cue.NONE:
		return
	_ensure_audio()
	var slot := _find_available_voice(tick)
	if slot < 0 and severity == Severity.CRITICAL:
		slot = _lowest_priority_voice()
		if slot >= 0:
			preempted_audio_count += 1
	if slot < 0:
		dropped_audio_count += 1
		return
	var player := _players[slot]
	player.stream = _streams.get(cue) as AudioStream
	player.volume_db = _cue_volume_db(cue)
	if player.is_inside_tree():
		player.play()
	_voice_until_ticks[slot] = tick + _cue_duration_ticks(cue)
	_voice_priorities[slot] = severity
	peak_concurrent_voice_count = maxi(peak_concurrent_voice_count, get_active_voice_count(tick))
	play_count += 1


func _ensure_audio() -> void:
	if _streams.is_empty():
		_streams = {
			Cue.ENGAGEMENT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([270.0, 390.0]), 0.07, 0.18, 0.05),
			Cue.VOLLEY: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([145.0, 185.0]), 0.035, 0.13, 0.24),
			Cue.IMPACT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([105.0, 78.0]), 0.045, 0.15, 0.34),
			Cue.FOCUS_FIRE: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([420.0, 590.0, 760.0]), 0.06, 0.18, 0.04),
			Cue.UNDER_PRESSURE: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([330.0, 265.0, 205.0]), 0.075, 0.2, 0.08),
			Cue.REINFORCEMENT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([440.0, 590.0, 740.0]), 0.07, 0.18, 0.02),
			Cue.SCOUT_REPORT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([620.0, 880.0, 740.0]), 0.055, 0.16, 0.0),
			Cue.DEPLOYMENT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([390.0, 520.0, 680.0]), 0.06, 0.17, 0.02),
			Cue.SUPPORT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([480.0, 640.0]), 0.065, 0.17, 0.01),
			Cue.ENGINEERING: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([310.0, 465.0, 620.0, 775.0]), 0.055, 0.18, 0.03),
			Cue.EFFECT_ENDED: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([440.0, 330.0]), 0.055, 0.13, 0.0),
			Cue.DOCTRINE: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([550.0, 690.0]), 0.06, 0.15, 0.0),
			Cue.REGION: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([370.0, 555.0, 740.0]), 0.06, 0.17, 0.01),
			Cue.HEADQUARTERS_CRITICAL: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([230.0, 230.0, 155.0, 155.0]), 0.09, 0.22, 0.12),
			Cue.VICTORY: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([440.0, 660.0, 880.0]), 0.11, 0.2, 0.0),
			Cue.DEFEAT: UIFeedbackAudio.create_combat_cue(PackedFloat32Array([330.0, 220.0, 165.0]), 0.12, 0.2, 0.04),
		}
	while _players.size() < MAX_CONCURRENT_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "BattleVoice%d" % (_players.size() + 1)
		add_child(player)
		_players.append(player)
		_voice_until_ticks.append(0)
		_voice_priorities.append(0)


func _find_available_voice(tick: int) -> int:
	for index in range(_voice_until_ticks.size()):
		if _voice_until_ticks[index] <= tick:
			return index
	return -1


func _lowest_priority_voice() -> int:
	var best_index := -1
	var best_priority := 1000000
	for index in range(_voice_priorities.size()):
		if _voice_priorities[index] < best_priority:
			best_priority = _voice_priorities[index]
			best_index = index
	return best_index


func _cue_cooldown_ticks(cue: Cue) -> int:
	match cue:
		Cue.VOLLEY, Cue.IMPACT:
			return 3
		Cue.ENGAGEMENT, Cue.FOCUS_FIRE:
			return 24
		Cue.UNDER_PRESSURE, Cue.REINFORCEMENT, Cue.SCOUT_REPORT:
			return 35
		Cue.DEPLOYMENT, Cue.SUPPORT, Cue.ENGINEERING, Cue.EFFECT_ENDED, Cue.DOCTRINE, Cue.REGION:
			return 8
		Cue.HEADQUARTERS_CRITICAL:
			return 50
		_:
			return 1


func _cue_duration_ticks(cue: Cue) -> int:
	return 5 if cue in [Cue.VOLLEY, Cue.IMPACT] else 9


func _cue_volume_db(cue: Cue) -> float:
	return -9.0 if cue in [Cue.HEADQUARTERS_CRITICAL, Cue.VICTORY, Cue.DEFEAT] else -13.0


func _is_relevant_attack(attacker: UnitSnapshot, target_id: int, snapshot: WorldSnapshot) -> bool:
	if attacker.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
		return true
	if attacker.is_visible_to_local_player:
		return true
	return _entity_faction(snapshot, target_id) == SimulationWorld.LOCAL_PLAYER_ID


func _unit_or_card_display_key(unit: UnitSnapshot, snapshot: WorldSnapshot) -> StringName:
	var card := snapshot.get_unit_card(unit.unit_card_id) if not unit.unit_card_id.is_empty() else null
	if card != null:
		return card.display_name_key
	return StringName("UNIT_%s" % String(unit.definition_id).to_upper())


func _entity_display_key(snapshot: WorldSnapshot, entity_id: int) -> StringName:
	var unit := snapshot.get_unit(entity_id)
	if unit != null:
		return _unit_or_card_display_key(unit, snapshot)
	var building := snapshot.get_building(entity_id)
	if building != null:
		return StringName("BUILDING_%s" % String(building.definition_id).to_upper())
	return &"BATTLE_FEEDBACK_UNKNOWN_TARGET"


func _entity_position(snapshot: WorldSnapshot, entity_id: int) -> Vector2:
	var unit := snapshot.get_unit(entity_id)
	if unit != null:
		return unit.position
	var building := snapshot.get_building(entity_id)
	return building.position if building != null else Vector2.ZERO


func _entity_faction(snapshot: WorldSnapshot, entity_id: int) -> int:
	var unit := snapshot.get_unit(entity_id)
	if unit != null:
		return unit.faction_id
	var building := snapshot.get_building(entity_id)
	return building.faction_id if building != null else 0


func _detail_int(detail: String, key: String) -> int:
	return int(_detail_string(detail, key))


func _detail_float(detail: String, key: String) -> float:
	return float(_detail_string(detail, key))


func _detail_string(detail: String, key: String) -> String:
	var prefix := "%s=" % key
	for part in detail.split(";"):
		if part.begins_with(prefix):
			return part.trim_prefix(prefix)
	return ""


func _detail_vector2(detail: String, key: String) -> Vector2:
	var components := _detail_string(detail, key).split(",")
	if components.size() != 2:
		return Vector2.ZERO
	return Vector2(float(components[0]), float(components[1]))


func _region_display_key(region: StrategicRegionSnapshot) -> StringName:
	return region.display_name_key if region != null else &"BATTLE_FEEDBACK_UNKNOWN_TARGET"
