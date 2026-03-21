extends PanelContainer

@onready var help_text: Label = %HelpText

func _ready() -> void:
	hide()
	_refresh_controls_text()

func _input(event: InputEvent) -> void:
	if GameInput.is_help_toggle_event(event):
		visible = not visible
		get_viewport().set_input_as_handled()

func _refresh_controls_text() -> void:
	var interact := GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)
	var help_toggle := GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_HELP)
	var ui_toggle := GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_UI)
	var camera_up := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_UP)
	var camera_down := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_DOWN)
	var zoom_in := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_ZOOM_IN)
	var zoom_out := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_ZOOM_OUT)

	var rows: Array[String] = [
		"CONTROLS",
		"",
		"Movement",
		"WASD        Move",
		"Shift       Sprint",
		"Space       Jump",
		"",
		"Tools",
		"1           Equip Hoe (Plow)",
		"2           Equip Seeds (Plant)",
		"Left Click  Use Tool",
		"%s           Interact" % interact,
		"",
		"Camera",
		"%s / %s   Up / Down" % [camera_up, camera_down],
		"%s / %s   Zoom In / Out" % [zoom_in, zoom_out],
		"",
		"%s          Toggle Help" % help_toggle,
		"%s          Toggle UI" % ui_toggle
	]

	help_text.text = "\n".join(rows)
