class_name Implement3D
extends EntityView3D

enum HitchType {
	HITCH_3_POINT,
	HITCH_DRAWBAR,
	FRONT_LOADER
}


@export var required_hitch_type: HitchType = HitchType.HITCH_3_POINT
@export var required_power_kw: float = 15.0
@export var effector_move_threshold_meters: float = 0.25

var is_lowered: bool = false
var is_active: bool = false

var _attached_socket: Node3D = null # Will refer to the HitchSocket3D
var _ground_effectors: Array[Node3D] = []
var _effector_last_processed_positions: Dictionary = {}
const GROUND_EFFECTOR_SCRIPT: Script = preload("res://Scripts/vehicles/GroundEffector3D.gd")

func get_attached_vehicle() -> RigidBody3D:
	if _attached_socket and is_instance_valid(_attached_socket):
		var p: Node = _attached_socket.get_parent()
		while p != null and not p is PhysicsBody3D:
			p = p.get_parent()
		return p as RigidBody3D
	return null

@onready var hitch_point: Node3D = get_node_or_null("HitchPoint")

func _ready() -> void:
	add_to_group("implements")
	_refresh_ground_effectors()

func _process(_delta: float) -> void:
	if is_nan(global_position.x) or is_nan(global_position.y) or is_nan(global_position.z) or global_position.length_squared() > 1000000000.0:
		GameLog.error("IMPLEMENT EXPLOSION DETECTED => [%s] Position is NaN or extremely large: %s! Linear Vel: %s" % [name, str(global_position), str(linear_velocity)])

func _physics_process(_delta: float) -> void:
	pass

func get_hitch_world_position() -> Vector3:
	if hitch_point:
		return hitch_point.global_position
	return global_position

func attach_to_socket(socket: Node3D) -> void:
	_attached_socket = socket

func detach() -> void:
	_attached_socket = null
	execute_lower_command(false)
	execute_pto_command(false)
	_clear_effector_tracking()

func execute_lower_command(state: bool) -> void:
	is_lowered = state
	_sync_data_to_simulation()
	_on_lower_changed(state)

func execute_pto_command(state: bool) -> void:
	is_active = state
	_sync_data_to_simulation()
	_on_pto_changed(state)

# --- Virtual Methods for Subclasses ---
func _on_lower_changed(_state: bool) -> void:
	pass

func _on_pto_changed(_state: bool) -> void:
	pass

func is_currently_lowered() -> bool:
	return is_lowered

func get_current_power_draw() -> float:
	return required_power_kw if is_active else 0.0

func _sync_data_to_simulation() -> void:
	if not entity_data: return
	
	# Future: sync to UESS attachment components
	pass

func _refresh_ground_effectors() -> void:
	_ground_effectors.clear()
	for child_any: Variant in find_children("*", "GroundEffector3D", true, false):
		if child_any is Node3D and child_any.get_script() == GROUND_EFFECTOR_SCRIPT:
			_ground_effectors.append(child_any)
	_ground_effectors.sort_custom(Callable(self, "_sort_ground_effector_by_path"))

func _sort_ground_effector_by_path(a: Node3D, b: Node3D) -> bool:
	return str(a.get_path()) < str(b.get_path())

func _clear_effector_tracking() -> void:
	_effector_last_processed_positions.clear()

func collect_ground_effector_batch(force_emit: bool = false) -> Array[Dictionary]:
	if _ground_effectors.is_empty():
		return []

	var threshold_sq: float = effector_move_threshold_meters * effector_move_threshold_meters
	var out: Array[Dictionary] = []

	for effector: Node3D in _ground_effectors:
		if effector == null or not is_instance_valid(effector):
			continue
		if not bool(effector.get("is_engaged")):
			continue

		var key: String = str(effector.get_path())
		var current_pos: Vector3 = effector.global_position
		var previous_pos: Vector3 = current_pos
		if _effector_last_processed_positions.has(key):
			previous_pos = _effector_last_processed_positions[key]

		var has_moved_enough: bool = force_emit
		if not has_moved_enough:
			has_moved_enough = not _effector_last_processed_positions.has(key) or previous_pos.distance_squared_to(current_pos) >= threshold_sq

		if not has_moved_enough:
			continue

		out.append(effector.call("to_ground_instruction", previous_pos))
		_effector_last_processed_positions[key] = current_pos

	return out
