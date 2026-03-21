# :grid: Chunk & Catch-Up System | [Home](../index.md)

The game handles persistence and memory footprint through chunks. However, there is a strict separation between rendering chunks and logical simulation.

---

## 📦 Visual Chunks

!!! abstract "World Streaming"
    Visual chunks are the units of the physical 3D world that are streamed in and out based on player proximity.

- **Active Radius**: Only chunks within a specific radius of the player are physically instantiated.
- **`VehicleManager`**: Responsible for spawning/despawning vehicles as they cross chunk boundaries.

---

## 🔄 Catch-Up Logic

!!! success "Simulation Persistence"
    When a chunk is unloaded, its logical state continues to exist in the **Logic Phase**.

- **Time-Stamping**: When a player re-enters a long-unseen chunk, the system calculates the time delta and "catches up" the simulation state (e.g., crop growth or fuel consumption).
- **Efficiency**: Only active chunks process every-frame updates, while unloaded chunks wait for the next "Catch-Up" event.

!!! warning "Logical Continuity"
    The catch-up system ensures that the simulation remains logically consistent even if the physical representation was missing for hours.
