extends Node

@export var world_map_scene: PackedScene = preload("res://Scenes/World/WorldMap.tscn")

@onready var _world_3d_container: Node3D = get_node("View_Manager/3D_World") as Node3D
@onready var _map_2d_container: Node2D = get_node("View_Manager/2D_Map") as Node2D
@onready var _ui_layer: Node = get_node("UI_Layer")

var _world_instance: Node = null

const _SETTING_ENABLE_DEVCONSOLE := "game/debug/enable_developer_console"
const _SETTING_ENABLE_DEBUG_OVERLAY := "game/debug/enable_debug_overlay"

func _ready() -> void:
	GameInput.ensure_default_bindings()
	_world_instance = _world_3d_container.get_node_or_null("WorldMap")
	_instantiate_ui()
	_instantiate_debug_tools()

	if _world_instance != null:
		MapManager.populate_world(_world_instance)
	else:
		set_3d_world_loaded(true)

func _instantiate_ui() -> void:
	if _ui_layer == null:
		return
	
	var master_ui_scene: PackedScene = load("res://Scenes/UI/MasterUI.tscn")
	if master_ui_scene:
		var master_ui: Node = master_ui_scene.instantiate()
		_ui_layer.add_child(master_ui)

func _instantiate_debug_tools() -> void:
	if _ui_layer == null:
		return

	# Developer Console — detachable via project setting
	if _is_setting_enabled(_SETTING_ENABLE_DEVCONSOLE, true):
		var console_script: GDScript = load("res://Scripts/debug/DeveloperConsole.gd") as GDScript
		if console_script != null:
			var console := CanvasLayer.new()
			console.name = "DeveloperConsole"
			console.set_script(console_script)
			_ui_layer.add_child(console)

func _is_setting_enabled(setting_name: String, default_value: bool) -> bool:
	if not ProjectSettings.has_setting(setting_name):
		return default_value
	return bool(ProjectSettings.get_setting(setting_name))

func set_3d_world_loaded(should_load: bool) -> void:
	if should_load:
		if _world_instance != null and is_instance_valid(_world_instance):
			return
		if world_map_scene == null:
			GameLog.warn("Main.set_3d_world_loaded called without a world_map_scene")
			return
		_world_instance = world_map_scene.instantiate()
		_world_instance.name = "WorldMap"
		_world_3d_container.add_child(_world_instance)
		
		# --- ADD THIS LINE ---
		MapManager.populate_world(_world_instance)
		# ---------------------
		return

	if _world_instance != null and is_instance_valid(_world_instance):
		_world_instance.queue_free()
	_world_instance = null

func set_2d_map_visible(is_visible: bool) -> void:
	_map_2d_container.visible = is_visible
