extends Node3D

signal runtime_paint_availability_changed(is_available: bool, reason: String)

@export var dirt_texture_index: int = 3 # Matches your scene file
@export var grass_texture_index: int = 0
@export var plow_brush_radius: float = 1.0 # Radius in meters
@export var ground_effect_segment_length_meters: float = 0.25
@export var collision_rebuild_distance_meters: float = 1.0
@export var default_engagement_margin_meters: float = 0.03
@export var map_rebuild_interval_seconds: float = 0.12

var _terrain: Node = null
var _terrain_api: Object = null # Points to Terrain3DData / Terrain3DStorage
var _runtime_paint_ready := false
var _runtime_paint_reason := "Not initialized"
var _batch_painting := false
var _suppress_tile_signal_paint := false
var _collision_distance_accumulator: float = 0.0
var _pending_height_map_rebuild: bool = false
var _pending_control_map_rebuild: bool = false
var _last_map_rebuild_msec: int = 0
var _edited_regions: Dictionary = {}
var _last_work_reports: Array = []
var _last_work_report_summaries: Array[String] = []

const MAP_TYPE_HEIGHT: int = 0
const MAP_TYPE_CONTROL: int = 1
const MAP_TYPE_ALL: int = 3
const BLEND_MODE_ADD: int = 0
const BLEND_MODE_SUBTRACT: int = 1
const BLEND_MODE_REPLACE_EXACT: int = 2
const TILE_AREA_M2: float = 1.0
const WORK_REQUEST_SCRIPT = preload("res://Scripts/farm/work/WorkRequest.gd")
const WORK_REPORT_SCRIPT = preload("res://Scripts/farm/work/WorkReport.gd")
const WORK_OPERATION_TYPE_SCRIPT = preload("res://Scripts/farm/work/WorkOperationType.gd")

func _ready() -> void:
	add_to_group("soil_layer_service")
	
	if not GameManager.session.farm.is_connected("tile_updated", Callable(self, "_on_tile_updated")):
		GameManager.session.farm.connect("tile_updated", Callable(self, "_on_tile_updated"))
		
	# Defer initialization until the end of the frame so MapDefinition._ready() has finished finding and grouping the terrain!
	call_deferred("_initialize_terrain")

func _process(_delta: float) -> void:
	_flush_pending_map_updates(false)

func _initialize_terrain() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain_node")
	if _terrain == null:
		_set_runtime_paint_available(false, "Terrain node not found")
		return

	# Handle API differences between Terrain3D v0.8 and v0.9+
	if _terrain.has_method("get_data"):
		_terrain_api = _terrain.get_data()
	elif _terrain.has_method("get_storage"):
		_terrain_api = _terrain.get_storage()
	elif "data" in _terrain:
		_terrain_api = _terrain.get("data")

	if _terrain_api == null:
		_set_runtime_paint_available(false, "Terrain data/storage not found")
		return

	if not _terrain_api.has_method("set_control"):
		_set_runtime_paint_available(false, "Terrain API lacks set_control/get_control")
		return

	_set_runtime_paint_available(true, "Runtime Terrain painting ready via set_control API")

func _set_runtime_paint_available(is_available: bool, reason: String) -> void:
	_runtime_paint_ready = is_available
	_runtime_paint_reason = reason
	runtime_paint_availability_changed.emit(is_available, reason)
	GameLog.info("[SoilLayerService] " + reason)

func is_runtime_paint_available() -> bool:
	return _runtime_paint_ready

func get_runtime_paint_reason() -> String:
	return _runtime_paint_reason

func refresh_terrain_api() -> void:
	_initialize_terrain()

# Called by PlowAttachment.gd
func plow_world(world_pos: Vector3) -> bool:
	var request := WORK_REQUEST_SCRIPT.point(
		WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE,
		world_pos,
		0.49,
		{
			"soil_state_output": FarmData.SoilState.PLOWED,
			"depth_offset": -0.05,
			"blend_mode": BLEND_MODE_ADD
		},
		&"legacy.plow_world",
		1
	)
	request.engagement_height = world_pos.y
	request.engagement_margin = default_engagement_margin_meters
	var reports: Array = process_work_batch([request])
	if reports.is_empty():
		return false
	var report: WorkReport = reports[0]
	return report.successful_area > 0.0

