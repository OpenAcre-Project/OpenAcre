extends Node3D
class_name MapDefinition

@export var map_id: StringName = &"default_map"
@export var map_display_name: String = "Default Map"
@export var default_player_spawn_id: StringName = &"spawn_main"
@export var starting_vehicles: VehicleSpawnTable
@export var region_mask: MapRegionMask

func _ready() -> void:
	add_to_group("map_root")
	
	if region_mask != null:
		region_mask.initialize()
	
	# Find the terrain node automatically and group it so SoilLayerService can find it
	var terrain: Node = _find_terrain(self)
	if terrain != null:
		terrain.add_to_group("terrain_node")
		GameLog.info("[Map] Registered terrain node: " + terrain.name)

# Recursively searches for Terrain3D
func _find_terrain(node: Node) -> Node:
	# Check for Terrain3D
	if node.get_class() == "Terrain3D":
		return node
		
	for child in node.get_children():
		var found: Node = _find_terrain(child)
		if found != null:
			return found
	return null
