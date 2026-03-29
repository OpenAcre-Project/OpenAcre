extends Node

const SAVE_ROOT := "user://Saves"
const SLOT_PREFIX := "Slot_"
const SAVE_VERSION := 1
const BLACKOUT_PHYSICS_FRAMES := 3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if EventBus.has_signal("save_game_requested"):
		EventBus.save_game_requested.connect(_on_save_game_requested)
	if EventBus.has_signal("load_game_requested"):
		EventBus.load_game_requested.connect(_on_load_game_requested)

func _on_save_game_requested() -> void:
	var ok := save_slot(1)
	if ok:
		GameLog.info("[SaveManager] Save completed for slot 1.")

func _on_load_game_requested() -> void:
	var ok := await load_slot(1)
	if ok:
		GameLog.info("[SaveManager] Load completed for slot 1.")

func slot_exists(slot_index: int = 1) -> bool:
	_recover_interrupted_slot(slot_index)
	return _dir_exists(_slot_dir(slot_index))

func get_slot_metadata(slot_index: int = 1) -> Dictionary:
	_recover_interrupted_slot(slot_index)
	var slot_dir := _slot_dir(slot_index)
	if not _dir_exists(slot_dir):
		return {}
	return _read_json(slot_dir.path_join("metadata.json"))

func list_slot_metadata(max_slots: int = 8) -> Dictionary:
	var out := {}
	for slot_index: int in range(1, maxi(1, max_slots) + 1):
		var metadata := get_slot_metadata(slot_index)
		if not metadata.is_empty():
			out[str(slot_index)] = metadata
	return out

func save_slot(slot_index: int = 1) -> bool:
	if GameManager.session == null:
		GameLog.warn("[SaveManager] Cannot save: session is null.")
		return false

	_recover_interrupted_slot(slot_index)

	if EventBus.has_signal("pre_save_flush"):
		EventBus.pre_save_flush.emit()

	var slot_dir := _slot_dir(slot_index)
	var tmp_dir := slot_dir + "_TMP"
	var bak_dir := slot_dir + "_BAK"
	var farm_layers_dir := tmp_dir.path_join("FarmLayers")

	if not _delete_dir_recursive(tmp_dir):
		GameLog.error("[SaveManager] Failed to clean temp save directory: " + tmp_dir)
		return false
	if not _delete_dir_recursive(bak_dir):
		GameLog.error("[SaveManager] Failed to clean backup save directory: " + bak_dir)
		return false

	if not _ensure_dir(tmp_dir):
		GameLog.error("[SaveManager] Failed to create temp save directory: " + tmp_dir)
		return false
	if not _ensure_dir(farm_layers_dir):
		GameLog.error("[SaveManager] Failed to create farm layers temp directory: " + farm_layers_dir)
		return false

	var farm: FarmData = GameManager.session.farm
	var crop_to_id := _build_crop_id_table(farm)
	var layers: Dictionary = farm.export_heatmap_layers(crop_to_id)

	var metadata: Dictionary = _build_metadata(slot_index, crop_to_id)
	var entities_payload: Dictionary = _build_entities_payload()

	if not _write_json(tmp_dir.path_join("metadata.json"), metadata):
		return false
	if not _write_json(tmp_dir.path_join("entities.json"), entities_payload):
		return false

	var soil_image: Image = layers.get("soil_state", null)
	var crop_image: Image = layers.get("crop_type", null)
	var planted_time_image: Image = layers.get("planted_time", null)

	if soil_image == null or crop_image == null or planted_time_image == null:
		GameLog.error("[SaveManager] Missing farm layers during save.")
		return false

	if soil_image.save_png(farm_layers_dir.path_join("soil_state.png")) != OK:
		GameLog.error("[SaveManager] Failed to save soil_state.png")
		return false
	if crop_image.save_png(farm_layers_dir.path_join("crop_type.png")) != OK:
		GameLog.error("[SaveManager] Failed to save crop_type.png")
		return false

	var exr_err: Error = planted_time_image.save_exr(farm_layers_dir.path_join("planted_time.exr"), false)
	if exr_err != OK:
		GameLog.warn("[SaveManager] planted_time.exr save failed, writing JSON fallback.")
		if not _write_json(farm_layers_dir.path_join("planted_time.json"), _build_planted_time_fallback(farm, crop_to_id)):
			return false

	if not _atomic_swap_slot(slot_dir, tmp_dir, bak_dir):
		return false

	return true

