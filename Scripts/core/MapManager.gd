class_name MapManager
extends RefCounted

const PLAYER_SCENE: PackedScene = preload("res://Scenes/Actors/Player.tscn")

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

	# 3. Register Vehicles (SimulationCore handles the rest!)
	if map_def.starting_vehicles != null:
		_register_map_vehicles(map_def.starting_vehicles, tree)

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

		if GameManager.session.entities.has_vehicle(entry.vehicle_id):
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

		GameManager.session.entities.register_vehicle(
			entry.vehicle_id,
			entry.spec_id,
			start_pos,
			start_yaw,
			entry.fuel_level,
			entry.maintenance
		)
	GameLog.info("[MapManager] Map vehicles registered to GameManager.session.entities.")
