extends Node3D

const ChunkGridOverlayRef = preload("res://Scripts/debug/ChunkGridOverlay.gd")
const FarmableGridOverlayRef = preload("res://Scripts/debug/FarmableGridOverlay.gd")
const CropNodeSceneRef = preload("res://Scenes/Interactables/CropNode.tscn")

@export var enable_chunk_streaming := true
@export var streamed_chunk_radius := 2  # change this to change spawing radiu
@export var stream_update_interval_seconds := 0.5

var _stream_target: Node3D = null
var _stream_update_timer := 0.0
var _currently_loaded_chunks: Dictionary = {}
var _chunk_grid_overlay: Node3D = null
var _farmable_grid_overlay: Node3D = null
var _crop_nodes_by_grid: Dictionary = {}
var _crop_nodes_container: Node3D = null

func _ready() -> void:
	add_to_group("grid_manager")
	_create_chunk_grid_overlay()
	_create_farmable_grid_overlay()
	_create_crop_nodes_container()
	if not GameManager.session.farm.is_connected("tile_updated", Callable(self, "_on_farm_tile_updated")):
		GameManager.session.farm.connect("tile_updated", Callable(self, "_on_farm_tile_updated"))
	if enable_chunk_streaming:
		_bind_stream_target()
		_update_streamed_chunks(true)

func _exit_tree() -> void:
	if enable_chunk_streaming:
		for chunk_pos_any: Variant in _currently_loaded_chunks.keys():
			if chunk_pos_any is Vector2i:
				GameManager.session.farm.mark_chunk_unloaded(chunk_pos_any)
		_currently_loaded_chunks.clear()
	_clear_all_crop_nodes()
	if GameManager.session != null and GameManager.session.farm != null:
		if GameManager.session.farm.is_connected("tile_updated", Callable(self, "_on_farm_tile_updated")):
			GameManager.session.farm.disconnect("tile_updated", Callable(self, "_on_farm_tile_updated"))

func _process(delta: float) -> void:
	if not enable_chunk_streaming:
		return

	_stream_update_timer += delta
	if _stream_update_timer < stream_update_interval_seconds:
		return

	_stream_update_timer = 0.0
	_update_streamed_chunks()

func _bind_stream_target() -> void:
	var first_player := get_tree().get_first_node_in_group("player")
	if first_player is Node3D:
		_stream_target = first_player

func _update_streamed_chunks(force_refresh: bool = false) -> void:
	if _stream_target == null or not is_instance_valid(_stream_target):
		_bind_stream_target()
	if _stream_target == null:
		return

	var center_chunk := GameManager.session.farm.world_to_chunk(_stream_target.global_position)
	var desired_chunks: Dictionary = {}
	for y in range(-streamed_chunk_radius, streamed_chunk_radius + 1):
		for x in range(-streamed_chunk_radius, streamed_chunk_radius + 1):
			desired_chunks[center_chunk + Vector2i(x, y)] = true

	if not force_refresh and _chunk_sets_equal(desired_chunks, _currently_loaded_chunks):
		return

	for chunk_pos_any: Variant in desired_chunks.keys():
		if chunk_pos_any is Vector2i and not _currently_loaded_chunks.has(chunk_pos_any):
			GameManager.session.farm.mark_chunk_loaded(chunk_pos_any, true)
			_spawn_crop_nodes_for_chunk(chunk_pos_any)

	for chunk_pos_any: Variant in _currently_loaded_chunks.keys():
		if chunk_pos_any is Vector2i and not desired_chunks.has(chunk_pos_any):
			GameManager.session.farm.mark_chunk_unloaded(chunk_pos_any)
			_despawn_crop_nodes_for_chunk(chunk_pos_any)

	var loaded_before := _currently_loaded_chunks.size()
	_currently_loaded_chunks = desired_chunks
	var loaded_after := _currently_loaded_chunks.size()

	if loaded_before != loaded_after or force_refresh:
		var total_data := GameManager.session.farm.get_total_chunk_count()
		GameLog.infof("Chunks streamed: %d loaded (radius %d) | %d data chunks | center (%d,%d)",
			[loaded_after, streamed_chunk_radius, total_data, center_chunk.x, center_chunk.y])

	if _chunk_grid_overlay != null and _chunk_grid_overlay.visible:
		var ground_y := _stream_target.global_position.y if _stream_target != null else 0.0
		_chunk_grid_overlay.rebuild(center_chunk, ground_y)

	if _farmable_grid_overlay != null and _farmable_grid_overlay.visible:
		var ground_y := _stream_target.global_position.y if _stream_target != null else 0.0
		_farmable_grid_overlay.rebuild(center_chunk, ground_y)

	if force_refresh:
		_rebuild_crop_nodes_for_loaded_chunks()

func _chunk_sets_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left.keys():
		if not right.has(key):
			return false
	return true

func get_stream_center_chunk() -> Vector2i:
	if _stream_target == null or not is_instance_valid(_stream_target):
		return Vector2i.ZERO
	return GameManager.session.farm.world_to_chunk(_stream_target.global_position)

func get_loaded_chunk_count() -> int:
	return _currently_loaded_chunks.size()

func get_stream_radius() -> int:
	return streamed_chunk_radius

func get_stream_target_position() -> Vector3:
	if _stream_target == null or not is_instance_valid(_stream_target):
		return Vector3.ZERO
	return _stream_target.global_position

