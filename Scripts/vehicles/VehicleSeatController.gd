extends RefCounted
class_name VehicleSeatController

static func enter_vehicle(player: CharacterBody3D, vehicle_camera: Camera3D) -> void:
	if player == null or vehicle_camera == null:
		return

	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	vehicle_camera.make_current()

static func exit_vehicle(player: CharacterBody3D, exit_point: Node3D, player_camera_path: NodePath = NodePath("SpringArm3D/Camera3D")) -> void:
	if player == null or exit_point == null:
		return

	player.global_position = exit_point.global_position
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT

	if player.has_node(player_camera_path):
		var player_camera: Node = player.get_node(player_camera_path)
		if player_camera is Camera3D:
			player_camera.make_current()
