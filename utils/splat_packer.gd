## ==============================================================================
## Terrain3D Control Map Generator (Splat Map Packer)
## ==============================================================================
## 
## Description:
## Terrain3D does not accept standard multi-channel splat maps. It requires a 
## highly specific "Control Map" where the top two texture IDs and their blend 
## values are bit-packed into a single 32-bit integer per pixel.
## 
## This script automates that conversion process. It reads 8 separate grayscale 
## weight maps, calculates the top 2 dominant textures for every single pixel, 
## performs the necessary bit-shifting, and saves the result as a raw Godot 
## Resource (.res) to safely bypass Godot's EXR float-corruption bugs.
##
## How to Use:
## 1. Update `DEM_PATH` to point to your main heightmap. The script will use 
##    this to ensure the generated Control Map perfectly matches its resolution.
## 2. Update the `SPLAT_MAPS` dictionary with the paths to your 8 weight maps. 
##    IMPORTANT: The dictionary keys (0-7) MUST match the exact Texture IDs 
##    you have set up in your Terrain3D texture list.
## 3. Open this script in the Godot Script Editor.
## 4. Go to File -> Run (or press Ctrl+Shift+X / Cmd+Shift+X).
## 5. Check the Output console for the "SUCCESS" message.
## 6. Open the Terrain3D Importer, load your heightmap, and set the Control File 
##    to the newly generated `final_terrain_control_map.res`. Click Import!
##
## Note on Formats: 
## We save as `.res` instead of `.exr` because bit-packed integers often 
## evaluate to "NaN" or subnormal floats. Godot's EXR saver tries to "fix" 
## these invalid floats, which scrambles the bits and ruins the map.
## ==============================================================================


@tool
extends EditorScript

# Add the path to your heightmap so we can steal its exact dimensions
const DEM_PATH = "res://Assets/TerrainAssets/Data/dem.png"

const SPLAT_MAPS = {
	0: "res://Assets/TerrainAssets/Data/temp/grass_weight.png",
	1: "res://Assets/TerrainAssets/Data/temp/sand_weight.png",
	2: "res://Assets/TerrainAssets/Data/temp/rock_weight.png",
	3: "res://Assets/TerrainAssets/Data/temp/mud_weight.png",
	4: "res://Assets/TerrainAssets/Data/temp/gravel_weight.png",
	5: "res://Assets/TerrainAssets/Data/temp/forestfloor_weight.png",
	6: "res://Assets/TerrainAssets/Data/temp/concrete_weight.png",
	7: "res://Assets/TerrainAssets/Data/temp/asphalt_weight.png"
}

func _run():
	# 1. Get exact dimensions from the DEM
	var dem_img = Image.load_from_file(DEM_PATH)
	if dem_img == null:
		printerr("Could not load DEM heightmap at: ", DEM_PATH)
		return
		
	var target_size = Vector2i(dem_img.get_width(), dem_img.get_height())
	print("Detected target resolution: ", target_size.x, "x", target_size.y)

	# 2. Load and resize weight maps
	print("Loading 8 splat maps...")
	var images = {}
	for tex_id in SPLAT_MAPS.keys():
		var img = Image.load_from_file(SPLAT_MAPS[tex_id])
		if img:
			# Force the splat maps to perfectly match the DEM size
			if img.get_width() != target_size.x or img.get_height() != target_size.y:
				img.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)
			images[tex_id] = img
		else:
			printerr("Failed to load: ", SPLAT_MAPS[tex_id])

	if images.size() == 0:
		printerr("No weight maps loaded. Aborting script.")
		return

	# FORMAT_RF is strictly required by Terrain3D docs for control maps
	var control_map = Image.create_empty(target_size.x, target_size.y, false, Image.FORMAT_RF)
	
	print("Baking Control Map...")
	for y in range(target_size.y):
		for x in range(target_size.x):
			var weights = []
			
			for tex_id in images.keys():
				weights.append({"id": tex_id, "w": images[tex_id].get_pixel(x, y).r})
			
			weights.sort_custom(func(a, b): return a.w > b.w)
			
			var base_id = weights[0].id
			var over_id = weights[1].id
			var blend_int = 0
			
			var total = weights[0].w + weights[1].w
			if total > 0.0:
				blend_int = int((weights[1].w / total) * 255.0)
			
			# --- EXACT TERRAIN3D DOCS BIT-PACKING ---
			var packed_bits: int = ((base_id & 0x1F) << 27) | \
								   ((over_id & 0x1F) << 22) | \
								   ((blend_int & 0xFF) << 14)
			
			var ba := PackedByteArray()
			ba.resize(4)
			ba.encode_u32(0, packed_bits)
			var float_val: float = ba.decode_float(0)
			
			control_map.set_pixel(x, y, Color(float_val, 0, 0, 1.0))

	# Save raw memory to avoid EXR float corruption
	var output_path = "res://final_terrain_control_map.res"
	var err = ResourceSaver.save(control_map, output_path)
	
	if err == OK:
		print("SUCCESS: saved raw data to ", output_path)
	else:
		printerr("Failed to save resource! Error code: ", err)