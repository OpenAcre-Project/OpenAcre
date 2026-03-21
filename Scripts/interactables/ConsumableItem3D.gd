extends InteractableItem3D
class_name ConsumableItem3D

## Calories restored when consumed.
@export var nutrition_value: float = 200.0

## Hydration restored when consumed.
@export var hydration_value: float = 0.0

func interact(player: Node3D) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		# Delegate to base pick up logic
		super.interact(player)
	else:
		consume(player)

func consume(player: Node3D) -> void:
	var player_id: StringName = &"player.main"
	var id_any: Variant = player.get("simulation_player_id")
	if id_any is StringName:
		player_id = id_any
	elif id_any is String:
		player_id = StringName(id_any)

	var player_data := GameManager.session.entities.get_player(player_id)
	
	if nutrition_value > 0.0:
		player_data.calories = min(player_data.calories + nutrition_value, player_data.max_calories)
	
	# Hydration logic can be added here if PlayerData supports it
	# player_data.thirst = min(player_data.thirst + hydration_value, player_data.max_thirst)

	var def_name: String = str(item_data.definition_id) if item_data else "Item"
	GameLog.info("[Interaction] Player consumed %s! Restored %.1f calories." % [def_name, nutrition_value])
	
	if item_data:
		item_data.stack -= 1
		if item_data.stack <= 0:
			queue_free()
		else:
			sync_physics_mass() # Recalculate mass for the remaining apples
	else:
		queue_free()

func get_interaction_prompt() -> String:
	var def_name: String = str(item_data.definition_id) if item_data else "Item"
	var interact_key: String = GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)
	return "Eat %s [%s] / Pick Up [Shift+%s]" % [def_name, interact_key, interact_key]
