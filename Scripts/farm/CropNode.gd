extends Node3D

var grid_position: Vector2i
const START_SCALE := Vector3(0.2, 0.2, 0.2)
const FULL_SCALE := Vector3(1.0, 1.0, 1.0)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var _harvest_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("crop_node")
	if GameManager.session != null and GameManager.session.farm != null:
		var farm := GameManager.session.farm
		if not farm.is_connected("tile_updated", Callable(self, "_on_farm_tile_updated")):
			farm.connect("tile_updated", Callable(self, "_on_farm_tile_updated"))
	scale = START_SCALE
	refresh_from_data()

func _exit_tree() -> void:
	if GameManager.session != null and GameManager.session.farm != null:
		var farm := GameManager.session.farm
		if farm.is_connected("tile_updated", Callable(self, "_on_farm_tile_updated")):
			farm.disconnect("tile_updated", Callable(self, "_on_farm_tile_updated"))

func refresh_from_data() -> void:
	var tile_data := GameManager.session.farm.get_tile_data(grid_position)
	apply_visual_from_tile_data(tile_data)

func apply_visual_from_tile_data(tile_data: FarmTileData) -> void:
	var growth_progress := GameManager.session.farm.get_tile_growth_progress(grid_position)
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

func _on_farm_tile_updated(updated_grid_pos: Vector2i, new_state: int) -> void:
	if updated_grid_pos != grid_position:
		return

	if new_state == FarmData.SoilState.SEEDED or new_state == FarmData.SoilState.HARVESTABLE:
		refresh_from_data()
		return

	queue_free()
