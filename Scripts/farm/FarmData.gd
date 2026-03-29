class_name FarmData
extends RefCounted

# The valid soil states
enum SoilState {
	GRASS = 0,
	PLOWED = 1,
	SEEDED = 2,
	HARVESTABLE = 3
}

const DEFAULT_CROP_GROWTH_MINUTES := 3 * 24 * 60
var simulation_chunk_size_tiles: int = 32

# The abstract grid dictionary: Vector2i -> FarmTileData
var _grid: Dictionary = {}
var _tiles_by_chunk: Dictionary = {}
var _seeded_tiles_by_chunk: Dictionary = {}
var _chunk_unloaded_at_minute: Dictionary = {}
var _loaded_chunks: Dictionary = {}
var _last_processed_minute: int = -1

var active_region_mask: MapRegionMask = null

var map_fields: Array[FieldPolygon] = []

# Emitted when a specific tile changes state
signal tile_updated(grid_pos: Vector2i, new_state: int)
signal chunk_loaded(chunk_pos: Vector2i, catch_up_seconds: int)
signal chunk_unloaded(chunk_pos: Vector2i, unloaded_at_minute: int)

func _init() -> void:
	pass

func tick(_delta: float) -> void:
	pass

func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(round(world_pos.x), round(world_pos.z))

func grid_to_world_center(grid_pos: Vector2i) -> Vector2:
	# Currently 1 tile = 1 meter, so the center is +0.5
	return Vector2(float(grid_pos.x) + 0.5, float(grid_pos.y) + 0.5)

func grid_to_chunk(grid_pos: Vector2i) -> Vector2i:
	var chunk_size := maxi(simulation_chunk_size_tiles, 1)
	return Vector2i(
		int(floor(float(grid_pos.x) / float(chunk_size))),
		int(floor(float(grid_pos.y) / float(chunk_size)))
	)

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return grid_to_chunk(world_to_grid(world_pos))

# Retrieves data for a specific tile. If it doesn't exist, returns a default tile struct.
func get_tile_data(grid_pos: Vector2i) -> FarmTileData:
	if _grid.has(grid_pos):
		return _grid[grid_pos]

	return FarmTileData.new()

func has_tile(grid_pos: Vector2i) -> bool:
	return _grid.has(grid_pos)

func get_total_tile_count() -> int:
	return _grid.size()

func get_total_chunk_count() -> int:
	return _tiles_by_chunk.size()

func get_seeded_tile_count() -> int:
	var count: int = 0
	for chunk_pos_any: Variant in _seeded_tiles_by_chunk.keys():
		if chunk_pos_any is Vector2i:
			var chunk_tiles: Dictionary = _seeded_tiles_by_chunk[chunk_pos_any]
			count += chunk_tiles.size()
	return count

func get_loaded_chunk_count() -> int:
	return _loaded_chunks.size()

func get_unloaded_chunk_count() -> int:
	return _chunk_unloaded_at_minute.size()

func get_chunk_unloaded_minute(chunk_pos: Vector2i) -> int:
	if not _chunk_unloaded_at_minute.has(chunk_pos):
		return -1
	return int(_chunk_unloaded_at_minute[chunk_pos])

func get_chunk_tiles(chunk_pos: Vector2i) -> Array[Vector2i]:
	if not _tiles_by_chunk.has(chunk_pos):
		return []

	var tiles: Array[Vector2i] = []
	var chunk_tiles: Dictionary = _tiles_by_chunk[chunk_pos]
	for grid_pos_any: Variant in chunk_tiles.keys():
		if grid_pos_any is Vector2i:
			tiles.append(grid_pos_any)
	return tiles

func get_seeded_chunk_tiles(chunk_pos: Vector2i) -> Array[Vector2i]:
	if not _seeded_tiles_by_chunk.has(chunk_pos):
		return []

	var tiles: Array[Vector2i] = []
	var chunk_tiles: Dictionary = _seeded_tiles_by_chunk[chunk_pos]
	for grid_pos_any: Variant in chunk_tiles.keys():
		if grid_pos_any is Vector2i:
			tiles.append(grid_pos_any)
	return tiles

