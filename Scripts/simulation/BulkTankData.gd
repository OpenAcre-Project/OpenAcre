extends Resource
class_name BulkTankData

## Absolute limit in Liters.
var max_volume: float = 100.0

## Allowed commodity IDs. Empty means all are allowed? User says fuel tank only accepts diesel.
var allowed_commodities: Array[StringName] = []

## Current commodity in the tank. Empty if empty.
var current_commodity: StringName = &""

## Current amount in Liters.
var current_liters: float = 0.0

## Adds fluid. Returns the actual amount added.
func try_add_fluid(commodity_id: StringName, amount_liters: float) -> float:
	if amount_liters <= 0.0:
		return 0.0
		
	if not allowed_commodities.is_empty() and not commodity_id in allowed_commodities:
		return 0.0
		
	if current_commodity != &"" and current_commodity != commodity_id:
		return 0.0
		
	var space: float = max_volume - current_liters
	var to_add: float = min(space, amount_liters)
	
	if current_commodity == &"":
		current_commodity = commodity_id
		
	current_liters += to_add
	return to_add

## Extracts fluid. Returns actual amount extracted.
func extract_fluid(amount_liters: float) -> float:
	var to_extract: float = min(current_liters, amount_liters)
	current_liters -= to_extract
	if current_liters <= 0.0:
		current_commodity = &""
	return to_extract

## Calculates current mass in kg.
func get_current_mass() -> float:
	if current_commodity == &"":
		return 0.0
	var density: float = ItemRegistry.get_commodity_density(current_commodity)
	return current_liters * density