func toggle_chunk_grid() -> bool:
	if _chunk_grid_overlay == null:
		return false
	var new_vis := not _chunk_grid_overlay.visible
	_chunk_grid_overlay.set_overlay_visible(new_vis)
	if new_vis:
		var center := get_stream_center_chunk()
		var ground_y := _stream_target.global_position.y if _stream_target != null else 0.0
		_chunk_grid_overlay.force_rebuild(center, ground_y)
	return new_vis

func is_chunk_grid_visible() -> bool:
	if _chunk_grid_overlay == null:
		return false
	return _chunk_grid_overlay.is_overlay_visible()

func toggle_farmable_grid() -> bool:
	if _farmable_grid_overlay == null:
		return false
	var new_vis := not _farmable_grid_overlay.visible
	_farmable_grid_overlay.set_overlay_visible(new_vis)
	if new_vis:
		var center := get_stream_center_chunk()
		var ground_y := _stream_target.global_position.y if _stream_target != null else 0.0
		_farmable_grid_overlay.force_rebuild(center, ground_y)
	return new_vis

func is_farmable_grid_visible() -> bool:
	if _farmable_grid_overlay == null:
		return false
	return _farmable_grid_overlay.is_overlay_visible()

func _create_chunk_grid_overlay() -> void:
	var overlay := Node3D.new()
	overlay.name = "ChunkGridOverlay"
	overlay.set_script(ChunkGridOverlayRef)
	overlay.chunk_size_meters = GameManager.session.farm.simulation_chunk_size_tiles
	overlay.grid_draw_radius = streamed_chunk_radius
	overlay.visible = false
	add_child(overlay)
	_chunk_grid_overlay = overlay

func _create_farmable_grid_overlay() -> void:
	var overlay := Node3D.new()
	overlay.name = "FarmableGridOverlay"
	overlay.set_script(FarmableGridOverlayRef)
	overlay.chunk_size_meters = GameManager.session.farm.simulation_chunk_size_tiles
	overlay.draw_radius_chunks = 1
	overlay.visible = false
	add_child(overlay)
	_farmable_grid_overlay = overlay

func _create_crop_nodes_container() -> void:
	_crop_nodes_container = Node3D.new()
	_crop_nodes_container.name = "CropNodes"
	add_child(_crop_nodes_container)

func rebuild_farm_visuals_after_load() -> void:
	_update_streamed_chunks(true)
	_rebuild_crop_nodes_for_loaded_chunks()

func _on_farm_tile_updated(grid_pos: Vector2i, new_state: int) -> void:
	var chunk_pos := GameManager.session.farm.grid_to_chunk(grid_pos)
	if not _currently_loaded_chunks.has(chunk_pos):
		return

	if new_state == FarmData.SoilState.SEEDED or new_state == FarmData.SoilState.HARVESTABLE:
		_ensure_crop_node(grid_pos)
		return

	_remove_crop_node(grid_pos)

func _spawn_crop_nodes_for_chunk(chunk_pos: Vector2i) -> void:
	var seeded_tiles: Array[Vector2i] = GameManager.session.farm.get_seeded_chunk_tiles(chunk_pos)
	for grid_pos: Vector2i in seeded_tiles:
		_ensure_crop_node(grid_pos)

func _despawn_crop_nodes_for_chunk(chunk_pos: Vector2i) -> void:
	var to_remove: Array[Vector2i] = []
	for grid_pos_any: Variant in _crop_nodes_by_grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		if GameManager.session.farm.grid_to_chunk(grid_pos) == chunk_pos:
			to_remove.append(grid_pos)

	for grid_pos: Vector2i in to_remove:
		_remove_crop_node(grid_pos)

func _rebuild_crop_nodes_for_loaded_chunks() -> void:
	_clear_all_crop_nodes()
	for chunk_pos_any: Variant in _currently_loaded_chunks.keys():
		if chunk_pos_any is Vector2i:
			_spawn_crop_nodes_for_chunk(chunk_pos_any)

func _clear_all_crop_nodes() -> void:
	for grid_pos_any: Variant in _crop_nodes_by_grid.keys():
		if grid_pos_any is Vector2i:
			_remove_crop_node(grid_pos_any)
	_crop_nodes_by_grid.clear()

func _ensure_crop_node(grid_pos: Vector2i) -> void:
	if _crop_nodes_by_grid.has(grid_pos):
		var existing: Node = _crop_nodes_by_grid[grid_pos]
		if existing != null and is_instance_valid(existing):
			if existing.has_method("refresh_from_data"):
				existing.call("refresh_from_data")
			return
		_crop_nodes_by_grid.erase(grid_pos)

	if _crop_nodes_container == null:
		_create_crop_nodes_container()

	var crop_node_any: Node = CropNodeSceneRef.instantiate()
	if crop_node_any == null:
		return

	if crop_node_any.get("grid_position") != null:
		crop_node_any.set("grid_position", grid_pos)

	_crop_nodes_container.add_child(crop_node_any)

	if crop_node_any is Node3D:
		var crop_node_3d: Node3D = crop_node_any as Node3D
		var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
		var world_center: Vector2 = GameManager.session.farm.grid_to_world_center(grid_pos)
		crop_node_3d.global_position = Vector3(world_center.x, tile_data.height, world_center.y)

	if crop_node_any.has_method("refresh_from_data"):
		crop_node_any.call("refresh_from_data")

	_crop_nodes_by_grid[grid_pos] = crop_node_any

func _remove_crop_node(grid_pos: Vector2i) -> void:
	if not _crop_nodes_by_grid.has(grid_pos):
		return
	var node: Node = _crop_nodes_by_grid[grid_pos]
	_crop_nodes_by_grid.erase(grid_pos)
	if node != null and is_instance_valid(node):
		node.queue_free()
