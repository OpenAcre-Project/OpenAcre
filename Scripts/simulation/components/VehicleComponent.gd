class_name VehicleComponent
extends Component

## Holds engine/fuel state for any drivable entity.

var fuel_level: float = 100.0
var max_fuel: float = 100.0
var engine_temp_celsius: float = 20.0
var fuel_burn_rate_per_minute: float = 0.05

func _init() -> void:
	type_id = &"vehicle"

func load_from_dict(data: Dictionary) -> void:
	fuel_level = data.get("fuel_level", 100.0)
	max_fuel = data.get("max_fuel", 100.0)
	engine_temp_celsius = data.get("engine_temp_celsius", 20.0)
	fuel_burn_rate_per_minute = data.get("fuel_burn_rate_per_minute", 0.05)

func save_to_dict() -> Dictionary:
	return {
		"fuel_level": fuel_level,
		"max_fuel": max_fuel,
		"engine_temp_celsius": engine_temp_celsius,
		"fuel_burn_rate_per_minute": fuel_burn_rate_per_minute
	}
