class_name GroundEffector3D
extends Marker3D

enum BlendMode {
	ADD,
	SUBTRACT,
	REPLACE_EXACT
}

@export var effect_radius: float = 0.2
@export var target_depth_offset: float = -0.15
@export var blend_mode: BlendMode = BlendMode.ADD
@export_enum("GRASS:0", "PLOWED:1", "SEEDED:2", "HARVESTABLE:3") var soil_state_output: int = 1
@export var is_engaged: bool = true
@export var engagement_depth_margin: float = 0.03

func to_ground_instruction(previous_position: Vector3) -> Dictionary:
	return {
		"effector_path": str(get_path()),
		"previous_pos": previous_position,
		"current_pos": global_position,
		"radius": maxf(effect_radius, 0.01),
		"depth_offset": target_depth_offset,
		"blend_mode": int(blend_mode),
		"soil_state_output": soil_state_output,
		"engagement_margin": maxf(engagement_depth_margin, 0.0)
	}
