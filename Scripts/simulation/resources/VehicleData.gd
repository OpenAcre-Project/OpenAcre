extends Resource
class_name VehicleData

@export var vehicle_id: StringName = &""
@export var spec_id: StringName = &""
@export var has_world_transform: bool = false
@export var world_position: Vector3 = Vector3.ZERO
@export var world_yaw_radians: float = 0.0
@export var speed_mps: float = 0.0
@export var fuel_level: float = 100.0
@export var maintenance: float = 100.0
@export var engine_temp_celsius: float = 20.0
@export var occupant_player_id: StringName = &""

func set_transform(position: Vector3, yaw_radians: float) -> void:
	has_world_transform = true
	world_position = position
	world_yaw_radians = yaw_radians
