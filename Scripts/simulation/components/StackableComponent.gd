class_name StackableComponent
extends Component

## Allows an item entity to represent multiple copies of itself in one slot.

var count: int = 1
var max_stack: int = 64

func _init() -> void:
	type_id = &"stackable"

func load_from_dict(data: Dictionary) -> void:
	count = int(data.get("count", 1))
	max_stack = int(data.get("max_stack", 64))

func save_to_dict() -> Dictionary:
	return {
		"count": count,
		"max_stack": max_stack
	}
