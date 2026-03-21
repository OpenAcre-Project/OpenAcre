extends CharacterBody3D

@export var simulation_player_id: StringName = &"player.main"
const OrbitCameraControllerRef = preload("res://Scripts/camera/OrbitCameraController.gd")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var camera_vertical_speed: float = 3.0
@export var camera_height_min: float = 1.2
@export var camera_height_max: float = 3.2
@export var camera_zoom_step: float = 0.5
@export var camera_zoom_min: float = 1.5
@export var camera_zoom_max: float = 6.0
@export var camera_follow_smooth_speed: float = 12.0
@export var camera_pitch_min_degrees: float = -70.0
@export var camera_pitch_max_degrees: float = 25.0
@export var camera_orbit_smooth_speed: float = 14.0
@export var mesh_turn_angle_degrees: float = 90.0
@export var mesh_turn_lerp_speed: float = 10.0
@export var player_turn_speed_degrees: float = 420.0
@export var player_turn_deadzone_degrees: float = 2.5
@export var walk_anim_scale_min: float = 0.7
@export var walk_anim_scale_max: float = 1.45
@export var walk_anim_scale_lerp_speed: float = 10.0
@export var run_lean_strength: float = 1.0
@export var run_lean_lerp_speed: float = 12.0
@export var run_lean_full_turn_rate_degrees: float = 240.0
@export var run_lean_min_speed: float = 0.75
@export var landing_roll_speed_threshold: float = 5.5
@export var landing_soft_hold_time: float = 0.2
@export var landing_roll_hold_time: float = 1.5
@export var landing_roll_movement_multiplier: float = 0.80
@export var landing_roll_zero_velocity_window: float = 0.12
@export var landing_roll_recover_time: float = 0.25
@export var landing_roll_recover_walk_scale: float = 1.2
@export var hover_ray_interval_frames: int = 10

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var hero_mesh: Node3D = $hero_male
@onready var Anim_tree: AnimationTree = $hero_male/AnimationTree


var _player_data: PlayerData

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var is_godmode := false
var godmode_speed := 25.0

var _tool_inventory: RefCounted = preload("res://Scripts/player/PlayerToolInventory.gd").new()
var _interaction_controller: RefCounted
var _movement_controller: RefCounted
var _camera_controller: OrbitCameraController
var _hero_base_yaw: float = 0.0
var _hover_frame_count: int = 0

func _ready() -> void:
	# Godot callback: runs when the node enters the scene tree and children are ready; sets up data, camera, tools, controllers, UI, and publishes initial state.
	
	add_to_group("player")
	_player_data = GameManager.session.entities.get_player(simulation_player_id)
	_sync_from_simulation_core()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_hero_base_yaw = hero_mesh.rotation.y
	_camera_controller = OrbitCameraControllerRef.new()
	add_child(_camera_controller)
	_camera_controller.setup(spring_arm, camera)
	_camera_controller.follow_smooth_speed = camera_follow_smooth_speed
	_camera_controller.orbit_smooth_speed = camera_orbit_smooth_speed
	_camera_controller.zoom_min = camera_zoom_min
	_camera_controller.zoom_max = camera_zoom_max
	_camera_controller.height_min = camera_height_min
	_camera_controller.height_max = camera_height_max

	_tool_inventory.add_tool(preload("res://Scripts/farm/tools/HoeTool.gd").new())
	_tool_inventory.add_tool(preload("res://Scripts/farm/tools/SeedTool.gd").new())
	_tool_inventory.equip_slot(1)

	_interaction_controller = preload("res://Scripts/player/PlayerInteractionController.gd").new(camera)
	_movement_controller = preload("res://Scripts/player/PlayerMovementController.gd").new(self, _player_data, gravity, hero_mesh, Anim_tree, _hero_base_yaw)
	if Anim_tree != null:
		_movement_controller.prime_animation_tree()

	# TERRAIN3D COLLISION FIX
	var terrain: Node = get_tree().root.find_child("Terrain3D", true, false)
	if terrain != null:
		terrain.set_camera(camera)
	

	_refresh_tool_ui()
	_publish_player_state_to_simulation_core()

