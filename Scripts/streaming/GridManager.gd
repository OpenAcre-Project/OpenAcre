class_name GridManager
extends RefCounted

## Manages coordinate math for Spatial Chunks and computes which chunks 
## should be active/loaded based on player position and render distance.

## Chunks are currently defined in EntityManager as 64x64m grids, but they scale easily.
const CHUNK_SIZE: float = 64.0 

## Calculates what chunk a given world position falls into.
static func get_chunk_for_position(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floor(world_pos.x / CHUNK_SIZE),
		floor(world_pos.z / CHUNK_SIZE)
	)

## Calculates an array of chunk coordinates that fall within `radius_chunks` 
## distance of the center position. 
static func get_active_chunks_around(center_pos: Vector3, radius_chunks: int = 1) -> Array[Vector2i]:
	var center_chunk: Vector2i = get_chunk_for_position(center_pos)
	var active_chunks: Array[Vector2i] = []
	
	# Build a square grid around the center
	for x_offset in range(-radius_chunks, radius_chunks + 1):
		for y_offset in range(-radius_chunks, radius_chunks + 1):
			active_chunks.append(Vector2i(center_chunk.x + x_offset, center_chunk.y + y_offset))
			
	return active_chunks

## (Preview for Phase 4) Computes which chunks need to be loaded vs unloaded
## given the previous frame's active chunks and the new frame's active chunks.
static func compute_chunk_deltas(old_chunks: Array[Vector2i], new_chunks: Array[Vector2i]) -> Dictionary:
	var to_load: Array[Vector2i] = []
	var to_unload: Array[Vector2i] = []
	
	var old_dict := {}
	for c in old_chunks:
		old_dict[c] = true
	var new_dict := {}
	for c in new_chunks:
		new_dict[c] = true
	
	for chunk in new_chunks:
		if not old_dict.has(chunk):
			to_load.append(chunk)
			
	for chunk in old_chunks:
		if not new_dict.has(chunk):
			to_unload.append(chunk)
			
	return {
		"load": to_load,
		"unload": to_unload
	}