# Called by SeedTool.gd
func seed_world(world_pos: Vector3) -> bool:
	var request := WORK_REQUEST_SCRIPT.point(
		WORK_OPERATION_TYPE_SCRIPT.Value.SOWING,
		world_pos,
		0.49,
		{
			"seed_item_id": &"generic",
			"growth_minutes_required": GameManager.session.farm.DEFAULT_CROP_GROWTH_MINUTES
		},
		&"legacy.seed_world",
		1
	)
	request.engagement_height = world_pos.y
	request.engagement_margin = default_engagement_margin_meters
	var reports: Array = process_work_batch([request])
	if reports.is_empty():
		return false
	var report: WorkReport = reports[0]
	return report.successful_area > 0.0

func harvest_world(world_pos: Vector3, payload: Dictionary = {}) -> WorkReport:
	var request := WORK_REQUEST_SCRIPT.point(
		WORK_OPERATION_TYPE_SCRIPT.Value.HARVESTING,
		world_pos,
		0.49,
		payload,
		&"legacy.harvest_world",
		1
	)
	request.engagement_height = world_pos.y
	request.engagement_margin = default_engagement_margin_meters
	var reports: Array = process_work_batch([request])
	if reports.is_empty():
		return WORK_REPORT_SCRIPT.new().set_operation(WORK_OPERATION_TYPE_SCRIPT.Value.HARVESTING)
	return reports[0]

func _on_tile_updated(grid_pos: Vector2i, new_state: int) -> void:
	if not _runtime_paint_ready or _suppress_tile_signal_paint:
		return

	var world_pos := Vector3(float(grid_pos.x), 0, float(grid_pos.y))
	_paint_control_data(world_pos, plow_brush_radius, _soil_state_to_overlay_id(new_state))

func apply_ground_effectors(batch: Array[Dictionary], force_collision_rebuild_now: bool = false) -> bool:
	if batch.is_empty():
		return false

	var requests: Array = []
	for instruction_any: Variant in batch:
		if instruction_any is not Dictionary:
			continue
		var instruction: Dictionary = instruction_any
		var current_pos: Vector3 = instruction.get("current_pos", Vector3.ZERO)
		var previous_pos: Vector3 = instruction.get("previous_pos", current_pos)
		var radius: float = maxf(float(instruction.get("radius", plow_brush_radius)), 0.01)
		var req := WORK_REQUEST_SCRIPT.line_sweep(
			int(instruction.get("operation", WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE)),
			previous_pos,
			current_pos,
			radius,
			{
				"depth_offset": float(instruction.get("depth_offset", 0.0)),
				"blend_mode": int(instruction.get("blend_mode", BLEND_MODE_ADD)),
				"soil_state_output": int(instruction.get("soil_state_output", FarmData.SoilState.PLOWED)),
				"seed_item_id": instruction.get("seed_item_id", &"generic"),
				"growth_minutes_required": int(instruction.get("growth_minutes_required", GameManager.session.farm.DEFAULT_CROP_GROWTH_MINUTES)),
				"base_tile_yield": float(instruction.get("base_tile_yield", 1.0))
			},
			StringName(String(instruction.get("effector_path", "legacy.effector"))),
			int(instruction.get("max_budget", -1))
		)
		req.engagement_height = current_pos.y
		req.engagement_margin = float(instruction.get("engagement_margin", default_engagement_margin_meters))
		requests.append(req)

	var reports: Array = process_work_batch(requests, force_collision_rebuild_now)
	for report_any: Variant in reports:
		if report_any != null and float(report_any.successful_area) > 0.0:
			return true
	return false

