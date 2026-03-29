class_name Implement3D
extends EntityView3D

enum HitchType {
	HITCH_3_POINT,
	HITCH_DRAWBAR,
	FRONT_LOADER
}


@export var required_hitch_type: HitchType = HitchType.HITCH_3_POINT
@export var required_power_kw: float = 15.0

var is_lowered: bool = false
var is_active: bool = false

var _attached_socket: Node3D = null # Will refer to the HitchSocket3D

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
