extends PanelContainer

var _vbox: VBoxContainer
var _crosshair_hint: String = ""
var _vehicle_hints: Array[String] = []

func _ready() -> void:
	# Styling
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	
	_vbox = VBoxContainer.new()
	margin.add_child(_vbox)
	
	hide()
	EventBus.update_vehicle_hints.connect(_on_update_vehicle_hints)
	EventBus.update_crosshair_prompt.connect(_on_update_crosshair_prompt)

func _on_update_crosshair_prompt(text: String) -> void:
	_crosshair_hint = text
	_refresh()

func _on_update_vehicle_hints(show_hud: bool, hints: Array) -> void:
	if not show_hud:
		_vehicle_hints = []
		_refresh()
		return

	var normalized_hints: Array[String] = []
	for hint_any: Variant in hints:
		normalized_hints.append(str(hint_any))
	_vehicle_hints = normalized_hints
	_refresh()

func _refresh() -> void:
	# Clear existing
	for child in _vbox.get_children():
		child.queue_free()
		
	var all_hints: Array[String] = []
	if not _crosshair_hint.is_empty():
		all_hints.append(_crosshair_hint)
	all_hints.append_array(_vehicle_hints)
	
	if all_hints.is_empty():
		hide()
		return
		
	# Rebuild
	for hint in all_hints:
		var label: Label = Label.new()
		label.text = hint
		label.add_theme_font_size_override("font_size", 14)
		_vbox.add_child(label)
		
	show()
