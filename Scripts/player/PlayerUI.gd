extends CanvasLayer

@onready var help_panel: Panel = $HelpPanel
@onready var tool_label: Label = $ToolLabel
@onready var help_text: Label = $HelpPanel/HelpText
@onready var help_hint: Label = $HelpHint

@export var help_panel_padding := Vector2(18.0, 14.0)
@export var help_panel_min_width := 300.0
@export var help_panel_max_width := 560.0

func _ready() -> void:
	refresh_controls_text()
	help_panel.hide()

func toggle_help() -> void:
	help_panel.visible = !help_panel.visible

func update_tool(tool_name: String) -> void:
	tool_label.text = "Equipped: " + tool_name

func refresh_controls_text() -> void:
	if help_text == null or help_hint == null:
		return

	var interact := GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)
	var help_toggle := GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_HELP)
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
		"%s          Toggle Help" % help_toggle
	]

	help_text.text = "\n".join(rows)
	_resize_help_panel_to_text(rows)

	help_hint.text = "Press %s for Help" % help_toggle

func _resize_help_panel_to_text(rows: Array[String]) -> void:
	var font: Font = help_text.get_theme_font("font")
	var font_size: int = help_text.get_theme_font_size("font_size")
	if font == null:
		return

	var line_spacing: int = help_text.get_theme_constant("line_spacing")
	var max_line_width: float = 0.0
	for row: String in rows:
		var line := row
		var line_size := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		max_line_width = max(max_line_width, line_size.x)

	var lines_count: int = rows.size()
	var total_text_height: float = (font.get_height(font_size) * float(lines_count)) + (float(maxi(0, lines_count - 1)) * float(line_spacing))
	var target_width: float = clamp(max_line_width + help_panel_padding.x * 2.0, help_panel_min_width, help_panel_max_width)
	var target_height: float = total_text_height + help_panel_padding.y * 2.0

	help_panel.custom_minimum_size = Vector2(target_width, target_height)
	help_panel.size = help_panel.custom_minimum_size
