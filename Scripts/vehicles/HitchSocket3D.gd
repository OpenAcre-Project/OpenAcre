extends Node3D
class_name HitchSocket3D

signal implement_attached(implement_node: RigidBody3D)
signal implement_detached(implement_node: RigidBody3D)

@export var hitch_type: Implement3D.HitchType = Implement3D.HitchType.HITCH_3_POINT
@export var can_lift: bool = true
@export var max_pto_kw: float = 100.0

@export var hitch_offset_lowered: float = -0.1
@export var hitch_offset_raised: float = 0.45
@export var hitch_animation_duration: float = 0.5
@export var hitch_face_implement_away: bool = true

@export_group("Physics Tuning")
@export var physics_blackout_frames: int = 0

var _attached_implement: Implement3D = null
var _hitch_tween: Tween = null
var _base_local_position: Vector3 = Vector3.ZERO
var _is_lowered: bool = false
var _is_pto_engaged: bool = false

@onready var detection_area: Area3D = get_node_or_null("DetectionArea")
@onready var hitch_point: Marker3D = get_node_or_null("HitchPoint")
@onready var hitch_spring: SpringArm3D = get_node_or_null("HitchSpring")

func _ready() -> void:
	_base_local_position = position

func _physics_process(delta: float) -> void:
	if _attached_implement != null:
		_sync_implement_transform(delta)

func get_attached_implement() -> Implement3D:
	return _attached_implement

func has_attached_implement() -> bool:
	return _attached_implement != null

func find_attach_candidate(fallback_radius: float = 3.0) -> Implement3D:
	if detection_area == null:
		return null

	for body: Variant in detection_area.get_overlapping_bodies():
		if _is_valid_candidate(body):
			return body as Implement3D

	var point_pos: Vector3 = hitch_point.global_position if hitch_point else global_position
	var nearest: Implement3D = null
	var nearest_dist_sq: float = fallback_radius * fallback_radius
	for node: Node in get_tree().get_nodes_in_group("implements"):
		if not _is_valid_candidate(node):
			continue
		var implement := node as Implement3D
		var dist_sq := point_pos.distance_squared_to(implement.get_hitch_world_position())
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = implement

	return nearest

func _is_valid_candidate(body: Variant) -> bool:
	if not (body is Implement3D):
		return false
	var implement := body as Implement3D
	
	# Skip if attaching to self or parent body
	var parent_body: Node = get_parent()
	while parent_body != null and not parent_body is PhysicsBody3D:
		parent_body = parent_body.get_parent()
	if implement == parent_body:
		return false
		
	if implement.required_hitch_type != hitch_type:
		return false
	if implement.required_power_kw > max_pto_kw:
		return false
		
	return true

func attach(implement: Implement3D) -> void:
	_attached_implement = implement
	
	if implement.has_method("attach_to_socket"):
		implement.attach_to_socket(self )
		
	# Synchronize state on attach if vehicle had it lowered/pto engaged from load or current state
	if implement.is_currently_lowered() != _is_lowered:
		_is_lowered = implement.is_currently_lowered()
		if can_lift:
			_apply_hitch_pose(false)
		
	# --- SNAP TO POSITION ---
	# Immediately snap to resting position to avoid massive forces on frame 1
	var desired := _calculate_desired_transform(implement)
	implement.global_transform = desired
	
	if implement is RigidBody3D:
		var rb := implement as RigidBody3D
		
		# Match tractor's base velocity to avoid sudden jerks
		var parent_body: Node = get_parent()
		while parent_body != null and not parent_body is RigidBody3D:
			parent_body = parent_body.get_parent()
			
		if parent_body is RigidBody3D:
			var tractor := parent_body as RigidBody3D
			rb.linear_velocity = tractor.linear_velocity
			rb.angular_velocity = tractor.angular_velocity
		else:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
		
		# Reset internal physics interpolation
		if rb.has_method("reset_physics_interpolation"):
			rb.call("reset_physics_interpolation")
		
		# --- PHYSICS BLACKOUT ---
		# Freeze physics for a few frames to allow collision exceptions to settle
		rb.freeze = true
		var original_layer := rb.collision_layer
		rb.collision_layer = 0
		
		# Emit signal (adds collision exception in Vehicle3D)
		implement_attached.emit(implement)
		
		for i in range(physics_blackout_frames):
			await get_tree().physics_frame
			
		if _attached_implement == implement:
			rb.freeze = false
			rb.collision_layer = original_layer
	else:
		implement_attached.emit(implement)
		
	# --- STREAMING GROUP BINDING ---
	if GameManager.session and GameManager.session.entities:
		var em := GameManager.session.entities as EntityManager
		var tractor_id: StringName = _get_parent_runtime_id()
		var implement_id: StringName = &""
		if "entity_data" in implement and implement.entity_data != null:
			implement_id = implement.get("entity_data").runtime_id

		if tractor_id != &"" and implement_id != &"":
			var group_id: StringName = StringName(tractor_id + "_hitch_group")
			em.assign_entity_to_group(tractor_id, group_id)
			em.assign_entity_to_group(implement_id, group_id)