func load_slot(slot_index: int = 1) -> bool:
	if GameManager.session == null:
		GameLog.warn("[SaveManager] Cannot load: session is null.")
		return false

	_recover_interrupted_slot(slot_index)

	var slot_dir := _slot_dir(slot_index)
	if not _dir_exists(slot_dir):
		GameLog.warn("[SaveManager] Slot does not exist: " + slot_dir)
		return false

	var metadata: Dictionary = _read_json(slot_dir.path_join("metadata.json"))
	var entities_payload: Dictionary = _read_json(slot_dir.path_join("entities.json"))
	if metadata.is_empty() or entities_payload.is_empty():
		GameLog.error("[SaveManager] Missing or invalid metadata/entities JSON in slot.")
		return false

	var crop_lookup: Dictionary = metadata.get("crop_lookup", {})
	var tree: SceneTree = get_tree()
	if tree == null:
		GameLog.error("[SaveManager] SceneTree is null during load.")
		return false

	var spooler: Node = _find_stream_spooler()
	tree.paused = true
	if spooler != null:
		if spooler.has_method("set_streaming_enabled"):
			spooler.call("set_streaming_enabled", false)
		if spooler.has_method("begin_load_blackout"):
			spooler.call("begin_load_blackout", BLACKOUT_PHYSICS_FRAMES)
		if spooler.has_method("clear_runtime_view_state"):
			spooler.call("clear_runtime_view_state", true)
	else:
		_clear_world_entity_container(true)

	# queue_free() completes at frame end; wait before hydration to avoid duplicate-node conflicts.
	await tree.process_frame

	_reset_runtime_data()
	_restore_time(metadata)
	_restore_entities(entities_payload)
	_restore_player(metadata)
	_repair_orphaned_entities()
	_restore_farm_layers(slot_dir, crop_lookup)
	_rebuild_world_farm_visuals_after_load()

	_teleport_player_node_to_data()

	if spooler != null:
		if spooler.has_method("set_streaming_enabled"):
			spooler.call("set_streaming_enabled", true)
		if spooler.has_method("update_active_chunks"):
			var player_data: PlayerData = GameManager.session.entities.get_player()
			spooler.call("update_active_chunks", player_data.world_position, 2)
		if spooler.has_method("refresh_from_current_chunks"):
			spooler.call("refresh_from_current_chunks", "load_slot")

	tree.paused = false

	if spooler != null and spooler.has_method("finalize_load_blackout"):
		spooler.call("finalize_load_blackout")

	if EventBus.has_signal("game_loaded_successfully"):
		EventBus.game_loaded_successfully.emit()

	return true

func _rebuild_world_farm_visuals_after_load() -> void:
	var soil_service: Node = get_tree().get_first_node_in_group("soil_layer_service")
	if soil_service != null and soil_service.has_method("rebuild_visuals_from_data"):
		soil_service.call("rebuild_visuals_from_data")

	var grid_manager: Node = get_tree().get_first_node_in_group("grid_manager")
	if grid_manager != null and grid_manager.has_method("rebuild_farm_visuals_after_load"):
		grid_manager.call("rebuild_farm_visuals_after_load")

