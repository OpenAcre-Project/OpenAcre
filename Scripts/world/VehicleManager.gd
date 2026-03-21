## [Manager] The central controller for vehicle "streaming" and spawning.
## This class handles:
## - Monitoring player proximity to logical vehicles
## - Spawning/Despawning 3D [Vehicle3D] instances based on render radius
## - Synchronizing persistent simulation data to physical world nodes
extends Node3D

@export var vehicle_catalog: VehicleCatalog
@export var load_radius: float = 160.0
@export var unload_radius: float = 220.0
@export var stream_update_interval_seconds := 0.4

var _stream_target: Node3D = null
var _stream_timer := 0.0
var _spawned_vehicles: Dictionary = {}
var _failed_spawn_ids: Dictionary = {}
var _runtime_spawn_serial := 0

func _ready() -> void:
	add_to_group("vehicle_manager")
	_bind_stream_target()
	_refresh_streamed_vehicles(true)

func _process(delta: float) -> void:
	_stream_timer += delta
	if _stream_timer < stream_update_interval_seconds:
		return

	_stream_timer = 0.0
	_refresh_streamed_vehicles()

func _bind_stream_target() -> void:
	var first_player := get_tree().get_first_node_in_group("player")
	if first_player is Node3D:
		_stream_target = first_player

func _refresh_streamed_vehicles(force_refresh: bool = false) -> void:
	if _stream_target == null or not is_instance_valid(_stream_target):
		_bind_stream_target()
	if _stream_target == null:
		return

	var center := _stream_target.global_position
	var nearby_vehicle_ids := GameManager.session.entities.get_nearby_vehicle_ids(center, load_radius)
	var desired: Dictionary = {}
	for vehicle_id: StringName in nearby_vehicle_ids:
		desired[vehicle_id] = true
		if not _spawned_vehicles.has(vehicle_id) and not _failed_spawn_ids.has(vehicle_id):
			_spawn_vehicle(vehicle_id)
		elif force_refresh:
			_sync_spawned_vehicle_transform(vehicle_id)

	for vehicle_id_any: Variant in _spawned_vehicles.keys():
		if not (vehicle_id_any is StringName):
			continue
		var vehicle_id := vehicle_id_any as StringName
		if desired.has(vehicle_id):
			continue

		var vehicle_data := GameManager.session.entities.get_vehicle(vehicle_id)
		var distance_sq := vehicle_data.world_position.distance_squared_to(center)
		if distance_sq > unload_radius * unload_radius:
			_despawn_vehicle(vehicle_id)

func _spawn_vehicle(vehicle_id: StringName) -> void:
	if vehicle_catalog == null:
		GameLog.warn("VehicleManager has no vehicle_catalog assigned")
		_failed_spawn_ids[vehicle_id] = true
		return

	var vehicle_data := GameManager.session.entities.get_vehicle(vehicle_id)
	var spec := vehicle_catalog.get_spec(vehicle_data.spec_id)
	if spec == null:
		GameLog.warn("Missing VehicleSpec for id: %s (vehicle: %s)" % [String(vehicle_data.spec_id), String(vehicle_id)])
		_failed_spawn_ids[vehicle_id] = true
		return
	if spec.vehicle_scene == null:
		GameLog.warn("VehicleSpec scene is null for id: %s (vehicle: %s)" % [String(vehicle_data.spec_id), String(vehicle_id)])
		_failed_spawn_ids[vehicle_id] = true
		return

	var instance := spec.vehicle_scene.instantiate()
	if instance == null:
		return

	# Set the simulation ID BEFORE adding to tree so Vehicle3D._ready()
	# sees the correct ID and finds the pre-registered SimulationCore entry.
	if instance.get("simulation_vehicle_id") != null:
		instance.set("simulation_vehicle_id", vehicle_id)

	_apply_vehicle_overrides(instance, spec.property_overrides)

	if instance is Node3D:
		var node3d := instance as Node3D
		# Use local position/rotation rather than global when the node 
		# is not inside the scene tree yet, to avoid Transform3D errors.
		node3d.position = vehicle_data.world_position
		node3d.rotation.y = vehicle_data.world_yaw_radians

	add_child(instance)
	_spawned_vehicles[vehicle_id] = instance

