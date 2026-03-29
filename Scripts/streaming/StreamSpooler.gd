extends Node

## StreamSpooler
## Manages synchronous evaluation of chunk visibility and throttled asynchronous
## instantiating/destroying of Godot 3D Nodes based on active chunks.
## Uses ResourceLoader.load_threaded_request() to perform disk I/O off the main thread.

const EntityDataRef = preload("res://Scripts/simulation/core/EntityData.gd")
const CatchUpEngineRef = preload("res://Scripts/simulation/systems/CatchUpEngine.gd")
const EntityView3DRef = preload("res://Scripts/views/base/EntityView3D.gd")

@export var stream_radius: int = 2
@export var stream_update_interval_seconds: float = 0.5
@export var auto_configure_radii_from_chunks: bool = true
@export var auto_sync_terrain_collision_radius_from_chunks: bool = true
@export var auto_sync_terrain_collision: bool = true
@export var collision_edge_margin_meters: float = 16.0
@export var stream_hysteresis_meters: float = 24.0
@export var terrain_collision_padding_meters: float = 32.0
@export var min_terrain_collision_radius_meters: int = 64
@export var min_auto_load_radius_meters: float = 32.0
@export var min_auto_unload_radius_meters: float = 48.0
@export var load_radius_meters: float = 96.0
@export var unload_radius_meters: float = 112.0

var _effective_load_radius_meters: float = 0.0
var _effective_unload_radius_meters: float = 0.0

var _current_active_chunks: Array[Vector2i] = []

# Queue dictionaries allow O(1) instantaneous cancellation if an entity dances 
# back and forth across a chunk line
var _pending_load: Dictionary = {}
var _pending_unload: Dictionary = {}

# Background Resource Loading (Phase 2 pipeline)
# Entities waiting for their scene to finish threaded loading
var _pending_resource: Dictionary = {} # entity_id -> { "scene_path": String, "entity": EntityData }

var _spawned_views: Dictionary = {} # runtime_id -> EntityView3D
var _scene_cache: Dictionary = {} # scene_path -> PackedScene

var _stream_timer: float = 0.0
var _bound_to_entity_manager: bool = false

func _ready() -> void:
	_bind_to_entity_manager()
	if not _bound_to_entity_manager:
		call_deferred("_bind_to_entity_manager")
	_recompute_stream_radii()
	
	# Connect to EventBus for external view release notifications (e.g., item pickup)
	if EventBus.has_signal("entity_view_released"):
		EventBus.entity_view_released.connect(_on_entity_view_released)

func _bind_to_entity_manager() -> void:
	if GameManager.session and GameManager.session.entities:
		var em := GameManager.session.entities as EntityManager
		if not em.entity_registered.is_connected(_on_entity_registered):
			em.entity_registered.connect(_on_entity_registered)
		_bound_to_entity_manager = true
		if not _current_active_chunks.is_empty():
			refresh_from_current_chunks("bind")

func _on_entity_registered(entity_id: StringName) -> void:
	if not GameManager.session or not GameManager.session.entities: return
	_recompute_stream_radii()
	var em := GameManager.session.entities as EntityManager
	if not _is_group_within_load_radius(em, entity_id):
		return
	var chunk_id := em.get_entity_chunk_id(entity_id)
	if _current_active_chunks.has(chunk_id):
		_queue_load_with_group(em, entity_id)

## Tick this whenever the player moves significantly to evaluate chunk boundaries
func update_active_chunks(player_position: Vector3, radius: int = 1) -> void:
	radius = _resolve_stream_radius(radius)
	_recompute_stream_radii(radius)

	var new_chunks := GridManager.get_active_chunks_around(player_position, radius)
	var deltas := GridManager.compute_chunk_deltas(_current_active_chunks, new_chunks)
	_current_active_chunks = new_chunks
	
	if _should_sync_terrain_collision_from_chunks() and not auto_configure_radii_from_chunks:
		_sync_terrain_collision_radius(radius)
	
	if not GameManager.session or not GameManager.session.entities: return
	var em := GameManager.session.entities as EntityManager
	
	for chunk: Vector2i in deltas["load"]:
		for entity_id: StringName in em.get_entities_in_chunk(chunk):
			if _is_group_within_load_radius(em, entity_id):
				_queue_load_with_group(em, entity_id)
			
	for chunk: Vector2i in deltas["unload"]:
		for entity_id: StringName in em.get_entities_in_chunk(chunk):
			if not _is_group_active(em, entity_id):
				_queue_unload_with_group(em, entity_id)

	_enforce_stream_radii(em)

