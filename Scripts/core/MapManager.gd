class_name MapManager
extends RefCounted

const PLAYER_SCENE: PackedScene = preload("res://Scenes/Actors/Player.tscn")
const STREAM_SPOOLER_SCRIPT: GDScript = preload("res://Scripts/streaming/StreamSpooler.gd")

static func populate_world(world_root: Node3D) -> void:
	var tree: SceneTree = world_root.get_tree()
	if tree == null:
		return

	# 1. Wait a frame for the scene tree to settle and groups to register
	await tree.process_frame

	var map_def := tree.get_first_node_in_group("map_root") as MapDefinition
	if map_def == null:
		GameLog.warn("[MapManager] No MapDefinition found in map_root group!")
		return

	if GameManager.session != null and GameManager.session.is_new_game:
		_isolate_runtime_terrain_data(tree)

	if map_def.region_mask != null:
		GameManager.session.farm.set_active_region_mask(map_def.region_mask)
		GameLog.info("[MapManager] Registered MapRegionMask with FarmData")
	else:
		GameLog.warn("[MapManager] MapDefinition is missing a region_mask!")

	# Load map fields from JSON if provided
	if not map_def.field_data_json.is_empty():
		GameManager.session.farm.load_map_fields_from_json(map_def.field_data_json, map_def.field_data_offset)
		GameLog.info("[MapManager] Loaded map fields from JSON")
		
		# If this is a new game, we need to mass-plow the predefined fields
		if GameManager.session.is_new_game:
			GameLog.info("[MapManager] New game detected, generating initial plowed fields...")
			GameManager.session.farm.generate_initial_plowed_fields()
			
			# Ensure the visuals are updated right away for the new plowed fields
			var soil_service: Node = tree.get_first_node_in_group("soil_layer_service")
			if soil_service != null and soil_service.has_method("rebuild_visuals_from_data"):
				soil_service.rebuild_visuals_from_data()
				GameLog.info("[MapManager] Rebuilt soil visuals for new map fields")

	# 2. Spawn the Player
	_spawn_player(world_root, tree)
	_ensure_streaming_runtime(world_root, tree)

	# 3. Register Vehicles (SimulationCore handles the rest!)
	if map_def.starting_vehicles != null:
		_register_map_vehicles(map_def.starting_vehicles, tree)

	var spooler_node: Node = world_root.find_child("StreamSpooler", true, false)
	if spooler_node != null and spooler_node.has_method("refresh_from_current_chunks"):
		spooler_node.call("refresh_from_current_chunks", "post_register_vehicles")

	if GameManager.session != null and GameManager.session.is_new_game:
		GameManager.session.is_new_game = false

static func _isolate_runtime_terrain_data(tree: SceneTree) -> void:
	var terrain: Node = tree.get_first_node_in_group("terrain_node")
	if terrain == null:
		return

	if terrain.has_meta("runtime_terrain_data_isolated") and bool(terrain.get_meta("runtime_terrain_data_isolated")):
		return

	var source_data: Resource = null
	var source_mode: String = ""
	if terrain.has_method("get_data"):
		var data_candidate: Variant = terrain.call("get_data")
		if data_candidate is Resource:
			source_data = data_candidate
			source_mode = "data"
	if source_data == null and terrain.has_method("get_storage"):
		var storage_candidate: Variant = terrain.call("get_storage")
		if storage_candidate is Resource:
			source_data = storage_candidate
			source_mode = "storage"
	elif "data" in terrain:
		var data_property: Variant = terrain.get("data")
		if data_property is Resource:
			source_data = data_property
			source_mode = "data_property"
	if source_data == null and "storage" in terrain:
		var storage_property: Variant = terrain.get("storage")
		if storage_property is Resource:
			source_data = storage_property
			source_mode = "storage_property"

	if source_data == null:
		GameLog.info("[MapManager] Terrain3D runtime isolation skipped (no data/storage API resource found).")
		return

	var runtime_copy: Resource = source_data.duplicate(true)
	if runtime_copy == null:
		GameLog.error("[MapManager] Failed to duplicate Terrain3D data resource.")
		return

	match source_mode:
		"data":
			if terrain.has_method("set_data"):
				terrain.call("set_data", runtime_copy)
			else:
				GameLog.error("[MapManager] Terrain3D get_data() was available, but set_data() is missing.")
				return
		"storage":
			if terrain.has_method("set_storage"):
				terrain.call("set_storage", runtime_copy)
			else:
				GameLog.error("[MapManager] Terrain3D get_storage() was available, but set_storage() is missing.")
				return
		"data_property":
			terrain.set("data", runtime_copy)
		"storage_property":
			terrain.set("storage", runtime_copy)
		_:
			if terrain.has_method("set_data"):
				terrain.call("set_data", runtime_copy)
			elif terrain.has_method("set_storage"):
				terrain.call("set_storage", runtime_copy)
			elif "data" in terrain:
				terrain.set("data", runtime_copy)
			elif "storage" in terrain:
				terrain.set("storage", runtime_copy)
			else:
				GameLog.error("[MapManager] Terrain3D node does not support setting runtime data/storage resource.")
				return

	terrain.set_meta("runtime_terrain_data_isolated", true)
	GameLog.info("[MapManager] Isolated runtime Terrain3D data from pristine map resource.")

	var soil_service: Node = tree.get_first_node_in_group("soil_layer_service")
	if soil_service != null and soil_service.has_method("refresh_terrain_api"):
		soil_service.call("refresh_terrain_api")

