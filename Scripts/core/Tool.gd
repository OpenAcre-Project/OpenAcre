extends Node

class_name Tool

# The name of the tool, displayed in the UI
@export var tool_name: String = "Base Tool"

# This function is called when the player clicks with the tool equipped.
# It should be overridden by child classes to perform specific actions.
func use_tool(_player: CharacterBody3D, _block_pos: Vector3, _normal: Vector3) -> void:
	pass
