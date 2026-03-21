extends Resource
class_name PlayerData

@export var player_id: StringName = &"player.main"
@export var has_world_transform: bool = false
@export var world_position: Vector3 = Vector3.ZERO
@export var world_yaw_radians: float = 0.0
@export var active_vehicle_id: StringName = &""

# Survival stats (headless — ticked by SimulationCore independently of 3D puppet)
@export var max_calories: float = 1000.0
@export var max_hydration: float = 100.0
@export var max_energy: float = 100.0
@export var calories: float = 1000.0
@export var hydration: float = 100.0
@export var energy: float = 100.0

# Inventory system
var pockets: InventoryData = InventoryData.new()
var equipment_back: ItemInstance = null # Slot for a backpack

func _init() -> void:
	# Default pocket settings
	pockets.max_volume = 2.0
	pockets.max_mass = 5.0

func get_total_encumbrance_mass() -> float:
	var total: float = pockets.get_current_mass()
	if equipment_back:
		total += equipment_back.get_total_mass()
	return total

# Legacy aliases for backwards compat with GameManager.session.entities.set_player_stats
var stamina: float:
	get: return energy
	set(value): energy = value
var health: float:
	get: return calories / max_calories * 100.0
	set(_value): pass

func set_transform(position: Vector3, yaw_radians: float) -> void:
	has_world_transform = true
	world_position = position
	world_yaw_radians = yaw_radians

func tick_survival_minute() -> void:
	calories = clamp(calories - 0.1, 0.0, max_calories)
	hydration = clamp(hydration - 0.05, 0.0, max_hydration)
	energy = clamp(energy - 0.02, 0.0, max_energy)

func burn_energy(delta: float) -> void:
	energy = clamp(energy - 10.0 * delta, 0.0, max_energy)
	calories = clamp(calories - 2.0 * delta, 0.0, max_calories)
