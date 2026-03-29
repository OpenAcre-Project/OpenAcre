extends CanvasLayer

@export var start_open: bool = false
@export var max_history_lines: int = 1000
@export var spawn_distance_from_player: float = 6.0
@export var default_spawn_count: int = 1
@export var auto_run_commands: Array[String] = ["st"]

var _panel: Panel
var _log: RichTextLabel
var _input_line: LineEdit
var _history: Array[String] = []
var _history_cursor: int = 0
var _spawn_registry: Dictionary = {}
var _was_mouse_captured_before_open := false

class CommandDef:
	var cmd_name: String
	var description: String
	var usage: String
	var method: String
	var aliases: Array[String]

	func _init(n: String, d: String, u: String, m: String, a: Array[String] = []) -> void:
		cmd_name = n
		description = d
		usage = u
		method = m
		aliases = a

var _commands: Array[CommandDef] = []
var _command_map: Dictionary = {}

func _ready() -> void:
	# Console survives game crashes — always processes even if scene tree pauses
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("developer_console")
	_build_ui()
	_build_spawn_registry()
	_register_all_commands()
	_set_console_visible(start_open)
	_print_line("Developer console ready. Type 'help'.")

	# Subscribe to the centralized game log
	EventBus.log_message.connect(Callable(self , "_on_game_log_message"))
	
	# Auto-run commands with a small delay to ensure world/player initialization
	_run_auto_commands_deferred()

func _run_auto_commands_deferred() -> void:
	await get_tree().create_timer(0.2).timeout
	for cmd in auto_run_commands:
		_print_line("[color=gray][Auto-run] > %s[/color]" % cmd)
		_execute_command(cmd)

func _on_game_log_message(text: String, level: int) -> void:
	# 0 = INFO, 1 = WARN, 2 = ERROR
	match level:
		1:
			_print_line("[color=yellow][WARN] %s[/color]" % text)
		2:
			_print_line("[color=red][ERROR] %s[/color]" % text)
		_:
			_print_line(text)

func _register_all_commands() -> void:
	_register_command("help", "Show this help message", "help", "_cmd_help")
	_register_command("clear", "Clear the console output", "clear", "_cmd_clear")
	_register_command("copy", "Copy log to clipboard", "copy", "_cmd_copy")
	_register_command("time", "Manage time (e.g. time now, time set)", "time now | time set <d> <h> <m>", "_cmd_time")
	_register_command("fastforward", "Fast forward time (e.g. ff 6h, ff 2d)", "ff <value>[m|h|d]", "_cmd_fast_forward", ["ff"])
	_register_command("spawn", "Spawn a vehicle or alias", "spawn list | spawn <brand|alias|spec> [count]", "_cmd_spawn", ["s"])
	_register_command("spawn_scene", "Spawn a specific .tscn file directly", "spawn_scene <res://...tscn> [count]", "_cmd_spawn_scene")
	_register_command("sim", "Manage simulation (e.g. catchup)", "sim catchup <seconds>", "_cmd_sim")
	_register_command("chunks", "Toggle chunk grid overlay or show chunks info", "chunks | chunks info", "_cmd_chunks")
	_register_command("farmable", "Toggle farmable grid overlay", "farmable", "_cmd_farmable")
	_register_command("godmode", "Toggle player noclip free-fly mode", "godmode", "_cmd_godmode", ["fly"])
	_register_command("inventory", "List all items currently in player pockets", "inv", "_cmd_inventory", ["inv"])
	_register_command("keybinds", "List all game keybinds", "keybinds", "_cmd_keybinds")
	_register_command("st", "Spawn tractor and plow in position", "spawntest [vehicle_spec] [plow_alias]", "_cmd_spawn_test")

func _register_command(cmd_name: String, desc: String, usage: String, method: String, aliases: Array[String] = []) -> void:
	var cmd := CommandDef.new(cmd_name, desc, usage, method, aliases)
	_commands.append(cmd)
	_command_map[cmd_name] = cmd
	for alias: String in aliases:
		_command_map[alias] = cmd

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
	if _command_map.has(verb):
		var cmd: CommandDef = _command_map[verb]
		call(cmd.method, parts)
	else:
		_print_line("Unknown command: %s" % verb)

func _cmd_help(_parts: Array[String] = []) -> void:
	_print_line("[color=white]========================================[/color]")
	_print_line("[color=cyan]DEVELOPER CONSOLE COMMANDS[/color]")
	_print_line("[color=white]========================================[/color]")
	for cmd: CommandDef in _commands:
		var name_str := cmd.cmd_name
		if not cmd.aliases.is_empty():
			name_str += " (" + ", ".join(cmd.aliases) + ")"
		
		var spaces := 20 - name_str.length()
		var padding := ""
		for i in range(maxi(1, spaces)):
			padding += " "
		
		_print_line("[color=yellow]%s[/color]%s- %s" % [name_str, padding, cmd.description])
		if cmd.usage != cmd.cmd_name:
			_print_line("  [color=gray]Usage: %s[/color]" % cmd.usage)
	_print_line("[color=white]========================================[/color]")

