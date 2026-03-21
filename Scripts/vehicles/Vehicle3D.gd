## [Instance] The physical 3D representation of a vehicle in the world.
## This class handles: 
## - Visual mesh rendering (wrapping GEVP)
## - Camera controls & Input processing
## - Interpolation between simulation frames
## - In-game interaction (entering/exiting)
extends Vehicle
class_name Vehicle3D

const VehicleSeatControllerRef = preload("res://Scripts/vehicles/VehicleSeatController.gd")
const OrbitCameraControllerRef = preload("res://Scripts/camera/OrbitCameraController.gd")

@export var camera_vertical_speed := 3.0
@export var mouse_sensitivity := 0.002
@export var simulation_vehicle_id: StringName = &""
@export var vehicle_spec_id: StringName = &""
@export var initial_fuel_level := 100.0
@export var initial_engine_temp_celsius := 20.0
@export var camera_height_min := 1.4
@export var camera_height_max := 4.0
@export var camera_zoom_step := 0.5
@export var camera_zoom_min := 2.5
@export var camera_zoom_max := 10.0
@export var camera_follow_smooth_speed := 10.0
@export var camera_pitch_min_degrees := -70.0
@export var camera_pitch_max_degrees := 25.0
@export var camera_auto_center_delay := 1.0
@export var camera_auto_center_speed := 2.0
@export var steering_sensitivity := 2.5
@export var steering_return_speed := 0.25
@export_enum("X", "Y", "Z") var front_visual_steering_axis: int = 1
@export_enum("X", "Y", "Z") var visual_spin_axis: int = 0
@export var invert_visual_steering_direction := false
@export var enforce_deterministic_drive_direction := true
@export var reverse_shift_speed_threshold := 0.75

@export var wheel_front_left_visual_path := NodePath("VehicleVisual/Wheels/WheelFL")
@export var wheel_front_right_visual_path := NodePath("VehicleVisual/Wheels/WheelFR")
@export var wheel_rear_left_visual_path := NodePath("VehicleVisual/Wheels/WheelRL")
@export var wheel_rear_right_visual_path := NodePath("VehicleVisual/Wheels/WheelRR")

var is_driven: bool = false
var can_exit: bool = false
var driver_player: CharacterBody3D = null
var _camera_controller: OrbitCameraController
var _steering_target: float = 0.0
var _resolved_simulation_vehicle_id: StringName = &""

@onready var wheel_front_left: Wheel = $WheelFrontLeft
@onready var wheel_front_right: Wheel = $WheelFrontRight
@onready var wheel_rear_left: Wheel = $WheelRearLeft
@onready var wheel_rear_right: Wheel = $WheelRearRight
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var exit_point: Node3D = $ExitPoint

func _ready() -> void:
	if torque_curve == null:
		torque_curve = Curve.new()
		torque_curve.add_point(Vector2(0.0, 1.0))
		torque_curve.add_point(Vector2(1.0, 1.0))
		
	_resolved_simulation_vehicle_id = _resolve_vehicle_id()
	_configure_wheel_visual_bindings()
	var vehicle_already_registered := GameManager.session.entities.has_vehicle(_resolved_simulation_vehicle_id)

	super._ready()
	camera.current = false
	_camera_controller = OrbitCameraControllerRef.new()
	add_child(_camera_controller)
	_camera_controller.setup(spring_arm, camera)
	_camera_controller.follow_smooth_speed = camera_follow_smooth_speed
	_camera_controller.zoom_min = camera_zoom_min
	_camera_controller.zoom_max = camera_zoom_max
	_camera_controller.height_min = camera_height_min
	_camera_controller.height_max = camera_height_max
	_camera_controller.is_auto_center_enabled = true
	_camera_controller.auto_center_delay = camera_auto_center_delay
	_camera_controller.auto_center_speed = camera_auto_center_speed

	if vehicle_already_registered:
		_sync_from_simulation_core()
	else:
		GameManager.session.entities.register_vehicle(
			_resolved_simulation_vehicle_id,
			vehicle_spec_id,
			global_position,
			rotation.y,
			initial_fuel_level,
			100.0
		)
		GameManager.session.entities.set_vehicle_stats(_resolved_simulation_vehicle_id, initial_fuel_level, initial_engine_temp_celsius)
		
	var vehicle_manager := get_tree().get_first_node_in_group("vehicle_manager")
	if vehicle_manager != null and vehicle_manager.has_method("adopt_vehicle"):
		vehicle_manager.adopt_vehicle(_resolved_simulation_vehicle_id, self)

	_publish_vehicle_state_to_simulation_core()
	_sync_physics_mass()
	
	GameManager.session.entities.vehicle_data_changed.connect(_on_simulation_vehicle_data_changed)