func process_work_batch(requests: Array, force_collision_rebuild_now: bool = false, collect_debug_tiles: bool = false) -> Array:
	var reports: Array = []
	_last_work_reports.clear()
	_last_work_report_summaries.clear()

	if requests.is_empty() or _terrain_api == null or GameManager.session == null or GameManager.session.farm == null:
		return reports

	var baseline_cache: Dictionary = {}
	var logical_state_updates: Dictionary = {}
	var any_height_changed := false
	var any_control_changed := false
	var longest_segment: float = 0.0

	_batch_painting = true
	_suppress_tile_signal_paint = true

	for request_any: Variant in requests:
		if request_any is not WorkRequest:
			continue
		var request: WorkRequest = request_any
		var report := WORK_REPORT_SCRIPT.new().set_operation(request.operation)

		var candidate_tiles: Array[Vector2i] = _rasterize_work_request_to_sorted_tiles(request)
		report.requested_area = float(candidate_tiles.size()) * TILE_AREA_M2
		var accepted_count: int = 0
		var max_budget: int = request.max_budget

		for grid_pos: Vector2i in candidate_tiles:
			var world_center: Vector3 = _grid_center_to_world(grid_pos)
			if not GameManager.session.farm.can_plow_at(world_center):
				report.rejected_unfarmable += 1
				if collect_debug_tiles:
					report.rejected_tiles.append(grid_pos)
				continue

			var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
			if not _can_apply_operation_to_tile(request.operation, tile_data):
				report.rejected_wrong_state += 1
				if collect_debug_tiles:
					report.rejected_tiles.append(grid_pos)
				continue

			var sample_height: float = _sample_ground_height(world_center)
			if not _passes_height_gate(request, sample_height):
				report.rejected_height += 1
				if collect_debug_tiles:
					report.rejected_tiles.append(grid_pos)
				continue

			if max_budget > 0 and accepted_count >= max_budget:
				report.rejected_budget += 1
				if collect_debug_tiles:
					report.rejected_tiles.append(grid_pos)
				continue

			var execute_result: Dictionary = _execute_request_for_tile(request, grid_pos, sample_height, baseline_cache, logical_state_updates)
			if not bool(execute_result.get("applied", false)):
				report.rejected_wrong_state += 1
				if collect_debug_tiles:
					report.rejected_tiles.append(grid_pos)
				continue

			accepted_count += 1
			if collect_debug_tiles:
				report.accepted_tiles.append(grid_pos)

			any_height_changed = any_height_changed or bool(execute_result.get("height_changed", false))
			any_control_changed = any_control_changed or bool(execute_result.get("control_changed", false))
			longest_segment = maxf(longest_segment, float(execute_result.get("segment_distance", 0.0)))

			var yield_generated: Dictionary = execute_result.get("yield_generated", {})
			for yield_key_any: Variant in yield_generated.keys():
				var yield_key: StringName = StringName(String(yield_key_any))
				report.add_yield(yield_key, float(yield_generated[yield_key_any]))

		report.successful_area = float(accepted_count) * TILE_AREA_M2
		report.rejected_area = float(report.rejected_unfarmable + report.rejected_wrong_state + report.rejected_height + report.rejected_budget) * TILE_AREA_M2
		report.finalize(TILE_AREA_M2)
		reports.append(report)
		_last_work_reports.append(report)
		_last_work_report_summaries.append(report.to_log_summary())

	for grid_pos_any: Variant in logical_state_updates.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		var state_payload: Dictionary = logical_state_updates[grid_pos]
		var state_id: int = int(state_payload.get("state", FarmData.SoilState.PLOWED))
		var sample_height: float = float(state_payload.get("height", NAN))
		GameManager.session.farm.set_tile_state(grid_pos, state_id, sample_height, true)

	_suppress_tile_signal_paint = false
	_batch_painting = false

	if any_height_changed or any_control_changed:
		_update_edited_maps(any_height_changed, any_control_changed, false)

	if longest_segment > 0.0:
		_collision_distance_accumulator += longest_segment

	if force_collision_rebuild_now:
		force_collision_rebuild()
	elif _collision_distance_accumulator >= maxf(collision_rebuild_distance_meters, 0.25):
		_update_terrain_collision(false)
		_collision_distance_accumulator = 0.0

	return reports

func get_last_work_reports() -> Array:
	return _last_work_reports.duplicate()

func get_last_work_report_summaries() -> Array[String]:
	return _last_work_report_summaries.duplicate()

func _rasterize_work_request_to_sorted_tiles(request: WorkRequest) -> Array[Vector2i]:
	var tile_set: Dictionary = {}
	match request.geometry_type:
		WorkRequest.GeometryType.POINT_RADIUS:
			_collect_tiles_in_point_radius(request.point_center, request.radius_meters, tile_set)
		WorkRequest.GeometryType.LINE_SWEEP:
			_collect_tiles_in_line_capsule(request.line_start, request.line_end, request.radius_meters, tile_set)
		WorkRequest.GeometryType.QUAD_SWEEP:
			_collect_tiles_in_quad(request.quad_points_xz, tile_set)
		_:
			_collect_tiles_in_point_radius(request.point_center, request.radius_meters, tile_set)

	var out: Array[Vector2i] = []
	for grid_pos_any: Variant in tile_set.keys():
		if grid_pos_any is Vector2i:
			out.append(grid_pos_any)
	out.sort_custom(Callable(self, "_sort_grid_positions"))
	return out

