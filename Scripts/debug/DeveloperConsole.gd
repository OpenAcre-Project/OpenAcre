extends CanvasLayer

@export var start_open: bool = false
@export var max_history_lines: int = 220
@export var spawn_distance_from_player: float = 6.0
@export var default_spawn_count: int = 1

var _panel: Panel
var _log: RichTextLabel
var _input_line: LineEdit
var _history: Array[String] = []
var _history_cursor: int = 0
var _spawn_registry: Dictionary = {}
var _was_mouse_captured_before_open := false

func _ready() -> void:
	# Console survives game crashes — always processes even if scene tree pauses
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("developer_console")
	_build_ui()
	_build_spawn_registry()
	_set_console_visible(start_open)
	_print_line("Developer console ready. Type 'help'.")

	# Subscribe to the centralized game log
	if Engine.has_singleton("GameLog") or has_node("/root/GameLog"):
		var game_log: Node = get_node_or_null("/root/GameLog")
		if game_log != null and game_log.has_signal("log_message"):
			game_log.connect("log_message", Callable(self, "_on_game_log_message"))

func _on_game_log_message(text: String, level: int) -> void:
	# 0 = INFO, 1 = WARN, 2 = ERROR
	match level:
		1:
			_print_line("[color=yellow][WARN] %s[/color]" % text)
		2:
			_print_line("[color=red][ERROR] %s[/color]" % text)
		_:
			_print_line(text)

func _input(event: InputEvent) -> void:
	if GameInput.is_console_toggle_event(event):
		toggle_console()
		get_viewport().set_input_as_handled()
		return

	if not _panel.visible:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_set_console_visible(false)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_UP:
				_recall_history(-1)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_DOWN:
				_recall_history(1)
				get_viewport().set_input_as_handled()
				return

func is_console_open() -> bool:
	return _panel != null and _panel.visible