func _on_simulation_vehicle_data_changed(id: StringName, _data: VehicleData) -> void:
	if id == _resolved_simulation_vehicle_id:
		_sync_physics_mass()

func _sync_physics_mass() -> void:
	var data := GameManager.session.entities.get_vehicle(_resolved_simulation_vehicle_id)
	if data:
		var new_mass := data.get_total_vehicle_mass()
		if not is_equal_approx(mass, new_mass):
			mass = new_mass
			
			# Pull the center of mass down to simulate low-slung tanks/chassis weight
			# Every 1000kg of added weight lowers the CoM by 0.1 meters
			var added_mass := maxf(0.0, mass - data.base_mass)
			center_of_mass = Vector3(0.0, -0.2 - (added_mass * 0.0001), 0.0)
			
			sleeping = false

func _unhandled_input(event: InputEvent) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if not is_driven:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_controller.handle_mouse_motion(event.relative)

	if event is InputEventMouseButton:
		if event.is_action_pressed(GameInput.ACTION_CAMERA_ZOOM_IN):
			_camera_controller.adjust_zoom(false)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(GameInput.ACTION_CAMERA_ZOOM_OUT):
			_camera_controller.adjust_zoom(true)
			get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		steering_input = 0.0
		throttle_input = 0.0
		brake_input = 1.0
		handbrake_input = 1.0
		clutch_input = 0.0
		super._physics_process(delta)
		_publish_vehicle_state_to_simulation_core()
		_sync_driver_position_to_vehicle()
		return

	if is_driven:
		var throttle_strength := Input.get_action_strength(GameInput.ACTION_VEHICLE_THROTTLE)
		var reverse_strength := Input.get_action_strength(GameInput.ACTION_VEHICLE_REVERSE)

		if enforce_deterministic_drive_direction:
			_sync_drive_gear_intent(throttle_strength, reverse_strength)

		# Realistic Accumulative Steering
		var steer_raw := Input.get_action_strength(GameInput.ACTION_VEHICLE_STEER_LEFT) - Input.get_action_strength(GameInput.ACTION_VEHICLE_STEER_RIGHT)
		
		# We use the absolute speed to scale the return-to-center force
		var current_speed := absf(speed)
		
		if abs(steer_raw) > 0.05:
			# At higher speeds, we slightly increase sensitivity to overcome GEVP's internal smoothing
			var speed_factor := clampf(current_speed * 0.05, 1.0, 2.0)
			_steering_target += steer_raw * (steering_sensitivity * speed_factor) * delta
		else:
			# Caster effect: the faster we go, the more the wheels want to straighten out
			var return_force := steering_return_speed * (0.5 + current_speed * 0.1)
			_steering_target = move_toward(_steering_target, 0.0, return_force * delta)
		
		_steering_target = clamp(_steering_target, -1.0, 1.0)
		steering_input = _steering_target

		throttle_input = throttle_strength
		brake_input = reverse_strength
		handbrake_input = Input.get_action_strength(GameInput.ACTION_VEHICLE_BRAKE)
		clutch_input = handbrake_input

		if current_gear == -1:
			throttle_input = reverse_strength
			brake_input = throttle_strength
	else:
		# When not driven, we keep the last steering target
		# so the wheels stay turned.
		steering_input = _steering_target
		throttle_input = 0.0
		brake_input = 1.0
		handbrake_input = 1.0
		clutch_input = 0.0

	super._physics_process(delta)

	if not is_driven:
		return

	_camera_controller.update(delta, GameInput.is_gameplay_input_blocked(get_tree()))
	_publish_vehicle_state_to_simulation_core()
	_sync_driver_position_to_vehicle()

func _input(event: InputEvent) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if is_driven and can_exit and GameInput.is_interact_event(event):
		get_viewport().set_input_as_handled()
		exit_vehicle()

func interact(player: Node3D) -> void:
	if not is_driven:
		enter_vehicle(player)

func get_interaction_prompt() -> String:
	return "Drive Vehicle [%s]" % GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)

func enter_vehicle(player: Node3D) -> void:
	is_driven = true
	can_exit = false
	driver_player = player
	requested_gear = 0
	current_gear = 0
	throttle_input = 0.0
	brake_input = 0.0
	handbrake_input = 0.0
	clutch_input = 0.0

	if driver_player is CharacterBody3D:
		VehicleSeatControllerRef.enter_vehicle(driver_player, camera)
		GameManager.session.entities.set_player_active_vehicle(_get_driver_player_id(), _resolved_simulation_vehicle_id)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	await get_tree().create_timer(0.5).timeout
	can_exit = true

func exit_vehicle() -> void:
	is_driven = false

	if driver_player:
		if driver_player is CharacterBody3D:
			GameManager.session.entities.set_player_active_vehicle(_get_driver_player_id(), &"")
			VehicleSeatControllerRef.exit_vehicle(driver_player, exit_point)
		driver_player = null

		await get_tree().create_timer(0.1).timeout

