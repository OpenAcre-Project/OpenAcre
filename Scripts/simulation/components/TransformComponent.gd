class_name TransformComponent
extends Component

## Represents the physical location of an Entity.

var world_position: Vector3 = Vector3.ZERO
var world_rotation_radians: float = 0.0
var is_sleeping: bool = false
var linear_velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO

## The current grid chunk the entity resides in.
## Updated by EntityManager when position crosses chunk boundaries.
var chunk_id: Vector2i = Vector2i.ZERO

func _init() -> void:
	type_id = &"transform"

func load_from_dict(data: Dictionary) -> void:
	if data.has("world_position"):
		var pos: Array = data["world_position"]
		world_position = Vector3(pos[0], pos[1], pos[2])
	
	if data.has("world_rotation_radians"):
		world_rotation_radians = data["world_rotation_radians"]
	
	if data.has("chunk_id"):
		var ch: Array = data["chunk_id"]
		chunk_id = Vector2i(ch[0], ch[1])

	if data.has("is_sleeping"):
		is_sleeping = bool(data["is_sleeping"])

	if data.has("linear_velocity"):
		var lv: Array = data["linear_velocity"]
		linear_velocity = Vector3(lv[0], lv[1], lv[2])

	if data.has("angular_velocity"):
		var av: Array = data["angular_velocity"]
		angular_velocity = Vector3(av[0], av[1], av[2])

func save_to_dict() -> Dictionary:
	return {
		"world_position": [world_position.x, world_position.y, world_position.z],
		"world_rotation_radians": world_rotation_radians,
		"chunk_id": [chunk_id.x, chunk_id.y],
		"is_sleeping": is_sleeping,
		"linear_velocity": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"angular_velocity": [angular_velocity.x, angular_velocity.y, angular_velocity.z]
	}