func is_chunk_loaded(chunk_pos: Vector2i) -> bool:
	return not _chunk_unloaded_at_minute.has(chunk_pos)

func get_current_total_minutes() -> int:
	if GameManager.session != null and GameManager.session.time != null:
		return GameManager.session.time.get_total_minutes()
	return 0

func get_tile_growth_progress(grid_pos: Vector2i, at_total_minutes: int = -1) -> float:
	if not _grid.has(grid_pos):
		return 0.0

	var data: FarmTileData = _grid[grid_pos]
	if not data.has_active_crop():
		return 0.0

	var sample_minutes: int = at_total_minutes
	if sample_minutes < 0:
		sample_minutes = get_current_total_minutes()

	var elapsed: int = maxi(0, sample_minutes - data.planted_at_minute)
	return clamp(float(elapsed) / float(data.growth_minutes_required), 0.0, 1.0)

# Sets the state of a tile and alerts listeners (like GridManager)
func set_tile_state(grid_pos: Vector2i, new_state: int, world_height: float = NAN, should_emit: bool = true) -> void:
	var had_existing := _grid.has(grid_pos)
	if had_existing:
		_remove_tile_from_indices(grid_pos)

	var data: FarmTileData = get_tile_data(grid_pos)
	data.state = new_state

	if new_state == SoilState.GRASS or new_state == SoilState.PLOWED:
		data.clear_crop_data()

	# Height should be captured when creating/refreshing soil patches, not during later state swaps.
	if not is_nan(world_height) and (new_state == SoilState.PLOWED or not had_existing):
		data.height = world_height

	if new_state == SoilState.GRASS:
		if had_existing:
			_grid.erase(grid_pos)
			if should_emit:
				self.emit_signal("tile_updated", grid_pos, SoilState.GRASS)
		return

	_grid[grid_pos] = data
	_register_tile_in_indices(grid_pos, data)
	if should_emit:
		self.emit_signal("tile_updated", grid_pos, new_state)

func set_active_region_mask(mask: MapRegionMask) -> void:
	active_region_mask = mask

func get_raw_region_value(world_pos: Vector3) -> int:
	if active_region_mask != null:
		return active_region_mask.get_raw_pixel_value(world_pos)
	return -1

func can_plow_at(world_pos: Vector3) -> bool:
	if active_region_mask != null:
		return active_region_mask.get_region_at(world_pos) == MapRegionMask.RegionType.FARMABLE
	return true # Default to true if no mask is provided for backwards compatibility/testing

func plant_crop(
	grid_pos: Vector2i,
	crop_type: StringName = &"generic",
	growth_minutes_required: int = DEFAULT_CROP_GROWTH_MINUTES,
	world_height: float = NAN
) -> bool:
	var tile_data := get_tile_data(grid_pos)
	if tile_data.state != SoilState.PLOWED:
		return false

	var had_existing := _grid.has(grid_pos)
	if had_existing:
		_remove_tile_from_indices(grid_pos)

	tile_data.state = SoilState.SEEDED
	tile_data.crop_type = crop_type
	tile_data.planted_at_minute = get_current_total_minutes()
	tile_data.growth_minutes_required = maxi(1, growth_minutes_required)
	if not is_nan(world_height):
		tile_data.height = world_height

	_grid[grid_pos] = tile_data
	_register_tile_in_indices(grid_pos, tile_data)
	emit_signal("tile_updated", grid_pos, SoilState.SEEDED)
	return true

func harvest_crop(grid_pos: Vector2i) -> Dictionary:
	if not _grid.has(grid_pos):
		return {}

	var tile_data: FarmTileData = _grid[grid_pos]
	if tile_data.state != SoilState.HARVESTABLE or not tile_data.has_active_crop():
		return {}

	var harvest := {
		"crop_type": tile_data.crop_type,
		"yield": 1
	}

	_remove_tile_from_indices(grid_pos)
	tile_data.state = SoilState.PLOWED
	tile_data.clear_crop_data()
	_grid[grid_pos] = tile_data
	_register_tile_in_indices(grid_pos, tile_data)
	emit_signal("tile_updated", grid_pos, SoilState.PLOWED)
	return harvest

