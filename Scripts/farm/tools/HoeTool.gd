extends Tool

class_name HoeTool

func _init() -> void:
	tool_name = "Hoe (Plow Grass)"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	if not FarmData.can_plow_at(block_pos):
		GameLog.info("[Tool] Cannot plow here. Ground is not farmable. (Greyscale ID: %d)" % FarmData.get_raw_region_value(block_pos))
		return

	var grid_pos := FarmData.world_to_grid(block_pos)
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")

	if soil_service != null and soil_service.has_method("plow_world"):
		if soil_service.plow_world(block_pos):
			GameLog.info("[Tool] Plowed the soil at %s! (Greyscale ID: %d)" % [str(grid_pos), FarmData.get_raw_region_value(block_pos)])
		else:
			GameLog.info("[Tool] Ground here is already plowed.")
		return

	# Fallback if world service is not present
	var tile_data: FarmTileData = FarmData.get_tile_data(grid_pos)
	if tile_data.state == FarmData.SoilState.GRASS:
		FarmData.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, block_pos.y)
		GameLog.info("[Tool] Plowed the soil at %s! (Greyscale ID: %d)" % [str(grid_pos), FarmData.get_raw_region_value(block_pos)])
	else:
		GameLog.info("[Tool] Ground here is already plowed.")
