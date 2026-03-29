class_name CatchUpEngine
extends RefCounted

## Processes elapsed time on entities during the spooling/wakeup process.
## Mutates or replaces entities when necessary.

## Processes the entity catching up to `current_total_minutes`.
## If the entity mutates (e.g. apple to rot pile), it returns the new substitute EntityData. 
## Otherwise returns the original.
static func catch_up_entity(entity: EntityData, current_total_minutes: int) -> EntityData:
	if not GameManager.session or not GameManager.session.entities:
		return entity
		
	var to_mutate_into_def: StringName = &""
	
	# Loop through components and process time
	for comp in entity.get_all_components():
		if comp.last_simulated_minute < current_total_minutes:
			var delta_mins: int = current_total_minutes - comp.last_simulated_minute
			
			if comp.type_id == &"durability":
				var dur := comp as DurabilityComponent
				dur.rot_amount += dur.rot_rate_per_minute * delta_mins
				dur.health = maxf(0.0, dur.health - dur.rot_amount) 
				if dur.health <= 0.0:
					to_mutate_into_def = &"item.rot_pile" # Definition swap trigger
					
			# Mark component as caught up
			comp.last_simulated_minute = current_total_minutes
			
	if to_mutate_into_def != &"":
		return _mutate_entity(entity, to_mutate_into_def)
		
	return entity

## Securely mutates an entity in-place by clearing its old components and resetting
## its definition to the new one, retaining its `runtime_id`, physical anchors, and parents.
static func _mutate_entity(old_entity: EntityData, new_def_id: StringName) -> EntityData:
	var registry: Node = Engine.get_main_loop().root.get_node_or_null(^"EntityRegistry")
	if not registry: 
		push_error("CatchUpEngine couldn't find EntityRegistry Autoload")
		return old_entity
	
	if not registry.has_def(new_def_id):
		push_error("CatchUpEngine: Cannot mutate to unknown definition " + str(new_def_id))
		return old_entity
		
	# 1. Clear current components except maybe ones we want to rigorously keep? 
	# For now, we clear them and reload from the new definition.
	var old_tf: TransformComponent = old_entity.get_transform()
	var pos: Vector3 = old_tf.world_position if old_tf else Vector3.ZERO
	var rot: float = old_tf.world_rotation_radians if old_tf else 0.0
	var chunk: Vector2i = old_tf.chunk_id if old_tf else Vector2i.ZERO
	
	old_entity._components.clear()
	old_entity.definition_id = new_def_id
	
	# 2. Reload components from definition
	var def: Dictionary = registry.get_def(new_def_id)
	var components_dict: Dictionary = def.get("components", {})
	
	var spawn_time: int = 0
	if GameManager.session != null and GameManager.session.time != null:
		spawn_time = GameManager.session.time.get_total_minutes()
		
	for comp_type: String in components_dict.keys():
		var comp_data: Dictionary = components_dict[comp_type]
		var comp: Component = registry._create_component(comp_type)
		if comp:
			comp.load_from_dict(comp_data)
			comp.last_simulated_minute = spawn_time
			old_entity.add_component(comp)
			
	# 3. Restore positional data
	var new_tf: TransformComponent = old_entity.get_transform()
	if new_tf:
		new_tf.world_position = pos
		new_tf.world_rotation_radians = rot
		new_tf.chunk_id = chunk
		
	return old_entity
