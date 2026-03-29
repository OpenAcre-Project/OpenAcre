# :mountain: Terrain3D Rendering | [Home](../index.md)

The application leverages the **Terrain3D** plugin to manage highly optimized heightmaps and material textures natively within the 3D space. 

---

## 🏗️ Terrain Management

!!! abstract "Collision & Alignment"
    The system handles map collisions, camera alignments, and live texture rendering (e.g., painting soil paths) through the Terrain3D engine integrations.

- **Heightmaps**: Optimized for large-scale maps.
- **Material Textures**: Supports multi-layer painting for diverse environments.

---

## :shield: Terrain Collision Runtime Controls

Terrain3D collision has its own runtime controls and is **independent** from farm chunk streaming unless explicitly synchronized.

Key Terrain3D properties:

| Property | Meaning |
| --- | --- |
| `collision_mode` | Collision generation mode (`DYNAMIC_GAME`, `DYNAMIC_EDITOR`, `FULL_GAME`, etc.). |
| `collision_radius` | In Dynamic modes, collision is generated around the active camera within this radius (meters). |
| `collision_shape_size` | Tile size of generated dynamic collision shapes. |

!!! warning "Common Misconfiguration"
    Raising `GridManager.streamed_chunk_radius` alone does not increase Terrain3D collision range by itself. Terrain3D uses `collision_radius` for physics availability.

---

## :camera: Active Camera Binding (Player vs Vehicle)

Dynamic Terrain3D collision follows the camera set by `Terrain3D.set_camera(...)`.

Project behavior:

- Player startup binds Terrain3D to player camera.
- Vehicle seat transitions now rebind Terrain3D camera on enter/exit so collision follows the active viewpoint.

This avoids mismatches where visual camera and collision center diverge during vehicle driving.

---

## :link: Integration With UESS Streaming

Vehicle safety near world edges is coordinated in `Scripts/streaming/StreamSpooler.gd`:

- Optional sync from chunk radius to `Terrain3D.collision_radius`.
- Entity load/unload radii derived from effective collision edge.
- Safety freeze before despawn to avoid falling while waiting for spool budget.

Runtime bootstrap is enforced by `Scripts/core/MapManager.gd`, which ensures:

- `WorldEntityContainer` exists.
- `StreamSpooler` exists and is primed from player position.
- A post-registration refresh pass queues startup entities in active chunks.

For tuning details, see [Chunk & Catch-Up System](chunk_system.md).

---

## :art: Live Texture Painting

!!! gear "SoilLayerService.gd"
    A specialized service that interacts with the Terrain3D Storage to update the control map (the "painting" layer) in real-time.

- **Plowed Fields**: When a field is plowed, the system paints a specific texture index into the storage.
- **Decoupled Logic**: The painting indices are mapped to the simulation grid logic coordinates.

!!! success "Performance Tip"
    The system uses batching to prevent individual pixel updates from overwhelming the GPU during large-scale field generation.
