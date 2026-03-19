extends RefCounted

var _tools: Array[Tool] = []
var _active_index: int = -1

func add_tool(tool: Tool) -> void:
	if tool == null:
		return
	_tools.append(tool)
	if _active_index == -1:
		_active_index = 0

func equip_slot(slot_number: int) -> bool:
	var index := slot_number - 1
	if index < 0 or index >= _tools.size():
		return false
	_active_index = index
	return true

func get_active_tool() -> Tool:
	if _active_index < 0 or _active_index >= _tools.size():
		return null
	return _tools[_active_index]

func get_active_tool_name() -> String:
	var tool := get_active_tool()
	if tool == null:
		return "None"
	return tool.tool_name
