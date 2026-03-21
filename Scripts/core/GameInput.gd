class_name GameInput
extends RefCounted

const ACTION_INTERACT := "game_interact"
const ACTION_TOGGLE_HELP := "game_toggle_help"
const ACTION_TOGGLE_DEBUG := "game_toggle_debug"
const ACTION_TOGGLE_CONSOLE := "game_toggle_console"
const ACTION_TOGGLE_UI := "game_toggle_ui"
const ACTION_CAMERA_UP := "camera_up"
const ACTION_CAMERA_DOWN := "camera_down"
const ACTION_CAMERA_ZOOM_IN := "camera_zoom_in"
const ACTION_CAMERA_ZOOM_OUT := "camera_zoom_out"
const ACTION_VEHICLE_THROTTLE := "vehicle_throttle"
const ACTION_VEHICLE_REVERSE := "vehicle_reverse"
const ACTION_VEHICLE_STEER_LEFT := "vehicle_steer_left"
const ACTION_VEHICLE_STEER_RIGHT := "vehicle_steer_right"
const ACTION_VEHICLE_BRAKE := "vehicle_brake"

static func ensure_default_bindings() -> void:
	_ensure_action_with_defaults(ACTION_INTERACT, [_key_event(KEY_F)])
	_ensure_action_with_defaults(ACTION_TOGGLE_HELP, [_key_event(KEY_F1)])
	_ensure_action_with_defaults(ACTION_TOGGLE_UI, [_key_event(KEY_F2)])
	_ensure_action_with_defaults(ACTION_TOGGLE_DEBUG, [_key_event(KEY_F3)])
	_ensure_action_with_defaults(ACTION_TOGGLE_CONSOLE, [_key_event(KEY_QUOTELEFT)])
	_ensure_action_with_defaults(ACTION_CAMERA_UP, [_key_event(KEY_Q)])
	_ensure_action_with_defaults(ACTION_CAMERA_DOWN, [_key_event(KEY_E)])
	_ensure_action_with_defaults(ACTION_CAMERA_ZOOM_IN, [_mouse_button_event(MOUSE_BUTTON_WHEEL_UP)])
	_ensure_action_with_defaults(ACTION_CAMERA_ZOOM_OUT, [_mouse_button_event(MOUSE_BUTTON_WHEEL_DOWN)])
	_ensure_action_with_defaults(ACTION_VEHICLE_THROTTLE, [_key_event(KEY_W), _key_event(KEY_UP)])
	_ensure_action_with_defaults(ACTION_VEHICLE_REVERSE, [_key_event(KEY_S), _key_event(KEY_DOWN)])
	_ensure_action_with_defaults(ACTION_VEHICLE_STEER_LEFT, [_key_event(KEY_A), _key_event(KEY_LEFT)])
	_ensure_action_with_defaults(ACTION_VEHICLE_STEER_RIGHT, [_key_event(KEY_D), _key_event(KEY_RIGHT)])
	_ensure_action_with_defaults(ACTION_VEHICLE_BRAKE, [_key_event(KEY_SPACE)])

static func _ensure_action_with_defaults(action_name: StringName, default_events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	if InputMap.action_get_events(action_name).is_empty():
		for input_event: InputEvent in default_events:
			InputMap.action_add_event(action_name, input_event)

static func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	return event

static func _mouse_button_event(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	return event

static func is_interact_event(event: InputEvent) -> bool:
	if not event.is_action_pressed(ACTION_INTERACT):
		return false
	if event is InputEventKey and event.is_echo():
		return false
	return true

static func is_help_toggle_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.is_echo() or not key_event.pressed:
			return false
		if key_event.keycode == KEY_F1 or key_event.physical_keycode == KEY_F1:
			return true

	return event.is_action_pressed(ACTION_TOGGLE_HELP)

static func is_debug_toggle_event(event: InputEvent) -> bool:
	if not event.is_action_pressed(ACTION_TOGGLE_DEBUG):
		return false
	if event is InputEventKey and event.is_echo():
		return false
	return true

static func is_ui_toggle_event(event: InputEvent) -> bool:
	if not event.is_action_pressed(ACTION_TOGGLE_UI):
		return false
	if event is InputEventKey and event.is_echo():
		return false
	return true

static func is_console_toggle_event(event: InputEvent) -> bool:
	if not event.is_action_pressed(ACTION_TOGGLE_CONSOLE):
		return false
	if event is InputEventKey and event.is_echo():
		return false
	return true

static func is_gameplay_input_blocked(tree: SceneTree) -> bool:
	if tree == null:
		return false

	for node_any: Node in tree.get_nodes_in_group("developer_console"):
		if node_any != null and node_any.has_method("is_console_open"):
			if node_any.call("is_console_open"):
				return true

	return false

static func get_action_binding_text(action_name: StringName) -> String:
	if not InputMap.has_action(action_name):
		return "Unbound"

	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	if events.is_empty():
		return "Unbound"

	var event: InputEvent = events[0]
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Mouse Wheel Down"
			MOUSE_BUTTON_LEFT:
				return "Mouse Left"
			MOUSE_BUTTON_RIGHT:
				return "Mouse Right"
			_:
				return "Mouse Button %d" % event.button_index

	return event.as_text()
