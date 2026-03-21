extends Node

## Singleton for looking up item and commodity definitions.
## Should be added as an Autoload named "ItemRegistry".

var _items: Dictionary = {} # StringName -> ItemDefinition
var _commodities: Dictionary = {} # StringName -> CommodityDefinition

func _ready() -> void:
	# Register default items
	var apple := ItemDefinition.new()
	apple.id = &"item.apple"
	apple.base_mass = 0.15
	apple.base_volume = 0.2
	apple.world_scene = preload("res://Scenes/Interactables/Apple.tscn")
	register_item(apple)
	
	# Register commodities
	var diesel := CommodityDefinition.new()
	diesel.id = &"commodity.diesel"
	diesel.density = 0.85
	register_commodity(diesel)
	
	var water := CommodityDefinition.new()
	water.id = &"commodity.water"
	water.density = 1.0
	register_commodity(water)

func register_item(item: ItemDefinition) -> void:
	if item == null or item.id == &"":
		return
	_items[item.id] = item

func register_commodity(commodity: CommodityDefinition) -> void:
	if commodity == null or commodity.id == &"":
		return
	_commodities[commodity.id] = commodity

func get_item(id: StringName) -> ItemDefinition:
	return _items.get(id)

func get_commodity(id: StringName) -> CommodityDefinition:
	return _commodities.get(id)

func get_commodity_density(id: StringName) -> float:
	var def: CommodityDefinition = get_commodity(id)
	return def.density if def else 1.0