func mark_chunk_unloaded(chunk_pos: Vector2i) -> void:
	if _chunk_unloaded_at_minute.has(chunk_pos):
		return

	var unloaded_at: int = get_current_total_minutes()
	_chunk_unloaded_at_minute[chunk_pos] = unloaded_at
	_loaded_chunks.erase(chunk_pos)
	emit_signal("chunk_unloaded", chunk_pos, unloaded_at)

func mark_chunk_loaded(chunk_pos: Vector2i, emit_tile_updates: bool = true) -> void:
	var now_minutes := get_current_total_minutes()
	var catch_up_seconds := 0
	if _chunk_unloaded_at_minute.has(chunk_pos):
		var unloaded_at: int = _chunk_unloaded_at_minute[chunk_pos]
		_chunk_unloaded_at_minute.erase(chunk_pos)
		if now_minutes > unloaded_at:
			_simulate_chunk_to_minute(chunk_pos, now_minutes, emit_tile_updates)
		catch_up_seconds = maxi(0, (now_minutes - unloaded_at) * 60)

	_loaded_chunks[chunk_pos] = true
	emit_signal("chunk_loaded", chunk_pos, catch_up_seconds)

func simulate_chunk_passage_of_time(chunk_pos: Vector2i, delta_seconds: int, emit_tile_updates: bool = false) -> void:
	if delta_seconds <= 0:
		return

	var delta_minutes := int(floor(float(delta_seconds) / 60.0))
	if delta_minutes <= 0:
		return

	var target_minute := get_current_total_minutes() + delta_minutes
	_simulate_chunk_to_minute(chunk_pos, target_minute, emit_tile_updates)

func simulate_passage_of_time(delta_seconds: int, emit_tile_updates: bool = false, target_chunks: Array = []) -> void:
	if delta_seconds <= 0:
		return

	var delta_minutes := int(floor(float(delta_seconds) / 60.0))
	if delta_minutes <= 0:
		return

	var target_minute := get_current_total_minutes() + delta_minutes
	var chunks_to_simulate: Array = target_chunks
	if chunks_to_simulate.is_empty():
		chunks_to_simulate = _seeded_tiles_by_chunk.keys()

	for chunk_any: Variant in chunks_to_simulate:
		if chunk_any is Vector2i:
			_simulate_chunk_to_minute(chunk_any, target_minute, emit_tile_updates)

# Completely clears a tile back to default grass
func reset_tile(grid_pos: Vector2i) -> void:
	if _grid.has(grid_pos):
		_remove_tile_from_indices(grid_pos)
		_grid.erase(grid_pos)
		emit_signal("tile_updated", grid_pos, SoilState.GRASS)

func _on_minute_passed() -> void:
	var now_minutes := get_current_total_minutes()
	if now_minutes == _last_processed_minute:
		return

	_last_processed_minute = now_minutes
	var chunks_to_simulate: Array[Vector2i] = _get_chunks_to_simulate_on_tick()
	for chunk_pos: Vector2i in chunks_to_simulate:
		_simulate_chunk_to_minute(chunk_pos, now_minutes, true)

func _get_chunks_to_simulate_on_tick() -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []

	# DESIGN NOTE: If no GridManager has registered any chunks as loaded/unloaded,
	# we fall back to simulating ALL seeded chunks. This ensures crop growth
	# continues even if chunk streaming is disabled or the GridManager is absent.
	# The chunk system is purely a 3D rendering optimisation — simulation must
	# never stall because of it.
	if _loaded_chunks.is_empty() and _chunk_unloaded_at_minute.is_empty():
		for chunk_pos_any: Variant in _seeded_tiles_by_chunk.keys():
			if chunk_pos_any is Vector2i:
				chunks.append(chunk_pos_any)
		return chunks

	for chunk_pos_any: Variant in _loaded_chunks.keys():
		if chunk_pos_any is Vector2i and _seeded_tiles_by_chunk.has(chunk_pos_any):
			chunks.append(chunk_pos_any)

	return chunks

