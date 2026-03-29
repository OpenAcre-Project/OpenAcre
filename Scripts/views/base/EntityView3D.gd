class_name EntityView3D
extends RigidBody3D

## The authoritative logic representation of this object
var entity_data: EntityData

## --- Sync Throttle State ---
## Prevents per-frame extract_data() calls when many objects move simultaneously.
## Data is synced only on: rest transition, chunk boundary crossing, or throttled interval.
const SYNC_INTERVAL: float = 0.5

var _was_moving: bool = false
var _sync_timer: float = 0.0
var _last_chunk_id: Vector2i = Vector2i.ZERO
var _last_synced_position: Vector3 = Vector3.ZERO

## Called by StreamSpooler exactly when this node enters the world
func apply_data(data: EntityData) -> void:
	entity_data = data
	var tf: TransformComponent = entity_data.get_transform()
	var should_spawn_sleeping: bool = false
	var spawn_linear_velocity: Vector3 = Vector3.ZERO
	var spawn_angular_velocity: Vector3 = Vector3.ZERO
	var target_world_position: Vector3 = _get_world_position_snapshot()
	if tf:
		should_spawn_sleeping = tf.is_sleeping
		spawn_linear_velocity = tf.linear_velocity
		spawn_angular_velocity = tf.angular_velocity
		target_world_position = tf.world_position
		if is_inside_tree():
			global_position = target_world_position
		else:
			position = target_world_position
		rotation.y = tf.world_rotation_radians
		_last_chunk_id = tf.chunk_id
	else:
		_last_chunk_id = _compute_chunk_id_from_position(target_world_position)

	_last_synced_position = target_world_position
	_sync_timer = 0.0
	_was_moving = false

	if should_spawn_sleeping:
		# Keep body inert during initialization to avoid mass/transform wake spikes.
		sleeping = true
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		freeze = false
		sleeping = false
		linear_velocity = spawn_linear_velocity
		angular_velocity = spawn_angular_velocity
		
	# Visual Initialization (Dynamic Mass)
	if "mass" in self and entity_data.has_component(&"container"):
		var container: Variant = entity_data.get_component(&"container")
		if container and "max_weight_kg" in container:
			set("mass", maxf(container.max_weight_kg, 0.01))

	if should_spawn_sleeping:
		call_deferred("_release_spawn_freeze_as_sleeping")


## Called by StreamSpooler right before destroying the node, or triggered before saving
func extract_data() -> void:
	if not entity_data: return
	var tf: TransformComponent = entity_data.get_transform()
	var world_pos := _get_world_position_snapshot()
	var new_chunk_id := _compute_chunk_id_from_position(world_pos)

	if GameManager.session and GameManager.session.entities:
		var em := GameManager.session.entities as EntityManager
		em.update_entity_transform(entity_data.runtime_id, world_pos, rotation.y)
	else:
		# Fallback path for headless/tooling contexts where session is not yet booted.
		if tf:
			tf.world_position = world_pos
			tf.world_rotation_radians = rotation.y
			tf.chunk_id = new_chunk_id

	if tf:
		tf.is_sleeping = sleeping
		if sleeping:
			tf.linear_velocity = Vector3.ZERO
			tf.angular_velocity = Vector3.ZERO
		else:
			tf.linear_velocity = linear_velocity
			tf.angular_velocity = angular_velocity

	_last_chunk_id = new_chunk_id
	_last_synced_position = world_pos

## Throttled physics synchronization.
## Instead of syncing every frame, only syncs when:
##   1. Object transitions from moving to rest (final position capture)
##   2. Object crosses a chunk boundary (triggers EntityManager chunk move)
##   3. Object moves a large distance since last sync (teleport/warp safety)
##   4. Throttle timer expires (safety net for long rolling sequences)
func _physics_process(delta: float) -> void:
	if not entity_data: return
	
	var is_moving := false
	var untyped_self: Variant = self
	
	if untyped_self is Vehicle3D:
		var vb: Vehicle3D = untyped_self as Vehicle3D
		is_moving = vb.linear_velocity.length_squared() > 0.01
	elif untyped_self is RigidBody3D:
		var rb: RigidBody3D = untyped_self as RigidBody3D
		is_moving = rb.linear_velocity.length_squared() > 0.01
		
	if is_moving:
		_sync_timer += delta
		var should_sync := false
		
		# Condition 1: Chunk boundary crossing
		var current_chunk := _compute_chunk_id_from_position(global_position)
		if current_chunk != _last_chunk_id:
			should_sync = true

		# Condition 2: Large movement jump (teleports/high-speed warps)
		var half_chunk := EntityManager.CHUNK_SIZE * 0.5
		var immediate_sync_distance_sq := half_chunk * half_chunk
		if global_position.distance_squared_to(_last_synced_position) > immediate_sync_distance_sq:
			should_sync = true
		
		# Condition 3: Throttle timer expired
		if _sync_timer >= SYNC_INTERVAL:
			should_sync = true
		
		if should_sync:
			extract_data()
			_sync_timer = 0.0
		
		_was_moving = true
	elif _was_moving:
		extract_data() # Fire ONE last time at exact resting position
		_was_moving = false
		_sync_timer = 0.0

func _compute_chunk_id_from_position(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / EntityManager.CHUNK_SIZE)),
		int(floor(world_pos.z / EntityManager.CHUNK_SIZE))
	)

func _get_world_position_snapshot() -> Vector3:
	if is_inside_tree():
		return global_position
	return position

func _release_spawn_freeze_as_sleeping() -> void:
	if not is_instance_valid(self):
		return
	freeze = false
	sleeping = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
