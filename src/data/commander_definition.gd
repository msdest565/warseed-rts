class_name CommanderDefinition
extends Resource

@export var definition_id: StringName
@export var display_name_key: StringName
@export var capacity: int = 1
@export var personality_key: StringName
@export var specialty_keys: Array[StringName] = []
@export var doctrine_keys: Array[StringName] = []
@export var available_doctrine_ids: Array[StringName] = []
