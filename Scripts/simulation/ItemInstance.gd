extends Resource
class_name ItemInstance

## UID linking back to static definition
var definition_id: StringName = &""

## Current stack amount
var stack: int = 1

## Arbitrary data (durability, battery, etc.)
var dynamic_data: Dictionary = {}

## Optional tank (e.g., fuel can)
var embedded_tank: BulkTankData

## Optional inventory (e.g., backpack)
var embedded_inventory: InventoryData

func get_definition() -> ItemDefinition:
	return ItemRegistry.get_item(definition_id)

func get_total_mass() -> float:
	var def: ItemDefinition = get_definition()
	var base: float = (def.base_mass if def else 0.0) * stack
	var tank_mass: float = embedded_tank.get_current_mass() if embedded_tank else 0.0
	var inv_mass: float = embedded_inventory.get_current_mass() if embedded_inventory else 0.0
	return base + tank_mass + inv_mass

func get_total_volume() -> float:
	var def: ItemDefinition = get_definition()
	# Usually just base_volume * stack. 
	# User says: "An empty backpack takes up the same space as a full one."
	return (def.base_volume if def else 0.0) * stack