func toggle_console() -> void:
	_set_console_visible(not _panel.visible)

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 10
	_panel.offset_top = 10
	_panel.offset_right = -10
	_panel.offset_bottom = -10
	add_child(_panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	_panel.add_child(root)

	var title := Label.new()
	title.text = "Developer Console"
	root.add_child(title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.selection_enabled = true
	_log.context_menu_enabled = true
	_log.mouse_filter = Control.MOUSE_FILTER_STOP
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log)

	_input_line = LineEdit.new()
	_input_line.placeholder_text = "Enter command (help, ff 6h, spawn apple 5, copy)"
	_input_line.text_submitted.connect(_on_command_submitted)
	root.add_child(_input_line)

func _set_console_visible(show_console: bool) -> void:
	if _panel == null:
		return

	if show_console == _panel.visible:
		return

	_panel.visible = show_console
	if show_console:
		_was_mouse_captured_before_open = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_input_line.grab_focus()
	else:
		_input_line.release_focus()
		if _was_mouse_captured_before_open:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_command_submitted(raw: String) -> void:
	var command := raw.strip_edges()
	if command.is_empty():
		return

	_input_line.clear()
	_history.append(command)
	_history_cursor = _history.size()
	_print_line("> " + command)
	_execute_command(command)

func _execute_command(command: String) -> void:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return

	var verb := parts[0].to_lower()
	match verb:
		"help":
			_cmd_help()
		"clear":
			_cmd_clear()
		"copy":
			_cmd_copy()
		"time":
			_cmd_time(parts)
		"ff", "fastforward":
			_cmd_fast_forward(parts)
		"spawn":
			_cmd_spawn(parts)
		"spawn_scene":
			_cmd_spawn_scene(parts)
		"sim":
			_cmd_sim(parts)
		"chunks":
			_cmd_chunks(parts)
		"farmable":
			_cmd_farmable(parts)
		"godmode", "fly":
			_cmd_godmode(parts)
		_:
			_print_line("Unknown command: %s" % verb)

func _cmd_help() -> void:
	_print_line("Commands:")
	_print_line("  help")
	_print_line("  clear")
	_print_line("  copy                              (copy log to clipboard)")
	_print_line("  time now")
	_print_line("  time set <day> <hour> <minute>")
	_print_line("  ff <value>[m|h|d]  (example: ff 6h, ff 2d)")
	_print_line("  spawn list")
	_print_line("  spawn <vehicleBrand|alias> [count]")
	_print_line("  spawn_scene <res://...tscn> [count]")
	_print_line("  sim catchup <seconds>")
	_print_line("  chunks                            (toggle chunk grid overlay)")
	_print_line("  chunks info                       (print chunk loading stats)")
	_print_line("  farmable                          (toggle farmable grid overlay)")
	_print_line("  godmode / fly                     (toggle player noclip free-fly)")

func _cmd_clear() -> void:
	if _log != null:
		_log.clear()

func _cmd_copy() -> void:
	if _log == null:
		return
	var text := _log.get_parsed_text()
	DisplayServer.clipboard_set(text)
	_print_line("[Copied %d characters to clipboard]" % text.length())

func _cmd_time(parts: Array[String]) -> void:
	if parts.size() < 2:
		_print_line("Usage: time now | time set <day> <hour> <minute>")
		return

	var sub := parts[1].to_lower()
	if sub == "now":
		_print_line("Day %d %02d:%02d" % [TimeManager.current_day, TimeManager.current_hour, TimeManager.current_minute])
		return

	if sub == "set":
		if parts.size() < 5:
			_print_line("Usage: time set <day> <hour> <minute>")
			return
		var day := int(parts[2])
		var hour := int(parts[3])
		var minute := int(parts[4])
		TimeManager.set_time(day, hour, minute)
		FarmData.simulate_passage_of_time(0)
		_print_line("Time set to Day %d %02d:%02d" % [TimeManager.current_day, TimeManager.current_hour, TimeManager.current_minute])
		return

	_print_line("Usage: time now | time set <day> <hour> <minute>")

func _cmd_fast_forward(parts: Array[String]) -> void:
	if parts.size() < 2:
		_print_line("Usage: ff <value>[m|h|d]")
		return

	var minutes := _parse_duration_to_minutes(parts[1])
	if minutes <= 0:
		_print_line("Invalid duration. Use formats like 30m, 6h, 2d")
		return

	var result: Dictionary = TimeManager.fast_forward_minutes(minutes, false)
	FarmData.simulate_passage_of_time(minutes * 60, true)
	_print_line("Fast-forwarded %d minutes. Now Day %d %02d:%02d" % [
		int(result.get("advanced_minutes", 0)),
		TimeManager.current_day,
		TimeManager.current_hour,
		TimeManager.current_minute
	])

func _cmd_spawn(parts: Array[String]) -> void:
	if parts.size() < 2:
		_print_line("Usage: spawn list | spawn <vehicleBrand|alias> [count]")
		return

	if parts[1].to_lower() == "list":
		var aliases := _spawn_registry.keys()
		aliases.sort()
		_print_line("Spawn aliases: " + ", ".join(aliases))
		var manager := _get_vehicle_manager()
		if manager != null and manager.has_method("get_spawnable_brands"):
			var brands_any: Variant = manager.call("get_spawnable_brands")
			if brands_any is Array and not (brands_any as Array).is_empty():
				var brand_names: Array[String] = []
				for item: Variant in brands_any:
					if item is String:
						brand_names.append(item)
				brand_names.sort()
				_print_line("Vehicle brands: " + ", ".join(brand_names))
		return

	var alias := parts[1].to_lower()
	var count := default_spawn_count
	if parts.size() >= 3:
		count = maxi(1, int(parts[2]))

	if _spawn_vehicle_brand(alias, count):
		return

	if not _spawn_registry.has(alias):
		_print_line("Unknown spawn brand/alias: %s" % alias)
		return

	_spawn_by_scene_path(String(_spawn_registry[alias]), count)

func _cmd_spawn_scene(parts: Array[String]) -> void:
	if parts.size() < 2:
		_print_line("Usage: spawn_scene <res://...tscn> [count]")
		return

	var scene_path := parts[1]
	var count := default_spawn_count
	if parts.size() >= 3:
		count = maxi(1, int(parts[2]))

	_spawn_by_scene_path(scene_path, count)

func _cmd_sim(parts: Array[String]) -> void:
	if parts.size() < 3:
		_print_line("Usage: sim catchup <seconds>")
		return

	if parts[1].to_lower() != "catchup":
		_print_line("Usage: sim catchup <seconds>")
		return

	var seconds := maxi(0, int(parts[2]))
	FarmData.simulate_passage_of_time(seconds, true)
	_print_line("Applied simulation catch-up for %d seconds." % seconds)

func _cmd_chunks(parts: Array[String]) -> void:
	if parts.size() >= 2 and parts[1].to_lower() == "info":
		_print_chunks_info()
		return

	var grid_mgr := _get_grid_manager()
	if grid_mgr == null or not grid_mgr.has_method("toggle_chunk_grid"):
		_print_line("Chunk grid not available (GridManager not found).")
		return

	var now_visible: bool = grid_mgr.toggle_chunk_grid()
	_print_line("Chunk grid overlay: %s" % ("ON" if now_visible else "OFF"))

func _cmd_farmable(_parts: Array[String]) -> void:
	var grid_mgr := _get_grid_manager()
	if grid_mgr == null or not grid_mgr.has_method("toggle_farmable_grid"):
		_print_line("GridManager not found or doesn't support farmable grid.")
		return
	var now_visible: bool = grid_mgr.toggle_farmable_grid()
	_print_line("Farmable grid overlay: %s" % ("ON" if now_visible else "OFF"))

func _cmd_godmode(_parts: Array[String]) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("toggle_godmode"):
		_print_line("Player not found or missing godmode method.")
		return
	var is_enabled: bool = player.toggle_godmode()
	_print_line("Godmode (Noclip Fly): %s" % ("ON" if is_enabled else "OFF"))

func _print_chunks_info() -> void:
	var grid_mgr := _get_grid_manager()
	var loaded_visual := 0
	var center := Vector2i.ZERO
	var radius := 0
	if grid_mgr != null:
		if grid_mgr.has_method("get_loaded_chunk_count"):
			loaded_visual = grid_mgr.get_loaded_chunk_count()
		if grid_mgr.has_method("get_stream_center_chunk"):
			center = grid_mgr.get_stream_center_chunk()
		if grid_mgr.has_method("get_stream_radius"):
			radius = grid_mgr.get_stream_radius()
	var total_data := FarmData.get_total_chunk_count()
	var loaded_sim := FarmData.get_loaded_chunk_count()
	var unloaded_sim := FarmData.get_unloaded_chunk_count()
	_print_line("Visual: %d chunks loaded (radius %d, center %d,%d)" % [loaded_visual, radius, center.x, center.y])
	_print_line("FarmData: %d total data chunks | %d sim-loaded | %d sim-unloaded" % [total_data, loaded_sim, unloaded_sim])
	_print_line("Chunk size: %d tiles" % FarmData.simulation_chunk_size_tiles)

func _get_grid_manager() -> Node:
	return get_tree().get_first_node_in_group("grid_manager")

func _parse_duration_to_minutes(token: String) -> int:
	var t := token.strip_edges().to_lower()
	if t.is_empty():
		return 0

	var unit := t.right(1)
	var value_text := t
	if unit == "m" or unit == "h" or unit == "d":
		value_text = t.left(t.length() - 1)
	else:
		unit = "m"

	var value := int(value_text)
	if value <= 0:
		return 0

	match unit:
		"m":
			return value
		"h":
			return value * 60
		"d":
			return value * 1440
		_:
			return 0

func _spawn_by_scene_path(scene_path: String, count: int) -> void:
	var packed := load(scene_path)
	if not (packed is PackedScene):
		_print_line("Failed to load PackedScene: %s" % scene_path)
		return

	var parent := get_tree().current_scene
	if parent == null:
		_print_line("No active scene to spawn into.")
		return

	var origin := _get_spawn_origin()
	var spawned := 0
	for i in range(count):
		var instance: Node = (packed as PackedScene).instantiate()
		if instance is Node3D:
			# Set position BEFORE adding to tree so that _ready(), SimulationCore registration,
			# and GEVP physics wheels initialize using the correct spawn position.
			var spawn_pos := _compute_spawn_position(origin, i)
			# Since instance is not in tree yet, setting global_position works on its local transform.
			(instance as Node3D).global_position = spawn_pos
		parent.add_child(instance)
		spawned += 1

	_print_line("Spawned %d x %s" % [spawned, scene_path])

func _compute_spawn_position(origin: Vector3, index: int) -> Vector3:
	if index == 0:
		return origin
	var ring := 1 + int(floor(sqrt(float(index))))
	var angle := float(index) * 0.7
	var spawn_offset := Vector3(cos(angle), 0.0, sin(angle)) * (ring * 1.5)
	return origin + spawn_offset

func _get_spawn_origin() -> Vector3:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		var p := player as Node3D
		var forward := -p.global_basis.z.normalized()
		return _snap_spawn_to_ground(p.global_position + forward * spawn_distance_from_player + Vector3.UP * 0.5)

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return _snap_spawn_to_ground(camera.global_position + (-camera.global_basis.z.normalized() * spawn_distance_from_player))

	return Vector3.ZERO

func _snap_spawn_to_ground(origin: Vector3) -> Vector3:
	var world := get_viewport().get_world_3d()
	if world == null:
		return origin

	var space_state := world.direct_space_state
	var ray_start := origin + Vector3.UP * 10.0
	var ray_end := origin + Vector3.DOWN * 50.0
	var params := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	var result := space_state.intersect_ray(params)
	if result.has("position"):
		var hit: Vector3 = result["position"]
		return Vector3(origin.x, hit.y + 0.5, origin.z)

	return origin

func _build_spawn_registry() -> void:
	_spawn_registry.clear()
	_register_default_spawn_alias("apple", "res://Scenes/Apple.tscn")
	_register_default_spawn_alias("tractor", "res://Scenes/Tractor.tscn")
	_register_default_spawn_alias("testboxvehicle", "res://Scenes/TestBoxVehicle.tscn")
	_register_default_spawn_alias("plow_attachment", "res://Scenes/PlowAttachment.tscn")
	_register_default_spawn_alias("player", "res://Scenes/Player.tscn")

	var dir := DirAccess.open("res://Scenes")
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".tscn"):
			var alias := file_name.trim_suffix(".tscn").to_lower()
			var scene_path := "res://Scenes/" + file_name
			if not _spawn_registry.has(alias):
				_spawn_registry[alias] = scene_path
		file_name = dir.get_next()
	dir.list_dir_end()

