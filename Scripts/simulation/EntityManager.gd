class_name EntityManager
extends RefCounted

const PlayerDataRef = preload("res://Scripts/simulation/resources/PlayerData.gd")


signal player_data_changed(player_id: StringName, data: PlayerData)
signal entity_registered(entity_id: StringName)

var _players: Dictionary = {}

# UESS Phase 1 & 2: General Entities and Chunking
var _entities: Dictionary = {}
var _chunks: Dictionary = {} # Vector2i -> Array[StringName]
var _children_by_parent: Dictionary = {} # StringName (parent_id) -> Array[StringName] (child_ids)
const CHUNK_SIZE: float = 64.0 # meters

# Streaming Groups (Phase 6)
var _streaming_groups: Dictionary = {} # StringName (group_id) -> Array[StringName] (entity_ids)
var _entity_to_group: Dictionary = {} # StringName (entity_id) -> StringName (group_id)

func tick(_delta: float) -> void:
	pass

func _init() -> void:
	pass

func _on_minute_passed() -> void:
	for player_id_any: Variant in _players.keys():
		if player_id_any is StringName:
			var data: PlayerData = _players[player_id_any]
			data.tick_survival_minute()



func ensure_player(player_id: StringName = &"player.main") -> PlayerData:
	if not _players.has(player_id):
		var data := PlayerDataRef.new()
		data.player_id = player_id
		_players[player_id] = data
	return _players[player_id]



func get_player(player_id: StringName = &"player.main") -> PlayerData:
	return ensure_player(player_id)



func set_player_transform(player_id: StringName, world_position: Vector3, world_yaw_radians: float) -> void:
	var data := ensure_player(player_id)
	data.set_transform(world_position, world_yaw_radians)
	player_data_changed.emit(player_id, data)

func set_player_stats(player_id: StringName, stamina: float, health: float) -> void:
	var data := ensure_player(player_id)
	data.stamina = stamina
	data.health = health
	player_data_changed.emit(player_id, data)

func set_player_active_vehicle(player_id: StringName, vehicle_id: StringName) -> void:
	var data := ensure_player(player_id)
	data.active_vehicle_id = vehicle_id
	player_data_changed.emit(player_id, data)



# ==========================================
# UESS: General Entity & Chunk Management
# ==========================================
func register_entity(entity: EntityData) -> void:
	if _entities.has(entity.runtime_id):
		var previous: EntityData = _entities[entity.runtime_id] as EntityData
		if previous != null:
			_unlink_child_from_parent(entity.runtime_id, previous.parent_id)
	_entities[entity.runtime_id] = entity
	_link_child_to_parent(entity.runtime_id, entity.parent_id)
	var tf: TransformComponent = entity.get_transform()
	if tf != null:
		_update_entity_chunk_internal(entity, tf)
	entity_registered.emit(entity.runtime_id)

func remove_entity(entity_id: StringName) -> void:
	if not _entities.has(entity_id): return

	var removal_order: Array[StringName] = []
	var stack: Array[StringName] = [entity_id]
	var visited: Dictionary = {}

	while not stack.is_empty():
		var current_id: StringName = stack.pop_back()
		if visited.has(current_id):
			continue
		visited[current_id] = true

		if not _entities.has(current_id):
			continue

		removal_order.append(current_id)
		for child_id: StringName in _get_children(current_id):
			stack.append(child_id)

	# Remove deepest children first so parent links can be cleaned safely.
	for idx: int in range(removal_order.size() - 1, -1, -1):
		var current_id: StringName = removal_order[idx]
		if not _entities.has(current_id):
			continue

		var current_entity: EntityData = _entities[current_id] as EntityData
		if current_entity == null:
			_entities.erase(current_id)
			_clear_children_index(current_id)
			continue

		var tf := current_entity.get_transform()
		if tf != null:
			_remove_from_chunk(current_id, tf.chunk_id)

		_unlink_child_from_parent(current_id, current_entity.parent_id)
		_clear_children_index(current_id)
		remove_entity_from_group(current_id)
		_entities.erase(current_id)

func get_entity(entity_id: StringName) -> EntityData:
	return _entities.get(entity_id, null)

## Dynamically resolves chunk ID by traversing parent hierarchy
func get_entity_chunk_id(entity_id: StringName) -> Vector2i:
	var entity: EntityData = get_entity(entity_id) as EntityData
	if not entity: return Vector2i.ZERO
	if entity.parent_id != &"":
		return get_entity_chunk_id(entity.parent_id)
	var tf: TransformComponent = entity.get_transform()
	if tf: return tf.chunk_id
	return Vector2i.ZERO

func update_entity_transform(entity_id: StringName, new_pos: Vector3, new_rot: float) -> void:
	var entity: EntityData = get_entity(entity_id)
	if entity == null: return
	
	var tf: TransformComponent = entity.get_transform()
	if tf == null: return
	
	tf.world_position = new_pos
	tf.world_rotation_radians = new_rot
	_update_entity_chunk_internal(entity, tf)

