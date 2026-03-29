extends Resource
class_name InventoryData

## ID-Based Inventory System (UESS Architecture)
## Stores only runtime_ids (StringName) of EntityData objects.
## The authoritative entity data lives in EntityManager._entities.
## This is a "flat database" approach: the inventory is a view, not a copy.

## Absolute volume limit in Liters.
var max_volume: float = 10.0

## Soft mass limit in kg (owner becomes encumbered if exceeded).
var max_mass: float = 20.0

## Runtime IDs of entities currently inside this inventory.
var entity_ids: Array[StringName] = []

## Attempts to add items from the given entity into this inventory.
## Returns the number of units absorbed (0 = inventory is full).
## When fully absorbed (return == entity's stack count), the caller should:
##   - set_entity_parent() on the entity if it was used directly (check has_entity)
##   - remove_entity() if it was fully merged into existing stacks (check !has_entity)
## When partially absorbed (0 < return < stack count), the caller should:
##   - reduce the entity's StackableComponent.count by the returned amount
func try_add_entity(entity_id: StringName) -> int:
	if not GameManager.session or not GameManager.session.entities:
		return 0
	var em := GameManager.session.entities as EntityManager
	var entity := em.get_entity(entity_id)
	if not entity:
		return 0
	
	# Must have an ItemComponent to be inventory-valid
	var item_comp := entity.get_component(&"item") as ItemComponent
	if not item_comp:
		return 0
	
	var stack_comp := entity.get_component(&"stackable") as StackableComponent
	var incoming: int = stack_comp.count if stack_comp else 1
	var max_stack: int = stack_comp.max_stack if stack_comp else 1
	var vol_per: float = maxf(item_comp.volume_liters, 0.001)
	
	# Volume gate
	var free_vol: float = maxf(0.0, max_volume - get_total_volume())
	if free_vol < vol_per:
		return 0 # Can't fit even one unit
	var max_fit: int = mini(incoming, int(free_vol / vol_per))
	if max_fit <= 0:
		return 0
	
	var units_left: int = max_fit
	
	# Phase 1: Merge into existing compatible stacks
	var can_merge: bool = stack_comp != null and max_stack > 1
	if can_merge:
		for ex_id: StringName in entity_ids:
			if units_left <= 0: break
			var ex := em.get_entity(ex_id)
			if not ex or not entity.can_stack_with(ex): continue
			var ex_stack := ex.get_component(&"stackable") as StackableComponent
			if not ex_stack or ex_stack.count >= max_stack: continue
			var xfer: int = mini(max_stack - ex_stack.count, units_left)
			ex_stack.count += xfer
			units_left -= xfer
	
	# Phase 2: Place remaining as new inventory slots
	var used_original: bool = false
	while units_left > 0:
		var slot_size: int = mini(units_left, max_stack)
		
		if not used_original and max_fit == incoming:
			# Entire entity is being absorbed and nothing was split —
			# use the original entity directly for the first slot.
			if stack_comp:
				stack_comp.count = slot_size
			entity_ids.append(entity_id)
			used_original = true
		else:
			# Create a clone for this inventory slot
			var registry: Node = Engine.get_main_loop().root.get_node(^"EntityRegistry")
			var clone: EntityData = registry.clone_entity(entity)
			var cs := clone.get_component(&"stackable") as StackableComponent
			if cs:
				cs.count = slot_size
			em.register_entity(clone)
			entity_ids.append(clone.runtime_id)
		
		units_left -= slot_size
	
	return max_fit

## Checks if a specific entity is in this inventory.
func has_entity(entity_id: StringName) -> bool:
	return entity_ids.has(entity_id)

## Removes an entity by runtime_id. Returns true if found and removed.
func remove_entity(entity_id: StringName) -> bool:
	var idx: int = entity_ids.find(entity_id)
	if idx < 0:
		return false
	entity_ids.remove_at(idx)
	return true

## Removes an entity at a specific index. Returns the runtime_id or empty StringName.
func remove_at(index: int) -> StringName:
	if index < 0 or index >= entity_ids.size():
		return &""
	var entity_id: StringName = entity_ids[index]
	entity_ids.remove_at(index)
	return entity_id

## Calculates total mass of all items using their UESS components.
func get_current_mass() -> float:
	if not GameManager.session or not GameManager.session.entities:
		return 0.0
	var em := GameManager.session.entities as EntityManager
	var total: float = 0.0
	for entity_id: StringName in entity_ids:
		var entity := em.get_entity(entity_id)
		if not entity: continue
		var item_comp := entity.get_component(&"item") as ItemComponent
		if not item_comp: continue
		var count: int = 1
		var stack_comp := entity.get_component(&"stackable") as StackableComponent
		if stack_comp:
			count = stack_comp.count
		total += item_comp.mass_kg * float(count)
	return total

## Calculates total volume of all items using their UESS components.
func get_total_volume() -> float:
	if not GameManager.session or not GameManager.session.entities:
		return 0.0
	var em := GameManager.session.entities as EntityManager
	var total: float = 0.0
	for entity_id: StringName in entity_ids:
		var entity := em.get_entity(entity_id)
		if not entity: continue
		var item_comp := entity.get_component(&"item") as ItemComponent
		if not item_comp: continue
		var count: int = 1
		var stack_comp := entity.get_component(&"stackable") as StackableComponent
		if stack_comp:
			count = stack_comp.count
		total += item_comp.volume_liters * float(count)
	return total

## Returns the number of occupied slots.
func get_slot_count() -> int:
	return entity_ids.size()
