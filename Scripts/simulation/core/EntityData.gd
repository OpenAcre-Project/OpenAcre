class_name EntityData
extends RefCounted

## Master Data Object for a single Entity. No 3D Nodes.

## The runtime unique ID of this entity instance
var runtime_id: StringName = &""
## The definition ID (which JSON template generated this)
var definition_id: StringName = &""

## If this entity is inside another entity (e.g. apple in truck), stores parent ID
var parent_id: StringName = &""

## Maps component type_id (StringName) -> Component instance
var _components: Dictionary = {}

func _init(p_runtime_id: StringName, p_definition_id: StringName) -> void:
	self.runtime_id = p_runtime_id
	self.definition_id = p_definition_id

## Add or overwrite a component
func add_component(comp: Component) -> void:
	_components[comp.type_id] = comp

## Retrieves a component by type_id, or null if not present
func get_component(type_id: StringName) -> Component:
	return _components.get(type_id, null)

## Check if entity has a specific component type
func has_component(type_id: StringName) -> bool:
	return _components.has(type_id)

func get_all_components() -> Array:
	return _components.values()

## Helper getter specifically for TransformComponent since it's used so often
func get_transform() -> TransformComponent:
	return get_component(&"transform") as TransformComponent

## Determines whether this entity can merge its stack with another entity.
## Returns true only if both entities have the same definition and ALL components
## (excluding StackableComponent.count and TransformComponent position data) are
## identical. This prevents stacking items with different durability, enchantments, etc.
func can_stack_with(other: EntityData) -> bool:
	if definition_id != other.definition_id:
		return false
	
	# Must both be stackable
	if not has_component(&"stackable") or not other.has_component(&"stackable"):
		return false
	
	# Compare all components except stackable and transform
	var my_keys: Array = []
	var other_keys: Array = []
	for key: StringName in _components:
		if key != &"stackable" and key != &"transform":
			my_keys.append(key)
	for key: StringName in other._components:
		if key != &"stackable" and key != &"transform":
			other_keys.append(key)
	
	if my_keys.size() != other_keys.size():
		return false
	
	for key: StringName in my_keys:
		if not other._components.has(key):
			return false
		var my_dict: Dictionary = _components[key].save_to_dict()
		var other_dict: Dictionary = other._components[key].save_to_dict()
		if my_dict != other_dict:
			return false
	
	return true

