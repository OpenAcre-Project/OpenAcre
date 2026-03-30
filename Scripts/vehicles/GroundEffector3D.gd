class_name GroundEffector3D
extends Marker3D

const WORK_REQUEST_SCRIPT = preload("res://Scripts/farm/work/WorkRequest.gd")

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

func to_work_request(operation: int, previous_position: Vector3, payload: Dictionary = {}, source_tag: StringName = &"", max_budget: int = -1) -> WorkRequest:
	var merged_payload: Dictionary = payload.duplicate(true)
	merged_payload["depth_offset"] = target_depth_offset
	merged_payload["blend_mode"] = int(blend_mode)
	merged_payload["soil_state_output"] = soil_state_output

	var request := WORK_REQUEST_SCRIPT.line_sweep(
		operation,
		previous_position,
		global_position,
		maxf(effect_radius, 0.01),
		merged_payload,
		source_tag,
		max_budget
	)
	request.engagement_height = global_position.y
	request.engagement_margin = maxf(engagement_depth_margin, 0.0)
	return request
