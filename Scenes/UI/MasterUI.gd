extends CanvasLayer

@onready var top_left: VBoxContainer = %TopLeft
@onready var bottom_left: VBoxContainer = %BottomLeft
@onready var top_right: VBoxContainer = %TopRight
@onready var bottom_right: VBoxContainer = %BottomRight
@onready var interaction_prompt: Label = %InteractionPrompt
@onready var center_container: CenterContainer = $Margin/Center
@onready var pause_overlay: Control = %PauseOverlay
@onready var slot_spinbox: SpinBox = %SlotSpinBox
@onready var slot_meta_label: Label = %SlotMetaLabel
@onready var pause_status_label: Label = %PauseStatusLabel
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var resume_button: Button = %ResumeButton

var _debug_overlay: Node = null
var _was_mouse_captured_before_pause := false
var _menu_busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	interaction_prompt.hide()
	pause_overlay.hide()
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	slot_spinbox.value_changed.connect(_on_slot_changed)
	_update_pause_status("", false)

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
	if GameInput.is_gameplay_input_blocked(get_tree()) and not pause_overlay.visible:
		return

	if GameInput.is_pause_menu_toggle_event(event):
		if pause_overlay.visible:
			_close_pause_menu()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if GameInput.is_ui_toggle_event(event):
		# Toggle visibility of the entire UI, including debug overlays
		visible = not visible
		get_viewport().set_input_as_handled()

func _open_pause_menu() -> void:
	if _menu_busy:
		return
	pause_overlay.show()
	_menu_busy = false
	_was_mouse_captured_before_pause = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	_update_pause_metadata_preview()
	save_button.grab_focus()

func _close_pause_menu() -> void:
	if _menu_busy:
		return
	pause_overlay.hide()
	get_tree().paused = false
	if _was_mouse_captured_before_pause:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _set_menu_busy(is_busy: bool) -> void:
	_menu_busy = is_busy
	save_button.disabled = is_busy
	load_button.disabled = is_busy
	slot_spinbox.editable = not is_busy

func _update_pause_metadata_preview() -> void:
	var slot_index := int(round(slot_spinbox.value))
	var metadata: Dictionary = SaveManager.get_slot_metadata(slot_index)
	if metadata.is_empty():
		slot_meta_label.text = "Slot %02d: Empty" % slot_index
		return

	var saved_unix := int(metadata.get("saved_unix", 0))
	var dt := Time.get_datetime_dict_from_unix_time(saved_unix)
	var map_name := str(metadata.get("map", "unknown"))
	var time_data: Dictionary = metadata.get("time", {})
	var day: int = int(time_data.get("day", 1))
	var hour: int = int(time_data.get("hour", 0))
	var minute: int = int(time_data.get("minute", 0))
	slot_meta_label.text = "Slot %02d: %04d-%02d-%02d %02d:%02d | map=%s | Day %d %02d:%02d" % [
		slot_index,
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
		map_name,
		day,
		hour,
		minute
	]

func _update_pause_status(text: String, is_error: bool) -> void:
	pause_status_label.text = text
	pause_status_label.modulate = Color(1.0, 0.45, 0.45, 1.0) if is_error else Color(0.75, 1.0, 0.75, 1.0)

func _on_slot_changed(_value: float) -> void:
	_update_pause_metadata_preview()

func _on_save_pressed() -> void:
	if _menu_busy:
		return
	var slot_index := int(round(slot_spinbox.value))
	_set_menu_busy(true)
	_update_pause_status("Saving slot %02d..." % slot_index, false)
	var ok := SaveManager.save_slot(slot_index)
	_set_menu_busy(false)
	if ok:
		_update_pause_metadata_preview()
		_update_pause_status("Save completed for slot %02d." % slot_index, false)
	else:
		_update_pause_status("Save failed for slot %02d. Check logs." % slot_index, true)

func _on_load_pressed() -> void:
	if _menu_busy:
		return
	var slot_index := int(round(slot_spinbox.value))
	_set_menu_busy(true)
	_update_pause_status("Loading slot %02d..." % slot_index, false)
	var ok := await SaveManager.load_slot(slot_index)
	_set_menu_busy(false)
	if ok:
		_update_pause_status("Load completed for slot %02d." % slot_index, false)
		_close_pause_menu()
	else:
		_update_pause_status("Load failed for slot %02d. Check logs." % slot_index, true)
		_update_pause_metadata_preview()

func _on_resume_pressed() -> void:
	_close_pause_menu()
