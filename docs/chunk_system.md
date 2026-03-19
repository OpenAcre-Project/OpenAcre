# Chunk & Catch-Up System

The game handles persistence and memory footprint through chunks. However, there is a strict separation between rendering chunks and logical simulation.

## Rendering vs. Simulation

The chunk streaming system in `GridManager.gd` is an optimization designed purely for **3D rendering**. It limits the spawned environment meshes, farm-tile decals (such as plowed soil), and crop nodes to an active radius around the player.

### What it DOES do:
- Manages visibility of soil terrain layers and meshes around the focal point (the player or a specified camera target).
- Instructs `FarmData.mark_chunk_loaded(chunk)` and `mark_chunk_unloaded(chunk)` to trigger visual generation sequences.
- Draws debugging grid overlays (`FarmableGridOverlay`, `ChunkGridOverlay`) to map boundaries visually in 3D space.

### What it DOES NOT do:
- **It does not prevent simulation.** `FarmData` simulates all actively growing regions or seeded logic regardless of visual load state.
- **It does not control entities.** Player or vehicle transforms, physics behaviors, and collisions are managed entirely separately (e.g., through `SimulationCore` and GEVP).
- **It does not govern game state over time.**

*Consequence:* If `GridManager.gd` is removed entirely, crops continue to grow and AI logic persists—you just won't dynamically cull their visual meshes across the map.

## Chunk Catch-Up Rules

When a chunk goes "offline" visually, we skip instantiating physical nodes for it. When it returns, we "catch up" visually to match the continuous headless simulation:

- Unloaded chunks are registered via `FarmData.mark_chunk_unloaded(chunk)`.
- Reloaded chunks call `FarmData.mark_chunk_loaded(chunk)`, which forces deterministic data catch-up using absolute timestamps computed against `TimeManager`.
- The system resolves missing time in bulk block operations rather than looping minute-by-minute calculations, saving heavy frame overhead.
