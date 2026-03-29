extends Node

## EntityRegistry Autoload
## Loads entity definitions (from JSON/Resources) and acts as the factory for new entities.

var _definitions: Dictionary = {}
var _id_counter: int = 0
var _component_scripts: Dictionary = {
	"transform": preload("res://Scripts/simulation/components/TransformComponent.gd"),
	"durability": preload("res://Scripts/simulation/components/DurabilityComponent.gd"),
	"container": preload("res://Scripts/simulation/components/ContainerComponent.gd"),
	"vehicle": preload("res://Scripts/simulation/components/VehicleComponent.gd"),
	"seat": preload("res://Scripts/simulation/components/SeatComponent.gd"),
	"item": preload("res://Scripts/simulation/components/ItemComponent.gd"),
	"stackable": preload("res://Scripts/simulation/components/StackableComponent.gd")
}

func register_component_class(type_id: String, script_res: GDScript) -> void:
	_component_scripts[type_id] = script_res

func _generate_uuid() -> StringName:
	_id_counter += 1
	var unix_part := int(Time.get_unix_time_from_system())
	var time_part := Time.get_ticks_usec()
	return StringName(str(unix_part) + "_" + str(time_part) + "_" + str(_id_counter))

func _ready() -> void:
	# Load definitions from disk here
	load_all_definitions()

func load_all_definitions() -> void:
	var path := "res://Data/Entities/"
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				_load_json_definition(path + file_name)
			file_name = dir.get_next()
	else:
		GameLog.warn("EntityRegistry: Data/Entities directory not found.")
		
func _load_json_definition(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		return
		
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file: return
	
	var json_text := file.get_as_text()
	var json := JSON.new()
	var error_err := json.parse(json_text)
	
	if error_err == OK:
		var data: Variant = json.data
		if typeof(data) == TYPE_DICTIONARY:
			var dict_data: Dictionary = data as Dictionary
			var def_id: StringName = dict_data.get("id", &"")
			if def_id != &"":
				register_def(def_id, dict_data)
				GameLog.info("EntityRegistry: Loaded JSON definition for " + str(def_id))
	else:
		GameLog.warn("EntityRegistry: Failed to parse JSON at " + file_path)

## Registers a factory definition manually (useful for code-driven defs or parsed JSONs)
## definition_data example:
## { "view_scene": "res://Scenes/Interactables/apple.tscn", "components": { "transform": {}, "durability": {"health": 50} } }
func register_def(def_id: StringName, definition_data: Dictionary) -> void:
	_definitions[def_id] = definition_data

func has_def(def_id: StringName) -> bool:
	return _definitions.has(def_id)

func get_def(def_id: StringName) -> Dictionary:
	return _definitions.get(def_id, {})

## Factory method: creates an EntityData with all components according to its definition.
## Generates a unique runtime ID unless force_runtime_id is provided.
func create_entity(def_id: StringName, force_runtime_id: StringName = &"") -> EntityData:
	if not has_def(def_id):
		GameLog.warn("EntityRegistry: Unknown definition_id: " + str(def_id))
		return null
	
	var def: Dictionary = get_def(def_id)
	var runtime_id: StringName = force_runtime_id if force_runtime_id != &"" else _generate_uuid()
	var entity: EntityData = EntityData.new(runtime_id, def_id)
	
	var components_dict: Dictionary = def.get("components", {})
	
	# Determine current global time to timestamp fresh instances
	var spawn_time: int = 0
	if GameManager.session != null and GameManager.session.time != null:
		spawn_time = GameManager.session.time.get_total_minutes()
		
	for comp_type: String in components_dict.keys():
		var comp_data: Dictionary = components_dict[comp_type]
		var comp: Component = _create_component(comp_type)
		if comp:
			comp.load_from_dict(comp_data)
			comp.last_simulated_minute = spawn_time
			entity.add_component(comp)
			
	return entity

## Internal factory for mapping type_id to Component Scripts
func _create_component(type_id: String) -> Component:
	if _component_scripts.has(type_id):
		return _component_scripts[type_id].new()
	GameLog.warn("EntityRegistry: Unhandled component type: " + type_id)
	return null

## Creates a deep copy of an EntityData with a new unique runtime_id.
## Uses the serialize/deserialize round-trip to ensure all component data is faithfully copied.
## Used when splitting stacks during inventory operations.
func clone_entity(source: EntityData) -> EntityData:
	var new_id: StringName = _generate_uuid()
	var clone: EntityData = EntityData.new(new_id, source.definition_id)
	clone.parent_id = source.parent_id
	
	for comp: Component in source.get_all_components():
		var new_comp: Component = _create_component(String(comp.type_id))
		if new_comp:
			new_comp.load_from_dict(comp.save_to_dict())
			new_comp.last_simulated_minute = comp.last_simulated_minute
			clone.add_component(new_comp)
	
	return clone
