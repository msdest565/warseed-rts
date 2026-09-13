class_name DoctrineDefinition
extends Resource

@export var definition_id: StringName
@export var display_name_key: StringName
@export var behavior_key: StringName
@export var tradeoff_key: StringName
@export var effects: Array[DoctrineEffectDefinition] = []


func validate(path: String = "doctrine") -> DataValidationResult:
	var result := DataValidationResult.new()
	DoctrineEffectDefinition.validate_id(result, definition_id, path + ".definition_id")
	DoctrineEffectDefinition.validate_text_key(result, display_name_key, path + ".display_name_key")
	DoctrineEffectDefinition.validate_text_key(result, behavior_key, path + ".behavior_key")
	DoctrineEffectDefinition.validate_text_key(result, tradeoff_key, path + ".tradeoff_key")
	var ids: Array[StringName] = []
	var kinds: Array[int] = []
	for index in range(effects.size()):
		var definition := effects[index]
		var effect_path := "%s.effects[%d]" % [path, index]
		if definition == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, effect_path)
			continue
		if ids.has(definition.effect_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, effect_path + ".effect_id is duplicated")
		ids.append(definition.effect_id)
		if definition.effect != null:
			if kinds.has(definition.effect.kind):
				result.add(DataValidationResult.Reason.INVALID_VALUE, effect_path + ".effect.kind cannot be stacked in one doctrine")
			kinds.append(definition.effect.kind)
		result.issues.append_array(definition.validate(effect_path).issues)
	return result