static func _ensure_streaming_runtime(world_root: Node3D, tree: SceneTree) -> void:
	var world_container: Node = tree.get_first_node_in_group("world_entity_container")
	if world_container == null:
		var container := Node3D.new()
		container.name = "WorldEntityContainer"
		container.add_to_group("world_entity_container")
		world_root.add_child(container)
		GameLog.info("[MapManager] Created WorldEntityContainer runtime node")

	var spooler_node: Node = world_root.find_child("StreamSpooler", true, false)
	if spooler_node == null:
		spooler_node = Node.new()
		spooler_node.name = "StreamSpooler"
		spooler_node.set_script(STREAM_SPOOLER_SCRIPT)
		world_root.add_child(spooler_node)
		GameLog.info("[MapManager] Created StreamSpooler runtime node")
	else:
		GameLog.info("[MapManager] Reusing existing StreamSpooler runtime node")

	if spooler_node != null and spooler_node.has_method("update_active_chunks"):
		var player_data: PlayerData = GameManager.session.entities.get_player()
		if player_data != null and player_data.has_world_transform:
			spooler_node.call("update_active_chunks", player_data.world_position, 2)
			GameLog.info("[MapManager] Primed StreamSpooler with player position")

static func _spawn_player(parent_node: Node, tree: SceneTree) -> void:
	var spawn_pts: Array[Node] = tree.get_nodes_in_group("spawn_points_player")
	var spawn_pos := Vector3(0, 5, 0)
	var spawn_yaw := 0.0

	# Find the designated player spawn point
	if spawn_pts.size() > 0:
		var pt: Node3D = spawn_pts[0] as Node3D
		spawn_pos = pt.global_position
		spawn_yaw = pt.global_rotation.y

	# Instantiate the Player
	var player: Node = PLAYER_SCENE.instantiate()
	parent_node.add_child(player)
	
	if player is Node3D:
		player.global_position = spawn_pos
		player.rotation.y = spawn_yaw

	# Immediately update SimulationCore so the camera and chunk streamers know where to look
	var player_id: StringName = &"player.main"
	if player.get("simulation_player_id") != null:
		player_id = player.get("simulation_player_id")
	
	GameManager.session.entities.set_player_transform(player_id, spawn_pos, spawn_yaw)
	GameLog.info("[MapManager] Player dynamically spawned at " + str(spawn_pos))

static func _register_map_vehicles(spawn_table: VehicleSpawnTable, tree: SceneTree) -> void:
	var vehicle_markers: Array[Node] = tree.get_nodes_in_group("spawn_points_vehicle")
	
	for entry: VehicleSpawnEntry in spawn_table.entries:
		if entry == null or entry.vehicle_id == &"" or entry.spec_id == &"":
			continue

		if GameManager.session.entities.get_entity(entry.vehicle_id) != null:
			continue

		# Cross-reference the table with our physical MapSpawnPoint markers!
		# If a marker shares the same spawn_id as the vehicle_id, override the position.
		var start_pos: Vector3 = entry.world_position
		var start_yaw: float = entry.world_yaw_radians
		
		for marker: Node3D in vehicle_markers:
			if marker.get("spawn_id") == entry.vehicle_id:
				start_pos = marker.global_position
				start_yaw = marker.global_rotation.y
				break

		var new_entity: EntityData = EntityRegistry.create_entity(entry.spec_id, entry.vehicle_id)
		if new_entity:
			var tf: TransformComponent = new_entity.get_transform()
			if tf:
				tf.world_position = start_pos
				tf.world_rotation_radians = start_yaw
			
			var container: ContainerComponent = new_entity.get_component(&"container") as ContainerComponent
			if container:
				# Note: Currently hardcoding fuel level to map specs, ignoring complex fluid routing for now
				if container.inventory.has("fuel"):
					var fuel_slot: Variant = container.inventory["fuel"]
					if fuel_slot is Dictionary:
						fuel_slot["quantity"] = entry.fuel_level
			
			GameManager.session.entities.register_entity(new_entity)
			
	GameLog.info("[MapManager] Map vehicles registered to UESS GameManager.")
