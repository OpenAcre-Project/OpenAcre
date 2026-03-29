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

	# Action Context HUD (Moved from top_left to bottom_right)
	var vehicle_hud_res: Resource = load("res://Scripts/ui/VehicleHUD.gd")
	if vehicle_hud_res is GDScript:
		var vehicle_hud: PanelContainer = PanelContainer.new()
		vehicle_hud.set_script(vehicle_hud_res)
		vehicle_hud.name = "VehicleHUD"
		bottom_right.add_child(vehicle_hud)
		bottom_right.move_child(vehicle_hud, 0)

func _add_component(parent: Control, scene: PackedScene) -> void:
	if scene != null:
		parent.add_child(scene.instantiate())

func _on_update_crosshair_prompt(_text: String) -> void:
	pass

func _input(event: InputEvent) -> void:
	if GameInput.is_ui_toggle_event(event):
		# Toggle visibility of the entire UI, including debug overlays
		visible = not visible
		get_viewport().set_input_as_handled()
