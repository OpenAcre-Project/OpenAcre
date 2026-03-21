extends RefCounted

var _player: CharacterBody3D
var _player_data: PlayerData
var _gravity: float
var _hero_mesh: Node3D
var _anim_tree: AnimationTree
var _hero_base_yaw: float

var _movement_anim_state: StringName = &"Idle"
var _walk_anim_scale: float = 1.0
var _run_lean_amount: float = 0.0
var _previous_velocity_direction: Vector2 = Vector2.ZERO
var _was_on_floor: bool = true
var _landing_state: StringName = &""
var _landing_state_time_left: float = 0.0
var _airborne_peak_horizontal_speed: float = 0.0
var _post_roll_recover_time_left: float = 0.0
var _roll_walk_handoff_pending: bool = false

func _init(player: CharacterBody3D, player_data: PlayerData, gravity: float, hero_mesh: Node3D, anim_tree: AnimationTree, hero_base_yaw: float) -> void:
	_player = player
	_player_data = player_data
	_gravity = gravity
	_hero_mesh = hero_mesh
	_anim_tree = anim_tree
	_hero_base_yaw = hero_base_yaw
	_was_on_floor = _player != null and _player.is_on_floor()

func prime_animation_tree() -> void:
	if _anim_tree == null:
		return

	_anim_tree.active = true
	_anim_tree.set("parameters/movement/transition_request", String("Idle"))
	_anim_tree.set("parameters/walk_speed/scale", _walk_anim_scale)
	_anim_tree.set("parameters/run_lean/add_amount", _run_lean_amount)

func process_movement(delta: float, movement_enabled: bool = true, reference_basis: Basis = Basis.IDENTITY) -> void:
	if _player == null:
		return

	# 1. Cache floor state at the start of the frame
	var current_is_on_floor := _player.is_on_floor()
	var speed_multiplier: float = 1.0

	# 2. Handle Landing Roll Speed Modifiers
	if _landing_state == &"LandRolling" and _landing_state_time_left > 0.0:
		var normalized_roll_time := clampf(_landing_state_time_left / maxf(_player.landing_roll_hold_time, 0.001), 0.0, 1.0)
		speed_multiplier = clampf(_player.landing_roll_movement_multiplier * normalized_roll_time, 0.0, 1.0)

		if _landing_state_time_left <= _player.landing_roll_zero_velocity_window:
			movement_enabled = false
	
	# 3. Apply GravityQ
	if not current_is_on_floor:
		_player.velocity.y -= _gravity * delta

	var move_direction_world := Vector3.ZERO
	var is_moving := false
	var is_sprinting := false

	# 4. Input & Velocity Calculation
	if not movement_enabled:
		# FIX: When movement is disabled (e.g., end of roll), brake smoothly instead of snapping to a halt.
		_player.velocity.x = lerpf(_player.velocity.x, 0.0, 6.0 * delta)
		_player.velocity.z = lerpf(_player.velocity.z, 0.0, 6.0 * delta)
	else:
		var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		is_moving = input_dir.length_squared() > 0.0
		is_sprinting = Input.is_physical_key_pressed(KEY_SHIFT)

		# 4b. Apply Encumbrance Modifiers
		var encumbrance_multiplier: float = 1.0
		var can_jump_mass := true
		
		if _player_data != null:
			var current_mass := _player_data.get_total_encumbrance_mass()
			var max_mass := _player_data.pockets.max_mass
			if _player_data.equipment_back:
				max_mass += 25.0 # Assume backpack increases weight limit
			
			var soft_limit := max_mass * 0.5
			if current_mass > soft_limit:
				var encumbrance_factor := (current_mass - soft_limit) / (max_mass - soft_limit + 0.001)
				encumbrance_multiplier = clampf(1.0 - (encumbrance_factor * 0.8), 0.2, 1.0)
				
			if current_mass > max_mass * 1.5: # Extremely heavy
				can_jump_mass = false

		# Prevent jumping while committed to a roll or too heavy
		var can_jump := current_is_on_floor and _landing_state != &"LandRolling" and can_jump_mass
		if Input.is_action_just_pressed("ui_accept") and can_jump:
			_player.velocity.y = _player.jump_velocity

		var speed: float = (_player.sprint_speed if is_sprinting else _player.walk_speed) * speed_multiplier * encumbrance_multiplier

		if is_sprinting and is_moving and _player_data != null:
			_player_data.burn_energy(delta)

		move_direction_world = _build_world_direction(input_dir, reference_basis)
		
		var target_vel_x := move_direction_world.x * speed
		var target_vel_z := move_direction_world.z * speed

		# MOMENTUM FIX: Dynamic acceleration/deceleration rates
		var accel_rate := 1.0
		if current_is_on_floor:
			if _landing_state == &"LandRolling":
				# Rolling momentum: Slide much longer (2.5) if keys are released to let the animation play out.
				accel_rate = 8.0 if is_moving else 2.5 
			else:
				# Normal ground momentum: Smooth Run -> Walk -> Idle deceleration (6.0) instead of a hard stop.
				accel_rate = 12.0 if is_moving else 6.0 
		else:
			# Air momentum
			accel_rate = 3.0 if is_moving else 0.5   

		_player.velocity.x = lerpf(_player.velocity.x, target_vel_x, accel_rate * delta)
		_player.velocity.z = lerpf(_player.velocity.z, target_vel_z, accel_rate * delta)

	_player.move_and_slide()
	current_is_on_floor = _player.is_on_floor()
	
	_update_hero_visuals(delta, is_moving, move_direction_world)
	_update_animation_tree(delta, is_moving, is_sprinting, current_is_on_floor)

