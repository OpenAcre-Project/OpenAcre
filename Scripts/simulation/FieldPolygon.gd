class_name FieldPolygon
extends RefCounted

var id: StringName = &""
var points: PackedVector2Array = PackedVector2Array()
var bounds: Rect2i

func calculate_bounds() -> void:
	if points.is_empty():
		return
		
	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y
	
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y) # Using Y here since Vector2 is (X, Y) which represents World (X, Z)
		max_y = maxf(max_y, p.y)
		
	bounds = Rect2i(
		floori(min_x), 
		floori(min_y), 
		ceili(max_x) - floori(min_x), 
		ceili(max_y) - floori(min_y)
	)
