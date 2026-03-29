class_name DurabilityComponent
extends Component

var health: float = 100.0
var max_health: float = 100.0

## Accumulates decay. When high enough, might trigger definition swap (e.g. Apple -> Rot Pile)
var rot_amount: float = 0.0
var rot_rate_per_minute: float = 0.0

func _init() -> void:
	type_id = &"durability"

func load_from_dict(data: Dictionary) -> void:
	health = data.get("health", 100.0)
	max_health = data.get("max_health", 100.0)
	rot_amount = data.get("rot_amount", 0.0)
	rot_rate_per_minute = data.get("rot_rate_per_minute", 0.0)

func save_to_dict() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"rot_amount": rot_amount,
		"rot_rate_per_minute": rot_rate_per_minute
	}