func detach() -> void:
	if _attached_implement:
		if _attached_implement is RigidBody3D:
			var rb := _attached_implement as RigidBody3D
			rb.sleeping = false # Wake up the body so gravity immediately takes over!
			rb.freeze = false
			
			var parent_body: Node = get_parent()
			while parent_body != null and not parent_body is PhysicsBody3D:
				parent_body = parent_body.get_parent()
			if parent_body is RigidBody3D:
				rb.linear_velocity = parent_body.linear_velocity
				
		if _attached_implement.has_method("detach"):
			_attached_implement.detach()
			
		var imp := _attached_implement
		_attached_implement = null
		implement_detached.emit(imp)
		
		# --- STREAMING GROUP DISSOLUTION ---
		if GameManager.session and GameManager.session.entities:
			var em := GameManager.session.entities as EntityManager
			var implement_id: StringName = &""
			if imp != null and "entity_data" in imp and imp.entity_data != null:
				implement_id = imp.get("entity_data").runtime_id
				
			if implement_id != &"":
				em.remove_entity_from_group(implement_id)
		
func _get_parent_runtime_id() -> StringName:
	var parent_body: Node = get_parent()
	while parent_body != null and not (parent_body is EntityView3D):
		parent_body = parent_body.get_parent()
	
	if parent_body is EntityView3D and parent_body.entity_data:
		return parent_body.entity_data.runtime_id
	return &""

func on_lower_command() -> void:
	if not has_attached_implement():
		return
	
	_is_lowered = not _is_lowered
	_apply_hitch_pose(true)
	
	if _attached_implement.has_method("execute_lower_command"):
		_attached_implement.execute_lower_command(_is_lowered)

func on_pto_command() -> void:
	if not has_attached_implement():
		return
		
	_is_pto_engaged = not _is_pto_engaged
	if _attached_implement.has_method("execute_pto_command"):
		_attached_implement.execute_pto_command(_is_pto_engaged)

func _apply_hitch_pose(animate: bool = false) -> void:
	if not can_lift:
		return
		
	var offset: float = hitch_offset_lowered if _is_lowered else hitch_offset_raised
	var target_y: float = _base_local_position.y + offset
	
	if animate and is_inside_tree():
		if _hitch_tween:
			_hitch_tween.kill()
		
		_hitch_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_hitch_tween.tween_property(self , "position:y", target_y, hitch_animation_duration)
	else:
		position.y = target_y
		if has_method("reset_physics_interpolation"):
			call("reset_physics_interpolation")
		if _attached_implement and _attached_implement.has_method("reset_physics_interpolation"):
			_attached_implement.reset_physics_interpolation()

func _calculate_desired_transform(implement: Implement3D) -> Transform3D:
	if implement == null:
		return hitch_point.global_transform if hitch_point else global_transform
		
	# 1. Base the transform exactly on the socket's hitch point
	var hitch_xform: Transform3D = hitch_point.global_transform if hitch_point else global_transform
	
	if hitch_spring:
		var distance_to_ground: float = hitch_spring.get_hit_length()
		var float_up: float = hitch_spring.spring_length - distance_to_ground
		if _is_lowered and float_up > 0.0:
			hitch_xform.origin += hitch_xform.basis.y * float_up
	
	if hitch_face_implement_away:
		hitch_xform = hitch_xform.rotated_local(Vector3.UP, PI)
		
	# 2. Offset the transform by the implement's hitch node to find the desired Center of Mass location!
	var implement_hitch: Node3D = implement.get_node_or_null("HitchPoint")
	if implement_hitch:
		return hitch_xform * implement_hitch.transform.affine_inverse()
	else:
		return hitch_xform