func adopt_vehicle(vehicle_id: StringName, instance: Node) -> void:
	_spawned_vehicles[vehicle_id] = instance

func _despawn_vehicle(vehicle_id: StringName) -> void:
	if not _spawned_vehicles.has(vehicle_id):
		return

	var instance: Node = _spawned_vehicles[vehicle_id]
	if is_instance_valid(instance):
		instance.queue_free()
	_spawned_vehicles.erase(vehicle_id)

func _sync_spawned_vehicle_transform(vehicle_id: StringName) -> void:
	if not _spawned_vehicles.has(vehicle_id):
		return

	var instance: Node = _spawned_vehicles[vehicle_id]
	if not is_instance_valid(instance):
		_spawned_vehicles.erase(vehicle_id)
		return

	if not (instance is Node3D):
		return

	var vehicle_data := GameManager.session.entities.get_vehicle(vehicle_id)
	
	if instance.has_method("teleport"):
		instance.call("teleport", vehicle_data.world_position, vehicle_data.world_yaw_radians)
	else:
		var node3d := instance as Node3D
		node3d.global_position = vehicle_data.world_position
		node3d.rotation.y = vehicle_data.world_yaw_radians

func _apply_vehicle_overrides(instance: Node, overrides: Dictionary) -> void:
	for key_any: Variant in overrides.keys():
		if not (key_any is String or key_any is StringName):
			continue

		var property_name := StringName(String(key_any))
		var value: Variant = overrides[key_any]
		if _has_property(instance, property_name):
			instance.set(property_name, value)

func get_spawnable_brands() -> Array[String]:
	if vehicle_catalog == null:
		return []
	return vehicle_catalog.get_brand_names()

func get_spawnable_spec_ids() -> Array[StringName]:
	if vehicle_catalog == null:
		return []
	return vehicle_catalog.get_spec_ids()

func spawn_vehicle_by_brand(brand: String, world_position: Vector3, world_yaw_radians: float = 0.0) -> StringName:
	if vehicle_catalog == null:
		return &""

	var specs := vehicle_catalog.get_specs_by_brand(brand)
	if specs.is_empty():
		return &""

	var spec := specs[0]
	var vehicle_id := _generate_runtime_vehicle_id(brand)
	GameManager.session.entities.register_vehicle(vehicle_id, spec.spec_id, world_position, world_yaw_radians, 100.0, 100.0)
	_spawn_vehicle(vehicle_id)
	return vehicle_id

func spawn_vehicle_by_spec(spec_id: StringName, world_position: Vector3, world_yaw_radians: float = 0.0) -> StringName:
	if vehicle_catalog == null:
		return &""

	var spec := vehicle_catalog.get_spec(spec_id)
	if spec == null:
		return &""

	var vehicle_id := _generate_runtime_vehicle_id(String(spec.spec_id))
	GameManager.session.entities.register_vehicle(vehicle_id, spec.spec_id, world_position, world_yaw_radians, 100.0, 100.0)
	_spawn_vehicle(vehicle_id)
	return vehicle_id

func _generate_runtime_vehicle_id(brand: String) -> StringName:
	_runtime_spawn_serial += 1
	var normalized := brand.strip_edges().to_lower()
	if normalized.is_empty():
		normalized = "vehicle"
	var stamp := Time.get_unix_time_from_system()
	return StringName("vehicle.runtime.%s.%d.%d" % [normalized, stamp, _runtime_spawn_serial])

func _has_property(instance: Object, property_name: StringName) -> bool:
	for property_info: Dictionary in instance.get_property_list():
		if StringName(String(property_info.get("name", ""))) == property_name:
			return true
	return false