func _sync_terrain_collision_radius(radius: int) -> void:
	var terrain: Node = _get_terrain_node()
	if terrain == null: return

	var chunk_collision_edge_meters: float = (float(radius) + 0.5) * _get_chunk_size_meters()
	var target_radius: int = maxi(min_terrain_collision_radius_meters, int(round(chunk_collision_edge_meters + terrain_collision_padding_meters)))
	var current_radius: int = _get_terrain_collision_radius(terrain)

	if current_radius != target_radius:
		_set_terrain_collision_radius(terrain, target_radius)

		var collision_obj: Variant = null
		if terrain.has_method("get_collision"):
			collision_obj = terrain.call("get_collision")
		else:
			collision_obj = terrain.get("collision")

		if collision_obj != null and collision_obj.has_method("update"):
			collision_obj.call("update", true)
			GameLog.info("[StreamSpooler] Synced Terrain3D collision radius to " + str(target_radius) + "m")

func _resolve_stream_radius(fallback_radius: int) -> int:
	var grid_manager_node: Node = get_tree().get_first_node_in_group("grid_manager")
	if grid_manager_node != null and grid_manager_node.has_method("get_stream_radius"):
		var node_radius: Variant = grid_manager_node.call("get_stream_radius")
		if node_radius is int:
			return maxi(0, node_radius)
	return maxi(0, fallback_radius)

func _should_sync_terrain_collision_from_chunks() -> bool:
	# Keep legacy toggle for scene compatibility while supporting the documented export name.
	return auto_sync_terrain_collision and auto_sync_terrain_collision_radius_from_chunks

func _recompute_stream_radii(chunk_radius: int = -1) -> void:
	if chunk_radius < 0:
		chunk_radius = _resolve_stream_radius(stream_radius)

	if auto_configure_radii_from_chunks:
		var chunk_collision_edge_meters: float = (float(chunk_radius) + 0.5) * _get_chunk_size_meters()

		if _should_sync_terrain_collision_from_chunks():
			_sync_terrain_collision_radius(chunk_radius)

		var terrain: Node = _get_terrain_node()
		var terrain_radius: float = chunk_collision_edge_meters
		if terrain != null:
			terrain_radius = float(_get_terrain_collision_radius(terrain))

		var effective_collision_edge: float = minf(chunk_collision_edge_meters, terrain_radius)
		_effective_unload_radius_meters = maxf(min_auto_unload_radius_meters, effective_collision_edge - collision_edge_margin_meters)
		_effective_load_radius_meters = maxf(min_auto_load_radius_meters, _effective_unload_radius_meters - stream_hysteresis_meters)
	else:
		_effective_load_radius_meters = maxf(min_auto_load_radius_meters, load_radius_meters)
		_effective_unload_radius_meters = maxf(min_auto_unload_radius_meters, unload_radius_meters)

	if _effective_unload_radius_meters < _effective_load_radius_meters:
		_effective_unload_radius_meters = _effective_load_radius_meters

func _get_chunk_size_meters() -> float:
	if GameManager.session != null and GameManager.session.farm != null:
		if "simulation_chunk_size_tiles" in GameManager.session.farm:
			return float(GameManager.session.farm.simulation_chunk_size_tiles)
	return GridManager.CHUNK_SIZE

func _get_terrain_node() -> Node:
	var terrain: Node = get_tree().get_first_node_in_group("terrain_node")
	if terrain == null:
		terrain = get_tree().root.find_child("Terrain3D", true, false)
	return terrain

func _get_terrain_collision_radius(terrain: Node) -> int:
	if terrain == null:
		return min_terrain_collision_radius_meters
	if terrain.has_method("get_collision_radius"):
		return int(terrain.call("get_collision_radius"))
	if "collision_radius" in terrain:
		return int(terrain.get("collision_radius"))
	return min_terrain_collision_radius_meters

