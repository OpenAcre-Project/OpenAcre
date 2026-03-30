extends RefCounted
class_name WorkRequest

const WORK_OPERATION_TYPE_SCRIPT = preload("res://Scripts/farm/work/WorkOperationType.gd")

enum GeometryType {
	POINT_RADIUS = 0,
	LINE_SWEEP = 1,
	QUAD_SWEEP = 2
}

var operation: int = WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE
var geometry_type: int = GeometryType.POINT_RADIUS
var payload: Dictionary = {}

# Point/radius geometry
var point_center: Vector3 = Vector3.ZERO

# Line/capsule geometry
var line_start: Vector3 = Vector3.ZERO
var line_end: Vector3 = Vector3.ZERO

# Quad geometry (XZ plane points in winding order)
var quad_points_xz: Array[Vector2] = []

# Shared geometry params
var radius_meters: float = 0.5

# Optional gate metadata
var engagement_height: float = NAN
var engagement_margin: float = 0.03

# Optional budget clamp (tiles) to avoid free commits when resources are low.
# <= 0 means unlimited for the request.
var max_budget: int = -1

# Optional audit tag (tool or implement identity)
var source_tag: StringName = &""

static func point(
	p_operation: int,
	center: Vector3,
	radius: float,
	p_payload: Dictionary = {},
	p_source_tag: StringName = &"",
	p_max_budget: int = -1
) -> WorkRequest:
	var req := WorkRequest.new()
	req.operation = p_operation
	req.geometry_type = GeometryType.POINT_RADIUS
	req.point_center = center
	req.radius_meters = maxf(radius, 0.01)
	req.payload = p_payload.duplicate(true)
	req.source_tag = p_source_tag
	req.max_budget = p_max_budget
	return req

static func line_sweep(
	p_operation: int,
	start_pos: Vector3,
	end_pos: Vector3,
	radius: float,
	p_payload: Dictionary = {},
	p_source_tag: StringName = &"",
	p_max_budget: int = -1
) -> WorkRequest:
	var req := WorkRequest.new()
	req.operation = p_operation
	req.geometry_type = GeometryType.LINE_SWEEP
	req.line_start = start_pos
	req.line_end = end_pos
	req.radius_meters = maxf(radius, 0.01)
	req.payload = p_payload.duplicate(true)
	req.source_tag = p_source_tag
	req.max_budget = p_max_budget
	return req

static func quad_sweep(
	p_operation: int,
	points_xz: Array[Vector2],
	p_payload: Dictionary = {},
	p_source_tag: StringName = &"",
	p_max_budget: int = -1
) -> WorkRequest:
	var req := WorkRequest.new()
	req.operation = p_operation
	req.geometry_type = GeometryType.QUAD_SWEEP
	req.quad_points_xz = points_xz.duplicate()
	req.payload = p_payload.duplicate(true)
	req.source_tag = p_source_tag
	req.max_budget = p_max_budget
	return req