func _build_metadata(slot_index: int, crop_to_id: Dictionary) -> Dictionary:
	var time_mgr: TimeManager = GameManager.session.time
	var em: EntityManager = GameManager.session.entities
	var player: PlayerData = em.get_player()

	var map_name := "unknown"
	var map_root: Node = get_tree().get_first_node_in_group("map_root")
	if map_root != null and map_root.get("map_id") != null:
		map_name = str(map_root.get("map_id"))

	return {
		"version": SAVE_VERSION,
		"slot": slot_index,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"map": map_name,
		"time": {
			"total_minutes": time_mgr.get_total_minutes(),
			"day": time_mgr.current_day,
			"hour": time_mgr.current_hour,
			"minute": time_mgr.current_minute
		},
		"player": {
			"player_id": str(player.player_id),
			"world_position": [player.world_position.x, player.world_position.y, player.world_position.z],
			"world_yaw_radians": player.world_yaw_radians,
			"active_vehicle_id": str(player.active_vehicle_id),
			"calories": player.calories,
			"hydration": player.hydration,
			"energy": player.energy,
			"max_calories": player.max_calories,
			"max_hydration": player.max_hydration,
			"max_energy": player.max_energy,
			"pockets": {
				"max_volume": player.pockets.max_volume,
				"max_mass": player.pockets.max_mass,
				"entity_ids": _stringify_string_name_array(player.pockets.entity_ids)
			},
			"equipment_back": str(player.equipment_back)
		},
		"crop_lookup": _invert_crop_table(crop_to_id)
	}

func _build_entities_payload() -> Dictionary:
	var em: EntityManager = GameManager.session.entities
	var entities: Array = []

	for runtime_id_any: Variant in em._entities.keys():
		if runtime_id_any is not StringName:
			continue
		var runtime_id: StringName = runtime_id_any
		var entity: EntityData = em._entities[runtime_id]
		if entity == null:
			continue

		var components_dict := {}
		for comp_any: Variant in entity.get_all_components():
			if comp_any is not Component:
				continue
			var comp: Component = comp_any
			var payload: Dictionary = comp.save_to_dict()
			payload["__last_simulated_minute"] = comp.last_simulated_minute
			components_dict[str(comp.type_id)] = payload

		entities.append({
			"runtime_id": str(entity.runtime_id),
			"definition_id": str(entity.definition_id),
			"parent_id": str(entity.parent_id),
			"components": components_dict
		})

	var entity_groups := {}
	for entity_id_any: Variant in em._entity_to_group.keys():
		if entity_id_any is not StringName:
			continue
		var entity_id: StringName = entity_id_any
		entity_groups[str(entity_id)] = str(em._entity_to_group[entity_id])

	return {
		"version": SAVE_VERSION,
		"entities": entities,
		"entity_groups": entity_groups
	}

func _build_crop_id_table(farm: FarmData) -> Dictionary:
	var crop_to_id := {}
	var next_id := 1

	for grid_pos_any: Variant in farm._grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var tile: FarmTileData = farm._grid[grid_pos_any]
		if tile == null or tile.crop_type == &"":
			continue
		if crop_to_id.has(tile.crop_type):
			continue
		crop_to_id[tile.crop_type] = next_id
		next_id += 1
		if next_id > 255:
			break

	return crop_to_id

func _invert_crop_table(crop_to_id: Dictionary) -> Dictionary:
	var id_to_crop := {}
	for crop_key_any: Variant in crop_to_id.keys():
		var crop_key: StringName = crop_key_any
		var crop_id: int = int(crop_to_id[crop_key])
		id_to_crop[str(crop_id)] = str(crop_key)
	return id_to_crop

func _build_planted_time_fallback(farm: FarmData, crop_to_id: Dictionary) -> Dictionary:
	var entries: Array = []
	var resolution: Vector2i = farm.get_heatmap_resolution()

	for grid_pos_any: Variant in farm._grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		var tile: FarmTileData = farm._grid[grid_pos]
		if tile == null or tile.crop_type == &"" or not crop_to_id.has(tile.crop_type):
			continue

		var pixel: Vector2i = farm._grid_to_heatmap_pixel(grid_pos, resolution.x, resolution.y)
		if pixel.x < 0 or pixel.y < 0:
			continue

		entries.append({
			"x": pixel.x,
			"y": pixel.y,
			"t": tile.planted_at_minute
		})

	return {
		"width": resolution.x,
		"height": resolution.y,
		"entries": entries
	}

func _reset_runtime_data() -> void:
	var session: GameSession = GameManager.session
	var em: EntityManager = session.entities

	em._entities.clear()
	em._chunks.clear()
	em._children_by_parent.clear()
	em._streaming_groups.clear()
	em._entity_to_group.clear()

	session.farm.clear_runtime_state(true)
	session.farm._last_processed_minute = session.time.get_total_minutes()