func _collect_tiles_in_point_radius(center_pos: Vector3, radius_meters: float, out_set: Dictionary) -> void:
	var radius: float = maxf(radius_meters, 0.01)
	var center_xz := Vector2(center_pos.x, center_pos.z)
	var min_x: int = int(floor(center_xz.x - radius))
	var max_x: int = int(ceil(center_xz.x + radius))
	var min_z: int = int(floor(center_xz.y - radius))
	var max_z: int = int(ceil(center_xz.y + radius))
	var radius_sq: float = radius * radius

	for x: int in range(min_x, max_x + 1):
		for z: int in range(min_z, max_z + 1):
			var tile_center := Vector2(float(x) + 0.5, float(z) + 0.5)
			if tile_center.distance_squared_to(center_xz) <= radius_sq:
				out_set[Vector2i(x, z)] = true

func _collect_tiles_in_line_capsule(start_pos: Vector3, end_pos: Vector3, radius_meters: float, out_set: Dictionary) -> void:
	var radius: float = maxf(radius_meters, 0.01)
	var a := Vector2(start_pos.x, start_pos.z)
	var b := Vector2(end_pos.x, end_pos.z)
	var min_x: int = int(floor(minf(a.x, b.x) - radius))
	var max_x: int = int(ceil(maxf(a.x, b.x) + radius))
	var min_z: int = int(floor(minf(a.y, b.y) - radius))
	var max_z: int = int(ceil(maxf(a.y, b.y) + radius))
	var radius_sq: float = radius * radius

	for x: int in range(min_x, max_x + 1):
		for z: int in range(min_z, max_z + 1):
			var tile_center := Vector2(float(x) + 0.5, float(z) + 0.5)
			if _distance_sq_to_segment_2d(tile_center, a, b) <= radius_sq:
				out_set[Vector2i(x, z)] = true

func _collect_tiles_in_quad(quad_points_xz: Array[Vector2], out_set: Dictionary) -> void:
	if quad_points_xz.size() < 3:
		return

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for point: Vector2 in quad_points_xz:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.y)
		max_z = maxf(max_z, point.y)

	for x: int in range(int(floor(min_x)), int(ceil(max_x)) + 1):
		for z: int in range(int(floor(min_z)), int(ceil(max_z)) + 1):
			var tile_center := Vector2(float(x) + 0.5, float(z) + 0.5)
			if Geometry2D.is_point_in_polygon(tile_center, quad_points_xz):
				out_set[Vector2i(x, z)] = true

func _distance_sq_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq <= 0.000001:
		return p.distance_squared_to(a)
	var t: float = clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return p.distance_squared_to(closest)

