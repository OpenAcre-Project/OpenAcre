@tool
extends SceneTree

func _init() -> void:
	print("=== RUNNING UESS FOUNDATION VERIFICATION ===")
	
	var EntityRegistry = preload("res://Scripts/core/EntityRegistry.gd").new()
	var EntityManagerScript = preload("res://Scripts/simulation/EntityManager.gd")
	var GridManagerScript = preload("res://Scripts/streaming/GridManager.gd")
	
	# 1. Test EntityRegistry Stub
	EntityRegistry.register_def(&"test_apple", {
		"components": {
			"transform": { "world_position": [10.0, 0.0, 10.0] },
			"durability": { "health": 100.0, "rot_rate_per_minute": 1.5 }
		}
	})
	
	# 2. Test Entity Creation
	var entity = EntityRegistry.create_entity(&"test_apple")
	assert(entity != null, "Entity creation failed")
	assert(entity.has_component(&"transform"), "Entity missing transform")
	assert(entity.has_component(&"durability"), "Entity missing durability")
	
	var tf = entity.get_transform()
	assert(tf.world_position.x == 10.0, "Transform data parsing failed")
	print("-> Entity Creation / Components OK")
	
	# 3. Test EntityManager Registration & Chunk Assignment
	var manager = EntityManagerScript.new()
	manager.register_entity(entity)
	
	var chunk_pos = tf.chunk_id
	assert(chunk_pos == Vector2i(0, 0), "Initial chunk calculation wrong")
	
	var chunk_entities = manager.get_entities_in_chunk(Vector2i(0, 0))
	assert(chunk_entities.has(entity.runtime_id), "Entity not in chunk map")
	print("-> Entity Registration and Chunk Assignment OK")
	
	# 4. Test Chunk Transition
	manager.update_entity_transform(entity.runtime_id, Vector3(100.0, 0.0, 100.0), 0.0)
	assert(tf.chunk_id == Vector2i(1, 1), "Chunk ID not updated after move")
	
	var old_chunk = manager.get_entities_in_chunk(Vector2i(0, 0))
	var new_chunk = manager.get_entities_in_chunk(Vector2i(1, 1))
	
	assert(not old_chunk.has(entity.runtime_id), "Entity still in old chunk")
	assert(new_chunk.has(entity.runtime_id), "Entity not in new chunk")
	print("-> Entity Chunk Transition OK")
	
	# 5. Test GridManager Active Chunks
	var active_chunks = GridManagerScript.get_active_chunks_around(Vector3(100.0, 0, 100.0), 1)
	assert(active_chunks.size() == 9, "GridManager radius math wrong")
	assert(active_chunks.has(Vector2i(1,1)), "GridManager missing center chunk")
	print("-> GridManager Active Chunks OK")
	
	print("=== UESS VERIFICATION COMPLETE ===")
	quit()
