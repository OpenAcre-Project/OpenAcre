@tool
extends Marker3D
class_name MapSpawnPoint

enum SpawnType { PLAYER, VEHICLE, NPC }

@export var spawn_type: SpawnType = SpawnType.PLAYER:
	set(val):
		spawn_type = val
		update_configuration_warnings()

@export var spawn_id: StringName = &"spawn_main"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	# Register this spawn point to a group so the MapManager can find it
	match spawn_type:
		SpawnType.PLAYER:
			add_to_group("spawn_points_player")
		SpawnType.VEHICLE:
			add_to_group("spawn_points_vehicle")
		SpawnType.NPC:
			add_to_group("spawn_points_npc")

# Helper to automatically snap the marker to the ground in the editor
func snap_to_ground() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 10.0, global_position + Vector3.DOWN * 100.0)
	var hit: Dictionary = space_state.intersect_ray(query)
	
	if hit and hit.has("position"):
		global_position = hit["position"]
		print("Snapped %s to ground." % name)
