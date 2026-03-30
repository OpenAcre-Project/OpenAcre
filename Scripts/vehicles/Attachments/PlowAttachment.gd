extends "res://Scripts/vehicles/Implement3D.gd"

const WORK_OPERATION_TYPE_SCRIPT = preload("res://Scripts/farm/work/WorkOperationType.gd")

@export var plow_width: float = 3.0
@export var min_apply_speed_sq: float = 0.005
@export var max_tiles_per_step: int = -1
@export var ground_contact_probe_margin: float = 0.20
@export var ground_contact_probe_depth: float = 1.50
@export var use_terrain_probe_fallback: bool = true

@onready var detection_area: Area3D = $DetectionArea
@onready var teeth_collision_region: Area3D = get_node_or_null("TeethCollisionRegion") as Area3D

var _teeth_collision_shapes: Array[CollisionShape3D] = []
var _teeth_region_default_monitoring: bool = true
var _teeth_region_default_monitorable: bool = true
var _teeth_region_default_layer: int = 1
var _teeth_region_default_mask: int = 1
var _last_rejection_log_msec: int = 0

func _ready() -> void:
	required_power_kw = 25.0
	# Allow custom width
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(plow_width, 0.5, 0.5)
	$DetectionArea/CollisionShape3D.shape = shape
	_cache_teeth_collision_region_defaults()
	super._ready()
	_update_processing_state()

func _on_lower_changed(_state: bool) -> void:
	_update_processing_state()
	if not is_lowered:
		_force_collision_rebuild()

func _on_pto_changed(_state: bool) -> void:
	_update_processing_state()
	if not is_active:
		_force_collision_rebuild()

func _update_processing_state() -> void:
	var should_process: bool = is_lowered and is_active
	set_physics_process(should_process)
	detection_area.monitoring = should_process
	_set_teeth_collision_region_active(not should_process)

func _physics_process(_delta: float) -> void:
	super._physics_process(_delta)
	# Only runs when lowered and active
	var move_speed_sq: float = linear_velocity.length_squared()
	var attached_vehicle := get_attached_vehicle()
	if attached_vehicle != null:
		move_speed_sq = attached_vehicle.linear_velocity.length_squared()
	if move_speed_sq <= min_apply_speed_sq:
		return
	if not _is_touching_floor():
		return

	var soil_service: Node = get_tree().get_first_node_in_group("soil_layer_service")
	var move_speed_mps: float = sqrt(maxf(move_speed_sq, 0.0))
	if soil_service != null and soil_service.has_method("process_work_batch") and has_method("collect_work_requests"):
		if not can_emit_work_requests(move_speed_mps):
			return
		var payload := {
			"soil_state_output": FarmData.SoilState.PLOWED,
			"depth_offset": -0.15,
			"blend_mode": GroundEffector3D.BlendMode.ADD
		}
		var requests: Array = collect_work_requests(WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE, payload, false, max_tiles_per_step)
		if requests.is_empty():
			return
		var reports: Array = soil_service.process_work_batch(requests)
		_handle_work_reports(reports)
		return

	if soil_service != null and soil_service.has_method("apply_ground_effectors"):
		var batch: Array[Dictionary] = collect_ground_effector_batch(false)
		if not batch.is_empty():
			soil_service.apply_ground_effectors(batch)
		return

	# Legacy fallback for scenes that have no GroundEffector3D nodes yet.
	_plow_ground()

func _handle_work_reports(reports: Array) -> void:
	var successful_area: float = 0.0
	var rejected_tiles: int = 0
	for report_any: Variant in reports:
		if report_any == null:
			continue
		var report: WorkReport = report_any
		successful_area += report.successful_area
		rejected_tiles += report.rejected_unfarmable + report.rejected_wrong_state + report.rejected_height + report.rejected_budget

	if successful_area > 0.0:
		return

	if rejected_tiles <= 0:
		return

	var now: int = Time.get_ticks_msec()
	if now - _last_rejection_log_msec < 800:
		return
	_last_rejection_log_msec = now
	GameLog.info("[PlowAttachment] Work pass rejected (%d tiles)." % rejected_tiles)

