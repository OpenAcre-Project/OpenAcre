extends Tool

class_name SeedTool

func _init() -> void:
	tool_name = "Seeds (Plant Crops)"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	var grid_pos := FarmData.world_to_grid(block_pos)
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")

	if soil_service != null and soil_service.has_method("seed_world"):
		if soil_service.seed_world(block_pos):
			GameLog.info("[Tool] Planted seeds at %s!" % str(grid_pos))
		else:
			var tile_data_fail: FarmTileData = FarmData.get_tile_data(grid_pos)
			if tile_data_fail.state == FarmData.SoilState.GRASS:
				GameLog.info("[Tool] Cannot plant on grass. Plow the soil first.")
			else:
				GameLog.info("[Tool] Something is already planted here.")
		return

	# Fallback if world service is not present
	var tile_data: FarmTileData = FarmData.get_tile_data(grid_pos)
	if tile_data.state == FarmData.SoilState.PLOWED:
		if FarmData.plant_crop(grid_pos, &"generic", FarmData.DEFAULT_CROP_GROWTH_MINUTES, block_pos.y):
			GameLog.info("[Tool] Planted seeds at %s!" % str(grid_pos))
		else:
			GameLog.info("[Tool] Failed to plant seeds at %s." % str(grid_pos))
	elif tile_data.state == FarmData.SoilState.GRASS:
		GameLog.info("[Tool] Cannot plant on grass. Plow the soil first.")
	else:
		GameLog.info("[Tool] Something is already planted here.")
