## [Instance] The physical 3D representation of a vehicle in the world.
## This class handles: 
## - Visual mesh rendering (wrapping GEVP)
## - Camera controls & Input processing
## - Interpolation between simulation frames
## - In-game interaction (entering/exiting)
@tool
extends Vehicle
class_name Vehicle3D

const VehicleSeatControllerRef = preload("res://Scripts/vehicles/VehicleSeatController.gd")
const OrbitCameraControllerRef = preload("res://Scripts/camera/OrbitCameraController.gd")

@export var camera_vertical_speed := 3.0
@export var mouse_sensitivity := 0.002

@export var camera_height_min := 1.4
@export var camera_height_max := 4.0
@export var camera_zoom_step := 0.5
@export var camera_zoom_min := 2.5
@export var camera_zoom_max := 10.0
@export var camera_follow_smooth_speed := 10.0
@export var camera_pitch_min_degrees := -70.0
@export var camera_pitch_max_degrees := 25.0
@export var camera_auto_center_delay := 0.0
@export var camera_auto_center_speed_factor := 0.2
@export var steering_sensitivity := 2.5
@export var steering_return_speed := 1.0
@export var hitch_detection_radius_fallback: float = 3.0
@export var hitch_debug_visual_enabled: bool = true
@export var hitch_face_implement_away_from_vehicle: bool = true
@export var hitch_offset_lowered: float = 0.0
@export var hitch_offset_raised: float = 0.45
@export var hitch_animation_duration: float = 0.5
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

var _available_sockets: Array[HitchSocket3D] = []
var active_socket_index: int = 0


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
		
	_configure_wheel_visual_bindings()
	_register_sockets(self)

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
	_camera_controller.is_auto_center_enabled = false
	_camera_controller.is_velocity_alignment_enabled = true
	_camera_controller.auto_center_delay = camera_auto_center_delay
	_camera_controller.velocity_alignment_factor = camera_auto_center_speed_factor

	# Improve traction parameters for off-road surfaces
	tire_stiffnesses["Dirt"] = 8.0
	tire_stiffnesses["Grass"] = 8.0
	coefficient_of_friction["Dirt"] = 8.0
	coefficient_of_friction["Grass"] = 7.0
	lateral_grip_assist["Dirt"] = 2.5
	lateral_grip_assist["Grass"] = 2.5
	longitudinal_grip_ratio["Dirt"] = 0.95
	longitudinal_grip_ratio["Grass"] = 0.95



	# Debugging physical collisions
	contact_monitor = true
	max_contacts_reported = 8
	print("[Vehicle3D] Collision debug system started on: ", name)

func _register_sockets(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is HitchSocket3D:
			var socket := child as HitchSocket3D
			_available_sockets.append(socket)
			socket.implement_attached.connect(_on_implement_attached.bind(socket))
			socket.implement_detached.connect(_on_implement_detached.bind(socket))
		else:
			_register_sockets(child)

func _on_implement_attached(implement: RigidBody3D, _socket: HitchSocket3D) -> void:
	add_collision_exception_with(implement)
	# Streaming assignments now happen at HitchSocket3D level
	pass

func _on_implement_detached(implement: RigidBody3D, _socket: HitchSocket3D) -> void:
	remove_collision_exception_with(implement)
	pass

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return



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
			var return_force := steering_return_speed * current_speed * 0.1
			_steering_target = move_toward(_steering_target, 0.0, return_force * delta)
		
		_steering_target = clamp(_steering_target, -1.0, 1.0)
		steering_input = _steering_target

		throttle_input = throttle_strength
		brake_input = reverse_strength
		
		# Idle brake: apply brakes if stationary and no input
		if throttle_strength < 0.05 and reverse_strength < 0.05 and current_speed < 0.5:
			brake_input = 0.5
			handbrake_input = 1.0
		else:
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
	_sync_driver_position_to_vehicle()

func _input(event: InputEvent) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if is_driven and can_exit:
		if GameInput.is_interact_event(event):
			get_viewport().set_input_as_handled()
			exit_vehicle()
		elif event.is_action_pressed(GameInput.ACTION_ATTACH_IMPLEMENT):
			_toggle_attachment()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(GameInput.ACTION_LOWER_IMPLEMENT):
			var active_socket: HitchSocket3D = _get_active_socket()
			if active_socket:
				active_socket.on_lower_command()
				_update_hints()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(GameInput.ACTION_TOGGLE_IMPLEMENT):
			var active_socket: HitchSocket3D = _get_active_socket()
			if active_socket:
				active_socket.on_pto_command()
				_update_hints()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(GameInput.ACTION_CYCLE_IMPLEMENT):
			if _available_sockets.size() > 1:
				active_socket_index = (active_socket_index + 1) % _available_sockets.size()
				_update_hints()
			get_viewport().set_input_as_handled()

func _get_active_socket() -> HitchSocket3D:
	if active_socket_index < _available_sockets.size() and active_socket_index >= 0:
		return _available_sockets[active_socket_index]
	return null

func interact(player: Node3D) -> void:
	if not is_driven:
		enter_vehicle(player)

func get_interaction_prompt() -> String:
	return "Drive Vehicle [%s]" % GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)

## UESS: Called by StreamSpooler when this node enters the world.
## Reads VehicleComponent data to initialize physical state.
func apply_data(data: EntityData) -> void:
	super.apply_data(data)
	reset_physics_state()

	var vc: VehicleComponent = entity_data.get_component(&"vehicle") as VehicleComponent
	if vc:
		if "fuel_level" in self:
			set("fuel_level", vc.fuel_level)
		if "engine_temp" in self:
			set("engine_temp", vc.engine_temp_celsius)