func _set_terrain_collision_radius(terrain: Node, radius: int) -> void:
	if terrain == null:
		return
	if terrain.has_method("set_collision_radius"):
		terrain.call("set_collision_radius", radius)
	else:
		terrain.set("collision_radius", radius)

func _is_entity_within_load_radius(em: EntityManager, entity_id: StringName) -> bool:
	if _effective_load_radius_meters <= 0.0:
		return true
	var distance_meters: float = _get_entity_distance_to_player(em, entity_id)
	if distance_meters < 0.0:
		return true
	return distance_meters <= _effective_load_radius_meters

func _is_entity_outside_unload_radius(em: EntityManager, entity_id: StringName) -> bool:
	if _effective_unload_radius_meters <= 0.0:
		return false
	var distance_meters: float = _get_entity_distance_to_player(em, entity_id)
	if distance_meters < 0.0:
		return false
	return distance_meters > _effective_unload_radius_meters

func _get_entity_distance_to_player(em: EntityManager, entity_id: StringName) -> float:
	if GameManager.session == null or GameManager.session.entities == null:
		return -1.0
	var player_data := GameManager.session.entities.get_player()
	if player_data == null or not player_data.has_world_transform:
		return -1.0
	var entity := em.get_entity(entity_id)
	if entity == null:
		return -1.0
	var tf := entity.get_transform()
	if tf == null:
		return -1.0
	return player_data.world_position.distance_to(tf.world_position)

func _enforce_stream_radii(em: EntityManager) -> void:
	# Ensure distance-driven hysteresis still applies in chunks that remain active.
	for entity_id_any: Variant in _spawned_views.keys():
		if entity_id_any is StringName:
			var spawned_id: StringName = entity_id_any
			if _is_group_outside_unload_radius(em, spawned_id):
				_queue_unload_with_group(em, spawned_id)

	for chunk: Vector2i in _current_active_chunks:
		for entity_id: StringName in em.get_entities_in_chunk(chunk):
			if _is_group_within_load_radius(em, entity_id):
				_queue_load_with_group(em, entity_id)

func _is_group_within_load_radius(em: EntityManager, entity_id: StringName) -> bool:
	var group_id := em.get_entity_group(entity_id)
	if group_id == &"":
		return _is_entity_within_load_radius(em, entity_id)

	for member_id: StringName in em.get_group_members(group_id):
		if _is_entity_within_load_radius(em, member_id):
			return true
	return false

func _is_group_outside_unload_radius(em: EntityManager, entity_id: StringName) -> bool:
	var group_id := em.get_entity_group(entity_id)
	if group_id == &"":
		return _is_entity_outside_unload_radius(em, entity_id)

	for member_id: StringName in em.get_group_members(group_id):
		if not _is_entity_outside_unload_radius(em, member_id):
			return false
	return true

func _is_group_active(em: EntityManager, entity_id: StringName) -> bool:
	var group_id := em.get_entity_group(entity_id)
	if group_id == &"":
		var chunk_id := em.get_entity_chunk_id(entity_id)
		return _current_active_chunks.has(chunk_id)

	var members := em.get_group_members(group_id)
	for member_id: StringName in members:
		var chunk_id := em.get_entity_chunk_id(member_id)
		if _current_active_chunks.has(chunk_id):
			return true
	return false

func _queue_load_with_group(em: EntityManager, entity_id: StringName) -> void:
	var group_id := em.get_entity_group(entity_id)
	if group_id == &"":
		_queue_load(entity_id)
	else:
		for member_id: StringName in em.get_group_members(group_id):
			_queue_load(member_id)

func _queue_unload_with_group(em: EntityManager, entity_id: StringName) -> void:
	var group_id := em.get_entity_group(entity_id)
	if group_id == &"":
		_queue_unload(entity_id)
	else:
		for member_id: StringName in em.get_group_members(group_id):
			_queue_unload(member_id)

func _queue_load(entity_id: StringName) -> void:
	_pending_unload.erase(entity_id)
	
	if _spawned_views.has(entity_id):
		# If it was spawned, queued for unload (and frozen), but the player turned back around:
		# Unfreeze it instantly and remove it from the load queue.
		var view: Node = _spawned_views[entity_id]
		if is_instance_valid(view) and view is RigidBody3D:
			view.freeze = false
			view.sleeping = false
		return
		
	# Also cancel pending resource loads if re-queued
	if _pending_resource.has(entity_id):
		return # Already waiting for background load
		
	_pending_load[entity_id] = true