func _is_touching_floor() -> bool:
	var overlapping_bodies: Array = detection_area.get_overlapping_bodies()
	for body: Node in overlapping_bodies:
		if body == self:
			continue
		var attached_vehicle: RigidBody3D = get_attached_vehicle()
		if attached_vehicle != null and body == attached_vehicle:
			continue
		if _is_ground_body(body):
			return true

	if use_terrain_probe_fallback and _is_touching_terrain_by_height_probe():
		return true
	return false

func _is_touching_terrain_by_height_probe() -> bool:
	var terrain: Node = get_tree().get_first_node_in_group("terrain_node")
	if terrain == null:
		return false

	var terrain_api: Object = null
	if terrain.has_method("get_data"):
		terrain_api = terrain.get_data()
	elif terrain.has_method("get_storage"):
		terrain_api = terrain.get_storage()
	elif "data" in terrain:
		terrain_api = terrain.get("data")

	if terrain_api == null or not terrain_api.has_method("get_height"):
		return false

	var probe_points: Array[Vector3] = [global_position, detection_area.global_position]
	for effector_any: Variant in find_children("*", "GroundEffector3D", true, false):
		if effector_any is Node3D:
			probe_points.append((effector_any as Node3D).global_position)

	for point: Vector3 in probe_points:
		var terrain_height: float = float(terrain_api.get_height(point))
		if is_nan(terrain_height):
			continue
		if point.y <= terrain_height + ground_contact_probe_margin and point.y >= terrain_height - ground_contact_probe_depth:
			return true

	return false

func _is_ground_body(body: Node) -> bool:
	if body == null:
		return false

	var lower_name: String = body.name.to_lower()
	if lower_name.contains("floor") or lower_name.contains("terrain"):
		return true

	if body.get_class() == "Terrain3D":
		return true

	if body.is_in_group("terrain_node"):
		return true

	var parent: Node = body.get_parent()
	while parent != null:
		if parent.is_in_group("terrain_node") or parent.get_class() == "Terrain3D":
			return true
		parent = parent.get_parent()

	# Last-resort fallback: terrain collision often arrives as static collision bodies.
	if body is StaticBody3D:
		return true

	return false

func _force_collision_rebuild() -> void:
	var soil_service: Node = get_tree().get_first_node_in_group("soil_layer_service")
	if soil_service != null and soil_service.has_method("force_collision_rebuild"):
		soil_service.force_collision_rebuild()

func _plow_ground() -> void:
	if not _is_touching_floor():
		return
	var soil_service: Node = get_tree().get_first_node_in_group("soil_layer_service")
	# Calculate grid coords from left to right along the plow width
	var center_pos: Vector3 = global_position
	var right_dir: Vector3 = global_transform.basis.x.normalized()
	# Sample grid blocks across the width of the plow
	var half_width_samples: int = int(plow_width / 2.0)
	for i: int in range(-half_width_samples, half_width_samples + 1):
		var sample_pos: Vector3 = center_pos + (right_dir * i)
		if not GameManager.session.farm.can_plow_at(sample_pos):
			continue
		var grid_pos: Vector2i = GameManager.session.farm.world_to_grid(sample_pos)
		if soil_service != null and soil_service.has_method("plow_world"):
			soil_service.plow_world(sample_pos)
		else:
			var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
			if tile_data.state == FarmData.SoilState.GRASS:
				GameManager.session.farm.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, sample_pos.y)
func _cache_teeth_collision_region_defaults() -> void:
	if teeth_collision_region == null:
		return

	_teeth_collision_shapes.clear()
	for child_any: Variant in teeth_collision_region.get_children():
		if child_any is CollisionShape3D:
			_teeth_collision_shapes.append(child_any)

	_teeth_region_default_monitoring = teeth_collision_region.monitoring
	_teeth_region_default_monitorable = teeth_collision_region.monitorable
	_teeth_region_default_layer = teeth_collision_region.collision_layer
	_teeth_region_default_mask = teeth_collision_region.collision_mask

func _set_teeth_collision_region_active(is_active_state: bool) -> void:
	if teeth_collision_region == null:
		return

	teeth_collision_region.monitoring = _teeth_region_default_monitoring if is_active_state else false
	teeth_collision_region.monitorable = _teeth_region_default_monitorable if is_active_state else false
	teeth_collision_region.collision_layer = _teeth_region_default_layer if is_active_state else 0
	teeth_collision_region.collision_mask = _teeth_region_default_mask if is_active_state else 0

	for shape: CollisionShape3D in _teeth_collision_shapes:
		shape.disabled = not is_active_state