func _cmd_clear(_parts: Array[String] = []) -> void:
	if _log != null:
		_log.clear()

func _cmd_copy(_parts: Array[String] = []) -> void:
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
		_print_line("Day %d %02d:%02d" % [GameManager.session.time.current_day, GameManager.session.time.current_hour, GameManager.session.time.current_minute])
		return

	if sub == "set":
		if parts.size() < 5:
			_print_line("Usage: time set <day> <hour> <minute>")
			return
		var day := int(parts[2])
		var hour := int(parts[3])
		var minute := int(parts[4])
		GameManager.session.time.set_time(day, hour, minute)
		GameManager.session.farm.simulate_passage_of_time(0)
		_print_line("Time set to Day %d %02d:%02d" % [GameManager.session.time.current_day, GameManager.session.time.current_hour, GameManager.session.time.current_minute])
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

	var result: Dictionary = GameManager.session.time.fast_forward_minutes(minutes, false)
	GameManager.session.farm.simulate_passage_of_time(minutes * 60, true)
	_print_line("Fast-forwarded %d minutes. Now Day %d %02d:%02d" % [
		int(result.get("advanced_minutes", 0)),
		GameManager.session.time.current_day,
		GameManager.session.time.current_hour,
		GameManager.session.time.current_minute
	])

func _cmd_spawn(parts: Array[String]) -> void:
	if parts.size() < 2:
		_print_line("Usage: spawn list | spawn <vehicleBrand|alias> [count]")
		return

	if parts[1].to_lower() == "list":
		var aliases := _spawn_registry.keys()
		aliases.sort()
		_print_line("Scene aliases: " + ", ".join(aliases))
		
		var specs: Array[String] = []
		for key: Variant in EntityRegistry._definitions.keys():
			specs.append(String(key))
		specs.sort()
		_print_line("Entity Registry (UESS): " + ", ".join(specs))
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

func _cmd_spawn_test(parts: Array[String]) -> void:
	var vehicle_id_to_spawn := "vehicle.truck"
	var implement_id_to_spawn := "vehicle.plow" # "vehicle.drawbar"
	
	if parts.size() >= 2: vehicle_id_to_spawn = parts[1]
	if parts.size() >= 3: implement_id_to_spawn = parts[2]
	
	var origin: Vector3 = _get_spawn_origin()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var yaw: float = player.rotation.y if player != null else 0.0
	var forward: Vector3 = - player.global_basis.z.normalized() if player != null else Vector3.FORWARD
	
	_print_line("Setting up test rig: Vehicle=%s, Implement=%s" % [vehicle_id_to_spawn, implement_id_to_spawn])
	
	# Spawn Tractor far away (facing same way)
	var tractor_pos: Vector3 = origin + forward * 6.0
	_spawn_vehicle(vehicle_id_to_spawn, tractor_pos, yaw)
	
	# Spawn Plow close-ish (behind tractor)
	var plow_pos := origin - forward * 1.0
	_spawn_vehicle(implement_id_to_spawn, plow_pos, yaw + 3.14)

func _spawn_vehicle(alias: String, pos: Vector3, yaw: float) -> void:
	var def_id: StringName = _resolve_entity_def_id(alias)
	if def_id == &"":
		_print_line("EntityRegistry: Unknown definition/alias: " + alias)
		return
		
	var entity: EntityData = EntityRegistry.create_entity(def_id)
	if entity:
		var tf: TransformComponent = entity.get_transform()
		if tf:
			tf.world_position = pos
			tf.world_rotation_radians = yaw
		GameManager.session.entities.register_entity(entity)
		_print_line("Spawned UESS Entity: " + String(def_id))

func _spawn_by_alias(alias: String, pos: Vector3, yaw: float) -> void:
	if not _spawn_registry.has(alias.to_lower()):
		_print_line("Unknown implement alias: " + alias)
		return
	var scene_path: String = _spawn_registry[alias.to_lower()]
	var packed := load(scene_path)
	if packed is PackedScene:
		var instance: Node = packed.instantiate()
		if instance is Node3D:
			instance.position = pos
			instance.rotation.y = yaw
		get_tree().current_scene.add_child(instance)
		_print_line("Spawned implement: " + scene_path)

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
	GameManager.session.farm.simulate_passage_of_time(seconds, true)
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

func _cmd_inventory(_parts: Array[String] = []) -> void:
	var player_data := GameManager.session.entities.get_player(&"player.main")
	if not player_data:
		_print_line("Player data not found.")
		return
		
	var pockets: InventoryData = player_data.pockets
	if pockets.entity_ids.is_empty():
		_print_line("Inventory is empty.")
		return
		
	_print_line("--- Player Inventory ---")
	var em := GameManager.session.entities as EntityManager
	for i in range(pockets.entity_ids.size()):
		var eid: StringName = pockets.entity_ids[i]
		var entity := em.get_entity(eid)
		if entity:
			var stack_count: int = 1
			var stack_comp := entity.get_component(&"stackable") as StackableComponent
			if stack_comp:
				stack_count = stack_comp.count
			var comp_list: Array = []
			for comp: Component in entity.get_all_components():
				comp_list.append(String(comp.type_id))
			_print_line("[%d] %s x%d  [%s]  (id: %s)" % [i, entity.definition_id, stack_count, ", ".join(comp_list), eid])
		else:
			_print_line("[%d] <missing entity: %s>" % [i, eid])
	_print_line("Total Mass: %.2f / %.2f kg" % [pockets.get_current_mass(), pockets.max_mass])
	_print_line("Total Volume: %.2f / %.2f L" % [pockets.get_total_volume(), pockets.max_volume])

