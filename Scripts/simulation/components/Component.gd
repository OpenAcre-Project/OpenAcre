class_name Component
extends RefCounted

## Base class for all Component data blocks.
## Components hold pure data and NO logic or 3D Node references.

## The string ID of this component type (e.g. "transform", "durability")
var type_id: StringName = &""

## The last world-minute this component was processed.
## Used by the CatchUpEngine for lazy evaluation.
var last_simulated_minute: int = 0

func _init() -> void:
	pass

## Initialize the component's data from a dictionary (e.g. parsed from JSON)
func load_from_dict(_data: Dictionary) -> void:
	pass

## Serialize component data to a dictionary for saving
func save_to_dict() -> Dictionary:
	return {}