func _simulate_chunk_to_minute(chunk_pos: Vector2i, target_minute: int, emit_tile_updates: bool) -> void:
	if not _seeded_tiles_by_chunk.has(chunk_pos):
		return

	var chunk_seeded_tiles: Dictionary = _seeded_tiles_by_chunk[chunk_pos]
	for grid_pos_any: Variant in chunk_seeded_tiles.keys():
		if grid_pos_any is Vector2i:
			_simulate_tile_to_minute(grid_pos_any, target_minute, emit_tile_updates)

func _simulate_tile_to_minute(grid_pos: Vector2i, target_minute: int, emit_tile_updates: bool) -> void:
	if not _grid.has(grid_pos):
		return

	var tile_data: FarmTileData = _grid[grid_pos]
	if not tile_data.has_active_crop():
		return

	if tile_data.state != SoilState.SEEDED and tile_data.state != SoilState.HARVESTABLE:
		return

	var elapsed_minutes := maxi(0, target_minute - tile_data.planted_at_minute)
	var desired_state := SoilState.SEEDED
	if elapsed_minutes >= tile_data.growth_minutes_required:
		desired_state = SoilState.HARVESTABLE

	if desired_state == tile_data.state:
		return

	_remove_tile_from_indices(grid_pos)
	tile_data.state = desired_state
	_grid[grid_pos] = tile_data
	_register_tile_in_indices(grid_pos, tile_data)

	if emit_tile_updates:
		emit_signal("tile_updated", grid_pos, tile_data.state)

func _register_tile_in_indices(grid_pos: Vector2i, tile_data: FarmTileData) -> void:
	var chunk_pos := grid_to_chunk(grid_pos)
	if not _tiles_by_chunk.has(chunk_pos):
		_tiles_by_chunk[chunk_pos] = {}
	var chunk_tiles: Dictionary = _tiles_by_chunk[chunk_pos]
	chunk_tiles[grid_pos] = true

	if tile_data.state == SoilState.SEEDED or tile_data.state == SoilState.HARVESTABLE:
		if not _seeded_tiles_by_chunk.has(chunk_pos):
			_seeded_tiles_by_chunk[chunk_pos] = {}
		var chunk_seeded_tiles: Dictionary = _seeded_tiles_by_chunk[chunk_pos]
		chunk_seeded_tiles[grid_pos] = true

func _remove_tile_from_indices(grid_pos: Vector2i) -> void:
	var chunk_pos := grid_to_chunk(grid_pos)

	if _tiles_by_chunk.has(chunk_pos):
		var chunk_tiles: Dictionary = _tiles_by_chunk[chunk_pos]
		chunk_tiles.erase(grid_pos)
		if chunk_tiles.is_empty():
			_tiles_by_chunk.erase(chunk_pos)

	if _seeded_tiles_by_chunk.has(chunk_pos):
		var chunk_seeded_tiles: Dictionary = _seeded_tiles_by_chunk[chunk_pos]
		chunk_seeded_tiles.erase(grid_pos)
		if chunk_seeded_tiles.is_empty():
			_seeded_tiles_by_chunk.erase(chunk_pos)

