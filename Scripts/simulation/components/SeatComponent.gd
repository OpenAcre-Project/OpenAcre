class_name SeatComponent
extends Component

## Marks an entity as enterable/drivable.

var is_occupied: bool = false
var occupant_id: StringName = &""

func _init() -> void:
	type_id = &"seat"

func load_from_dict(data: Dictionary) -> void:
	is_occupied = data.get("is_occupied", false)
	occupant_id = StringName(data.get("occupant_id", ""))

func save_to_dict() -> Dictionary:
	return {
		"is_occupied": is_occupied,
		"occupant_id": str(occupant_id)
	}
