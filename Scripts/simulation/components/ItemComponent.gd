class_name ItemComponent
extends Component

## Describes physical properties of a pickup-able item in the world.

var mass_kg: float = 1.0
var volume_liters: float = 1.0
var display_name: String = "Item"

func _init() -> void:
	type_id = &"item"

func load_from_dict(data: Dictionary) -> void:
	mass_kg = data.get("mass_kg", 1.0)
	volume_liters = data.get("volume_liters", 1.0)
	display_name = data.get("display_name", "Item")

func save_to_dict() -> Dictionary:
	return {
		"mass_kg": mass_kg,
		"volume_liters": volume_liters,
		"display_name": display_name
	}
