## [Component] A shared third-person orbit camera controller.
## This component manages a SpringArm3D to provide smooth mouse-driven orbiting,
## scroll-based zooming, and height adjustments. It keeps the camera yaw stable
## relative to the world, preventing rotation "snapping" when the parent turns.
extends Node
class_name OrbitCameraController

@export var mouse_sensitivity: float = 0.002
@export var vertical_speed: float = 3.0
@export var zoom_step: float = 0.5
@export var follow_smooth_speed: float = 12.0
@export var orbit_smooth_speed: float = 14.0
@export var auto_center_delay: float = 1.5
@export var auto_center_speed: float = 2.0
@export var is_auto_center_enabled: bool = false

@export_group("Constraints")
@export var height_min: float = 1.2
@export var height_max: float = 4.0
@export var zoom_min: float = 1.5
@export var zoom_max: float = 10.0
@export var pitch_min_degrees: float = -70.0
@export var pitch_max_degrees: float = 25.0

var _spring_arm: SpringArm3D
var _camera: Camera3D
var _target_height: float = 1.6
var _target_distance: float = 4.0
var yaw_global: float = 0.0
var pitch: float = 0.0
var _last_input_time: float = 0.0

func setup(spring_arm: SpringArm3D, camera: Camera3D) -> void:
	_spring_arm = spring_arm
	_camera = camera
	
	_target_height = _spring_arm.position.y
	_target_distance = _spring_arm.spring_length
	
	# Initialize angles from the current spring arm rotation
	var parent_rotation_y := _spring_arm.get_parent_node_3d().global_rotation.y if _spring_arm.get_parent_node_3d() else 0.0
	yaw_global = parent_rotation_y + _spring_arm.rotation.y
	pitch = _spring_arm.rotation.x
	_last_input_time = Time.get_ticks_msec()

func handle_mouse_motion(relative: Vector2) -> void:
	_last_input_time = Time.get_ticks_msec()
	yaw_global = wrapf(yaw_global - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(
		pitch - relative.y * mouse_sensitivity,
		deg_to_rad(pitch_min_degrees),
		deg_to_rad(pitch_max_degrees)
	)

func adjust_zoom(out: bool) -> void:
	var delta := zoom_step if out else -zoom_step
	_target_distance = clamp(_target_distance + delta, zoom_min, zoom_max)

func update(delta: float, is_input_blocked: bool) -> void:
	if _spring_arm == null:
		return

	if not is_input_blocked:
		if Input.is_action_pressed(GameInput.ACTION_CAMERA_UP):
			_target_height += vertical_speed * delta
		if Input.is_action_pressed(GameInput.ACTION_CAMERA_DOWN):
			_target_height -= vertical_speed * delta

	_target_height = clamp(_target_height, height_min, height_max)
	
	# Smoothly lerp position and spring length
	_spring_arm.position.y = lerp(_spring_arm.position.y, _target_height, follow_smooth_speed * delta)
	_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_distance, follow_smooth_speed * delta)

	# Calculate and apply smooth rotation
	var parent_rotation_y := _spring_arm.get_parent_node_3d().global_rotation.y if _spring_arm.get_parent_node_3d() else 0.0
	
	if is_auto_center_enabled and Time.get_ticks_msec() - _last_input_time > auto_center_delay * 1000:
		yaw_global = lerp_angle(yaw_global, parent_rotation_y, auto_center_speed * delta)
	
	var target_local_yaw: float = wrapf(yaw_global - parent_rotation_y, -PI, PI)
	
	_spring_arm.rotation.y = target_local_yaw
	_spring_arm.rotation.x = lerpf(_spring_arm.rotation.x, pitch, orbit_smooth_speed * delta)
	_spring_arm.rotation.z = 0.0

func set_yaw_global(yaw: float) -> void:
	yaw_global = yaw

func get_yaw_global() -> float:
	return yaw_global