func _sync_implement_transform(dt: float) -> void:
	var parent_body: Node = get_parent()
	while parent_body != null and not parent_body is RigidBody3D:
		parent_body = parent_body.get_parent()
	
	var tractor: RigidBody3D = parent_body as RigidBody3D
	if tractor == null:
		return

	var desired: Transform3D = _calculate_desired_transform(_attached_implement)
	
	if _attached_implement is RigidBody3D:
		var attachement_rb := _attached_implement as RigidBody3D

		# ==========================================
		# 1. POSITIONAL TETHERING (The Rigid Pin Constraint)
		# ==========================================
		var p_tractor: Vector3 = hitch_point.global_position if hitch_point else global_position
		
		# Robustly find implement hitch position, falling back to global_position if missing
		var imp_hitch_node: Node3D = _attached_implement.get_node_or_null("HitchPoint")
		var p_tongue: Vector3 = imp_hitch_node.global_position if imp_hitch_node else _attached_implement.global_position
		
		# Offsets from centers of mass
		var r_tractor: Vector3 = p_tractor - tractor.global_position
		var r_imp: Vector3 = p_tongue - attachement_rb.global_position
		
		var err_pos: Vector3 = Vector3.ZERO
		var err_vel: Vector3 = Vector3.ZERO
		
		if hitch_type == Implement3D.HitchType.HITCH_DRAWBAR:
			# --- YOUR DRAWBAR LOGIC (UNTOUCHED) ---
			var v_tractor: Vector3 = tractor.linear_velocity + tractor.angular_velocity.cross(r_tractor)
			var v_imp: Vector3 = attachement_rb.linear_velocity + attachement_rb.angular_velocity.cross(r_imp)
			
			err_pos = p_tractor - p_tongue
			err_vel = v_tractor - v_imp
			
			var force: Vector3 = attachement_rb.mass * ((err_pos * 80.0) + (err_vel * 12.0))
			
			var max_tow_force: float = tractor.mass * 9.8 * 2.0
			if force.length() > max_tow_force:
				force = force.normalized() * max_tow_force

			attachement_rb.apply_force(force, r_imp)
			tractor.apply_central_force(-force)

			# --- VIRTUAL TIRES: The Rudder Effect ---
			var imp_lat_axis: Vector3 = attachement_rb.global_transform.basis.x
			var imp_lat_vel: float = attachement_rb.linear_velocity.dot(imp_lat_axis)
			var rudder_force: Vector3 = -imp_lat_axis * (imp_lat_vel * attachement_rb.mass * 8.0)
			var rudder_offset: Vector3 = -attachement_rb.global_transform.basis.z * 1.5 
			attachement_rb.apply_force(rudder_force, rudder_offset)
			
		else:
			# --- 3-POINT HITCH FIX ---
			# Use the precise required COM transform calculated earlier so the hitches flawlessly align!
			err_pos = desired.origin - attachement_rb.global_position
			
			# Target velocity of the exact COM offset point locked to the moving tractor
			var target_com_offset: Vector3 = desired.origin - tractor.global_position
			var target_vel: Vector3 = tractor.linear_velocity + tractor.angular_velocity.cross(target_com_offset)
			err_vel = target_vel - attachement_rb.linear_velocity
			
			# LOWERED GAINS: Prevents over-correcting a 1mm suspension drop
			var kp: float = 150.0 # Down from 800.0
			var kd: float = 30.0  # Down from 80.0
			var force: Vector3 = attachement_rb.mass * ((err_pos * kp) + (err_vel * kd))
			
			# STRICT FORCE CAP: Prevents the "500 Gs" explosion
			# Caps the max pull to about ~5 Gs relative to the tractor's mass
			var rigid_limit: float = tractor.mass * 9.8 * 5.0 
			if force.length() > rigid_limit:
				force = force.normalized() * rigid_limit
				
			# Apply force CENTRALLY to the plow. 
			attachement_rb.apply_central_force(force)
			
			# Apply reaction to the tractor. Because force is capped, 
			# the lever arm (r_tractor) will squat the truck realistically without exploding it.
			tractor.apply_force(-force, r_tractor)

			# ==========================================
			# 1.5 SHOCK TRANSFER (The Brick Wall / Snag Limit)
			# ==========================================
			# If the implement hits an immovable object, the PD spring will stretch.
			# If it stretches past 10cm, the physical limit of the metal hitch is reached.
			var stretch: float = err_pos.length()
			if stretch > 0.1: 
				var tether_dir: Vector3 = err_pos.normalized()
				# Calculate the separation speed (how fast the truck is abandoning the plow)
				var v_sep: float = tractor.linear_velocity.dot(tether_dir) - attachement_rb.linear_velocity.dot(tether_dir)
				if v_sep > 0.5: # Only trigger if they are forcefully pulling apart
					# Calculate the exact impulse needed to kill the tractor's escape velocity.
					# We use 80% (0.8) of the mass to prevent the physics engine from "bouncing" the truck backward.
					var shock: Vector3 = tether_dir * (-v_sep * tractor.mass * 0.8)
					# Apply the violent stop to the tractor. 
					# Because we apply it at 'r_tractor' (the rear hitch), hitting a rock at high 
					# speed will realistically yank the rear axle down and pop the front wheels up!
					tractor.apply_impulse(shock, r_tractor)

		# ==========================================
		# 2. ROTATIONAL TETHERING (Anti-Flip / Up-Vector Lock)
		# ==========================================
		var q_target: Quaternion = desired.basis.get_rotation_quaternion()
		var q_current: Quaternion = attachement_rb.global_transform.basis.get_rotation_quaternion()
		var q_err: Quaternion = (q_target * q_current.inverse()).normalized()
		
		var axis: Vector3 = q_err.get_axis()
		var angle: float = q_err.get_angle()
		if angle > PI: angle -= TAU
			
		var torque: Vector3 = Vector3.ZERO
		if axis.is_normalized() and abs(angle) > 0.001:
			if hitch_type == Implement3D.HitchType.HITCH_DRAWBAR:
				# We only care about aligning the UP vectors (Pitch and Roll). Yaw is completely free.
				var imp_up: Vector3 = attachement_rb.global_transform.basis.y.normalized()
				var tractor_up: Vector3 = tractor.global_transform.basis.y.normalized()
				var alignment_axis: Vector3 = imp_up.cross(tractor_up)
				
				if alignment_axis.length_squared() > 0.0001:
					var angle_error: float = asin(alignment_axis.length())
					var target_ang_vel: Vector3 = alignment_axis.normalized() * (angle_error / dt) * 0.5
					var current_ang_vel: Vector3 = attachement_rb.angular_velocity
					torque = attachement_rb.mass * (target_ang_vel - current_ang_vel) / dt
					
					var max_torque: float = tractor.mass * 20.0
					if torque.length() > max_torque:
						torque = torque.normalized() * max_torque
						
				# THE FIX: Strip out all Yaw torque so the hinge swings completely free!
				var local_torque: Vector3 = attachement_rb.global_basis.inverse() * torque
				local_torque.y = 0.0
				torque = attachement_rb.global_basis * local_torque
					
				attachement_rb.apply_torque(torque)
				tractor.apply_torque(-torque * 0.1)
			else:
				# --- 3-POINT: Rotational PD Controller ---
				# LOWERED GAINS to prevent torque feedback loops
				var kp_rot: float = attachement_rb.mass * 200.0 # Down from 1000.0
				var kd_rot: float = attachement_rb.mass * 40.0  # Down from 100.0
				
				var target_ang_vel: Vector3 = axis * angle
				var current_ang_vel: Vector3 = attachement_rb.angular_velocity - tractor.angular_velocity
				
				torque = (target_ang_vel * kp_rot) - (current_ang_vel * kd_rot)
				
				# STRICT TORQUE CAP: Prevents astronomical twist forces
				var max_torque: float = tractor.mass * 100.0
				if torque.length() > max_torque:
					torque = torque.normalized() * max_torque
				
				attachement_rb.apply_torque(torque)
				
				# REDUCED REACTION TRANSFER: Feed 25% of the twist back to the tractor.
				# 100% feedback on a perfectly stiff joint causes instant vibration/NaNs.
				tractor.apply_torque(-torque * 0.25)

		# ==========================================
		# 3. KINEMATIC SLEEP DEADZONE
		# ==========================================
		# If the tractor is parked and the implement is practically aligned, 
		# kill all microscopic physics noise to let the rigidbodies sleep.
		if tractor.linear_velocity.length_squared() < 0.01 and tractor.angular_velocity.length_squared() < 0.01:
			if err_pos.length_squared() < 0.001 and abs(angle) < 0.01:
				attachement_rb.linear_velocity = Vector3.ZERO
				attachement_rb.angular_velocity = Vector3.ZERO
	else:
		_attached_implement.global_transform = desired
