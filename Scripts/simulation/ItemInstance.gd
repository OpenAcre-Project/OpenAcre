extends Resource
class_name ItemInstance

## @deprecated — This class is superseded by EntityData in the UESS architecture.
## Inventories now store entity runtime_ids (StringName) and resolve EntityData
## from EntityManager. All item state lives in UESS Components (ItemComponent, 
## StackableComponent, DurabilityComponent, etc.).
##
## This file is retained only for reference. It should NOT be used in new code.
## All references have been migrated to the UESS EntityData + InventoryData system.

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
	return base + tank_mass

func get_total_volume() -> float:
	var def: ItemDefinition = get_definition()
	return (def.base_volume if def else 0.0) * stack
