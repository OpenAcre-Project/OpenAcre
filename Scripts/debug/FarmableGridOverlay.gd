extends Node3D

@export var chunk_size_meters: int = 32
@export var draw_radius_chunks: int = 1 # Keep it small (3x3 chunks) to reduce vertex count
@export var farmable_color: Color = Color(0.1, 0.9, 0.2, 0.3)
@export var unfarmable_color: Color = Color(0.9, 0.1, 0.1, 0.3)
@export var y_offset: float = 0.2 # Offset off the ground to avoid Z-fighting

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _mat_farmable: StandardMaterial3D
var _mat_unfarmable: StandardMaterial3D
var _last_center_chunk := Vector2i(-999999, -999999)

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()

	_mat_farmable = StandardMaterial3D.new()
	_mat_farmable.albedo_color = farmable_color
	_mat_farmable.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_farmable.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_farmable.no_depth_test = true
	_mat_farmable.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_unfarmable = StandardMaterial3D.new()
	_mat_unfarmable.albedo_color = unfarmable_color
	_mat_unfarmable.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_unfarmable.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_unfarmable.no_depth_test = true
	_mat_unfarmable.cull_mode = BaseMaterial3D.CULL_DISABLED

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
	var r := draw_radius_chunks
	var draw_y := ground_y + y_offset

	var min_cx := center_chunk.x - r
	var max_cx := center_chunk.x + r
	var min_cy := center_chunk.y - r
	var max_cy := center_chunk.y + r

	var farmable_vertices: Array[Vector3] = []
	var unfarmable_vertices: Array[Vector3] = []

	# Tile size is exactly 1x1 meter
	var tile_size := 1.0
	var inset := 0.1 # Shrink the visual tiles slightly so there's a mini gap between them

	# We will retrieve Surface Y from FarmData if requested, otherwise flat
	var use_dynamic_height: bool = _terrain_height_supported()
	var terrain_data: Object = null
	if use_dynamic_height:
		var tb: Node = get_tree().get_first_node_in_group("terrain_node")
		if tb != null and tb.has_method("get_data"):
			terrain_data = tb.get_data()

	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			var chunk_origin_x := float(cx) * cs
			var chunk_origin_z := float(cy) * cs
			
			for tx in range(int(cs)):
				for tz in range(int(cs)):
					var world_x := chunk_origin_x + float(tx)
					var world_z := chunk_origin_z + float(tz)
					var check_pos := Vector3(world_x + 0.5, 0.0, world_z + 0.5)
					
					var surface_y := draw_y
					if use_dynamic_height and terrain_data != null and terrain_data.has_method("get_height"):
						surface_y = terrain_data.get_height(Vector2(world_x + 0.5, world_z + 0.5)) + y_offset

					# Check validity using FarmData (which wraps MapRegionMask)
					var is_farmable: bool = GameManager.session.farm.can_plow_at(check_pos)

					var p1 := Vector3(world_x + inset, surface_y, world_z + inset)
					var p2 := Vector3(world_x + tile_size - inset, surface_y, world_z + inset)
					var p3 := Vector3(world_x + tile_size - inset, surface_y, world_z + tile_size - inset)
					var p4 := Vector3(world_x + inset, surface_y, world_z + tile_size - inset)

					if is_farmable:
						farmable_vertices.append_array([p1, p2, p3, p1, p3, p4])
					else:
						# Only draw unfarmable crosses to save vertices, or draw the quad?
						# Quad is clearer
						unfarmable_vertices.append_array([p1, p2, p3, p1, p3, p4])

	if farmable_vertices.size() > 0:
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_farmable)
		for v in farmable_vertices:
			_immediate_mesh.surface_add_vertex(v)
		_immediate_mesh.surface_end()

	if unfarmable_vertices.size() > 0:
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_unfarmable)
		for v in unfarmable_vertices:
			_immediate_mesh.surface_add_vertex(v)
		_immediate_mesh.surface_end()

func _terrain_height_supported() -> bool:
	var tb: Node = get_tree().get_first_node_in_group("terrain_node")
	if tb != null and tb.has_method("get_data"):
		var data: Resource = tb.get_data()
		return data != null and data.has_method("get_height")
	return false
