extends Resource
class_name InventoryData

## Absolute volume limit in Liters.
var max_volume: float = 10.0

## Soft mass limit in kg (owner becomes encumbered if exceeded).
var max_mass: float = 20.0

## The items currently inside the inventory.
var items: Array[ItemInstance] = []

## Tries to add an item. Returns true if AT LEAST ONE unit was added. 
## The passed new_item will have its stack reduced by the amount added.
func try_add_item(new_item: ItemInstance) -> bool:
	if new_item == null or new_item.stack <= 0:
		return false
	
	var def: ItemDefinition = new_item.get_definition()
	if not def:
		return false

	var volume_per_unit := def.base_volume
	if volume_per_unit <= 0.0:
		volume_per_unit = 0.001
		
	var current_vol := get_total_volume()
	var free_volume: float = maxf(0.0, max_volume - current_vol)
	
	var max_can_fit: int = new_item.stack
	if (new_item.stack * volume_per_unit) > free_volume:
		max_can_fit = int(free_volume / volume_per_unit)
		
	if max_can_fit <= 0:
		return false # Cannot fit even one item
		
	var amount_to_add := max_can_fit
	var initial_add_amount := amount_to_add
	
	var max_stack := def.max_stack_size
	
	# Only allow stacking if there is no unique embedded data
	var can_stack: bool = max_stack > 1 and \
		new_item.dynamic_data.is_empty() and \
		new_item.embedded_inventory == null and \
		new_item.embedded_tank == null
	
	# Handle stacking into existing slots if applicable
	if can_stack:
		for item in items:
			if amount_to_add <= 0:
				break
			if item.definition_id == new_item.definition_id and item.stack < max_stack and item.dynamic_data.is_empty():
				var space: int = max_stack - item.stack
				var transferred: int = int(min(space, amount_to_add))
				item.stack += transferred
				amount_to_add -= transferred

	# Split remaining stack into proper maximum capacities
	while amount_to_add > 0:
		var chunk_size := int(min(amount_to_add, max_stack))
		var chunk := ItemInstance.new()
		chunk.definition_id = new_item.definition_id
		chunk.stack = chunk_size
		chunk.dynamic_data = new_item.dynamic_data.duplicate()
		items.append(chunk)
		amount_to_add -= chunk_size
		
	# Reduce the original item's stack by the amount we actually transferred
	new_item.stack -= initial_add_amount
	
	return true

## Removes an item at a specific index.
func remove_item(index: int) -> ItemInstance:
	if index < 0 or index >= items.size():
		return null
	var item: ItemInstance = items[index]
	items.remove_at(index)
	return item

## Calculates total mass of all items.
func get_current_mass() -> float:
	var total: float = 0.0
	for item: ItemInstance in items:
		if item:
			total += item.get_total_mass()
	return total

## Calculates total volume of all items.
func get_total_volume() -> float:
	var total: float = 0.0
	for item: ItemInstance in items:
		if item:
			total += item.get_total_volume()
	return total