func _restore_time(metadata: Dictionary) -> void:
	var time_data: Dictionary = metadata.get("time", {})
	var total_minutes: int = int(time_data.get("total_minutes", 0))
	GameManager.session.time.set_total_minutes(total_minutes, false)
	GameManager.session.farm._last_processed_minute = total_minutes

func _restore_entities(payload: Dictionary) -> void:
	var em: EntityManager = GameManager.session.entities
	var entries: Array = payload.get("entities", [])

	for entry_any: Variant in entries:
		if entry_any is not Dictionary:
			continue
		var entry: Dictionary = entry_any
		var runtime_id := StringName(str(entry.get("runtime_id", "")))
		var definition_id := StringName(str(entry.get("definition_id", "")))
		if runtime_id == &"" or definition_id == &"":
			continue

		var entity := EntityData.new(runtime_id, definition_id)
		entity.parent_id = StringName(str(entry.get("parent_id", "")))

		var components: Dictionary = entry.get("components", {})
		for comp_type_any: Variant in components.keys():
			var comp_type: String = str(comp_type_any)
			var comp_data_any: Variant = components[comp_type_any]
			if comp_data_any is not Dictionary:
				continue
			var comp_data: Dictionary = comp_data_any

			var comp: Component = EntityRegistry._create_component(comp_type)
			if comp == null:
				continue

			comp.load_from_dict(comp_data)
			comp.last_simulated_minute = int(comp_data.get("__last_simulated_minute", GameManager.session.time.get_total_minutes()))
			entity.add_component(comp)

		em.register_entity(entity)

	var entity_groups: Dictionary = payload.get("entity_groups", {})
	for entity_id_any: Variant in entity_groups.keys():
		var group_id_any: Variant = entity_groups[entity_id_any]
		var entity_id := StringName(str(entity_id_any))
		var group_id := StringName(str(group_id_any))
		if entity_id != &"" and group_id != &"":
			em.assign_entity_to_group(entity_id, group_id)

func _restore_player(metadata: Dictionary) -> void:
	var player_payload: Dictionary = metadata.get("player", {})
	var player_id := StringName(str(player_payload.get("player_id", "player.main")))
	var player: PlayerData = GameManager.session.entities.ensure_player(player_id)

	var pos_data: Array = player_payload.get("world_position", [0.0, 0.0, 0.0])
	if pos_data.size() >= 3:
		player.world_position = Vector3(float(pos_data[0]), float(pos_data[1]), float(pos_data[2]))
	player.world_yaw_radians = float(player_payload.get("world_yaw_radians", 0.0))
	player.has_world_transform = true

	player.active_vehicle_id = StringName(str(player_payload.get("active_vehicle_id", "")))
	player.calories = float(player_payload.get("calories", player.calories))
	player.hydration = float(player_payload.get("hydration", player.hydration))
	player.energy = float(player_payload.get("energy", player.energy))
	player.max_calories = float(player_payload.get("max_calories", player.max_calories))
	player.max_hydration = float(player_payload.get("max_hydration", player.max_hydration))
	player.max_energy = float(player_payload.get("max_energy", player.max_energy))

	var pockets_payload: Dictionary = player_payload.get("pockets", {})
	player.pockets.max_volume = float(pockets_payload.get("max_volume", player.pockets.max_volume))
	player.pockets.max_mass = float(pockets_payload.get("max_mass", player.pockets.max_mass))
	player.pockets.entity_ids.clear()
	for entity_id_any: Variant in pockets_payload.get("entity_ids", []):
		var entity_id := StringName(str(entity_id_any))
		if entity_id != &"":
			player.pockets.entity_ids.append(entity_id)

	player.equipment_back = StringName(str(player_payload.get("equipment_back", "")))
	GameManager.session.entities.set_player_transform(player_id, player.world_position, player.world_yaw_radians)