func _update_animation_tree(delta: float, is_moving: bool, is_sprinting: bool, is_on_floor_now: bool) -> void:
	if _anim_tree == null:
		_was_on_floor = is_on_floor_now
		return

	var horizontal_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	var walk_ratio: float = clampf(horizontal_speed / maxf(_player.walk_speed, 0.01), 0.0, 1.25)
	var target_walk_scale: float = lerpf(_player.walk_anim_scale_min, _player.walk_anim_scale_max, walk_ratio)

	var next_state: StringName = &"Idle"

	# DECELERATION: Base animation states on actual physical speed when input stops.
	var is_physically_running : float = horizontal_speed > (_player.walk_speed + 0.5)
	var is_physically_walking := horizontal_speed > 0.2

	if (is_sprinting and is_moving) or (not is_moving and is_physically_running):
		next_state = &"Run"
	elif is_moving or is_physically_walking:
		next_state = &"Walk"

	var just_landed: bool = (not _was_on_floor) and is_on_floor_now

	if not is_on_floor_now:
		if _player.velocity.y > 0.0:
			next_state = &"Jump"
		else:
			next_state = &"Fall"

		_landing_state = &""
		_landing_state_time_left = 0.0
		_post_roll_recover_time_left = 0.0
		_roll_walk_handoff_pending = false
		_airborne_peak_horizontal_speed = maxf(_airborne_peak_horizontal_speed, horizontal_speed)
	elif just_landed:
		var landing_speed := maxf(horizontal_speed, _airborne_peak_horizontal_speed)
		if landing_speed >= _player.landing_roll_speed_threshold:
			_landing_state = &"LandRolling"
			# T-POSE FIX: Trigger the handoff exactly 0.25s BEFORE the animation finishes to account for the BlendTree Xfade.
			_landing_state_time_left = minf(_player.landing_roll_hold_time, 1.5333 - 0.3) 
			_post_roll_recover_time_left = _player.landing_roll_recover_time
			_roll_walk_handoff_pending = false
		else:
			_landing_state = &"LandSoft"
			_landing_state_time_left = _player.landing_soft_hold_time
			_post_roll_recover_time_left = 0.0
			_roll_walk_handoff_pending = false
		_airborne_peak_horizontal_speed = 0.0
		next_state = _landing_state
	elif _landing_state_time_left > 0.0 and _landing_state != &"":
		_landing_state_time_left = maxf(_landing_state_time_left - delta, 0.0)
		if _landing_state_time_left > 0.0:
			next_state = _landing_state
		else:
			if _landing_state == &"LandRolling":
				_roll_walk_handoff_pending = true
			_landing_state = &""
	else:
		_airborne_peak_horizontal_speed = 0.0

	var walk_scale_override: float = -1.0
	if is_on_floor_now and _roll_walk_handoff_pending:
		next_state = &"Walk"
		walk_scale_override = maxf(_player.landing_roll_recover_walk_scale, 0.01)
		if _anim_tree.get("parameters/movement/current_state") == &"Walk":
			_roll_walk_handoff_pending = false

	if is_on_floor_now and _landing_state == &"" and _post_roll_recover_time_left > 0.0:
		_post_roll_recover_time_left = maxf(_post_roll_recover_time_left - delta, 0.0)
		next_state = &"Walk"
		walk_scale_override = maxf(_player.landing_roll_recover_walk_scale, 0.01)
	else:
		if not is_on_floor_now:
			_post_roll_recover_time_left = 0.0

	if walk_scale_override > 0.0:
		target_walk_scale = walk_scale_override

	_walk_anim_scale = lerpf(_walk_anim_scale, target_walk_scale, _player.walk_anim_scale_lerp_speed * delta)
	_anim_tree.set("parameters/walk_speed/scale", _walk_anim_scale)

	var target_run_lean: float = 0.0
	var horizontal_velocity := Vector2(_player.velocity.x, _player.velocity.z)
	var run_horizontal_speed := horizontal_velocity.length()
	
	if next_state == &"Run" and run_horizontal_speed >= _player.run_lean_min_speed:
		var current_velocity_direction := horizontal_velocity / run_horizontal_speed
		if _previous_velocity_direction.length_squared() > 0.0:
			var cross_z := _previous_velocity_direction.x * current_velocity_direction.y - _previous_velocity_direction.y * current_velocity_direction.x
			var dot_value := _previous_velocity_direction.dot(current_velocity_direction)
			var signed_angle_delta := atan2(cross_z, dot_value)
			var turn_rate := signed_angle_delta / maxf(delta, 0.0001)
			var full_turn_rate := deg_to_rad(maxf(_player.run_lean_full_turn_rate_degrees, 1.0))
			target_run_lean = clampf((turn_rate / full_turn_rate) * _player.run_lean_strength, -1.0, 1.0)
		_previous_velocity_direction = current_velocity_direction
	else:
		_previous_velocity_direction = Vector2.ZERO

	_run_lean_amount = lerpf(_run_lean_amount, target_run_lean, _player.run_lean_lerp_speed * delta)
	_anim_tree.set("parameters/run_lean/add_amount", _run_lean_amount)

	if next_state == _movement_anim_state:
		_was_on_floor = is_on_floor_now
		return

	_anim_tree.set("parameters/movement/transition_request", String(next_state))
	_movement_anim_state = next_state
	_was_on_floor = is_on_floor_now

