## Blender script that projects a mesh's vertices onto a heightmap image, with enhanced error 
# handling and performance optimizations.

import bpy
import bmesh
import mathutils
import time

# ==========================================
# CONFIGURATION
# ==========================================
IMAGE_NAME = "dem.exr"      
MAP_SIZE = 2048.0           
HEIGHT_SCALE = 255.0        
ROAD_OFFSET = 0.15          

def project_mesh_bulletproof():
    start_time = time.time()
    
    obj = bpy.context.active_object
    if not obj or obj.type != 'MESH':
        print("\n[!] FATAL ERROR: No mesh object selected.")
        return

    if IMAGE_NAME not in bpy.data.images:
        print(f"\n[!] FATAL ERROR: Reference image '{IMAGE_NAME}' not loaded.")
        return
    
    img = bpy.data.images[IMAGE_NAME]
    
    # Force raw data
    if img.colorspace_settings.name != 'Non-Color':
        try: img.colorspace_settings.name = 'Non-Color'
        except: pass

    width, height = img.size
    pixels = list(img.pixels) 
    
    print(f"\n==================================================")
    print(f"  INITIATING BMESH TERRAIN PROJECTION")
    print(f"==================================================")
    print(f"[*] Target Mesh:   {obj.name}")
    print(f"[*] Processing...")

    stats = {
        'max_up_shift': 0.0, 'max_down_shift': 0.0, 'total_absolute_shift': 0.0,
        'z_original_min': float('inf'), 'z_original_max': float('-inf'),
        'z_new_min': float('inf'), 'z_new_max': float('-inf'), 'modified_count': 0
    }

    if bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')

    # Initialize Engine-Level BMesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    
    matrix_world = obj.matrix_world.copy()
    matrix_world_inv = matrix_world.inverted()

    for v in bm.verts:
        world_coord = matrix_world @ v.co
        x = world_coord.x
        y = world_coord.y
        original_z = world_coord.z
        
        if original_z < stats['z_original_min']: stats['z_original_min'] = original_z
        if original_z > stats['z_original_max']: stats['z_original_max'] = original_z

        u = max(0.0, min(1.0, (x / MAP_SIZE) + 0.5))
        v_coord = max(0.0, min(1.0, (y / MAP_SIZE) + 0.5))
        
        pixel_x = int(u * (width - 1))
        pixel_y = int(v_coord * (height - 1))
        pixel_index = (pixel_y * width + pixel_x) * 4
        
        try: height_value = pixels[pixel_index] 
        except IndexError: height_value = 0.0
            
        target_z = (height_value * HEIGHT_SCALE) + ROAD_OFFSET
        delta_z = target_z - original_z
        
        if delta_z > stats['max_up_shift']: stats['max_up_shift'] = delta_z
        if delta_z < stats['max_down_shift']: stats['max_down_shift'] = delta_z
        stats['total_absolute_shift'] += abs(delta_z)
        
        if target_z < stats['z_new_min']: stats['z_new_min'] = target_z
        if target_z > stats['z_new_max']: stats['z_new_max'] = target_z
        stats['modified_count'] += 1

        # THE CRITICAL FIX: Overwrite the entire 3D vector, not just Z
        new_world_coord = mathutils.Vector((x, y, target_z))
        v.co = matrix_world_inv @ new_world_coord

    # Hard overwrite the geometry data
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    
    elapsed_time = time.time() - start_time
    vert_count = len(obj.data.vertices)
    avg_shift = stats['total_absolute_shift'] / vert_count if vert_count > 0 else 0

    print(f"\n==================================================")
    print(f"  PROJECTION COMPLETE - DIAGNOSTIC REPORT")
    print(f"==================================================")
    print(f"Execution Time:     {elapsed_time:.3f} seconds")
    print(f"Average Shift:      ±{avg_shift:.3f} meters")
    print(f"Original Z Range:   {stats['z_original_min']:.3f}m  to  {stats['z_original_max']:.3f}m")
    print(f"New Z Range:        {stats['z_new_min']:.3f}m  to  {stats['z_new_max']:.3f}m")
    print(f"==================================================\n")

project_mesh_bulletproof()