func _queue_unload(entity_id: StringName) -> void:
	_pending_load.erase(entity_id)
	_pending_resource.erase(entity_id)
	if _should_preserve_active_vehicle_group(entity_id):
		return
	if not _spawned_views.has(entity_id): return
	_pending_unload[entity_id] = true
	
	# THE SAFETY FREEZE: Prevent falling through the floor while waiting for the spooler budget
	var view: Node = _spawned_views[entity_id]
	if is_instance_valid(view) and view is RigidBody3D:
		view.freeze = true
		view.sleeping = true

func _should_preserve_active_vehicle_group(entity_id: StringName) -> bool:
	if not GameManager.session or not GameManager.session.entities:
		return false

	var em := GameManager.session.entities as EntityManager
	var player_data := em.get_player()
	if player_data == null:
		return false

	var active_vehicle_id: StringName = player_data.active_vehicle_id
	if active_vehicle_id == &"":
		return false

	if entity_id == active_vehicle_id:
		return true

	var active_vehicle_group_id := em.get_entity_group(active_vehicle_id)
	if active_vehicle_group_id == &"":
		return false

	var entity_group_id := em.get_entity_group(entity_id)
	return entity_group_id != &"" and entity_group_id == active_vehicle_group_id

## Called externally (via EventBus signal) when a view is destroyed outside the
## normal streaming lifecycle (e.g., item picked up by player).
func release_view(entity_id: StringName) -> void:
	_pending_load.erase(entity_id)
	_pending_unload.erase(entity_id)
	_pending_resource.erase(entity_id)
	_spawned_views.erase(entity_id)

func _on_entity_view_released(entity_id: StringName) -> void:
	release_view(entity_id)

func _process(delta: float) -> void:
	# Lazy-bind if session wasn't ready during _ready()
	if not _bound_to_entity_manager:
		_bind_to_entity_manager()

	# Drive the spooler loop: poll player position at configurable interval
	_stream_timer += delta
	var tick_interval: float = maxf(0.01, stream_update_interval_seconds)
	while _stream_timer >= tick_interval:
		_stream_timer -= tick_interval
		if GameManager.session and GameManager.session.entities:
			var player_data := GameManager.session.entities.get_player()
			if player_data.has_world_transform:
				update_active_chunks(player_data.world_position, _resolve_stream_radius(stream_radius))

	# Background Resource Loading: poll threaded load status
	if not _pending_resource.is_empty():
		_poll_pending_resources()

	if not _pending_unload.is_empty():
		_spool_unloads()
	if not _pending_load.is_empty():
		_spool_loads()

## Polls ResourceLoader for threaded load completion.
## Moves completed loads back into _pending_load for instantiation.
func _poll_pending_resources() -> void:
	var completed_ids: Array[StringName] = []
	
	for entity_id_any: Variant in _pending_resource.keys():
		if entity_id_any is not StringName:
			continue
		var entity_id: StringName = entity_id_any
		var info: Dictionary = _pending_resource[entity_id]
		var scene_path: String = info["scene_path"]
		
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(scene_path)
		
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var scene: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
				if scene:
					_scene_cache[scene_path] = scene
				completed_ids.append(entity_id)
				
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				GameLog.warn("[StreamSpooler] Background load FAILED for: " + scene_path)
				completed_ids.append(entity_id)
				
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pass # Still loading, check next frame
	
	for entity_id: StringName in completed_ids:
		var info: Dictionary = _pending_resource[entity_id]
		_pending_resource.erase(entity_id)
		
		# Only re-queue for load if scene was successfully cached
		if _scene_cache.has(info["scene_path"]):
			_pending_load[entity_id] = true

