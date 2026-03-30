class_name Implement3D
extends EntityView3D

const WORK_REQUEST_SCRIPT = preload("res://Scripts/farm/work/WorkRequest.gd")

enum HitchType {
	HITCH_3_POINT,
	HITCH_DRAWBAR,
	FRONT_LOADER
}


@export var required_hitch_type: HitchType = HitchType.HITCH_3_POINT
@export var required_power_kw: float = 15.0
@export var effector_move_threshold_meters: float = 0.25
@export var requires_pto: bool = true
@export var requires_lowering: bool = true
@export var min_work_speed: float = 0.0
@export var max_work_speed: float = 100.0
@export var use_span_quad_mode: bool = false
@export var span_left_marker_path: NodePath = NodePath("Effector_Left")
@export var span_right_marker_path: NodePath = NodePath("Effector_Right")

var is_lowered: bool = false
var is_active: bool = false

var _attached_socket: Node3D = null # Will refer to the HitchSocket3D
var _ground_effectors: Array[Node3D] = []
var _effector_last_processed_positions: Dictionary = {}
var _span_prev_left: Vector3 = Vector3.ZERO
var _span_prev_right: Vector3 = Vector3.ZERO
var _span_prev_valid: bool = false
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
	_span_prev_valid = false

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

func can_emit_work_requests(current_speed_mps: float) -> bool:
	if requires_lowering and not is_lowered:
		return false
	if requires_pto and not is_active:
		return false
	if current_speed_mps < min_work_speed:
		return false
	if max_work_speed > 0.0 and current_speed_mps > max_work_speed:
		return false
	return true

func collect_work_requests(operation: int, payload_template: Dictionary = {}, force_emit: bool = false, max_budget: int = -1) -> Array:
	if use_span_quad_mode:
		var span_request: WorkRequest = _collect_span_quad_request(operation, payload_template, force_emit, max_budget)
		if span_request == null:
			return []
		return [span_request]

	if _ground_effectors.is_empty():
		return []

	var threshold_sq: float = effector_move_threshold_meters * effector_move_threshold_meters
	var out: Array = []
	for effector_any: Node3D in _ground_effectors:
		if effector_any == null or not is_instance_valid(effector_any):
			continue
		var effector: GroundEffector3D = effector_any as GroundEffector3D
		if effector == null or not effector.is_engaged:
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

		var source_tag: StringName = _get_work_source_tag(effector)
		out.append(effector.to_work_request(operation, previous_pos, payload_template, source_tag, max_budget))
		_effector_last_processed_positions[key] = current_pos

	return out

func _collect_span_quad_request(operation: int, payload_template: Dictionary, force_emit: bool, max_budget: int) -> WorkRequest:
	var left_marker: Node3D = get_node_or_null(span_left_marker_path) as Node3D
	var right_marker: Node3D = get_node_or_null(span_right_marker_path) as Node3D
	if left_marker == null or right_marker == null:
		return null

	var left_curr: Vector3 = left_marker.global_position
	var right_curr: Vector3 = right_marker.global_position
	if not _span_prev_valid:
		_span_prev_left = left_curr
		_span_prev_right = right_curr
		_span_prev_valid = true

	var travel_sq: float = maxf(_span_prev_left.distance_squared_to(left_curr), _span_prev_right.distance_squared_to(right_curr))
	var threshold_sq: float = effector_move_threshold_meters * effector_move_threshold_meters
	if not force_emit and travel_sq < threshold_sq:
		return null

	var points_xz: Array[Vector2] = [
		Vector2(_span_prev_left.x, _span_prev_left.z),
		Vector2(_span_prev_right.x, _span_prev_right.z),
		Vector2(right_curr.x, right_curr.z),
		Vector2(left_curr.x, left_curr.z)
	]
	var merged_payload: Dictionary = payload_template.duplicate(true)
	merged_payload["segment_distance"] = ((Vector2(_span_prev_left.x, _span_prev_left.z) + Vector2(_span_prev_right.x, _span_prev_right.z)) * 0.5).distance_to((Vector2(left_curr.x, left_curr.z) + Vector2(right_curr.x, right_curr.z)) * 0.5)

	var request := WORK_REQUEST_SCRIPT.quad_sweep(operation, points_xz, merged_payload, _get_work_source_tag(self), max_budget)
	request.engagement_height = (left_curr.y + right_curr.y) * 0.5
	request.engagement_margin = float(payload_template.get("engagement_margin", 0.03))

	_span_prev_left = left_curr
	_span_prev_right = right_curr
	_span_prev_valid = true
	return request

func _get_work_source_tag(source_node: Node) -> StringName:
	if entity_data != null and entity_data.runtime_id != &"":
		return entity_data.runtime_id
	if source_node != null:
		return StringName(str(source_node.get_path()))
	return StringName(str(get_path()))