func _sort_grid_positions(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x

func _grid_center_to_world(grid_pos: Vector2i) -> Vector3:
	var center_xz: Vector2 = GameManager.session.farm.grid_to_world_center(grid_pos)
	return Vector3(center_xz.x, 0.0, center_xz.y)

func _can_apply_operation_to_tile(operation: int, tile_data: FarmTileData) -> bool:
	match operation:
		WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE:
			return tile_data.state == FarmData.SoilState.GRASS
		WORK_OPERATION_TYPE_SCRIPT.Value.SOWING:
			return tile_data.state == FarmData.SoilState.PLOWED
		WORK_OPERATION_TYPE_SCRIPT.Value.HARVESTING:
			return tile_data.state == FarmData.SoilState.HARVESTABLE and tile_data.has_active_crop()
		_:
			return false

func _passes_height_gate(request: WorkRequest, sample_height: float) -> bool:
	if is_nan(sample_height):
		return false
	if is_nan(request.engagement_height):
		return true
	return request.engagement_height <= sample_height + maxf(request.engagement_margin, 0.0)

func _execute_request_for_tile(request: WorkRequest, grid_pos: Vector2i, sample_height: float, baseline_cache: Dictionary, logical_state_updates: Dictionary) -> Dictionary:
	var world_center: Vector3 = _grid_center_to_world(grid_pos)
	world_center.y = sample_height
	var segment_distance: float = _estimate_request_segment_distance(request)

	match request.operation:
		WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE:
			var tillage_result: Dictionary = _apply_tillage_to_tile(request, grid_pos, world_center, sample_height, baseline_cache, logical_state_updates)
			tillage_result["applied"] = true
			tillage_result["segment_distance"] = segment_distance
			return tillage_result
		WORK_OPERATION_TYPE_SCRIPT.Value.SOWING:
			var seed_item: StringName = StringName(String(request.payload.get("seed_item_id", "generic")))
			var growth_minutes: int = int(request.payload.get("growth_minutes_required", GameManager.session.farm.DEFAULT_CROP_GROWTH_MINUTES))
			if GameManager.session.farm.plant_crop(grid_pos, seed_item, growth_minutes, sample_height):
				var sow_overlay: int = _soil_state_to_overlay_id(FarmData.SoilState.SEEDED)
				var sow_control_changed: bool = _modify_single_pixel(world_center, sow_overlay, 0.0)
				return {
					"applied": true,
					"height_changed": false,
					"control_changed": sow_control_changed,
					"segment_distance": segment_distance,
					"yield_generated": {}
				}
			return {
				"applied": false,
				"height_changed": false,
				"control_changed": false,
				"segment_distance": 0.0,
				"yield_generated": {}
			}
		WORK_OPERATION_TYPE_SCRIPT.Value.HARVESTING:
			var tile_before: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos).duplicate_data()
			var harvest_payload: Dictionary = GameManager.session.farm.harvest_crop(grid_pos)
			if harvest_payload.is_empty():
				return {
					"applied": false,
					"height_changed": false,
					"control_changed": false,
					"segment_distance": 0.0,
					"yield_generated": {}
				}

			var base_tile_yield: float = float(request.payload.get("base_tile_yield", float(harvest_payload.get("yield", 1.0))))
			var maturity_ratio: float = _compute_harvest_maturity_ratio(tile_before)
			var final_yield: float = maxf(base_tile_yield * maturity_ratio, 0.0)

			var crop_type: String = String(harvest_payload.get("crop_type", tile_before.crop_type))
			if crop_type.is_empty():
				crop_type = "generic"
			var harvest_item_id: StringName = StringName(String(request.payload.get("harvest_item_id", "item.%s" % crop_type)))

			var harvest_overlay: int = _soil_state_to_overlay_id(FarmData.SoilState.PLOWED)
			var harvest_control_changed: bool = _modify_single_pixel(world_center, harvest_overlay, 0.0)
			return {
				"applied": true,
				"height_changed": false,
				"control_changed": harvest_control_changed,
				"segment_distance": segment_distance,
				"yield_generated": {str(harvest_item_id): final_yield}
			}
		_:
			return {
				"applied": false,
				"height_changed": false,
				"control_changed": false,
				"segment_distance": 0.0,
				"yield_generated": {}
			}

func _apply_tillage_to_tile(request: WorkRequest, grid_pos: Vector2i, world_center: Vector3, sample_height: float, baseline_cache: Dictionary, logical_state_updates: Dictionary) -> Dictionary:
	var depth_offset: float = float(request.payload.get("depth_offset", -0.05))
	var blend_mode: int = int(request.payload.get("blend_mode", BLEND_MODE_ADD))
	var soil_state_output: int = clampi(int(request.payload.get("soil_state_output", FarmData.SoilState.PLOWED)), FarmData.SoilState.GRASS, FarmData.SoilState.HARVESTABLE)

	var baseline_height: float = sample_height
	if baseline_cache.has(grid_pos):
		baseline_height = float(baseline_cache[grid_pos])
	else:
		baseline_cache[grid_pos] = sample_height

	var target_height: float = _resolve_target_height(blend_mode, baseline_height, depth_offset)
	var height_changed: bool = false
	if not is_equal_approx(target_height, sample_height):
		height_changed = _set_height(world_center, target_height)

	logical_state_updates[grid_pos] = {
		"state": soil_state_output,
		"height": target_height if not is_nan(target_height) else sample_height
	}

	var target_overlay_id: int = _soil_state_to_overlay_id(soil_state_output)
	var control_changed: bool = _modify_single_pixel(world_center, target_overlay_id, 0.0)
	return {
		"height_changed": height_changed,
		"control_changed": control_changed,
		"yield_generated": {}
	}

