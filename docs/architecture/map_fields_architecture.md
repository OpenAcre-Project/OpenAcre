# :world_map: Map Fields Architecture | [Home](../index.md)

OpenAcre supports a modular map architecture where each map can define its own plowing fields via a data-driven approach. This keeps the engine robust and completely generic to map variations.

---

## 1. Map Definitions & Field Coordinates

!!! abstract "The Map Anchor"
    Each map (e.g., `WorldMap.tscn`) defines a `MapDefinition.gd` root component. This component serves as the anchor for world-specific payload data.

- **`field_data_json`**: The relative path to a JSON file containing the polygon coordinates.
- **`field_data_offset`**: Allows shifting the imported polygon coordinates universally (e.g., `Vector2(1024, 1024)`), reconciling external origin coordinate systems with Godot's `Terrain3D` positive integer grids.

### :json: JSON Field Format
Maps parse raw polygon vertices mapped in 3D, but only extract the `X` and `Z` bounds. The `Y` height dimension is stripped entirely. 

!!! info "Height Independence"
    In a farming game, players can often terraform and level ground dynamically. Dropping the predefined `Y` preserves dynamic rendering offsets over dynamically shaped ground.

```json
{
    "field_1": [
        {"x": -31.87, "y": -1.34, "z": 40.44},
        {"x": 30.26,  "y": -3.06, "z": 40.40},
        // ...
    ]
}
```

---

## 2. In-Memory Mathematical Execution

The JSON boundaries are converted into lightweight `FieldPolygon` `RefCounted` objects to be queried securely without recalculation.
During JSON interpretation:
1. `x` and `z` values are extracted and offset using the map's `field_data_offset`.
2. A Bounding Box (`Rect2i`) is instantly pre-calculated utilizing `floori()` and `ceili()` parameters to conservatively encapsulate maximum exterior float bounds safely.

!!! success "Optimization"
    When fields are initialized, the engine relies on the pre-calculated bounding rects to prevent a brute-force traversal over all 4,000,000 map tiles.

---

## 3. Batch Rendering Optimization (Signal Suppression)

### :sound: The "Signal Storm" Check
Updating thousands of initial tiles into the `FarmData` logic grid forces `tile_updated` signals natively. This induction induces critical startup latency or Out-Of-Memory exceptions.

### :loop: Suppression and Batch Rendering Pipeline

!!! warning "Avoid Individual GPU Calls"
    OpenAcre implements a Batch Rendering Pipeline to solve the signal storm constraint.

1. **Signal Suppression**: coordinates changes via `set_tile_state(..., emit_signal=false)`.
2. **Visual Rebuild Mode**: `MapManager` instructs `SoilLayerService` to redraw the map identically using `rebuild_visuals_from_data()`.
3. **The `_batch_painting` Flag**: An active batch flag is toggled on `SoilLayerService`. It suppresses `Terrain3D` engine API rendering executions locally at the individual pixel modification stages.
4. **Final Single Batch Update**: Once the localized logic loop finishes, the script releases `_batch_painting` and executes exactly **one** master `update_maps(1)` payload to rewrite the GPU control map.
