extends RigidBody3D

@export var plow_width: float = 3.0
@export var is_lowered: bool = true

@onready var detection_area: Area3D = $DetectionArea

func _ready() -> void:
	# Allow custom width
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(plow_width, 0.5, 0.5)
	$DetectionArea/CollisionShape3D.shape = shape
	
func _physics_process(_delta: float) -> void:
	# If dragged across the floor while lowered
	if is_lowered:
		if linear_velocity.length_squared() > 0.1:
			_plow_ground()

func _plow_ground() -> void:
	var overlapping_bodies: Array = detection_area.get_overlapping_bodies()
	
	# Check if we are physically touching the floor
	var touching_floor: bool = false
	for body: Node in overlapping_bodies:
		if body.name == "Floor":
			touching_floor = true
			break
			
	if touching_floor:
		var soil_service: Node = get_tree().get_first_node_in_group("soil_layer_service")

		# Calculate grid coords from left to right along the plow width
		var center_pos: Vector3 = global_position
		var right_dir: Vector3 = global_transform.basis.x.normalized()
		
		# Sample grid blocks across the width of the plow
		var half_width_samples: int = int(plow_width / 2.0)
		for i: int in range(-half_width_samples, half_width_samples + 1):
			var sample_pos: Vector3 = center_pos + (right_dir * i)
			
			if not FarmData.can_plow_at(sample_pos):
				continue
				
			var grid_pos: Vector2i = FarmData.world_to_grid(sample_pos)

			if soil_service != null and soil_service.has_method("plow_world"):
				soil_service.plow_world(sample_pos)
			else:
				var tile_data: FarmTileData = FarmData.get_tile_data(grid_pos)
				if tile_data.state == FarmData.SoilState.GRASS:
					FarmData.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, sample_pos.y)
