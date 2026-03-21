extends Resource
class_name CommodityDefinition

## Unique ID (e.g., "commodity.diesel", "commodity.wheat")
@export var id: StringName = &""

## Density in kg per Liter (e.g., Water = 1.0, Wheat = 0.77, Diesel = 0.85)
@export var density: float = 1.0
