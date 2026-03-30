extends Tool

class_name SeedTool

const WORK_REQUEST_SCRIPT = preload("res://Scripts/farm/work/WorkRequest.gd")
const WORK_OPERATION_TYPE_SCRIPT = preload("res://Scripts/farm/work/WorkOperationType.gd")

func _init() -> void:
	tool_name = "Seeds (Plant Crops)"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	var grid_pos := GameManager.session.farm.world_to_grid(block_pos)
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")
	if soil_service != null and soil_service.has_method("process_work_batch"):
		var request := WORK_REQUEST_SCRIPT.point(
			WORK_OPERATION_TYPE_SCRIPT.Value.SOWING,
			block_pos,
			0.49,
			{
				"seed_item_id": &"generic",
				"growth_minutes_required": GameManager.session.farm.DEFAULT_CROP_GROWTH_MINUTES
			},
			&"tool.seed",
			1
		)
		request.engagement_height = block_pos.y
		request.engagement_margin = 0.03

		var reports: Array = soil_service.process_work_batch([request])
		if reports.is_empty():
			GameLog.info("[Tool] Unable to process sowing request at %s." % str(grid_pos))
			return

		var report: WorkReport = reports[0]
		if report.successful_area > 0.0:
			GameLog.info("[Tool] Planted seeds at %s!" % str(grid_pos))
		elif report.rejected_wrong_state > 0:
			var tile_data_fail: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
			if tile_data_fail.state == FarmData.SoilState.GRASS:
				GameLog.info("[Tool] Cannot plant on grass. Plow the soil first.")
			else:
				GameLog.info("[Tool] Something is already planted here.")
		elif report.rejected_unfarmable > 0:
			GameLog.info("[Tool] Cannot plant here. Ground is not farmable.")
		else:
			GameLog.info("[Tool] Seeding action rejected.")
		return

	if soil_service != null and soil_service.has_method("seed_world"):
		if soil_service.seed_world(block_pos):
			GameLog.info("[Tool] Planted seeds at %s!" % str(grid_pos))
		else:
			var tile_data_fail: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
			if tile_data_fail.state == FarmData.SoilState.GRASS:
				GameLog.info("[Tool] Cannot plant on grass. Plow the soil first.")
			else:
				GameLog.info("[Tool] Something is already planted here.")
		return

	# Fallback if world service is not present
	var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
	if tile_data.state == FarmData.SoilState.PLOWED:
		if GameManager.session.farm.plant_crop(grid_pos, &"generic", GameManager.session.farm.DEFAULT_CROP_GROWTH_MINUTES, block_pos.y):
			GameLog.info("[Tool] Planted seeds at %s!" % str(grid_pos))
		else:
			GameLog.info("[Tool] Failed to plant seeds at %s." % str(grid_pos))
	elif tile_data.state == FarmData.SoilState.GRASS:
		GameLog.info("[Tool] Cannot plant on grass. Plow the soil first.")
	else:
		GameLog.info("[Tool] Something is already planted here.")