func _spawn_vehicle_brand(brand: String, count: int) -> bool:
	var manager := _get_vehicle_manager()
	if manager == null or not manager.has_method("spawn_vehicle_by_brand"):
		return false

	var origin := _get_spawn_origin()
	var spawned := 0
	for i in range(count):
		var spawn_pos := _compute_spawn_position(origin, i)
		var vehicle_id_any: Variant = manager.call("spawn_vehicle_by_brand", brand, spawn_pos, 0.0)
		if vehicle_id_any is StringName and vehicle_id_any != &"":
			spawned += 1
		elif vehicle_id_any is String and not String(vehicle_id_any).is_empty():
			spawned += 1

	if spawned > 0:
		_print_line("Spawned %d x vehicle brand '%s'" % [spawned, brand])
		return true

	return false

func _get_vehicle_manager() -> Node:
	return get_tree().get_first_node_in_group("vehicle_manager")

func _register_default_spawn_alias(alias: String, scene_path: String) -> void:
	if ResourceLoader.exists(scene_path):
		_spawn_registry[alias.to_lower()] = scene_path

func _recall_history(direction: int) -> void:
	if _history.is_empty():
		return

	_history_cursor = clampi(_history_cursor + direction, 0, _history.size())
	if _history_cursor >= _history.size():
		_input_line.text = ""
		return

	_input_line.text = _history[_history_cursor]
	_input_line.caret_column = _input_line.text.length()

func _print_line(text: String) -> void:
	if _log == null:
		return
	_log.append_text(text + "\n")
	_trim_log_history()

func _trim_log_history() -> void:
	if _log == null:
		return

	var parsed_text := _log.get_parsed_text()
	var lines := parsed_text.split("\n", false)
	if lines.size() <= max_history_lines:
		return

	var start := lines.size() - max_history_lines
	_log.clear()
	_log.append_text("\n".join(lines.slice(start, lines.size())) + "\n")
