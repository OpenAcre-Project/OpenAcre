extends RigidBody3D

@export var nutrition_value: float = 200.0

func interact(player: Node3D) -> void:
	var player_id: StringName = &"player.main"
	var id_any: Variant = player.get("simulation_player_id")
	if id_any is StringName:
		player_id = id_any
	elif id_any is String:
		player_id = StringName(id_any)

	var player_data := SimulationCore.get_player(player_id)
	player_data.calories = clamp(player_data.calories + nutrition_value, 0.0, player_data.max_calories)
	GameLog.info("[Interaction] Player ate the apple! Restored %.1f calories." % nutrition_value)
	queue_free()
