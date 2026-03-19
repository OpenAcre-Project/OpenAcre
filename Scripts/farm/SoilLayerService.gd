extends Node3D

signal runtime_paint_availability_changed(is_available: bool, reason: String)

@export var dirt_texture_index: int = 3 # Matches your scene file
@export var grass_texture_index: int = 0
@export var plow_brush_radius: float = 1.0 # Radius in meters

var _terrain: Node = null
var _terrain_api: Object = null # Points to Terrain3DData / Terrain3DStorage
var _runtime_paint_ready := false
var _runtime_paint_reason := "Not initialized"

func _ready() -> void:
	add_to_group("soil_layer_service")
	
	if not FarmData.is_connected("tile_updated", Callable(self, "_on_tile_updated")):
		FarmData.connect("tile_updated", Callable(self, "_on_tile_updated"))
		
	# Defer initialization until the end of the frame so MapDefinition._ready() has finished finding and grouping the terrain!
	call_deferred("_initialize_terrain")

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

# Called by PlowAttachment.gd
func plow_world(world_pos: Vector3) -> bool:
	var grid_pos := FarmData.world_to_grid(world_pos)
	var tile_data = FarmData.get_tile_data(grid_pos)

	if tile_data.state == FarmData.SoilState.GRASS:
		# Modifies logical grid, emits "tile_updated", which triggers the visual paint below
		FarmData.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, world_pos.y)
		return true
	return false

# Called by SeedTool.gd
func seed_world(world_pos: Vector3) -> bool:
	var grid_pos := FarmData.world_to_grid(world_pos)
	var tile_data = FarmData.get_tile_data(grid_pos)

	if tile_data.state == FarmData.SoilState.PLOWED:
		return FarmData.plant_crop(grid_pos, &"generic", FarmData.DEFAULT_CROP_GROWTH_MINUTES, world_pos.y)
	return false

func _on_tile_updated(grid_pos: Vector2i, new_state: int) -> void:
	if not _runtime_paint_ready:
		return

	var world_pos := Vector3(float(grid_pos.x), 0, float(grid_pos.y))

	if new_state == FarmData.SoilState.PLOWED or new_state == FarmData.SoilState.SEEDED or new_state == FarmData.SoilState.HARVESTABLE:
		_paint_control_data(world_pos, plow_brush_radius, dirt_texture_index)
	elif new_state == FarmData.SoilState.GRASS:
		_paint_control_data(world_pos, plow_brush_radius, grass_texture_index)

func _paint_control_data(world_center: Vector3, radius_meters: float, target_overlay_id: int) -> void:
	if _terrain_api == null:
		return

	# Accommodate 2x resolution if you change Terrain3D vertex spacing later!
	var vertex_spacing: float = 1.0
	if _terrain.get("vertex_spacing") != null:
		vertex_spacing = _terrain.get("vertex_spacing")

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
				
	if dirty:
		# Map types: 0=height, 1=control, 2=color
		var map_type_control = 1
		
		if _terrain_api.has_method("update_maps"):
			_terrain_api.update_maps(map_type_control)
		elif _terrain_api.has_method("force_update_maps"):
			_terrain_api.force_update_maps(map_type_control)


func _modify_single_pixel(world_pos: Vector3, target_overlay_id: int, distance_ratio: float) -> bool:
	# Terrain3D helpers take the global world_pos (Vector3), not the integer control value!
	var overlay_id = _terrain_api.get_control_overlay_id(world_pos)
	var blend = _terrain_api.get_control_blend(world_pos)

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

	GameLog.info("[SoilLayerService] Rebuilding visuals from FarmData...")
	for chunk_pos_any: Variant in FarmData._tiles_by_chunk.keys():
		var chunk_pos: Vector2i = chunk_pos_any
		var tiles: Array[Vector2i] = FarmData.get_chunk_tiles(chunk_pos)
		for grid_pos: Vector2i in tiles:
			var tile_data: FarmTileData = FarmData.get_tile_data(grid_pos)
			_on_tile_updated(grid_pos, tile_data.state)

	GameLog.info("[SoilLayerService] Rebuilt terrain visuals from save data.")
