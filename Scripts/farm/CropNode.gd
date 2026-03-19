extends Node3D

var grid_position: Vector2i
const START_SCALE := Vector3(0.2, 0.2, 0.2)
const FULL_SCALE := Vector3(1.0, 1.0, 1.0)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var _harvest_material: StandardMaterial3D

func _ready() -> void:
	scale = START_SCALE
	refresh_from_data()

func refresh_from_data() -> void:
	var tile_data := FarmData.get_tile_data(grid_position)
	apply_visual_from_tile_data(tile_data)

func apply_visual_from_tile_data(tile_data: FarmTileData) -> void:
	var growth_progress := FarmData.get_tile_growth_progress(grid_position)
	scale = START_SCALE.lerp(FULL_SCALE, growth_progress)
	set_harvestable_visual(tile_data.state == FarmData.SoilState.HARVESTABLE)

func set_harvestable_visual(is_harvestable: bool) -> void:
	if not is_harvestable:
		mesh_instance.set_surface_override_material(0, null)
		return

	if _harvest_material == null:
		_harvest_material = StandardMaterial3D.new()
		_harvest_material.albedo_color = Color(0.8, 0.8, 0.1)

	mesh_instance.set_surface_override_material(0, _harvest_material)
