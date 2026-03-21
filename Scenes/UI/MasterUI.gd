extends CanvasLayer

@onready var top_left: VBoxContainer = %TopLeft
@onready var bottom_left: VBoxContainer = %BottomLeft
@onready var top_right: VBoxContainer = %TopRight
@onready var bottom_right: VBoxContainer = %BottomRight
@onready var interaction_prompt: Label = %InteractionPrompt
@onready var center_container: CenterContainer = $Margin/Center

var _debug_overlay: Node = null

func _ready() -> void:
	interaction_prompt.hide()
	EventBus.update_crosshair_prompt.connect(_on_update_crosshair_prompt)

	_add_component(top_right, preload("res://Scenes/UI/TimeUI.tscn"))
	_add_component(bottom_left, preload("res://Scenes/UI/ToolUI.tscn"))
	_add_component(center_container, preload("res://Scenes/UI/HelpUI.tscn"))

	# Load debug overlays only if enabled in Project Settings
	if ProjectSettings.get_setting("game/debug/enable_debug_overlay"):
		var debug_script_res: Resource = load("res://Scripts/debug/SimulationDebugOverlay.gd")
		if debug_script_res is GDScript:
			_debug_overlay = Control.new()
			_debug_overlay.set_script(debug_script_res)
			_debug_overlay.name = "SimulationDebugOverlay"
			top_left.add_child(_debug_overlay)

func _add_component(parent: Control, scene: PackedScene) -> void:
	if scene != null:
		parent.add_child(scene.instantiate())

func _on_update_crosshair_prompt(text: String) -> void:
	if text.is_empty():
		interaction_prompt.hide()
	else:
		interaction_prompt.text = text
		interaction_prompt.show()

func _input(event: InputEvent) -> void:
	if GameInput.is_ui_toggle_event(event):
		# Toggle visibility of the entire UI, including debug overlays
		visible = not visible
		get_viewport().set_input_as_handled()