func load_map_fields_from_json(file_path: String, offset: Vector2 = Vector2.ZERO) -> void:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		GameLog.warn("No field data JSON found at: " + file_path)
		return
		
	var file_string := FileAccess.get_file_as_string(file_path)
	var json_data: Variant = JSON.parse_string(file_string)
	
	if json_data == null or not typeof(json_data) == TYPE_DICTIONARY:
		GameLog.error("Failed to parse field data JSON or invalid format: " + file_path)
		return
	
	map_fields.clear()
	var dict_data: Dictionary = json_data
	for field_key_any: Variant in dict_data.keys():
		var field_key: String = str(field_key_any)
		var field_obj: Variant = dict_data[field_key_any]
		if typeof(field_obj) == TYPE_ARRAY:
			var points_array: Array = field_obj
			if points_array.is_empty():
				continue
			var polygon := FieldPolygon.new()
			polygon.id = StringName(field_key)
			for p_dict_any: Variant in points_array:
				if typeof(p_dict_any) == TYPE_DICTIONARY:
					var p_dict: Dictionary = p_dict_any
					if p_dict.has("x") and p_dict.has("z"):
						polygon.points.append(Vector2(float(p_dict["x"]), float(p_dict["z"])) + offset)
			
			if not polygon.points.is_empty():
				polygon.calculate_bounds()
				map_fields.append(polygon)

func generate_initial_plowed_fields() -> void:
	for field in map_fields:
		var bounds: Rect2i = field.bounds
		for x in range(bounds.position.x, bounds.end.x):
			for y in range(bounds.position.y, bounds.end.y):
				var grid_pos := Vector2i(x, y)
				var center_point := grid_to_world_center(grid_pos)
				if Geometry2D.is_point_in_polygon(center_point, field.points):
					# Intentionally pass false to emit_signal so we batch updates and avoid a signal storm
					set_tile_state(grid_pos, SoilState.PLOWED, NAN, false)

func clear_runtime_state(keep_region_mask: bool = true) -> void:
	_grid.clear()
	_tiles_by_chunk.clear()
	_seeded_tiles_by_chunk.clear()
	_chunk_unloaded_at_minute.clear()
	_loaded_chunks.clear()
	_last_processed_minute = -1
	if not keep_region_mask:
		active_region_mask = null

func rebuild_active_growth_chunk_index() -> void:
	_tiles_by_chunk.clear()
	_seeded_tiles_by_chunk.clear()

	for grid_pos_any: Variant in _grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		var tile_data: FarmTileData = _grid[grid_pos]
		_register_tile_in_indices(grid_pos, tile_data)

func get_heatmap_resolution() -> Vector2i:
	if active_region_mask != null and active_region_mask.mask_texture != null:
		var width := maxi(1, active_region_mask.mask_texture.get_width())
		var height := maxi(1, active_region_mask.mask_texture.get_height())
		return Vector2i(width, height)
	return Vector2i(1024, 1024)

func _grid_to_heatmap_pixel(grid_pos: Vector2i, width: int, height: int) -> Vector2i:
	var safe_width := maxi(width, 1)
	var safe_height := maxi(height, 1)
	var world_size := 2048.0
	var world_center := Vector2.ZERO
	if active_region_mask != null:
		world_size = maxf(active_region_mask.world_size_meters, 1.0)
		world_center = active_region_mask.world_center_position

	var tile_center: Vector2 = grid_to_world_center(grid_pos)
	var half_size := world_size * 0.5
	var percent_x: float = (tile_center.x - world_center.x + half_size) / world_size
	var percent_y: float = (tile_center.y - world_center.y + half_size) / world_size

	var pixel_x: int = int(floor(percent_x * float(safe_width)))
	var pixel_y: int = int(floor(percent_y * float(safe_height)))

	if pixel_x < 0 or pixel_x >= safe_width or pixel_y < 0 or pixel_y >= safe_height:
		return Vector2i(-1, -1)

	return Vector2i(pixel_x, pixel_y)

func _heatmap_pixel_to_grid(pixel: Vector2i, width: int, height: int) -> Vector2i:
	var safe_width := maxi(width, 1)
	var safe_height := maxi(height, 1)
	var world_size := 2048.0
	var world_center := Vector2.ZERO
	if active_region_mask != null:
		world_size = maxf(active_region_mask.world_size_meters, 1.0)
		world_center = active_region_mask.world_center_position

	var half_size := world_size * 0.5
	var world_x: float = world_center.x - half_size + ((float(pixel.x) + 0.5) / float(safe_width)) * world_size
	var world_z: float = world_center.y - half_size + ((float(pixel.y) + 0.5) / float(safe_height)) * world_size

	return Vector2i(int(round(world_x - 0.5)), int(round(world_z - 0.5)))

