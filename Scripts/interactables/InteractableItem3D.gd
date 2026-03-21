extends RigidBody3D
class_name InteractableItem3D

## The authoritative data payload for this item.
@export var item_data: ItemInstance

## If item_data is null at start, generate a fresh one using these:
@export var initial_item_id: StringName = &""
@export var initial_stack: int = 1

func _ready() -> void:
	if item_data == null:
		item_data = ItemInstance.new()
		item_data.definition_id = initial_item_id
		item_data.stack = initial_stack
	
	sync_physics_mass()

func sync_physics_mass() -> void:
	if item_data:
		# Godot/Jolt requires mass > 0.0
		mass = maxf(item_data.get_total_mass(), 0.01)
		sleeping = false # Wake up physics engine to process mass change

func interact(player: Node3D) -> void:
	GameLog.info("[InteractableItem3D] Interaction triggered on %s" % name)
	var player_id: StringName = &"player.main"
	var id_any: Variant = player.get("simulation_player_id")
	if id_any is StringName:
		player_id = id_any
	elif id_any is String:
		player_id = StringName(id_any)

	var player_data := GameManager.session.entities.get_player(player_id)
	
	if player_data.pockets.try_add_item(item_data):
		GameLog.info("[Interaction] Picked up %s" % item_data.definition_id)
		if item_data.stack <= 0:
			queue_free()
		else:
			GameLog.warn("[Interaction] Pockets full! Left %d of %s" % [item_data.stack, item_data.definition_id])
			sync_physics_mass()
	else:
		GameLog.warn("[Interaction] Pockets full! Cannot pick up %s" % item_data.definition_id)

func get_interaction_prompt() -> String:
	var item_name: String = str(item_data.definition_id) if item_data else "Item"
	if item_data and item_data.stack > 1:
		return "Pick Up %s (x%d) [%s]" % [item_name, item_data.stack, GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)]
	return "Pick Up %s [%s]" % [item_name, GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)]
