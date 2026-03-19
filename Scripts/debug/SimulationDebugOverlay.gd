extends CanvasLayer

@export var visible_on_start: bool = true
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

	var time_line := "Time  Day %d  %02d:%02d" % [TimeManager.current_day, TimeManager.current_hour, TimeManager.current_minute]

	# Player position for debugging teleport issues
	var player_pos_line := "Player  pos=(?, ?, ?)"
	if _grid_manager != null and _grid_manager.has_method("get_stream_target_position"):
		var pos: Vector3 = _grid_manager.get_stream_target_position()
		player_pos_line = "Player  pos=(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

	var farm_line := "Tiles  total=%d  seeded=%d" % [
		FarmData.get_total_tile_count(),
		FarmData.get_seeded_tile_count()
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
	var total_data := FarmData.get_total_chunk_count()
	var chunk_line := "Chunks  loaded=%d / total=%d  (@ %d,%d  r=%d)" % [
		loaded_visual, total_data, center.x, center.y, radius
	]
	var grid_line := "Grid overlay  %s" % ("ON" if chunk_grid_on else "OFF (use `chunks` in console)")

	var controls_line := "Toggle  %s" % GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_DEBUG)
	_label.text = "SIM DEBUG\n\n%s\n%s\n%s\n%s\n%s\n\n%s" % [
		time_line,
		player_pos_line,
		farm_line,
		chunk_line,
		grid_line,
		controls_line
	]
