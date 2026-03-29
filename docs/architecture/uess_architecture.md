# Universal Entity Streaming System (UESS)

The **Universal Entity Streaming System (UESS)** enforces a strict separation of **Data (The Truth)** and **View (The Illusion)**. Powered by an ECS-lite architecture and a Catch-Up Simulation Engine, it ensures that if an entity is not near the player, it exists only as lightweight math, consuming 0% GPU and 0% physics CPU overhead.

---

## :building_construction: Architectural Philosophy
**The Problem:** Traditional OOP design relying on 3D Nodes collapses under the weight of thousands of objects (crops, dropped apples, tractors).
**The Solution:**
1. **Mathematical Reality:** Unloaded entities are just dictionaries in memory.
2. **Lazy Evaluation:** Time-based mechanics are processed instantly when a player approaches (Catch-Up Math).
3. **Data-Driven:** All entities are built via JSON definitions combining pure data Components.
4. **Time-Sliced Streaming:** Instantiations are throttled across frames to prevent stutters.

---

## :open_file_folder: Implementation Structure

### 1. The Core Data Layer (`Scripts/simulation/`)
Pure data structures representing entity states. Never reference `Node3D` or visual objects here.

#### Components (`Scripts/simulation/components/`)
*   **`Component.gd`**: Base class. Holds `type_id` and `last_simulated_minute` for catch-up math.
*   **`TransformComponent`**: World position, rotation, and current `chunk_id`.
*   **`DurabilityComponent`**: Health, rot accumulation, and decay rate.
*   **`ContainerComponent`**: Inventory capacity (`max_weight_kg`, `max_slots`).
*   **`VehicleComponent`**: Fuel level, max fuel, engine temperature, burn rate.
*   **`SeatComponent`**: Marks entity as enterable, tracks occupant.
*   **`ItemComponent`**: Physical properties for pickup-able items (mass, volume, display name).
*   **`StackableComponent`**: Item stacking (`count`, `max_stack`).

#### Core (`Scripts/simulation/core/`)
*   **`EntityData.gd`**: Master data object. Holds `runtime_id`, `definition_id`, `parent_id`, and a dictionary of active Components.

### 2. The Systems & Streaming (`Scripts/simulation/` & `Scripts/streaming/`)
*   **`EntityManager.gd`**: Central brain. Maintains `_entities` pool, $O(1)$ spatial hashing via `_chunks`, parent/child hierarchy, and `StreamingGroup` management. Emits `entity_registered` signal for reactive spawning.
*   **`GridManager.gd`**: Static math library for converting 3D positions into `Vector2i` chunk coordinates and computing chunk deltas.
*   **`CatchUpEngine.gd`**: Processes elapsed time when entities wake up. Can mutate entity definitions (e.g. decayed apple → rot pile).
*   **`StreamSpooler.gd`**: Time-sliced queue processor. Manages load/unload queues with microsecond budgets (1.5ms load, 0.5ms unload). Polls player position from `PlayerData` to drive chunk evaluation. Listens to `entity_registered` for mid-chunk spawn awareness, and supports a forced active-chunk refresh pass to avoid startup misses.

### 3. The View Layer (`Scripts/views/` & `Scripts/vehicles/`)
*   **`EntityView3D.gd`**: Base class for all spawned 3D representations. Provides `apply_data()` / `extract_data()` hooks and continuous physics sync in `_physics_process`.
*   **`Vehicle3D.gd`**: Overrides `apply_data()` / `extract_data()` to sync `VehicleComponent` fuel/engine state.
*   **`Implement3D.gd`**: Extends `EntityView3D` for towable attachments.
*   **`InteractableItem3D.gd`**: Extends `EntityView3D` for world items.

View sync contract:
- `EntityView3D.extract_data()` writes transforms through `EntityManager.update_entity_transform(...)`, never by mutating `TransformComponent` directly.
- `_physics_process` retains throttled sync but forces immediate sync for large movement deltas (teleport/warp safety).

### 4. Registries (`Scripts/core/`)
*   **`EntityRegistry.gd` (Autoload)**: Factory singleton that parses JSON definitions from `Data/Entities/` and constructs `EntityData` objects. Maps component type strings to scripts.

---

## :rocket: Implementation Roadmap

### :white_check_mark: Phase 1: Component-Based Data Foundation
- [x] Create pure data Components (Transform, Durability, Container, Vehicle, Seat, Item, Stackable).
- [x] Create `EntityData` wrapper with parent/child hierarchy.
- [x] Build `EntityRegistry` factory with JSON parsing.

### :white_check_mark: Phase 2: Spatial Partitioning (The Grid)
- [x] Implement $O(1)$ chunk dictionary inside `EntityManager`.
- [x] Automate chunk transitions when entities move.
- [x] Implement `GridManager` for calculating render distances and deltas.

### :white_check_mark: Phase 3: The Catch-Up Simulation Engine
- [x] Add `last_simulated_minute` timestamp tracking across all components.
- [x] Build `CatchUpEngine` to process elapsed `delta_minutes` when entities wake up.
- [x] Add state mutation triggers (e.g. decayed Apple swaps definition ID to Rot Pile).

### :white_check_mark: Phase 4: Time-Sliced Streaming
- [x] Create `StreamSpooler` with Pending Load/Unload queues.
- [x] Implement microsecond-budgeted instantiations per frame.
- [x] Establish the freeze/despool handshake (`extract_data()` → `queue_free()`).
- [x] Add `entity_registered` signal for mid-chunk spawn awareness.
- [x] Drive chunk evaluation via `PlayerData` polling (default 0.5s interval, 2-chunk radius).
- [x] Add startup bootstrap + refresh flow so pre-existing active-chunk entities are queued (`MapManager` -> `StreamSpooler.refresh_from_current_chunks`).

### :white_check_mark: Phase 5: The View Layer & Universal Sync
- [x] Create `EntityView3D` base class with `apply_data()` / `extract_data()`.
- [x] Implement continuous transform sync in `_physics_process` (movement threshold optimization).
- [x] Wire `Vehicle3D` to read/write `VehicleComponent` data via overrides.
- [x] Allow components to drive physics (mass from `ContainerComponent`).
- [x] Universal interaction prompts via `PlayerInteractionController` querying components.
- [x] Enforce manager-authoritative transform persistence (`EntityManager.update_entity_transform`) to keep chunk hashes correct.
- [x] Add large-delta immediate sync path to prevent stale-chunk teleports.

### :white_check_mark: Phase 6: Complex Linkages (Streaming Groups)
- [x] Implement `StreamingGroup` IDs in `EntityManager` to prevent half-loading attached vehicles.
- [x] Override chunk logic: if any group member is in an active chunk, the entire group loads.
- [x] Integrate group dissolution upon physical detachment (`HitchSocket3D`).
- [x] Add active-player convoy immunity: unload queue skips entities sharing the active vehicle's `StreamingGroup`.
- [x] Add driven-vehicle unload guard: force eject synchronously before queue-free to preserve camera/control continuity.

### :hourglass_flowing_sand: Phase 7: Save/Load Serialization (Planned)
- [ ] Serialize `EntityManager._entities` via `save_to_dict()` on every component.
- [ ] Write JSON to `user://savegame.json` including global time.
- [ ] Reconstruct `EntityData` objects on load, preserving `runtime_id`.
