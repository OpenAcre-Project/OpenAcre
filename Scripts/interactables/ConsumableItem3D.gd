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
	var player_id: StringName = _resolve_player_id(player)
	var player_data := GameManager.session.entities.get_player(player_id)
	
	if nutrition_value > 0.0:
		player_data.calories = min(player_data.calories + nutrition_value, player_data.max_calories)
	
	var def_name: String = str(entity_data.definition_id) if entity_data else "Item"
	GameLog.info("[Interaction] Player consumed %s! Restored %.1f calories." % [def_name, nutrition_value])
	
	if entity_data:
		var stk_comp := entity_data.get_component(&"stackable") as StackableComponent
		
		if stk_comp and stk_comp.count > 1:
			stk_comp.count -= 1
			sync_physics_mass() # Recalculate mass for the remaining items
		else:
			# Last one consumed — destroy the entity entirely
			GameManager.session.entities.remove_entity(entity_data.runtime_id)
			_release_world_view()
	else:
		_release_world_view()

func get_interaction_prompt() -> String:
	var def_name: String = str(entity_data.definition_id) if entity_data else "Item"
	var interact_key: String = GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)
	return "Eat %s [%s] / Pick Up [Shift+%s]" % [def_name, interact_key, interact_key]
