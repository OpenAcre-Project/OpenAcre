extends RefCounted
class_name WorkReport

const WORK_OPERATION_TYPE_SCRIPT = preload("res://Scripts/farm/work/WorkOperationType.gd")

var operation: int = WORK_OPERATION_TYPE_SCRIPT.Value.TILLAGE
var requested_area: float = 0.0
var successful_area: float = 0.0
var rejected_area: float = 0.0

var yield_generated: Dictionary = {}

var rejected_unfarmable: int = 0
var rejected_wrong_state: int = 0
var rejected_height: int = 0
var rejected_budget: int = 0

# Optional debug buffers (only filled when debug flag is enabled)
var accepted_tiles: Array[Vector2i] = []
var rejected_tiles: Array[Vector2i] = []

func set_operation(value: int) -> WorkReport:
	operation = value
	return self

func add_yield(item_id: StringName, quantity: float) -> void:
	if quantity <= 0.0:
		return
	var key: String = String(item_id)
	yield_generated[key] = float(yield_generated.get(key, 0.0)) + quantity

func finalize(tile_area_m2: float) -> void:
	requested_area = maxf(requested_area, 0.0)
	successful_area = maxf(successful_area, 0.0)
	rejected_area = maxf(rejected_area, 0.0)
	# Keep area fields coherent with integer tile counters when caller filled only tallies.
	if is_equal_approx(requested_area, 0.0):
		requested_area = float(get_total_tiles()) * tile_area_m2
	if is_equal_approx(successful_area, 0.0):
		successful_area = float(get_success_tiles()) * tile_area_m2
	if is_equal_approx(rejected_area, 0.0):
		rejected_area = float(get_rejected_tiles()) * tile_area_m2

func get_success_tiles() -> int:
	return accepted_tiles.size()

func get_rejected_tiles() -> int:
	return rejected_unfarmable + rejected_wrong_state + rejected_height + rejected_budget

func get_total_tiles() -> int:
	return get_success_tiles() + get_rejected_tiles()

func to_log_summary() -> String:
	return "op=%s req=%.1f succ=%.1f rej=%.1f (unfarmable=%d wrong_state=%d height=%d budget=%d)" % [
		WORK_OPERATION_TYPE_SCRIPT.as_string(operation),
		requested_area,
		successful_area,
		rejected_area,
		rejected_unfarmable,
		rejected_wrong_state,
		rejected_height,
		rejected_budget
	]