func export_heatmap_layers(crop_to_id: Dictionary) -> Dictionary:
	var resolution: Vector2i = get_heatmap_resolution()
	var width := maxi(resolution.x, 1)
	var height := maxi(resolution.y, 1)

	var soil_image := Image.create(width, height, false, Image.FORMAT_L8)
	soil_image.fill(Color(0, 0, 0, 1))

	var crop_image := Image.create(width, height, false, Image.FORMAT_L8)
	crop_image.fill(Color(0, 0, 0, 1))

	var planted_time_image := Image.create(width, height, false, Image.FORMAT_RF)
	planted_time_image.fill(Color(-1.0, 0, 0, 1))

	for grid_pos_any: Variant in _grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		var tile_data: FarmTileData = _grid[grid_pos]
		var pixel: Vector2i = _grid_to_heatmap_pixel(grid_pos, width, height)
		if pixel.x < 0 or pixel.y < 0:
			continue

		soil_image.set_pixelv(pixel, Color(float(tile_data.state) / 255.0, 0, 0, 1))

		if tile_data.crop_type != &"" and crop_to_id.has(tile_data.crop_type):
			var crop_id: int = int(crop_to_id[tile_data.crop_type])
			crop_image.set_pixelv(pixel, Color(float(clampi(crop_id, 0, 255)) / 255.0, 0, 0, 1))
			planted_time_image.set_pixelv(pixel, Color(float(tile_data.planted_at_minute), 0, 0, 1))

	return {
		"soil_state": soil_image,
		"crop_type": crop_image,
		"planted_time": planted_time_image
	}

func import_heatmap_layers(soil_image: Image, crop_image: Image, planted_time_image: Image, id_to_crop: Dictionary) -> void:
	if soil_image == null or crop_image == null:
		return

	clear_runtime_state(true)

	var width := mini(soil_image.get_width(), crop_image.get_width())
	var height := mini(soil_image.get_height(), crop_image.get_height())
	if planted_time_image != null:
		width = mini(width, planted_time_image.get_width())
		height = mini(height, planted_time_image.get_height())

	if width <= 0 or height <= 0:
		return

	for y: int in range(height):
		for x: int in range(width):
			var soil_value: int = int(round(soil_image.get_pixel(x, y).r * 255.0))
			var crop_value: int = int(round(crop_image.get_pixel(x, y).r * 255.0))
			if soil_value == SoilState.GRASS and crop_value == 0:
				continue

			var grid_pos := _heatmap_pixel_to_grid(Vector2i(x, y), width, height)
			var tile := FarmTileData.new()
			tile.state = clampi(soil_value, SoilState.GRASS, SoilState.HARVESTABLE)

			if crop_value > 0 and id_to_crop.has(str(crop_value)):
				tile.crop_type = StringName(String(id_to_crop[str(crop_value)]))
				tile.growth_minutes_required = DEFAULT_CROP_GROWTH_MINUTES
				if planted_time_image != null:
					tile.planted_at_minute = int(round(planted_time_image.get_pixel(x, y).r))
				else:
					tile.planted_at_minute = get_current_total_minutes()

				if tile.planted_at_minute < 0:
					tile.planted_at_minute = get_current_total_minutes()

				if tile.state == SoilState.GRASS or tile.state == SoilState.PLOWED:
					tile.state = SoilState.SEEDED

				# Offline catch-up: hydrate to correct growth state immediately on load.
				var elapsed_minutes := maxi(0, get_current_total_minutes() - tile.planted_at_minute)
				if elapsed_minutes >= tile.growth_minutes_required:
					tile.state = SoilState.HARVESTABLE
				else:
					tile.state = SoilState.SEEDED
			else:
				tile.clear_crop_data()
				if tile.state == SoilState.SEEDED or tile.state == SoilState.HARVESTABLE:
					tile.state = SoilState.PLOWED

			_grid[grid_pos] = tile

	rebuild_active_growth_chunk_index()