func _sync_drive_gear_intent(throttle_strength: float, reverse_strength: float) -> void:
	if is_shifting:
		return

	if throttle_strength > 0.05 and reverse_strength < 0.05:
		if current_gear < 0:
			shift(1)
		elif current_gear == 0:
			shift(1)
		return

	if reverse_strength > 0.05 and throttle_strength < 0.05 and speed <= reverse_shift_speed_threshold:
		if current_gear > 0:
			shift(-1)
		elif current_gear == 0:
			shift(-1)

func teleport(world_position: Vector3, world_yaw_radians: float) -> void:
	global_position = world_position
	rotation.y = world_yaw_radians
	reset_physics_state()

func reset_physics_state() -> void:
	# Reset body velocities
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Godot Advanced Vehicle Physics (GEVP) wheels track their previous_global_position. 
	# When forcibly moving the vehicle, we must reset their state so they don't calculate
	# a massive velocity spike that shoots the vehicle into space.
	if wheel_front_left: wheel_front_left.previous_global_position = wheel_front_left.global_position
	if wheel_front_right: wheel_front_right.previous_global_position = wheel_front_right.global_position
	if wheel_rear_left: wheel_rear_left.previous_global_position = wheel_rear_left.global_position
	if wheel_rear_right: wheel_rear_right.previous_global_position = wheel_rear_right.global_position

func _sync_from_simulation_core() -> void:
	var vehicle_data := GameManager.session.entities.get_vehicle(_resolved_simulation_vehicle_id)
	if not vehicle_data.has_world_transform:
		return

	_steering_target = vehicle_data.steering_input
	steering_input = _steering_target
	teleport(vehicle_data.world_position, vehicle_data.world_yaw_radians)

func _publish_vehicle_state_to_simulation_core() -> void:
	var occupant_player_id: StringName = &""
	if is_driven:
		occupant_player_id = _get_driver_player_id()

	GameManager.session.entities.set_vehicle_state(
		_resolved_simulation_vehicle_id,
		global_position,
		rotation.y,
		linear_velocity.length(),
		steering_input,
		occupant_player_id
	)

## Keep the driver Player node's position in sync with the vehicle.
## The Player's process_mode is DISABLED while seated, so it cannot
## update itself. The vehicle takes responsibility for keeping the
## Player's global_position and SimulationCore data authoritative.
func _sync_driver_position_to_vehicle() -> void:
	if not is_driven or driver_player == null:
		return
	driver_player.global_position = global_position
	var player_id := _get_driver_player_id()
	if player_id != &"":
		GameManager.session.entities.set_player_transform(player_id, global_position, rotation.y)

func _resolve_vehicle_id() -> StringName:
	if simulation_vehicle_id != &"":
		return simulation_vehicle_id

	var path_id := str(get_path()).replace("/", ".")
	if path_id.begins_with("."):
		path_id = path_id.substr(1)
	return StringName("vehicle." + path_id)

func _get_driver_player_id() -> StringName:
	if driver_player == null:
		return &""

	var player_id_any: Variant = driver_player.get("simulation_player_id")
	if player_id_any is StringName:
		return player_id_any
	if player_id_any is String:
		return StringName(player_id_any)

	return &"player.main"

func _configure_wheel_visual_bindings() -> void:
	_bind_wheel_visual_node(wheel_front_left, wheel_front_left_visual_path)
	_bind_wheel_visual_node(wheel_front_right, wheel_front_right_visual_path)
	_bind_wheel_visual_node(wheel_rear_left, wheel_rear_left_visual_path)
	_bind_wheel_visual_node(wheel_rear_right, wheel_rear_right_visual_path)

	var visual_steer_multiplier := -1.0 if invert_visual_steering_direction else 1.0
	wheel_front_left.visual_steering_multiplier = visual_steer_multiplier
	wheel_front_right.visual_steering_multiplier = visual_steer_multiplier
	wheel_front_left.visual_steering_axis = front_visual_steering_axis
	wheel_front_right.visual_steering_axis = front_visual_steering_axis

	wheel_front_left.visual_spin_axis = visual_spin_axis
	wheel_front_right.visual_spin_axis = visual_spin_axis
	wheel_rear_left.visual_spin_axis = visual_spin_axis
	wheel_rear_right.visual_spin_axis = visual_spin_axis

func _bind_wheel_visual_node(wheel: Wheel, visual_path: NodePath) -> void:
	if wheel == null:
		return
	if visual_path == NodePath(""):
		return
	if not has_node(visual_path):
		return

	var visual_node: Node = get_node(visual_path)
	if visual_node is Node3D:
		wheel.wheel_node = visual_node as Node3D