func _unhandled_input(event: InputEvent) -> void:
	# Godot callback: handles input not consumed elsewhere; processes mouse-look and toggles mouse capture.
	
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_controller.handle_mouse_motion(event.relative)
	
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	# Godot callback: primary input handler; toggles help, equips tools, interacts, adjusts zoom, and uses the active tool.
	
	if GameInput.is_gameplay_input_blocked(get_tree()):
		return

	if event is InputEventKey:
		# Equip Tools
		if event.physical_keycode == KEY_1 and event.is_pressed() and not event.is_echo():
			if _tool_inventory.equip_slot(1):
				_refresh_tool_ui()
		elif event.physical_keycode == KEY_2 and event.is_pressed() and not event.is_echo():
			if _tool_inventory.equip_slot(2):
				_refresh_tool_ui()
			
		# Interact
		if GameInput.is_interact_event(event):
			if _interaction_controller.try_interact(self):
				get_viewport().set_input_as_handled()
					
	# Use Tool
	if event is InputEventMouseButton:
		if event.is_action_pressed(GameInput.ACTION_CAMERA_ZOOM_IN):
			_camera_controller.adjust_zoom(false)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(GameInput.ACTION_CAMERA_ZOOM_OUT):
			_camera_controller.adjust_zoom(true)
			get_viewport().set_input_as_handled()

		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			var active_tool: Tool = _tool_inventory.get_active_tool()
			if _interaction_controller.try_use_tool(self, active_tool):
				get_viewport().set_input_as_handled()
		
	# Test Drop (using 'G' for now as there is no UI yet)
	if event is InputEventKey and event.keycode == KEY_G and event.pressed and not event.is_echo():
		drop_item(0) # Drops first item in pockets for testing

func drop_item(index: int) -> void:
	if _player_data == null or _player_data.pockets.items.size() <= index:
		return
		
	var item: ItemInstance = _player_data.pockets.remove_item(index)
	if item == null:
		return
		
	var def: ItemDefinition = item.get_definition()
	if def == null or def.world_scene == null:
		GameLog.warn("Cannot drop item %s: No world scene defined." % item.definition_id)
		return
		
	var dropped_node: Node = def.world_scene.instantiate()
	if not dropped_node is RigidBody3D:
		GameLog.error("Dropped scene for %s must be a RigidBody3D" % item.definition_id)
		dropped_node.queue_free()
		return
		
	var spawn_pos: Vector3 = global_position + (-global_transform.basis.z * 1.5) + Vector3.UP * 1.0
	
	var interactable_node: InteractableItem3D = dropped_node if dropped_node is InteractableItem3D else null
	if not interactable_node:
		# Search children just in case
		for child in dropped_node.get_children():
			if child is InteractableItem3D:
				interactable_node = child
				break
				
	if interactable_node:
		interactable_node.item_data = item
	else:
		GameLog.warn("Dropped scene lacks an InteractableItem3D script!")
	
	# Spawn into the same world as the player (crucial for World3D rendering)
	var spawn_parent: Node = get_parent()
	if spawn_parent:
		spawn_parent.add_child(dropped_node)
	else:
		get_tree().root.add_child(dropped_node)
		
	dropped_node.global_position = spawn_pos
	
	# Impulse
	var force: Vector3 = -global_transform.basis.z * 2.0 + Vector3.UP * 1.0
	if dropped_node is RigidBody3D:
		dropped_node.apply_central_impulse(force)
	
	GameLog.info("Dropped %s x%d" % [item.definition_id, item.stack])

func toggle_godmode() -> bool:
	is_godmode = not is_godmode
	if is_godmode:
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
	else:
		collision_layer = 1
		collision_mask = 1
	return is_godmode

func _physics_process(delta: float) -> void:
	# Godot physics callback: per-physics-frame delegates movement/animation to controller, updates camera, and syncs state.
	
	if GameInput.is_gameplay_input_blocked(get_tree()):
		_publish_player_state_to_simulation_core()
		return

	if is_godmode:
		_process_godmode(delta)
	else:
		_movement_controller.process_movement(
			delta,
			true,
			Basis(Vector3.UP, _camera_controller.get_yaw_global())
		)

	_hover_frame_count += 1
	if _hover_frame_count >= hover_ray_interval_frames:
		_hover_frame_count = 0
		_interaction_controller.process_hover(self)

	_camera_controller.update(delta, GameInput.is_gameplay_input_blocked(get_tree()))
	_publish_player_state_to_simulation_core()

func _process_godmode(delta: float) -> void:
	var speed := godmode_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 3.0
	elif Input.is_physical_key_pressed(KEY_CTRL):
		speed *= 0.2
		
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var cam_basis := Basis.from_euler(Vector3(_camera_controller.pitch, _camera_controller.yaw_global, 0))
	var direction := (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if Input.is_physical_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	elif Input.is_physical_key_pressed(KEY_C):
		direction += Vector3.DOWN
		
	velocity = direction.normalized() * speed
	global_position += velocity * delta

func _sync_from_simulation_core() -> void:
	# Pulls transform from SimulationCore if available so the player matches authoritative state.
	
	if _player_data == null:
		_player_data = GameManager.session.entities.get_player(simulation_player_id)
	if not _player_data.has_world_transform:
		return

	global_position = _player_data.world_position
	rotation.y = _player_data.world_yaw_radians

func _publish_player_state_to_simulation_core() -> void:
	# Pushes the current transform into SimulationCore for other systems to consume.
	
	GameManager.session.entities.set_player_transform(simulation_player_id, global_position, rotation.y)

func _refresh_tool_ui() -> void:
	# Updates the UI with the currently equipped tool name.
	EventBus.player_tool_equipped.emit(_tool_inventory.get_active_tool_name())
