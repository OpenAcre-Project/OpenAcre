extends Resource
class_name MapRegionMask

enum RegionType {
	UNPLOWABLE = 0,
	FARMABLE = 1
}

@export var mask_texture: Texture2D
@export var world_size_meters: float = 2048.0 # E.g., Elmcreek is 2km x 2km
@export var world_center_position: Vector2 = Vector2(1024, 1024) # Set to (1024,1024) to match the +1024 shifted roads in WorldMap.tscn

# We expose this so you can define exactly which IDs are farmable in the inspector
@export var plowable_ids: Array[int] = [0] 

var _raw_bytes: PackedByteArray
var _width: int = 0
var _height: int = 0
var _is_ready: bool = false

func initialize() -> void:
	if mask_texture == null:
		GameLog.error("MapRegionMask has no texture assigned!")
		return
		
	var image: Image = mask_texture.get_image()
	
	# FOOLPROOFING: Force the image into an 8-bit Grayscale format (1 byte per pixel).
	# This strips away Alpha channels and RGB bloat, making our math 100% safe.
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
		
	_raw_bytes = image.get_data()
	_width = image.get_width()
	_height = image.get_height()
	_is_ready = true
	GameLog.info("Region mask initialized in memory (FORMAT_L8).")

func get_raw_pixel_value(world_pos: Vector3) -> int:
	if not _is_ready:
		GameLog.error("[MapRegionMask] Not ready (Texture missing or failed to initialize).")
		return -1

	# 1. Normalize world coordinates. 
	# Example: If center is 0,0 and map is 2048, left edge is -1024.
	# percent = (x - center.x + half_size) / size -> (-1024 - 0 + 1024) / 2048 = 0.0
	var half_size := world_size_meters * 0.5
	var percent_x: float = (world_pos.x - world_center_position.x + half_size) / world_size_meters
	var percent_y: float = (world_pos.z - world_center_position.y + half_size) / world_size_meters
	
	# 2. Convert percentages to exact Image pixel coordinates
	var pixel_x: int = int(percent_x * float(_width))
	var pixel_y: int = int(percent_y * float(_height))

	# 3. Safety Check: Did the tractor drive off the edge of the world?
	if pixel_x < 0 or pixel_x >= _width or pixel_y < 0 or pixel_y >= _height:
		GameLog.warn("[MapRegionMask] Out of bounds check: world(%.1f, %.1f) -> pixel(%d, %d) limits(%d, %d)" % [world_pos.x, world_pos.z, pixel_x, pixel_y, _width, _height])
		return -1

	# 4. Ultra-fast 1D Array memory lookup
	var index: int = (pixel_y * _width) + pixel_x
	return _raw_bytes[index]

func get_region_at(world_pos: Vector3) -> int:
	var pixel_value := get_raw_pixel_value(world_pos)

	if pixel_value == -1:
		return RegionType.UNPLOWABLE

	if pixel_value in plowable_ids:
		return RegionType.FARMABLE
		
	return RegionType.UNPLOWABLE