func _update_hero_visuals(delta: float, is_moving: bool, move_direction_world: Vector3) -> void:
	if _hero_mesh == null:
		return

	if is_moving and move_direction_world.length_squared() > 0.0:
		var target_player_yaw: float = atan2(-move_direction_world.x, -move_direction_world.z)
		var yaw_delta: float = absf(wrapf(target_player_yaw - _player.rotation.y, -PI, PI))
		if yaw_delta > deg_to_rad(_player.player_turn_deadzone_degrees):
			var max_turn_step: float = deg_to_rad(_player.player_turn_speed_degrees) * delta
			_player.rotation.y = rotate_toward(_player.rotation.y, target_player_yaw, max_turn_step)

	_hero_mesh.rotation.y = lerp_angle(_hero_mesh.rotation.y, _hero_base_yaw, _player.mesh_turn_lerp_speed * delta)

func _build_world_direction(input_dir: Vector2, reference_basis: Basis) -> Vector3:
	if input_dir.length_squared() <= 0.0:
		return Vector3.ZERO

	var forward: Vector3 = -reference_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right: Vector3 = reference_basis.x
	right.y = 0.0
	right = right.normalized()

	var world_direction: Vector3 = right * input_dir.x + forward * -input_dir.y
	return world_direction.normalized()