func _cmd_keybinds(_parts: Array[String] = []) -> void:
	_print_line("--- Keybindings ---")
	_print_line("Interact: " + GameInput.get_action_binding_text(GameInput.ACTION_INTERACT))
	_print_line("Toggle UI: " + GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_UI))
	_print_line("Toggle Help: " + GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_HELP))
	_print_line("Toggle Debug Overlay: " + GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_DEBUG))
	_print_line("Toggle Developer Console: " + GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_CONSOLE))
	_print_line("Camera Up: " + GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_UP))
	_print_line("Camera Down: " + GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_DOWN))
	_print_line("Camera Zoom In: " + GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_ZOOM_IN))
	_print_line("Camera Zoom Out: " + GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_ZOOM_OUT))
	_print_line("Vehicle Throttle: " + GameInput.get_action_binding_text(GameInput.ACTION_VEHICLE_THROTTLE))
	_print_line("Vehicle Reverse: " + GameInput.get_action_binding_text(GameInput.ACTION_VEHICLE_REVERSE))
	_print_line("Vehicle Steer Left: " + GameInput.get_action_binding_text(GameInput.ACTION_VEHICLE_STEER_LEFT))
	_print_line("Vehicle Steer Right: " + GameInput.get_action_binding_text(GameInput.ACTION_VEHICLE_STEER_RIGHT))
	_print_line("Vehicle Brake: " + GameInput.get_action_binding_text(GameInput.ACTION_VEHICLE_BRAKE))

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
	var total_data := GameManager.session.farm.get_total_chunk_count()
	var loaded_sim := GameManager.session.farm.get_loaded_chunk_count()
	var unloaded_sim := GameManager.session.farm.get_unloaded_chunk_count()
	_print_line("Visual: %d chunks loaded (radius %d, center %d,%d)" % [loaded_visual, radius, center.x, center.y])
	_print_line("FarmData: %d total data chunks | %d sim-loaded | %d sim-unloaded" % [total_data, loaded_sim, unloaded_sim])
	_print_line("Chunk size: %d tiles" % GameManager.session.farm.simulation_chunk_size_tiles)

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
			# Since instance is not in tree yet, setting position works identically
			(instance as Node3D).position = spawn_pos
		parent.add_child(instance)
		spawned += 1

	_print_line("Spawned %d x %s" % [spawned, scene_path])
	if scene_path.begins_with("res://Scenes/Vehicles/"):
		_print_line("Warning: Scene-spawned vehicles bypass UESS streaming/despawn. Use Entity IDs like 'vehicle.truck' with spawn.")

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
	_register_default_spawn_alias("apple", "res://Scenes/Interactables/Apple.tscn")
	_register_default_spawn_alias("plow", "res://Scenes/Vehicles/Attachments/PlowAttachment.tscn")
	_register_default_spawn_alias("draw", "res://Scenes/Vehicles/Attachments/DrawbarAttachment.tscn")
	_register_default_spawn_alias("player", "res://Scenes/Actors/Player.tscn")

	_scan_scenes_recursive("res://Scenes")

func _scan_scenes_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_scenes_recursive(path.path_join(file_name))
		elif file_name.to_lower().ends_with(".tscn"):
			var alias := file_name.trim_suffix(".tscn").to_lower()
			var scene_path := path.path_join(file_name)
			if not _spawn_registry.has(alias):
				_spawn_registry[alias] = scene_path
		file_name = dir.get_next()
	dir.list_dir_end()

func _spawn_vehicle_brand(alias: String, count: int) -> bool:
	var def_id: StringName = _resolve_entity_def_id(alias)
	if def_id == &"":
		return false

	var origin := _get_spawn_origin()
	var spawned := 0
	for i in range(count):
		var spawn_pos := _compute_spawn_position(origin, i)
		var entity: EntityData = EntityRegistry.create_entity(def_id)
		if entity:
			var tf: TransformComponent = entity.get_transform()
			if tf:
				tf.world_position = spawn_pos
				tf.world_rotation_radians = 0.0
			GameManager.session.entities.register_entity(entity)
			spawned += 1

	if spawned > 0:
		_print_line("Spawned %d x UESS Entity '%s'" % [spawned, String(def_id)])
		return true

	return false

func _resolve_entity_def_id(alias: String) -> StringName:
	var cleaned := alias.strip_edges().to_lower()
	var candidates: Array[StringName] = [
		StringName(cleaned),
		StringName("vehicle." + cleaned),
		StringName("item." + cleaned)
	]

	for candidate: StringName in candidates:
		if EntityRegistry.has_def(candidate):
			return candidate
	return &""

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
