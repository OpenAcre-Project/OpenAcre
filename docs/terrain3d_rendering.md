# Terrain3D Rendering

The application leverages the Terrain3D plugin to manage highly optimized heightmaps and material textures natively within the 3D space. The system handles map collisions, camera alignments, and live texture rendering (e.g., painting soil paths).

## Live Texture Rendering

The live texture system operates by transforming rigid simulation data from `FarmData` into localized GPU pixel textures. The principal actor in this flow is `SoilLayerService.gd`.

### Translation Pipeline

1. **Tool Usage:** Ploughs (`PlowAttachment`) interact with the ground through `RayCast`. This flags the coordinate in `FarmData` as `PLOWED` or `SEEDED`.
2. **Signal Dispatch:** When a tile is logically altered, `FarmData` emits the `"tile_updated"` signal containing the new integer `grid_pos` and `new_state`.
3. **Terrain Execution:** `SoilLayerService.gd` observes the signal and intercepts it to paint directly to the Terrain3D control/color maps over a given pixel radius (using `_modify_single_pixel`).
   - `FarmData.SoilState.PLOWED` -> Terrain Map Overlay `dirt_texture_index` (typically 3), Blend: `255`.
   - `FarmData.SoilState.GRASS` -> Terrain Map Overlay `grass_texture_index` (typically 0), Blend: `0`.

### Map Storage Binding

To paint control bits across a procedural vertex scale safely, `MapDefinition.gd` locates the `Terrain3D` node recursively and assigns it to the `terrain_node` group upon scene load.

Once grouped, `SoilLayerService` invokes `_terrain.get_data()` or `_terrain.get_storage()` (dependent on plugin version) and accesses the map arrays via:
- `set_control_overlay_id`
- `set_control_blend`
- Finally, invoking `update_maps(1)` to upload modified control mappings to the shader pipeline efficiently.

### Rebuilding Visuals

When a player enters a region dynamically, or loads a save game, chunk data must be visualized instantly. `SoilLayerService.rebuild_visuals_from_data()` iterates existing logic definitions and reapplies the control maps iteratively, restoring the player's previously modified landscape identically.
