## [Registry] The central manifest of all spawnable vehicles.
## This class handles:
## - Looking up [VehicleSpec] data by unique spec_id
## - Filtering vehicles by brand
## - Providing lists for the developer console and spawning menus
extends Resource
class_name VehicleCatalog

@export var specs: Array[VehicleSpec] = []

func get_spec(spec_id: StringName) -> VehicleSpec:
	for spec: VehicleSpec in specs:
		if spec != null and spec.spec_id == spec_id:
			return spec
	return null

func get_specs_by_brand(brand: String) -> Array[VehicleSpec]:
	var normalized := brand.strip_edges().to_lower()
	var result: Array[VehicleSpec] = []
	for spec: VehicleSpec in specs:
		if spec == null:
			continue
		if spec.brand.strip_edges().to_lower() == normalized:
			result.append(spec)
	return result

func get_brand_names() -> Array[String]:
	var map: Dictionary = {}
	for spec: VehicleSpec in specs:
		if spec == null:
			continue
		var brand := spec.brand.strip_edges().to_lower()
		if brand.is_empty():
			continue
		map[brand] = true

	var names: Array[String] = []
	for key_any: Variant in map.keys():
		if key_any is String:
			names.append(key_any)
	names.sort()
	return names

func get_spec_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for spec: VehicleSpec in specs:
		if spec == null:
			continue
		if spec.spec_id != &"":
			ids.append(spec.spec_id)
	return ids
