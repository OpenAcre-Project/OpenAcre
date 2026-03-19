extends RefCounted
class_name FarmTileData

var state: int = FarmData.SoilState.GRASS
var moisture: float = 50.0
var nutrients: float = 50.0
var height: float = 0.0
var crop_type: StringName = &""
var planted_at_minute: int = -1
var growth_minutes_required: int = 0

func duplicate_data() -> FarmTileData:
	var copy := FarmTileData.new()
	copy.state = state
	copy.moisture = moisture
	copy.nutrients = nutrients
	copy.height = height
	copy.crop_type = crop_type
	copy.planted_at_minute = planted_at_minute
	copy.growth_minutes_required = growth_minutes_required
	return copy

func has_active_crop() -> bool:
	return crop_type != &"" and planted_at_minute >= 0 and growth_minutes_required > 0

func clear_crop_data() -> void:
	crop_type = &""
	planted_at_minute = -1
	growth_minutes_required = 0
