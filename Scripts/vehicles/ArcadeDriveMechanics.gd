extends RigidBody3D
class_name ArcadeDriveMechanics

@export var max_speed: float = 0.0 # 0 or less means uncapped speed
@export var turn_speed: float = 1.2
@export var acceleration_rate: float = 28.0
@export var deceleration_rate: float = 10.0
@export var driving_linear_damp: float = 0.0
@export var idle_linear_damp: float = 3.0
@export var driving_angular_damp: float = 8.0

var is_driven: bool = false

func _ready() -> void:
	linear_damp = idle_linear_damp
	angular_damp = driving_angular_damp
	# Keep arcade vehicles stable by restricting pitch/roll rotation.
	axis_lock_angular_x = true
	axis_lock_angular_z = true

func _physics_process(delta: float) -> void:
	if not is_driven:
		return

	var steer_input: float = _get_steer_input()
	var throttle_input: float = _get_throttle_input()
	var y_velocity: float = linear_velocity.y

	# Deterministic steering: right key always turns right.
	rotate_y(-steer_input * turn_speed * delta)
	angular_velocity = Vector3.ZERO

	# Arcade acceleration model: hold throttle to keep accelerating.
	var forward: Vector3 = -global_transform.basis.z
	var current_planar_velocity: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var new_planar_velocity: Vector3 = current_planar_velocity

	if abs(throttle_input) > 0.01:
		new_planar_velocity += forward * (throttle_input * acceleration_rate * delta)
	else:
		new_planar_velocity = new_planar_velocity.move_toward(Vector3.ZERO, deceleration_rate * delta)

	if max_speed > 0.0 and new_planar_velocity.length() > max_speed:
		new_planar_velocity = new_planar_velocity.normalized() * max_speed

	linear_velocity = Vector3(new_planar_velocity.x, y_velocity, new_planar_velocity.z)

func set_driven_state(driven: bool) -> void:
	is_driven = driven
	linear_damp = driving_linear_damp if driven else idle_linear_damp
	if driven:
		sleeping = false

func _get_throttle_input() -> float:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return 0.0

	var input_value: float = Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
	if Input.is_physical_key_pressed(KEY_W):
		input_value += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_value -= 1.0
	return clamp(input_value, -1.0, 1.0)

func _get_steer_input() -> float:
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return 0.0

	var input_value: float = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	if Input.is_physical_key_pressed(KEY_D):
		input_value += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_value -= 1.0
	return clamp(input_value, -1.0, 1.0)