func _repair_orphaned_entities() -> void:
	var em: EntityManager = GameManager.session.entities
	var player: PlayerData = em.get_player()
	var fallback_pos := player.world_position + Vector3(0, 0.8, 0)
	var fallback_yaw := player.world_yaw_radians

	var valid_entity_ids := {}
	for entity_id_any: Variant in em._entities.keys():
		if entity_id_any is StringName:
			valid_entity_ids[entity_id_any] = true

	var orphaned: Array[StringName] = []
	for entity_id_any: Variant in em._entities.keys():
		if entity_id_any is not StringName:
			continue
		var entity_id: StringName = entity_id_any
		var entity: EntityData = em._entities[entity_id]
		if entity == null:
			continue

		var parent_id: StringName = entity.parent_id
		if parent_id == &"":
			continue

		var parent_str := str(parent_id)
		if parent_str.begins_with("player"):
			if not player.pockets.entity_ids.has(entity_id):
				orphaned.append(entity_id)
			continue

		if not valid_entity_ids.has(parent_id):
			orphaned.append(entity_id)

	for orphan_id: StringName in orphaned:
		em.clear_entity_parent(orphan_id, fallback_pos, fallback_yaw)
		GameLog.warn("[SaveManager] Repaired orphaned entity parent link for %s" % str(orphan_id))

func _restore_farm_layers(slot_dir: String, crop_lookup: Dictionary) -> void:
	var farm: FarmData = GameManager.session.farm
	var layers_dir := slot_dir.path_join("FarmLayers")
	var resolution: Vector2i = farm.get_heatmap_resolution()

	var soil_path := layers_dir.path_join("soil_state.png")
	var crop_path := layers_dir.path_join("crop_type.png")
	var planted_exr_path := layers_dir.path_join("planted_time.exr")
	var planted_json_path := layers_dir.path_join("planted_time.json")

	var soil_image := _load_image_or_default(soil_path, Image.FORMAT_L8, Color(0, 0, 0, 1), resolution)
	var crop_image := _load_image_or_default(crop_path, Image.FORMAT_L8, Color(0, 0, 0, 1), resolution)
	var planted_image: Image = null

	if FileAccess.file_exists(planted_exr_path):
		planted_image = _load_image_or_default(planted_exr_path, Image.FORMAT_RF, Color(-1.0, 0, 0, 1), resolution)
	elif FileAccess.file_exists(planted_json_path):
		planted_image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RF)
		planted_image.fill(Color(-1.0, 0, 0, 1))
		_apply_planted_time_fallback(planted_image, _read_json(planted_json_path))
	else:
		planted_image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RF)
		planted_image.fill(Color(-1.0, 0, 0, 1))

	farm.import_heatmap_layers(soil_image, crop_image, planted_image, crop_lookup)

func _apply_planted_time_fallback(image: Image, payload: Dictionary) -> void:
	if image == null:
		return
	for entry_any: Variant in payload.get("entries", []):
		if entry_any is not Dictionary:
			continue
		var entry: Dictionary = entry_any
		var x: int = int(entry.get("x", -1))
		var y: int = int(entry.get("y", -1))
		var t: float = float(entry.get("t", -1.0))
		if x < 0 or x >= image.get_width() or y < 0 or y >= image.get_height():
			continue
		image.set_pixel(x, y, Color(t, 0, 0, 1))

func _teleport_player_node_to_data() -> void:
	var player_data: PlayerData = GameManager.session.entities.get_player()
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node != null and player_node is Node3D:
		var player_3d: Node3D = player_node as Node3D
		player_3d.global_position = player_data.world_position
		player_3d.rotation.y = player_data.world_yaw_radians

func _clear_world_entity_container(use_queue_free: bool) -> void:
	var container: Node = get_tree().get_first_node_in_group("world_entity_container")
	if container == null:
		return
	for child: Node in container.get_children():
		container.remove_child(child)
		if use_queue_free:
			child.queue_free()
		else:
			child.free()

func _slot_dir(slot_index: int) -> String:
	return SAVE_ROOT.path_join("%s%02d" % [SLOT_PREFIX, maxi(slot_index, 1)])