func _spool_unloads() -> void:
	var start_time := Time.get_ticks_usec()
	var ids: Array = _pending_unload.keys()
	
	for entity_id: StringName in ids:
		if Time.get_ticks_usec() - start_time > 500: # 0.5ms limit for unloads
			break
			
		_pending_unload.erase(entity_id)
		var view: Node = _spawned_views.get(entity_id, null)
		if view and is_instance_valid(view):
			if view is Vehicle3D:
				var vehicle_view := view as Vehicle3D
				if vehicle_view.is_driven:
					vehicle_view.force_eject()
			if view.has_method("extract_data"):
				view.extract_data()
			# Safety Fix: remove from tree instantly before queue_free prevents physics/name collision
			if view.get_parent():
				view.get_parent().remove_child(view)
			view.queue_free()
			
		_spawned_views.erase(entity_id)

func _spool_loads() -> void:
	var start_time := Time.get_ticks_usec()
	var ids: Array = _pending_load.keys()
	
	for entity_id: StringName in ids:
		if Time.get_ticks_usec() - start_time > 1500: # 1.5ms limit for loads
			break
			
		_pending_load.erase(entity_id)
		if _spawned_views.has(entity_id): continue
		
		# Validate active state
		var entity: EntityDataRef = GameManager.session.entities.get_entity(entity_id)
		if not entity: continue
		
		# Skip entities that are inside another entity (e.g., in player's pocket)
		if entity.parent_id != &"":
			continue
		
		var current_mins: int = GameManager.session.time.get_total_minutes()
		var active_entity: EntityDataRef = CatchUpEngineRef.catch_up_entity(entity, current_mins)
		
		var EntityRegistry: Node = Engine.get_main_loop().root.get_node(^"EntityRegistry")
		var def: Dictionary = EntityRegistry.get_def(active_entity.definition_id)
		
		if def.has("view_scene"):
			var scene_path: String = String(def["view_scene"])
			var scene: PackedScene = _scene_cache.get(scene_path, null) as PackedScene
			
			if scene == null:
				# Scene not cached — fire threaded load request and defer this entity
				ResourceLoader.load_threaded_request(scene_path)
				_pending_resource[entity_id] = {
					"scene_path": scene_path,
					"entity": active_entity
				}
				continue
			
			# Scene is cached — instantiate on the main thread (fast path)
			var view: Node = scene.instantiate()
			if view is EntityView3DRef:
				var entity_view: EntityView3DRef = view as EntityView3DRef
				var container: Node = get_tree().get_first_node_in_group("world_entity_container")
				var spawn_parent: Node = container if container else self
				_spawn_view_entity(entity_view, active_entity, spawn_parent)
					
				_spawned_views[active_entity.runtime_id] = view

func _spawn_view_entity(view: EntityView3DRef, active_entity: EntityDataRef, spawn_parent: Node) -> void:
	# Vehicle3D initialization touches global transform-dependent state in the GEVP layer,
	# so it must be parented before apply_data().
	if view is Vehicle3D:
		spawn_parent.add_child(view)
		view.apply_data(active_entity)
		return

	# Pre-applying before parenting avoids a redundant transform pass when the parent
	# is world-identity. Fall back to parent-first for non-identity parents.
	if _can_preapply_data_before_parent(spawn_parent):
		view.apply_data(active_entity)
		spawn_parent.add_child(view)
	else:
		spawn_parent.add_child(view)
		view.apply_data(active_entity)

func _can_preapply_data_before_parent(spawn_parent: Node) -> bool:
	if spawn_parent is not Node3D:
		return false
	var parent_3d: Node3D = spawn_parent as Node3D
	return _is_identity_world_transform(parent_3d.global_transform)

func _is_identity_world_transform(xf: Transform3D, epsilon: float = 0.0001) -> bool:
	var eps_sq: float = epsilon * epsilon
	if xf.origin.length_squared() > eps_sq:
		return false
	if xf.basis.x.distance_squared_to(Vector3.RIGHT) > eps_sq:
		return false
	if xf.basis.y.distance_squared_to(Vector3.UP) > eps_sq:
		return false
	if xf.basis.z.distance_squared_to(Vector3.BACK) > eps_sq:
		return false
	return true

func refresh_from_current_chunks(reason: String = "manual") -> void:
	if not GameManager.session or not GameManager.session.entities:
		return
	var em := GameManager.session.entities as EntityManager
	for chunk: Vector2i in _current_active_chunks:
		for entity_id: StringName in em.get_entities_in_chunk(chunk):
			if _is_group_within_load_radius(em, entity_id):
				_queue_load_with_group(em, entity_id)