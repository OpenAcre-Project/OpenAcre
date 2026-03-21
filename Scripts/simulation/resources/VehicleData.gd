## [Data] The authoritative, persistent state of a vehicle.
## This class is purely data-driven (no 3D nodes) and handles:
## - Persistent world transform (Position/Yaw) for Save/Load
## - Simulation metrics (Fuel level, Speed, Engine status)
## - Inventory tanks (Slurry, Grain, Water, etc.)
## This object resides in the [SimulationCore] and persists even when the vehicle is not rendered.
extends Resource
class_name VehicleData

@export var vehicle_id: StringName = &""
@export var spec_id: StringName = &""
@export var has_world_transform: bool = false
@export var world_position: Vector3 = Vector3.ZERO
@export var world_yaw_radians: float = 0.0
@export var speed_mps: float = 0.0
@export var steering_input: float = 0.0
@export var fuel_level: float = 100.0
@export var maintenance: float = 100.0
@export var engine_temp_celsius: float = 20.0
@export var occupant_player_id: StringName = &""

# Mass and Storage
@export var base_mass: float = 1500.0 # Default empty mass
var cabin_storage: InventoryData = InventoryData.new()
var tanks: Dictionary = {} # StringName -> BulkTankData

func _init() -> void:
	# Default cabin storage settings
	cabin_storage.max_volume = 5.0
	cabin_storage.max_mass = 10.0

func ensure_tank(tank_id: StringName, max_vol: float, allowed_types: Array[StringName] = []) -> BulkTankData:
	if not tanks.has(tank_id):
		var new_tank: BulkTankData = BulkTankData.new()
		new_tank.max_volume = max_vol
		new_tank.allowed_commodities = allowed_types
		tanks[tank_id] = new_tank
	return tanks[tank_id]

func get_total_vehicle_mass() -> float:
	var total := base_mass
	total += cabin_storage.get_current_mass()
	for tank_id: StringName in tanks:
		var tank: BulkTankData = tanks[tank_id]
		total += tank.get_current_mass()
	return total

func set_transform(position: Vector3, yaw_radians: float) -> void:
	has_world_transform = true
	world_position = position
	world_yaw_radians = yaw_radians