## UESS: Called by StreamSpooler right before destroying the node.
## Writes current physical state back to VehicleComponent.
func extract_data() -> void:
	super.extract_data()
	if not entity_data: return

	var vc: VehicleComponent = entity_data.get_component(&"vehicle") as VehicleComponent
	if vc:
		if "fuel_level" in self:
			vc.fuel_level = get("fuel_level")
		if "engine_temp" in self:
			vc.engine_temp_celsius = get("engine_temp")

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
		if entity_data:
			var em := GameManager.session.entities as EntityManager
			var p_id := StringName(driver_player.name) if driver_player.name == "player.main" else &"player.main"
			em.set_player_active_vehicle(p_id, entity_data.runtime_id)
			
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	await get_tree().create_timer(0.5).timeout
	can_exit = true
	_update_hints()

func exit_vehicle() -> void:
	is_driven = false
	can_exit = false
	EventBus.update_vehicle_hints.emit(false, [])
	_clear_active_vehicle_owner()

	if driver_player:
		if driver_player is CharacterBody3D:
			VehicleSeatControllerRef.exit_vehicle(driver_player, _get_exit_anchor())
		driver_player = null

		await get_tree().create_timer(0.1).timeout

func force_eject() -> void:
	# Synchronous emergency exit used by streaming/destruction paths.
	EventBus.update_vehicle_hints.emit(false, [])
	_clear_active_vehicle_owner()

	if driver_player and driver_player is CharacterBody3D:
		VehicleSeatControllerRef.exit_vehicle(driver_player, _get_exit_anchor())

	driver_player = null
	is_driven = false
	can_exit = false

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
	extract_data()

func reset_physics_state() -> void:
	# Reset body velocities
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	local_velocity = Vector3.ZERO
	speed = 0.0

	if not is_inside_tree():
		previous_global_position = position
		return

	previous_global_position = global_position
	
	# Godot Advanced Vehicle Physics (GEVP) wheels track their previous_global_position. 
	# When forcibly moving the vehicle, we must reset their state so they don't calculate
	# a massive velocity spike that shoots the vehicle into space.
	if wheel_front_left: wheel_front_left.previous_global_position = wheel_front_left.global_position
	if wheel_front_right: wheel_front_right.previous_global_position = wheel_front_right.global_position
	if wheel_rear_left: wheel_rear_left.previous_global_position = wheel_rear_left.global_position
	if wheel_rear_right: wheel_rear_right.previous_global_position = wheel_rear_right.global_position



func _get_current_hints() -> Array[String]:
	var hints: Array[String] = []
	var active_socket: HitchSocket3D = _get_active_socket()
	
	if active_socket == null:
		return hints

	var socket_name := str(active_socket.name).replace("_", " ")
	hints.append("--- Active: %s ---" % socket_name)

	if _available_sockets.size() > 1:
		hints.append("[%s] Cycle Implement" % GameInput.get_action_binding_text(GameInput.ACTION_CYCLE_IMPLEMENT))

	if not active_socket.has_attached_implement():
		var candidate: Implement3D = active_socket.find_attach_candidate(hitch_detection_radius_fallback)
		if candidate != null:
			hints.append("[%s] Attach Implement" % GameInput.get_action_binding_text(GameInput.ACTION_ATTACH_IMPLEMENT))
	else:
		hints.append("[%s] Detach Implement" % GameInput.get_action_binding_text(GameInput.ACTION_ATTACH_IMPLEMENT))
		
		var imp: Implement3D = active_socket.get_attached_implement()
		var is_lowered: bool = imp.is_currently_lowered() if (imp and imp.has_method("is_currently_lowered")) else false
		var lower_text: String = "Raise" if is_lowered else "Lower"
		hints.append("[%s] %s Implement" % [GameInput.get_action_binding_text(GameInput.ACTION_LOWER_IMPLEMENT), lower_text])
		
		var is_pto: bool = imp.is_active if (imp and "is_active" in imp) else false
		var pto_text: String = "Turn Off PTO" if is_pto else "Turn On PTO"
		hints.append("[%s] %s" % [GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_IMPLEMENT), pto_text])
	return hints

func _update_hints() -> void:
	if is_driven:
		EventBus.update_vehicle_hints.emit(true, _get_current_hints())

func _toggle_attachment() -> void:
	var active_socket: HitchSocket3D = _get_active_socket()
	if active_socket == null: return
	
	if active_socket.has_attached_implement():
		active_socket.detach()
	else:
		var candidate: Implement3D = active_socket.find_attach_candidate(hitch_detection_radius_fallback)
		if candidate != null:
			active_socket.attach(candidate)
	_update_hints()

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

func _get_runtime_id() -> StringName:
	if entity_data: return entity_data.runtime_id
	return &""

func _get_exit_anchor() -> Node3D:
	if is_instance_valid(exit_point):
		return exit_point
	return self

func _clear_active_vehicle_owner() -> void:
	if not entity_data:
		return
	if not GameManager.session or not GameManager.session.entities:
		return

	var em := GameManager.session.entities as EntityManager
	var player_id := _get_driver_player_id()
	if player_id != &"":
		em.set_player_active_vehicle(player_id, &"")
		return

	var fallback_player := em.get_player(&"player.main")
	if fallback_player != null and fallback_player.active_vehicle_id == entity_data.runtime_id:
		em.set_player_active_vehicle(&"player.main", &"")

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
