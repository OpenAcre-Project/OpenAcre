extends Resource
class_name ItemDefinition

## Unique ID (e.g., "item.water_bottle", "item.apple")
@export var id: StringName = &""

## Base Mass in kg per unit
@export var base_mass: float = 0.1

## Base Volume in Liters per unit
@export var base_volume: float = 0.1

## If > 1, the item cannot contain embedded inventories/tanks.
@export var max_stack_size: int = 1

## The 3D RigidBody to spawn when dropped.
@export var world_scene: PackedScene