func _update_entity_chunk_internal(entity: EntityData, tf: TransformComponent) -> void:
	# Ignore hierarchical children for rendering chunks
	if entity.parent_id != &"":
		_remove_from_chunk(entity.runtime_id, tf.chunk_id)
		return
		
	var new_chunk_id := Vector2i(floor(tf.world_position.x / CHUNK_SIZE), floor(tf.world_position.z / CHUNK_SIZE))
	
	# Only update if chunk changed or entity isn't properly registered in the target chunk yet
	if new_chunk_id != tf.chunk_id or not _chunks.has(tf.chunk_id) or not _chunks[tf.chunk_id].has(entity.runtime_id):
		_remove_from_chunk(entity.runtime_id, tf.chunk_id)
		tf.chunk_id = new_chunk_id
		if not _chunks.has(new_chunk_id):
			_chunks[new_chunk_id] = [] as Array[StringName]
		if not _chunks[new_chunk_id].has(entity.runtime_id):
			_chunks[new_chunk_id].append(entity.runtime_id)

func _remove_from_chunk(entity_id: StringName, chunk_id: Vector2i) -> void:
	if _chunks.has(chunk_id):
		_chunks[chunk_id].erase(entity_id)
		if _chunks[chunk_id].is_empty():
			_chunks.erase(chunk_id)

func _link_child_to_parent(child_id: StringName, parent_id: StringName) -> void:
	if parent_id == &"":
		return
	if not _children_by_parent.has(parent_id):
		_children_by_parent[parent_id] = [] as Array[StringName]
	var children: Array[StringName] = _children_by_parent[parent_id]
	if not children.has(child_id):
		children.append(child_id)

func _unlink_child_from_parent(child_id: StringName, parent_id: StringName) -> void:
	if parent_id == &"":
		return
	if not _children_by_parent.has(parent_id):
		return
	var children: Array[StringName] = _children_by_parent[parent_id]
	children.erase(child_id)
	if children.is_empty():
		_children_by_parent.erase(parent_id)

func _clear_children_index(parent_id: StringName) -> void:
	if _children_by_parent.has(parent_id):
		_children_by_parent.erase(parent_id)

func _get_children(parent_id: StringName) -> Array[StringName]:
	if _children_by_parent.has(parent_id):
		return (_children_by_parent[parent_id] as Array[StringName]).duplicate()
	return [] as Array[StringName]

## Assigns a parent to an entity, removing it from spatial chunks.
## Used when an item enters an inventory: the entity stops being streamed/rendered
## but remains in _entities for the flat-database save system.
func set_entity_parent(entity_id: StringName, new_parent_id: StringName) -> void:
	var entity: EntityData = get_entity(entity_id)
	if not entity: return
	if entity.parent_id == new_parent_id:
		return

	_unlink_child_from_parent(entity_id, entity.parent_id)
	entity.parent_id = new_parent_id
	_link_child_to_parent(entity_id, new_parent_id)
	var tf: TransformComponent = entity.get_transform()
	if tf:
		_update_entity_chunk_internal(entity, tf)

## Clears an entity's parent and re-registers it into the spatial chunk system
## at the given world position. StreamSpooler will automatically detect and spawn it.
## Used when an item is dropped from an inventory back into the world.
func clear_entity_parent(entity_id: StringName, new_world_pos: Vector3, new_rot: float) -> void:
	var entity: EntityData = get_entity(entity_id)
	if not entity: return
	_unlink_child_from_parent(entity_id, entity.parent_id)
	entity.parent_id = &""
	var tf: TransformComponent = entity.get_transform()
	if tf:
		tf.world_position = new_world_pos
		tf.world_rotation_radians = new_rot
		# Force chunk_id to an impossible value so _update_entity_chunk_internal
		# always re-inserts into the correct chunk.
		tf.chunk_id = Vector2i(999999, 999999)
		_update_entity_chunk_internal(entity, tf)

func get_entities_in_chunk(chunk_id: Vector2i) -> Array[StringName]:
	if _chunks.has(chunk_id):
		return _chunks[chunk_id] as Array[StringName]
	return [] as Array[StringName]

# ==========================================
# UESS: Streaming Groups (Phase 6)
# ==========================================
func assign_entity_to_group(entity_id: StringName, group_id: StringName) -> void:
	remove_entity_from_group(entity_id)
	
	if not _streaming_groups.has(group_id):
		_streaming_groups[group_id] = [] as Array[StringName]
	_streaming_groups[group_id].append(entity_id)
	_entity_to_group[entity_id] = group_id

func remove_entity_from_group(entity_id: StringName) -> void:
	if _entity_to_group.has(entity_id):
		var group_id: StringName = _entity_to_group[entity_id]
		if _streaming_groups.has(group_id):
			_streaming_groups[group_id].erase(entity_id)
			if _streaming_groups[group_id].is_empty():
				_streaming_groups.erase(group_id)
		_entity_to_group.erase(entity_id)

func get_entity_group(entity_id: StringName) -> StringName:
	return _entity_to_group.get(entity_id, &"")

func get_group_members(group_id: StringName) -> Array[StringName]:
	if _streaming_groups.has(group_id):
		return _streaming_groups[group_id]
	return [] as Array[StringName]
