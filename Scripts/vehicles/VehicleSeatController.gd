extends RefCounted
class_name VehicleSeatController

static func _set_terrain_camera(context_node: Node, camera: Camera3D) -> void:
	if context_node == null or camera == null:
		return
	var terrain: Node = context_node.get_tree().root.find_child("Terrain3D", true, false)
	if terrain != null and terrain.has_method("set_camera"):
		terrain.set_camera(camera)

static func enter_vehicle(player: CharacterBody3D, vehicle_camera: Camera3D) -> void:
	if player == null or vehicle_camera == null:
		return

	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	vehicle_camera.make_current()
	_set_terrain_camera(player, vehicle_camera)

static func exit_vehicle(player: CharacterBody3D, exit_point: Node3D, player_camera_path: NodePath = NodePath("SpringArm3D/Camera3D")) -> void:
	if player == null or exit_point == null:
		return

	player.global_position = exit_point.global_position
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT

	if player.has_node(player_camera_path):
		var player_camera: Node = player.get_node(player_camera_path)
		if player_camera is Camera3D:
			var player_camera_3d := player_camera as Camera3D
			player_camera_3d.make_current()
			_set_terrain_camera(player, player_camera_3d)
