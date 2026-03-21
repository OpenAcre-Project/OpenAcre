extends ArcadeDriveMechanics

const VehicleSeatControllerRef = preload("res://Scripts/vehicles/VehicleSeatController.gd")

@export var mouse_sensitivity: float = 0.002
@export var simulation_vehicle_id: StringName = &""
@export var initial_fuel_level := 100.0
@export var initial_engine_temp_celsius := 20.0
@export var camera_vertical_speed: float = 3.0
@export var camera_height_min: float = 1.4
@export var camera_height_max: float = 4.0
@export var camera_zoom_step: float = 0.5
@export var camera_zoom_min: float = 2.5
@export var camera_zoom_max: float = 10.0
@export var camera_follow_smooth_speed: float = 10.0
@export var camera_pitch_min_degrees: float = -70.0
@export var camera_pitch_max_degrees: float = 25.0

var driver_player: CharacterBody3D = null
var can_exit: bool = false
var _camera_target_height := 2.4
var _camera_target_distance := 6.0
var _resolved_simulation_vehicle_id: StringName = &""

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var exit_point: Node3D = $ExitPoint

func _ready() -> void:
	_resolved_simulation_vehicle_id = _resolve_vehicle_id()
	super._ready()
	_camera_target_height = spring_arm.position.y
	_camera_target_distance = spring_arm.spring_length
	camera.current = false # Let the player camera be active by default
	_sync_from_simulation_core()
	GameManager.session.entities.set_vehicle_stats(_resolved_simulation_vehicle_id, initial_fuel_level, initial_engine_temp_celsius)
	_publish_vehicle_state_to_simulation_core()

func _unhandled_input(event: InputEvent) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if not is_driven:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(
			spring_arm.rotation.x,
			deg_to_rad(camera_pitch_min_degrees),
			deg_to_rad(camera_pitch_max_degrees)
		)

	if event is InputEventMouseButton:
		if event.is_action_pressed(GameInput.ACTION_CAMERA_ZOOM_IN):
			_camera_target_distance = clamp(_camera_target_distance - camera_zoom_step, camera_zoom_min, camera_zoom_max)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(GameInput.ACTION_CAMERA_ZOOM_OUT):
			_camera_target_distance = clamp(_camera_target_distance + camera_zoom_step, camera_zoom_min, camera_zoom_max)
			get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		_publish_vehicle_state_to_simulation_core()
		return

	super._physics_process(delta)
	if not is_driven:
		_publish_vehicle_state_to_simulation_core()
		return

	if Input.is_action_pressed(GameInput.ACTION_CAMERA_UP):
		_camera_target_height += camera_vertical_speed * delta
	if Input.is_action_pressed(GameInput.ACTION_CAMERA_DOWN):
		_camera_target_height -= camera_vertical_speed * delta

	_camera_target_height = clamp(_camera_target_height, camera_height_min, camera_height_max)
	_camera_target_distance = clamp(_camera_target_distance, camera_zoom_min, camera_zoom_max)

	spring_arm.position.y = lerp(spring_arm.position.y, _camera_target_height, camera_follow_smooth_speed * delta)
	spring_arm.spring_length = lerp(spring_arm.spring_length, _camera_target_distance, camera_follow_smooth_speed * delta)
	_publish_vehicle_state_to_simulation_core()

func _input(event: InputEvent) -> void:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if is_driven and can_exit and GameInput.is_interact_event(event):
		get_viewport().set_input_as_handled()
		exit_vehicle()

func interact(player: Node3D) -> void:
	if not is_driven:
		GameLog.info("TestBoxVehicle Interacted!")
		enter_vehicle(player)

func get_interaction_prompt() -> String:
	return "Drive Box Vehicle [%s]" % GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)

func enter_vehicle(player: Node3D) -> void:
	set_driven_state(true)
	can_exit = false
	driver_player = player

	if driver_player is CharacterBody3D:
		VehicleSeatControllerRef.enter_vehicle(driver_player, camera)
		GameManager.session.entities.set_player_active_vehicle(_get_driver_player_id(), _resolved_simulation_vehicle_id)
	GameLog.info("Entered TestBoxVehicle")

	await get_tree().create_timer(0.4).timeout
	can_exit = true

func exit_vehicle() -> void:
	set_driven_state(false)
	can_exit = false
	GameLog.info("Exited TestBoxVehicle")
	
	if driver_player:
		if driver_player is CharacterBody3D:
			GameManager.session.entities.set_player_active_vehicle(_get_driver_player_id(), &"")
			VehicleSeatControllerRef.exit_vehicle(driver_player, exit_point)
		driver_player = null
		
		await get_tree().create_timer(0.1).timeout

func _sync_from_simulation_core() -> void:
	var vehicle_data := GameManager.session.entities.get_vehicle(_resolved_simulation_vehicle_id)
	if not vehicle_data.has_world_transform:
		return

	global_position = vehicle_data.world_position
	rotation.y = vehicle_data.world_yaw_radians

func _publish_vehicle_state_to_simulation_core() -> void:
	var occupant_player_id: StringName = &""
	if is_driven:
		occupant_player_id = _get_driver_player_id()

	GameManager.session.entities.set_vehicle_state(
		_resolved_simulation_vehicle_id,
		global_position,
		rotation.y,
		linear_velocity.length(),
		occupant_player_id
	)

func _get_driver_player_id() -> StringName:
	if driver_player == null:
		return &""

	var player_id_any: Variant = driver_player.get("simulation_player_id")
	if player_id_any is StringName:
		return player_id_any
	if player_id_any is String:
		return StringName(player_id_any)

	return &"player.main"

func _resolve_vehicle_id() -> StringName:
	if simulation_vehicle_id != &"":
		return simulation_vehicle_id

	var path_id := str(get_path()).replace("/", ".")
	if path_id.begins_with("."):
		path_id = path_id.substr(1)
	return StringName("vehicle." + path_id)
