class_name ContainerComponent
extends Component

## Handles inventory capacity. Actual items (entities) should have their `parent_id` 
## set to this entity's ID in the EntityManager, or they can be stored here if simple.
## We will track them via the EntityManager hierarchy primarily, but store limits here.

var max_weight_kg: float = 100.0
var max_slots: int = 10

func _init() -> void:
	type_id = &"container"

func load_from_dict(data: Dictionary) -> void:
	max_weight_kg = data.get("max_weight_kg", 100.0)
	max_slots = int(data.get("max_slots", 10))

func save_to_dict() -> Dictionary:
	return {
		"max_weight_kg": max_weight_kg,
		"max_slots": max_slots
	}
