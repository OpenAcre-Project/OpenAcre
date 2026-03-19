extends Node

const PlayerDataRef = preload("res://Scripts/simulation/resources/PlayerData.gd")
const VehicleDataRef = preload("res://Scripts/simulation/resources/VehicleData.gd")

signal player_data_changed(player_id: StringName, data: PlayerData)
signal vehicle_data_changed(vehicle_id: StringName, data: VehicleData)

var _players: Dictionary = {}
var _vehicles: Dictionary = {}

func _ready() -> void:
	if TimeManager.has_signal("minute_passed") and not TimeManager.is_connected("minute_passed", Callable(self, "_on_minute_passed")):
		TimeManager.connect("minute_passed", Callable(self, "_on_minute_passed"))

func _on_minute_passed() -> void:
	for player_id_any: Variant in _players.keys():
		if player_id_any is StringName:
			var data: PlayerData = _players[player_id_any]
			data.tick_survival_minute()

func has_vehicle(vehicle_id: StringName) -> bool:
	return _vehicles.has(vehicle_id)

func ensure_player(player_id: StringName = &"player.main") -> PlayerData:
	if not _players.has(player_id):
		var data := PlayerDataRef.new()
		data.player_id = player_id
		_players[player_id] = data
	return _players[player_id]

func ensure_vehicle(vehicle_id: StringName) -> VehicleData:
	if vehicle_id == &"":
		GameLog.warn("SimulationCore.ensure_vehicle called with an empty id")
		vehicle_id = &"vehicle.unknown"

	if not _vehicles.has(vehicle_id):
		var data := VehicleDataRef.new()
		data.vehicle_id = vehicle_id
		_vehicles[vehicle_id] = data
	return _vehicles[vehicle_id]

func get_player(player_id: StringName = &"player.main") -> PlayerData:
	return ensure_player(player_id)

func get_vehicle(vehicle_id: StringName) -> VehicleData:
	return ensure_vehicle(vehicle_id)

func register_vehicle(
	vehicle_id: StringName,
	spec_id: StringName,
	world_position: Vector3,
	world_yaw_radians: float,
	fuel_level: float = 100.0,
	maintenance: float = 100.0
) -> VehicleData:
	var data := ensure_vehicle(vehicle_id)
	data.spec_id = spec_id
	data.set_transform(world_position, world_yaw_radians)
	data.fuel_level = fuel_level
	data.maintenance = maintenance
	vehicle_data_changed.emit(vehicle_id, data)
	return data

func get_vehicle_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key_any: Variant in _vehicles.keys():
		if key_any is StringName:
			ids.append(key_any)
	return ids

func set_player_transform(player_id: StringName, world_position: Vector3, world_yaw_radians: float) -> void:
	var data := ensure_player(player_id)
	data.set_transform(world_position, world_yaw_radians)
	player_data_changed.emit(player_id, data)

func set_player_stats(player_id: StringName, stamina: float, health: float) -> void:
	var data := ensure_player(player_id)
	data.stamina = stamina
	data.health = health
	player_data_changed.emit(player_id, data)

func set_player_active_vehicle(player_id: StringName, vehicle_id: StringName) -> void:
	var data := ensure_player(player_id)
	data.active_vehicle_id = vehicle_id
	player_data_changed.emit(player_id, data)

func set_vehicle_state(
	vehicle_id: StringName,
	world_position: Vector3,
	world_yaw_radians: float,
	speed_mps: float,
	occupant_player_id: StringName
) -> void:
	var data := ensure_vehicle(vehicle_id)
	data.set_transform(world_position, world_yaw_radians)
	data.speed_mps = speed_mps
	data.occupant_player_id = occupant_player_id
	vehicle_data_changed.emit(vehicle_id, data)

func set_vehicle_stats(vehicle_id: StringName, fuel_level: float, engine_temp_celsius: float) -> void:
	var data := ensure_vehicle(vehicle_id)
	data.fuel_level = fuel_level
	data.engine_temp_celsius = engine_temp_celsius
	vehicle_data_changed.emit(vehicle_id, data)

func set_vehicle_maintenance(vehicle_id: StringName, maintenance: float) -> void:
	var data := ensure_vehicle(vehicle_id)
	data.maintenance = maintenance
	vehicle_data_changed.emit(vehicle_id, data)

func get_nearby_vehicle_ids(center: Vector3, radius: float) -> Array[StringName]:
	var result: Array[StringName] = []
	if radius <= 0.0:
		return result

	var radius_sq := radius * radius
	for key_any: Variant in _vehicles.keys():
		if not (key_any is StringName):
			continue
		var vehicle_id := key_any as StringName
		var data: VehicleData = _vehicles[vehicle_id]
		if not data.has_world_transform:
			continue
		if data.world_position.distance_squared_to(center) <= radius_sq:
			result.append(vehicle_id)

	return result

func get_map_data_singleton() -> Node:
	return FarmData
