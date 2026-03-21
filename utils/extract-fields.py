import xml.etree.ElementTree as ET
import json
import matplotlib.pyplot as plt


I3D_FILE = "mapUS.i3d"
OUTPUT_FILE = "fields_data.json"

def plot_fields_2d(fields_data):
    print("Generating 2D plot...")
    plt.figure(figsize=(10, 10))
    
    for field_name, points in fields_data.items():
        if not points:
            continue
            
        # Extract X and Z coordinates (Y is elevation, ignore for top-down)
        xs = [p["x"] for p in points]
        zs = [p["z"] for p in points]
        
        # Append the first point to the end to close the polygon visually
        xs.append(xs[0])
        zs.append(zs[0])
        
        # Plot the lines and add a label at the starting point
        plt.plot(xs, zs, marker='o', markersize=2, label=field_name)
        plt.text(xs[0], zs[0], field_name, fontsize=8)

    plt.xlabel("X Coordinate")
    plt.ylabel("Z Coordinate")
    plt.title("GIANTS Fields Top-Down View (X vs Z)")
    
    # Crucial: This ensures 1 unit X visually equals 1 unit Z, preventing stretching
    plt.axis('equal') 
    
    # Optional: If the plot looks upside down compared to GIANTS, uncomment this:
    # plt.gca().invert_yaxis() 
    
    plt.show()

def extract_fields():
    print(f"Parsing {I3D_FILE}...")
    try:
        tree = ET.parse(I3D_FILE)
        root = tree.getroot()
    except Exception as e:
        print(f"Failed to load {I3D_FILE}: {e}")
        return

    fields_data = {}

    # Find the 'Scene' node first
    scene = root.find('Scene')
    if scene is None:
        print("Could not find <Scene> node in i3d.")
        return

    # Helper function to recursively find a TransformGroup by name
    def find_node_by_name(parent, name):
        for child in parent.findall('TransformGroup'):
            if child.get('name') == name:
                return child
            # Recursive search
            result = find_node_by_name(child, name)
            if result is not None:
                return result
        return None

    # Find the main 'fields' group
    fields_group = find_node_by_name(scene, "fields")
    if fields_group is None:
        print("Could not find the 'fields' TransformGroup.")
        return

    # Iterate through field1, field2, etc.
    # Iterate through field1, field2, etc.
    for field in fields_group.findall('TransformGroup'):
        field_name = field.get('name')
        if not field_name.startswith("field"):
            continue

        # --- NEW: Extract the field's base translation (centroid) ---
        base_translation = field.get('translation')
        if base_translation:
            base_x, base_y, base_z = map(float, base_translation.split())
        else:
            base_x, base_y, base_z = 0.0, 0.0, 0.0

        polygon_points_group = find_node_by_name(field, "polygonPoints")
        if polygon_points_group is None:
            continue

        # Extract the translations for each point
        points = []
        for point in polygon_points_group.findall('TransformGroup'):
            local_translation = point.get('translation')
            if local_translation:
                local_x, local_y, local_z = map(float, local_translation.split())
                
                # --- NEW: Add base translation to local translation for World Coordinates ---
                world_x = base_x + local_x
                world_y = base_y + local_y
                world_z = base_z + local_z
                
                points.append({"x": world_x, "y": world_y, "z": world_z})

        if points:
            fields_data[field_name] = points
            print(f"Extracted {len(points)} world points for {field_name}")

    # Save to JSON
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(fields_data, f, indent=4)
    
    print(f"\nSuccessfully extracted data to {OUTPUT_FILE}")

    plot_fields_2d(fields_data)

if __name__ == "__main__":
    extract_fields()