func _estimate_request_segment_distance(request: WorkRequest) -> float:
	match request.geometry_type:
		WorkRequest.GeometryType.LINE_SWEEP:
			return request.line_start.distance_to(request.line_end)
		WorkRequest.GeometryType.QUAD_SWEEP:
			if request.payload.has("segment_distance"):
				return float(request.payload.get("segment_distance", 0.0))
			if request.quad_points_xz.size() >= 4:
				var prev_center: Vector2 = (request.quad_points_xz[0] + request.quad_points_xz[1]) * 0.5
				var curr_center: Vector2 = (request.quad_points_xz[2] + request.quad_points_xz[3]) * 0.5
				return prev_center.distance_to(curr_center)
			return 0.0
		_:
			return 0.0

func _compute_harvest_maturity_ratio(tile_data: FarmTileData) -> float:
	if tile_data == null or not tile_data.has_active_crop():
		return 0.0
	var growth_required: int = maxi(tile_data.growth_minutes_required, 1)
	var now_minutes: int = GameManager.session.farm.get_current_total_minutes()
	var elapsed: int = maxi(0, now_minutes - tile_data.planted_at_minute)
	return clampf(float(elapsed) / float(growth_required), 0.0, 1.0)

func force_collision_rebuild() -> void:
	_update_terrain_collision(true)
	_collision_distance_accumulator = 0.0

func _apply_ground_effector_instruction(instruction: Dictionary, baseline_cache: Dictionary, logical_state_updates: Dictionary) -> Dictionary:
	var current_pos: Vector3 = instruction.get("current_pos", Vector3.ZERO)
	var previous_pos: Vector3 = instruction.get("previous_pos", current_pos)
	var radius: float = maxf(float(instruction.get("radius", plow_brush_radius)), 0.01)
	var depth_offset: float = float(instruction.get("depth_offset", 0.0))
	var blend_mode: int = int(instruction.get("blend_mode", BLEND_MODE_ADD))
	var soil_state_output: int = int(instruction.get("soil_state_output", FarmData.SoilState.PLOWED))
	var engagement_margin: float = float(instruction.get("engagement_margin", default_engagement_margin_meters))

	var current_ground_height: float = _sample_ground_height(current_pos)
	if is_nan(current_ground_height):
		return {
			"height_changed": false,
			"control_changed": false,
			"segment_distance": 0.0
		}

	# Effector Y only determines engagement state, never carve depth baseline.
	if current_pos.y > current_ground_height + engagement_margin:
		return {
			"height_changed": false,
			"control_changed": false,
			"segment_distance": 0.0
		}

	var segment_distance: float = previous_pos.distance_to(current_pos)
	var step_length: float = maxf(ground_effect_segment_length_meters, 0.05)
	var segment_count: int = maxi(1, int(ceil(segment_distance / step_length)))

	var height_changed := false
	var control_changed := false

	for i: int in range(segment_count + 1):
		var t: float = float(i) / float(segment_count)
		var sample_center: Vector3 = previous_pos.lerp(current_pos, t)
		var stamp_result: Dictionary = _apply_ground_stamp(sample_center, radius, depth_offset, blend_mode, soil_state_output, baseline_cache, logical_state_updates)
		if bool(stamp_result.get("height_changed", false)):
			height_changed = true
		if bool(stamp_result.get("control_changed", false)):
			control_changed = true

	return {
		"height_changed": height_changed,
		"control_changed": control_changed,
		"segment_distance": segment_distance
	}

func _apply_ground_stamp(center_pos: Vector3, radius_meters: float, depth_offset: float, blend_mode: int, soil_state_output: int, baseline_cache: Dictionary, logical_state_updates: Dictionary) -> Dictionary:
	var vertex_spacing: float = _get_vertex_spacing()
	var steps := int(ceil(radius_meters / vertex_spacing))
	var radius_sq := radius_meters * radius_meters

	var target_overlay_id: int = _soil_state_to_overlay_id(soil_state_output)
	var height_changed := false
	var control_changed := false

	for z: int in range(-steps, steps + 1):
		for x: int in range(-steps, steps + 1):
			var offset := Vector3(x * vertex_spacing, 0, z * vertex_spacing)
			if offset.length_squared() > radius_sq:
				continue

			var sample_pos: Vector3 = center_pos + offset
			var distance_ratio: float = 0.0
			if radius_meters > 0.0:
				distance_ratio = clampf(offset.length() / radius_meters, 0.0, 1.0)

			var baseline_height: float = _get_cached_baseline_height(sample_pos, baseline_cache)
			if is_nan(baseline_height):
				continue

			var current_height: float = _sample_ground_height(sample_pos)
			if is_nan(current_height):
				continue

			var target_height: float = _resolve_target_height(blend_mode, baseline_height, depth_offset)
			var brush_weight: float = 1.0 - distance_ratio
			var new_height: float = lerpf(current_height, target_height, brush_weight)

			if not is_equal_approx(new_height, current_height):
				if _set_height(sample_pos, new_height):
					height_changed = true

			_queue_logical_state_update(sample_pos, soil_state_output, logical_state_updates)
			if _modify_single_pixel(sample_pos, target_overlay_id, distance_ratio):
				control_changed = true

	return {
		"height_changed": height_changed,
		"control_changed": control_changed
	}

