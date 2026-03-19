extends Node3D

## Minecraft-style chunk grid overlay.
## Draws wireframe borders at chunk boundaries using ImmediateMesh.
## Purely visual — has no effect on game logic or simulation.

@export var chunk_size_meters: int = 32
@export var grid_color: Color = Color(0.0, 0.85, 0.95, 0.45)
@export var grid_line_height: float = 20.0
@export var grid_draw_radius: int = 2

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D
var _last_center_chunk := Vector2i(-999999, -999999)

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()

	_material = StandardMaterial3D.new()
	_material.albedo_color = grid_color
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

func rebuild(center_chunk: Vector2i, ground_y: float = 0.0) -> void:
	if not visible:
		return
	if center_chunk == _last_center_chunk:
		return
	_last_center_chunk = center_chunk
	_draw_grid(center_chunk, ground_y)

func force_rebuild(center_chunk: Vector2i, ground_y: float = 0.0) -> void:
	_last_center_chunk = Vector2i(-999999, -999999)
	rebuild(center_chunk, ground_y)

func set_overlay_visible(should_be_visible: bool) -> void:
	visible = should_be_visible
	if not should_be_visible:
		_clear_mesh()
		_last_center_chunk = Vector2i(-999999, -999999)

func is_overlay_visible() -> bool:
	return visible

func _clear_mesh() -> void:
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()

func _draw_grid(center_chunk: Vector2i, ground_y: float) -> void:
	_clear_mesh()

	var cs := float(chunk_size_meters)
	var half_height := grid_line_height * 0.5
	var bottom_y := ground_y - half_height
	var top_y := ground_y + half_height
	var r := grid_draw_radius

	# Compute world-space bounds of the grid area
	var min_cx := center_chunk.x - r
	var max_cx := center_chunk.x + r
	var min_cy := center_chunk.y - r
	var max_cy := center_chunk.y + r

	var _world_min_x := float(min_cx) * cs
	var _world_max_x := float(max_cx + 1) * cs
	var _world_min_z := float(min_cy) * cs
	var _world_max_z := float(max_cy + 1) * cs

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)

	# Draw vertical lines along X boundaries (one per chunk boundary)
	for cx in range(min_cx, max_cx + 2):
		var x := float(cx) * cs
		for cy in range(min_cy, max_cy + 1):
			var z_start := float(cy) * cs
			var z_end := float(cy + 1) * cs
			# Bottom horizontal line segment
			_immediate_mesh.surface_add_vertex(Vector3(x, bottom_y, z_start))
			_immediate_mesh.surface_add_vertex(Vector3(x, bottom_y, z_end))
			# Top horizontal line segment
			_immediate_mesh.surface_add_vertex(Vector3(x, top_y, z_start))
			_immediate_mesh.surface_add_vertex(Vector3(x, top_y, z_end))

	# Draw vertical lines along Z boundaries
	for cy in range(min_cy, max_cy + 2):
		var z := float(cy) * cs
		for cx in range(min_cx, max_cx + 1):
			var x_start := float(cx) * cs
			var x_end := float(cx + 1) * cs
			# Bottom horizontal line segment
			_immediate_mesh.surface_add_vertex(Vector3(x_start, bottom_y, z))
			_immediate_mesh.surface_add_vertex(Vector3(x_end, bottom_y, z))
			# Top horizontal line segment
			_immediate_mesh.surface_add_vertex(Vector3(x_start, top_y, z))
			_immediate_mesh.surface_add_vertex(Vector3(x_end, top_y, z))

	# Draw vertical pillars at chunk corners
	for cx in range(min_cx, max_cx + 2):
		var x := float(cx) * cs
		for cy in range(min_cy, max_cy + 2):
			var z := float(cy) * cs
			_immediate_mesh.surface_add_vertex(Vector3(x, bottom_y, z))
			_immediate_mesh.surface_add_vertex(Vector3(x, top_y, z))

	# Highlight the center chunk with additional mid-height lines
	var center_x0 := float(center_chunk.x) * cs
	var center_x1 := float(center_chunk.x + 1) * cs
	var center_z0 := float(center_chunk.y) * cs
	var center_z1 := float(center_chunk.y + 1) * cs
	var mid_y := ground_y

	# Center chunk border at mid height
	_immediate_mesh.surface_add_vertex(Vector3(center_x0, mid_y, center_z0))
	_immediate_mesh.surface_add_vertex(Vector3(center_x1, mid_y, center_z0))

	_immediate_mesh.surface_add_vertex(Vector3(center_x1, mid_y, center_z0))
	_immediate_mesh.surface_add_vertex(Vector3(center_x1, mid_y, center_z1))

	_immediate_mesh.surface_add_vertex(Vector3(center_x1, mid_y, center_z1))
	_immediate_mesh.surface_add_vertex(Vector3(center_x0, mid_y, center_z1))

	_immediate_mesh.surface_add_vertex(Vector3(center_x0, mid_y, center_z1))
	_immediate_mesh.surface_add_vertex(Vector3(center_x0, mid_y, center_z0))

	_immediate_mesh.surface_end()
