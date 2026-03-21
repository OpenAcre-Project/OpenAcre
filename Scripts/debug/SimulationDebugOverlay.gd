extends Control

@export var visible_on_start: bool = false
@export var update_interval_seconds: float = 0.25
@export var panel_margin := Vector2(14.0, 14.0)
@export var panel_min_size := Vector2(460.0, 180.0)
@export var grid_manager_path: NodePath = NodePath("")

var _panel: Panel
var _label: Label
var _update_accumulator := 0.0
var _grid_manager: Node = null

func _ready() -> void:
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = panel_margin
	_panel.custom_minimum_size = panel_min_size
	_panel.visible = visible_on_start
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 10
	_label.offset_top = 8
	_label.offset_right = -10
	_label.offset_bottom = -8
	_panel.add_child(_label)

	_bind_grid_manager()
	_refresh_text()

func _process(delta: float) -> void:
	if not _panel.visible:
		return

	_update_accumulator += delta
	if _update_accumulator < update_interval_seconds:
		return

	_update_accumulator = 0.0
	_refresh_text()

func _input(event: InputEvent) -> void:
	if GameInput.is_debug_toggle_event(event):
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_text()
		get_viewport().set_input_as_handled()

func _bind_grid_manager() -> void:
	if grid_manager_path != NodePath("") and has_node(grid_manager_path):
		_grid_manager = get_node(grid_manager_path)
		return

	_grid_manager = get_tree().get_first_node_in_group("grid_manager")

func _refresh_text() -> void:
	if _label == null:
		return

	if _grid_manager == null or not is_instance_valid(_grid_manager):
		_bind_grid_manager()

	# Player position for debugging teleport issues
	var player_pos_line := "Player  pos=(?, ?, ?)"
	if _grid_manager != null and _grid_manager.has_method("get_stream_target_position"):
		var pos: Vector3 = _grid_manager.get_stream_target_position()
		player_pos_line = "Player  pos=(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

	var farm_line := "Tiles  total=%d  seeded=%d" % [
		GameManager.session.farm.get_total_tile_count(),
		GameManager.session.farm.get_seeded_tile_count()
	]

	# Chunk stats: currently loaded (visual) / total data chunks
	var loaded_visual := 0
	var center := Vector2i.ZERO
	var radius := 0
	var chunk_grid_on := false
	if _grid_manager != null:
		if _grid_manager.has_method("get_loaded_chunk_count"):
			loaded_visual = _grid_manager.get_loaded_chunk_count()
		if _grid_manager.has_method("get_stream_center_chunk"):
			center = _grid_manager.get_stream_center_chunk()
		if _grid_manager.has_method("get_stream_radius"):
			radius = _grid_manager.get_stream_radius()
		if _grid_manager.has_method("is_chunk_grid_visible"):
			chunk_grid_on = _grid_manager.is_chunk_grid_visible()
	var total_data := GameManager.session.farm.get_total_chunk_count()
	var chunk_line := "Chunks  loaded=%d / total=%d  (@ %d,%d  r=%d)  (Grid: %s)" % [
		loaded_visual, total_data, center.x, center.y, radius, "ON" if chunk_grid_on else "OFF"
	]

	var ray_line := "Raycast  [None]"
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var center_screen := camera.get_viewport().get_visible_rect().size * 0.5
		var origin := camera.project_ray_origin(center_screen)
		var dir := camera.project_ray_normal(center_screen)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 64.0)
		var world := camera.get_world_3d()
		if world != null:
			var hit := world.direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var collider: Variant = hit.get("collider")
				if collider != null and collider is Node:
					ray_line = "Raycast  hit=%s  pos=(%.1f, %.1f, %.1f)" % [collider.name, hit.position.x, hit.position.y, hit.position.z]
					if collider.has_method("get_interaction_prompt"):
						ray_line += "  [Interactable]"

	# Inventory & Weight
	var inv_line := "Pockets [None]"
	var player_data := GameManager.session.entities.get_player()
	if player_data != null:
		var curr_v: float = player_data.pockets.get_total_volume()
		var max_v: float = player_data.pockets.max_volume
		var curr_m: float = player_data.get_total_encumbrance_mass()
		inv_line = "Pockets  vol=%.1f/%.1f L  mass=%.1f kg" % [curr_v, max_v, curr_m]

	# Vehicle Context
	var veh_line := "Vehicle [None]"
	var active_veh_id := player_data.active_vehicle_id if player_data else &""
	if active_veh_id != &"":
		var v_data := GameManager.session.entities.get_vehicle(active_veh_id)
		var tank_info := ""
		for t_id: StringName in v_data.tanks:
			var tank: BulkTankData = v_data.tanks[t_id]
			tank_info += " %s: %.1f/%.1f L" % [t_id, tank.current_liters, tank.max_volume]
		veh_line = "Vehicle  id=%s  mass=%.0f kg %s" % [active_veh_id, v_data.get_total_vehicle_mass(), tank_info]

	var controls_line := "Toggle  %s" % GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_DEBUG)
	_label.text = "SIM DEBUG\n\n%s\n%s\n%s\n%s\n%s\n%s\n\n%s" % [
		player_pos_line,
		farm_line,
		chunk_line,
		inv_line,
		veh_line,
		ray_line,
		controls_line
	]
