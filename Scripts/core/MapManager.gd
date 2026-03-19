extends Node

signal actors_spawned

var player_scene: PackedScene = preload("res://Scenes/Player.tscn")

func populate_world(world_root: Node3D) -> void:
	# 1. Wait a frame for the scene tree to settle and groups to register
	await get_tree().process_frame

	var map_def := get_tree().get_first_node_in_group("map_root") as MapDefinition
	if map_def == null:
		GameLog.warn("[MapManager] No MapDefinition found in map_root group!")
		return

	if map_def.region_mask != null:
		FarmData.set_active_region_mask(map_def.region_mask)
		GameLog.info("[MapManager] Registered MapRegionMask with FarmData")
	else:
		GameLog.warn("[MapManager] MapDefinition is missing a region_mask!")

	# 2. Spawn the Player
	_spawn_player(world_root)

	# 3. Register Vehicles (SimulationCore handles the rest!)
	if map_def.starting_vehicles != null:
		_register_map_vehicles(map_def.starting_vehicles)

	actors_spawned.emit()

func _spawn_player(parent_node: Node) -> void:
	var spawn_pts: Array[Node] = get_tree().get_nodes_in_group("spawn_points_player")
	var spawn_pos := Vector3(0, 5, 0)
	var spawn_yaw := 0.0

	# Find the designated player spawn point
	if spawn_pts.size() > 0:
		var pt: Node3D = spawn_pts[0] as Node3D
		spawn_pos = pt.global_position
		spawn_yaw = pt.global_rotation.y

	# Instantiate the Player
	var player: Node = player_scene.instantiate()
	parent_node.add_child(player)
	
	if player is Node3D:
		player.global_position = spawn_pos
		player.rotation.y = spawn_yaw

	# Immediately update SimulationCore so the camera and chunk streamers know where to look
	var player_id: StringName = &"player.main"
	if player.get("simulation_player_id") != null:
		player_id = player.get("simulation_player_id")
	
	SimulationCore.set_player_transform(player_id, spawn_pos, spawn_yaw)
	GameLog.info("[MapManager] Player dynamically spawned at " + str(spawn_pos))

func _register_map_vehicles(spawn_table: VehicleSpawnTable) -> void:
	var vehicle_markers: Array[Node] = get_tree().get_nodes_in_group("spawn_points_vehicle")
	
	for entry: VehicleSpawnEntry in spawn_table.entries:
		if entry == null or entry.vehicle_id == &"" or entry.spec_id == &"":
			continue

		if SimulationCore.has_vehicle(entry.vehicle_id):
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

		SimulationCore.register_vehicle(
			entry.vehicle_id,
			entry.spec_id,
			start_pos,
			start_yaw,
			entry.fuel_level,
			entry.maintenance
		)
	GameLog.info("[MapManager] Map vehicles registered to SimulationCore.")