func _recover_interrupted_slot(slot_index: int) -> void:
	var slot_dir := _slot_dir(slot_index)
	var tmp_dir := slot_dir + "_TMP"
	var bak_dir := slot_dir + "_BAK"
	var global_slot := _global_path(slot_dir)
	var global_tmp := _global_path(tmp_dir)
	var global_bak := _global_path(bak_dir)

	var has_slot := DirAccess.dir_exists_absolute(global_slot)
	var has_tmp := DirAccess.dir_exists_absolute(global_tmp)
	var has_bak := DirAccess.dir_exists_absolute(global_bak)

	if has_slot:
		if has_tmp:
			_delete_dir_recursive(tmp_dir)
		if has_bak:
			_delete_dir_recursive(bak_dir)
		return

	if has_bak and has_tmp:
		# Crash during swap: prefer known-good backup, discard incomplete temp.
		if DirAccess.rename_absolute(global_bak, global_slot) == OK:
			_delete_dir_recursive(tmp_dir)
		return

	if has_bak and not has_tmp:
		DirAccess.rename_absolute(global_bak, global_slot)
		return

	if has_tmp and not has_bak:
		# No previous slot existed, temp can be promoted safely.
		DirAccess.rename_absolute(global_tmp, global_slot)

func _find_stream_spooler() -> Node:
	return get_tree().root.find_child("StreamSpooler", true, false)

func _write_json(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		GameLog.error("[SaveManager] Failed to open JSON for write: " + path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var content := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(content)
	if parsed is Dictionary:
		return parsed
	return {}

func _load_image_or_default(path: String, format: Image.Format, default_color: Color, resolution: Vector2i) -> Image:
	var image := Image.new()
	if FileAccess.file_exists(path):
		if image.load(path) == OK:
			if image.get_format() != format:
				image.convert(format)
			return image

	image = Image.create(maxi(1, resolution.x), maxi(1, resolution.y), false, format)
	image.fill(default_color)
	return image

func _ensure_dir(path: String) -> bool:
	var global := _global_path(path)
	var err: Error = DirAccess.make_dir_recursive_absolute(global)
	return err == OK

func _dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(_global_path(path))

func _file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func _global_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func _delete_dir_recursive(path: String) -> bool:
	var global := _global_path(path)
	return _delete_dir_recursive_global(global)

func _delete_dir_recursive_global(global: String) -> bool:
	if not DirAccess.dir_exists_absolute(global):
		return true

	var dir := DirAccess.open(global)
	if dir == null:
		return false

	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if entry_name != "." and entry_name != "..":
			var child_global := global.path_join(entry_name)
			if dir.current_is_dir():
				if not _delete_dir_recursive_global(child_global):
					dir.list_dir_end()
					return false
			else:
				if DirAccess.remove_absolute(child_global) != OK:
					dir.list_dir_end()
					return false
		entry_name = dir.get_next()
	dir.list_dir_end()

	return DirAccess.remove_absolute(global) == OK

func _atomic_swap_slot(slot_dir: String, tmp_dir: String, bak_dir: String) -> bool:
	var global_slot := _global_path(slot_dir)
	var global_tmp := _global_path(tmp_dir)
	var global_bak := _global_path(bak_dir)

	if _dir_exists(slot_dir):
		var move_to_backup_err := DirAccess.rename_absolute(global_slot, global_bak)
		if move_to_backup_err != OK:
			GameLog.error("[SaveManager] Failed to move old slot to backup.")
			return false

	var promote_err := DirAccess.rename_absolute(global_tmp, global_slot)
	if promote_err != OK:
		GameLog.error("[SaveManager] Failed to promote temp slot to live slot.")
		if DirAccess.dir_exists_absolute(global_bak):
			DirAccess.rename_absolute(global_bak, global_slot)
		return false

	if DirAccess.dir_exists_absolute(global_bak):
		if not _delete_dir_recursive(bak_dir):
			GameLog.warn("[SaveManager] Could not remove backup slot after atomic swap: " + bak_dir)

	return true

func _stringify_string_name_array(values: Array[StringName]) -> Array:
	var out: Array = []
	for value: StringName in values:
		out.append(str(value))
	return out