func _queue_logical_state_update(world_pos: Vector3, soil_state_output: int, logical_state_updates: Dictionary) -> void:
	if GameManager.session == null or GameManager.session.farm == null:
		return

	var grid_pos: Vector2i = GameManager.session.farm.world_to_grid(world_pos)
	logical_state_updates[grid_pos] = {
		"state": clampi(soil_state_output, FarmData.SoilState.GRASS, FarmData.SoilState.HARVESTABLE),
		"height": _sample_ground_height(world_pos)
	}

func _resolve_target_height(blend_mode: int, baseline_height: float, depth_offset: float) -> float:
	match blend_mode:
		BLEND_MODE_SUBTRACT:
			return baseline_height - absf(depth_offset)
		BLEND_MODE_REPLACE_EXACT:
			return depth_offset
		_:
			return baseline_height + depth_offset

func _soil_state_to_overlay_id(soil_state: int) -> int:
	if soil_state == FarmData.SoilState.GRASS:
		return grass_texture_index
	return dirt_texture_index

func _get_vertex_spacing() -> float:
	if _terrain != null and _terrain.get("vertex_spacing") != null:
		return maxf(float(_terrain.get("vertex_spacing")), 0.25)
	return 1.0

func _sample_ground_height(world_pos: Vector3) -> float:
	if _terrain_api != null and _terrain_api.has_method("get_height"):
		return float(_terrain_api.get_height(world_pos))
	return NAN

func _set_height(world_pos: Vector3, height_value: float) -> bool:
	if _terrain_api != null and _terrain_api.has_method("set_height"):
		_terrain_api.set_height(world_pos, height_value)
		_mark_region_edited(world_pos)
		return true
	return false

func _get_cached_baseline_height(world_pos: Vector3, baseline_cache: Dictionary) -> float:
	var key := Vector2i(int(floor(world_pos.x)), int(floor(world_pos.z)))
	if baseline_cache.has(key):
		return float(baseline_cache[key])

	var sampled: float = _sample_ground_height(world_pos)
	baseline_cache[key] = sampled
	return sampled

func _update_edited_maps(height_changed: bool, control_changed: bool, force_immediate: bool) -> void:
	if _terrain_api == null:
		return

	if height_changed:
		_pending_height_map_rebuild = true
	if control_changed:
		_pending_control_map_rebuild = true

	if force_immediate:
		_flush_pending_map_updates(true)
		return

	_flush_pending_map_updates(false)

func _flush_pending_map_updates(force: bool) -> void:
	if _terrain_api == null:
		return
	if not _pending_height_map_rebuild and not _pending_control_map_rebuild:
		return

	var interval_msec: int = int(maxf(map_rebuild_interval_seconds, 0.01) * 1000.0)
	var now: int = Time.get_ticks_msec()
	if not force and (now - _last_map_rebuild_msec) < interval_msec:
		return

	var map_type: int = MAP_TYPE_CONTROL
	if _pending_height_map_rebuild and _pending_control_map_rebuild:
		map_type = MAP_TYPE_ALL
	elif _pending_height_map_rebuild:
		map_type = MAP_TYPE_HEIGHT
	else:
		map_type = MAP_TYPE_CONTROL

	if _terrain_api.has_method("update_maps"):
		if map_type == MAP_TYPE_ALL:
			_terrain_api.call("update_maps", MAP_TYPE_ALL, false)
		elif map_type == MAP_TYPE_HEIGHT:
			_terrain_api.call("update_maps", MAP_TYPE_HEIGHT, false)
		else:
			_terrain_api.call("update_maps", MAP_TYPE_CONTROL, false)
	elif _terrain_api.has_method("force_update_maps"):
		if map_type == MAP_TYPE_ALL:
			_terrain_api.force_update_maps(MAP_TYPE_ALL)
		elif map_type == MAP_TYPE_HEIGHT:
			_terrain_api.force_update_maps(MAP_TYPE_HEIGHT)
		else:
			_terrain_api.force_update_maps(MAP_TYPE_CONTROL)

	_last_map_rebuild_msec = now
	_pending_height_map_rebuild = false
	_pending_control_map_rebuild = false
	_clear_edited_region_marks()

