extends EntityView3D
class_name InteractableItem3D

## If entity_data is null at start, generate a fresh one using these:
@export var initial_item_id: StringName = &""
@export var initial_stack: int = 1

func _ready() -> void:
	if entity_data == null and initial_item_id != &"":
		if GameManager.session and GameManager.session.entities:
			var registry: Node = Engine.get_main_loop().root.get_node(^"EntityRegistry")
			var new_data: EntityData = registry.create_entity(initial_item_id)
			if new_data:
				if new_data.has_component(&"stackable"):
					var stack_comp: Variant = new_data.get_component(&"stackable")
					if stack_comp and "count" in stack_comp:
						stack_comp.count = initial_stack
				apply_data(new_data)
				GameManager.session.entities.register_entity(new_data)
	sync_physics_mass()

func sync_physics_mass() -> void:
	if entity_data:
		var total_mass: float = 0.5
		if entity_data.has_component(&"item"):
			var itm: Variant = entity_data.get_component(&"item")
			if itm and "mass_kg" in itm:
				total_mass = itm.mass_kg
		if entity_data.has_component(&"stackable"):
			var stk: Variant = entity_data.get_component(&"stackable")
			if stk and "count" in stk:
				total_mass *= float(stk.count)
				
		mass = maxf(total_mass, 0.01)
		sleeping = false

func interact(player: Node3D) -> void:
	if not entity_data: return
	GameLog.info("[InteractableItem3D] Interaction triggered on %s" % name)
	var player_id: StringName = _resolve_player_id(player)
	var player_data := GameManager.session.entities.get_player(player_id)
	
	if not player_data or not "pockets" in player_data:
		return
	
	var stack_comp := entity_data.get_component(&"stackable") as StackableComponent
	var total_before: int = stack_comp.count if stack_comp else 1
	
	# UESS Direct Pickup: pass the entity's runtime_id to the inventory
	var absorbed: int = player_data.pockets.try_add_entity(entity_data.runtime_id)
	
	if absorbed <= 0:
		GameLog.warn("[Interaction] Pockets full! Cannot pick up %s" % entity_data.definition_id)
		return
	
	GameLog.info("[Interaction] Picked up %s x%d" % [entity_data.definition_id, absorbed])
	
	if absorbed >= total_before:
		# Fully picked up
		if player_data.pockets.has_entity(entity_data.runtime_id):
			# Entity was moved directly into inventory — parent it
			GameManager.session.entities.set_entity_parent(entity_data.runtime_id, player_id)
		else:
			# Entity was fully merged into existing stacks — remove from world
			GameManager.session.entities.remove_entity(entity_data.runtime_id)
		_release_world_view()
	else:
		# Partial pickup — reduce the world entity's remaining count
		if stack_comp:
			stack_comp.count = total_before - absorbed
		sync_physics_mass()

## Destroys the 3D view and notifies StreamSpooler to forget about this entity.
func _release_world_view() -> void:
	var rid: StringName = entity_data.runtime_id if entity_data else &""
	
	# Notify StreamSpooler to clean up its _spawned_views entry
	if rid != &"":
		EventBus.entity_view_released.emit(rid)
	
	# Remove from scene tree and free
	if get_parent():
		get_parent().remove_child(self)
	queue_free()

func _resolve_player_id(player: Node3D) -> StringName:
	var player_id: StringName = &"player.main"
	var id_any: Variant = player.get("simulation_player_id")
	if id_any is StringName:
		player_id = id_any
	elif id_any is String:
		player_id = StringName(id_any)
	return player_id

func get_interaction_prompt() -> String:
	var item_name: String = str(entity_data.definition_id) if entity_data else "Item"
	var stack_count: int = 1
	if entity_data and entity_data.has_component(&"stackable"):
		var stk: Variant = entity_data.get_component(&"stackable")
		if stk and "count" in stk:
			stack_count = stk.count
		
	if stack_count > 1:
		return "Pick Up %s (x%d) [%s]" % [item_name, stack_count, GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)]
	return "Pick Up %s [%s]" % [item_name, GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)]
