extends Tool

class_name HoeTool

const WORK_REQUEST_SCRIPT = preload("res://Scripts/farm/work/WorkRequest.gd")
const WORK_OPERATION_TYPE_SCRIPT = preload("res://Scripts/farm/work/WorkOperationType.gd")

func _init() -> void:
	tool_name = "Hoe (Plow Grass)"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	var grid_pos := GameManager.session.farm.world_to_grid(block_pos)
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")
	if soil_service != null and soil_service.has_method("process_work_batch"):
		var request := WORK_REQUEST_SCRIPT.point(
			WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE,
			block_pos,
			0.49,
			{
				"soil_state_output": FarmData.SoilState.PLOWED,
				"depth_offset": -0.05,
				"blend_mode": GroundEffector3D.BlendMode.ADD
			},
			&"tool.hoe",
			1
		)
		request.engagement_height = block_pos.y
		request.engagement_margin = 0.03
		var reports: Array = soil_service.process_work_batch([request])
		if reports.is_empty():
			GameLog.info("[Tool] Unable to process hoe request at %s." % str(grid_pos))
			return

		var report: WorkReport = reports[0]
		if report.successful_area > 0.0:
			GameLog.info("[Tool] Plowed the soil at %s!" % str(grid_pos))
		elif report.rejected_unfarmable > 0:
			GameLog.info("[Tool] Cannot plow here. Ground is not farmable. (Greyscale ID: %d)" % GameManager.session.farm.get_raw_region_value(block_pos))
		else:
			GameLog.info("[Tool] Ground here cannot be plowed right now.")
		return

	if soil_service != null and soil_service.has_method("plow_world"):
		if soil_service.plow_world(block_pos):
			GameLog.info("[Tool] Plowed the soil at %s! (Greyscale ID: %d)" % [str(grid_pos), GameManager.session.farm.get_raw_region_value(block_pos)])
		else:
			GameLog.info("[Tool] Ground here is already plowed.")
		return

	# Fallback if world service is not present
	var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
	if tile_data.state == FarmData.SoilState.GRASS:
		GameManager.session.farm.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, block_pos.y)
		GameLog.info("[Tool] Plowed the soil at %s! (Greyscale ID: %d)" % [str(grid_pos), GameManager.session.farm.get_raw_region_value(block_pos)])
	else:
		GameLog.info("[Tool] Ground here is already plowed.")