func _mark_region_edited(world_pos: Vector3) -> void:
	if _terrain_api == null:
		return
	if not _terrain_api.has_method("get_regionp"):
		return

	var region: Object = _terrain_api.get_regionp(world_pos)
	if region == null:
		return

	var key: Variant = null
	if _terrain_api.has_method("get_region_location"):
		key = _terrain_api.get_region_location(world_pos)
	else:
		key = region.get_instance_id()

	_edited_regions[key] = region
	if "edited" in region:
		region.set("edited", true)
	elif region.has_method("set_edited"):
		region.call("set_edited", true)

func _clear_edited_region_marks() -> void:
	for region_any: Variant in _edited_regions.values():
		if region_any == null:
			continue
		var region: Object = region_any
		if "edited" in region:
			region.set("edited", false)
		elif region.has_method("set_edited"):
			region.call("set_edited", false)
	_edited_regions.clear()

func _update_terrain_collision(rebuild: bool) -> void:
	if _terrain == null:
		return

	var collision_api: Object = null
	if _terrain.has_method("get_collision"):
		collision_api = _terrain.get_collision()
	elif "collision" in _terrain:
		collision_api = _terrain.get("collision")

	if collision_api == null:
		return

	if collision_api.has_method("update"):
		collision_api.update(rebuild)
	elif rebuild and collision_api.has_method("build"):
		collision_api.build()

func _paint_control_data(world_center: Vector3, radius_meters: float, target_overlay_id: int) -> void:
	if _terrain_api == null:
		return

	# Accommodate 2x resolution if you change Terrain3D vertex spacing later!
	var vertex_spacing: float = _get_vertex_spacing()

	var steps := int(ceil(radius_meters / vertex_spacing))
	var radius_sq := radius_meters * radius_meters

	var dirty := false
	for z in range(-steps, steps + 1):
		for x in range(-steps, steps + 1):
			var offset := Vector3(x * vertex_spacing, 0, z * vertex_spacing)
			if offset.length_squared() > radius_sq:
				continue

			var sample_pos := world_center + offset
			var distance_ratio := offset.length() / radius_meters
			if _modify_single_pixel(sample_pos, target_overlay_id, distance_ratio):
				dirty = true
				
	if dirty and not _batch_painting:
		_update_edited_maps(false, true, false)


func _modify_single_pixel(world_pos: Vector3, target_overlay_id: int, _distance_ratio: float) -> bool:
	# Terrain3D helpers take the global world_pos (Vector3), not the integer control value!
	var overlay_id: int = _terrain_api.get_control_overlay_id(world_pos)
	var blend: int = _terrain_api.get_control_blend(world_pos)

	var changed := false

	if target_overlay_id != grass_texture_index:
		if overlay_id != target_overlay_id:
			overlay_id = target_overlay_id
			changed = true
		if blend != 255:
			blend = 255
			changed = true
	else:
		if overlay_id != target_overlay_id:
			overlay_id = target_overlay_id
			changed = true
		if blend != 0:
			blend = 0
			changed = true

	if changed:
		_terrain_api.set_control_overlay_id(world_pos, overlay_id)
		_terrain_api.set_control_blend(world_pos, blend)
		return true

	return false

func rebuild_visuals_from_data() -> void:
	if not _runtime_paint_ready:
		return

	GameLog.info("[SoilLayerService] Rebuilding visuals from GameManager.session.farm...")
	
	_batch_painting = true

	for chunk_pos_any: Variant in GameManager.session.farm._tiles_by_chunk.keys():
		var chunk_pos: Vector2i = chunk_pos_any
		var tiles: Array[Vector2i] = GameManager.session.farm.get_chunk_tiles(chunk_pos)
		for grid_pos: Vector2i in tiles:
			var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
			_on_tile_updated(grid_pos, tile_data.state)

	_batch_painting = false
	
	# Manually update maps once after all batch updates
	_update_edited_maps(false, true, true)

	GameLog.info("[SoilLayerService] Rebuilt terrain visuals from save data.")
