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

const MAP_TYPE_HEIGHT: int = 0
const MAP_TYPE_CONTROL: int = 1
const MAP_TYPE_ALL: int = 3
const BLEND_MODE_ADD: int = 0
const BLEND_MODE_SUBTRACT: int = 1
const BLEND_MODE_REPLACE_EXACT: int = 2

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
	var grid_pos := GameManager.session.farm.world_to_grid(world_pos)
	var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)

	if tile_data.state == FarmData.SoilState.GRASS:
		# Modifies logical grid, emits "tile_updated", which triggers the visual paint below
		GameManager.session.farm.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, world_pos.y)
		return true
	return false

# Called by SeedTool.gd
func seed_world(world_pos: Vector3) -> bool:
	var grid_pos := GameManager.session.farm.world_to_grid(world_pos)
	var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)

	if tile_data.state == FarmData.SoilState.PLOWED:
		return GameManager.session.farm.plant_crop(grid_pos, &"generic", GameManager.session.farm.DEFAULT_CROP_GROWTH_MINUTES, world_pos.y)
	return false

func _on_tile_updated(grid_pos: Vector2i, new_state: int) -> void:
	if not _runtime_paint_ready or _suppress_tile_signal_paint:
		return

	var world_pos := Vector3(float(grid_pos.x), 0, float(grid_pos.y))
	_paint_control_data(world_pos, plow_brush_radius, _soil_state_to_overlay_id(new_state))

func apply_ground_effectors(batch: Array[Dictionary], force_collision_rebuild_now: bool = false) -> bool:
	if batch.is_empty():
		return false

	if _terrain_api == null:
		return false

	var baseline_cache: Dictionary = {}
	var logical_state_updates: Dictionary = {}
	var any_height_changed := false
	var any_control_changed := false
	var longest_segment: float = 0.0

	_batch_painting = true
	_suppress_tile_signal_paint = true

	for instruction_any: Variant in batch:
		if instruction_any is not Dictionary:
			continue
		var instruction: Dictionary = instruction_any
		var apply_result: Dictionary = _apply_ground_effector_instruction(instruction, baseline_cache, logical_state_updates)
		if bool(apply_result.get("height_changed", false)):
			any_height_changed = true
		if bool(apply_result.get("control_changed", false)):
			any_control_changed = true
		longest_segment = maxf(longest_segment, float(apply_result.get("segment_distance", 0.0)))

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

	return any_height_changed or any_control_changed

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
