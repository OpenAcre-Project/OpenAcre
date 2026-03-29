# UESS Technical Reference
 
## ⚙️ Architectural Implementations & Decisions

This document outlines the concrete architectural decisions made during the rollout of the **Universal Entity Streaming System (UESS)** across its designated blueprint phases.

---

### Static Typing Enforcement (Phase 5)
During the implementation of `EntityView3D.gd` and the View Layer, the codebase encountered parsing errors when attempting to use sibling-to-sibling Godot downcasting (e.g., verifying if the parent `Node3D` was a `RigidBody3D` or `CharacterBody3D`). 
Godot 4's static analyzer rejects invalid typed casts. 

**Decision:** We adopted a bridging `Variant` pattern (`var untyped_self: Variant = self`). This explicitly communicates the dynamic intent to the compiler, bypassing the analyzer's strict hierarchy enforcement for initial detection, while allowing us to continuously enforce strict static typing warnings (`:=`, `Array[Vector2i]`) throughout the remainder of the scripts.

---

### StreamingGroups & Spatial Logic (Phase 6)
Traditional grid chunking fails with connected linkages (like a Tractor pulling a Plow), as the two objects can physically rest across a chunk border, leading to one despawning and snapping the physical `HitchSocket3D` joint.

**Decision:** We implemented `StreamingGroup` logic into `EntityManager.gd`. The `StreamSpooler.gd` was heavily modified to use `_queue_load_with_group` and `_queue_unload_with_group`. The stream spooler prioritizes group integrity over mathematical boundaries: **If any entity that belongs to a group exists within the active radius, the entire physics chain is forced to instantiate and remains loaded.**

This allows seamless edge-crossing for vehicles with implements.

---

### Spatial Hash Authority Fix (Ghost In Old Chunk)
An identified failure path allowed `EntityView3D.extract_data()` to write `TransformComponent.world_position` directly, bypassing `EntityManager` chunk reassignment logic.

Impact:
- Entities could move physically while still indexed in an old chunk.
- Chunk unload would then despawn the wrong entity (including actively driven vehicles).

Decision:
- `EntityView3D.extract_data()` now calls `EntityManager.update_entity_transform(runtime_id, pos, yaw)`.
- `EntityManager` remains the single source of truth for both persisted transform and `chunk_id` ownership.
- `_physics_process` keeps interval throttling but bypasses it for large position deltas to handle teleports safely.

---

### Active Vehicle Plot Armor + Forced Eject Guard
Even with correct chunk math, the active vehicle requires lifecycle protection against edge conditions (teleport jumps, queue ordering, or explicit deletes).

Decision:
- In `StreamSpooler._queue_unload()`, unload is skipped when the candidate entity is either:
	- the active vehicle (`PlayerData.active_vehicle_id`), or
	- any entity sharing that vehicle's `StreamingGroup`.
- In `StreamSpooler._spool_unloads()`, driven `Vehicle3D` instances call `force_eject()` before `queue_free()`.
- `Vehicle3D.force_eject()` executes synchronously in one frame and clears active vehicle ownership from the vehicle/seat path, not from spooler logic.

Result:
- Convoys do not tear apart near stream edges.
- Camera ownership is restored before destruction, preventing grey-screen soft locks.

---

### Tree-Safe Spawn Application (Pre-Parent Regression Fix)
To reduce spawn overhead, `StreamSpooler` introduced an optimization that can call `apply_data()` before `add_child()` when the target parent has identity world transform. A runtime regression surfaced because some initialization paths touched `global_position`/`global_transform` while the node was not yet inside the tree.

Decision:
- `EntityView3D.apply_data()` and related extraction paths now use tree-safe position snapshots, avoiding non-tree global transform reads.
- `Vehicle3D` is explicitly excluded from pre-parent apply optimization; vehicles are always parented first, then `apply_data()` executes.
- `Vehicle3D.reset_physics_state()` now early-outs safely when not inside tree.

Result:
- Eliminates `Condition "!is_inside_tree()"` runtime errors during chunk spawn.
- Preserves optimization for non-vehicle entities where parent-space assumptions are safe.

---

### Data-Driven Instantiation & JSON Modding (Phase 7)
`EntityRegistry` acts as the UESS instantiation brain. Initially stubbed, this factory class now physically pulls definitions off the disk.

**Decision:** We engineered a passive JSON parser that iterates over `res://Data/Entities/` at startup. Modders can build plain `.json` dictionaries mapping `definition_id` to Component arrays and values (such as `transform` and `durability`). The game auto-constructs the data footprint and handles injection autonomously, enabling total Logic-Visual separation without requiring developers to manipulate core Godot GDScript or packed scenes.

---

### Mid-Chunk Spawn Awareness (Blind Spooler Fix)
The `StreamSpooler` originally only queued entities for loading during chunk transitions (unloaded → loaded). Entities spawned directly into already-active chunks (e.g. via the developer console) remained invisible.

**Decision:** `EntityManager` now emits an `entity_registered(entity_id)` signal at the end of `register_entity()`. `StreamSpooler` connects to this signal and checks if the entity's chunk is in `_current_active_chunks`. If yes, it force-queues the load via `_queue_load_with_group()`, respecting streaming group integrity.

---

### Runtime Bootstrap & Post-Registration Refresh
Even with `entity_registered`, startup ordering can still miss loads when the spooler is created after map entities already exist in active chunks.

**Decision:** `MapManager` now enforces runtime bootstrap by creating `WorldEntityContainer` and `StreamSpooler` if missing, priming `update_active_chunks()` from player position, then calling `refresh_from_current_chunks("post_register_vehicles")` after map vehicle registration. This guarantees startup entities are queued even if they were registered before the connection became active.

---

### Definition-First Spawn Ownership (Console)
Raw scene spawning can create visible vehicles that are not owned by UESS, which means StreamSpooler cannot despawn/freeze them.

**Decision:** Developer console spawn flow now resolves aliases to entity definition IDs first (e.g. `truck` -> `vehicle.truck`) and spawns through `EntityRegistry` + `EntityManager`. Direct scene spawning remains available (`spawn_scene`) but is explicitly non-UESS and should be used only for isolated visual debugging.

---

### Engine Loop Driver (StreamSpooler Polling)
Initially, `StreamSpooler.update_active_chunks()` was a public method that nothing called. No chunks ever loaded or unloaded.

**Decision:** `StreamSpooler._process()` now polls `PlayerData.world_position` from the simulation layer every **0.5 seconds** (avoiding per-frame overhead). This reads data directly from `GameManager.session.entities.get_player()` — the pure data layer — rather than querying the SceneTree for a 3D Node, maintaining strict Data-View separation. A lazy-bind pattern in `_process()` handles the case where the session isn't ready during `_ready()`.

---

### Complete Component Library
The initial UESS rollout only included `TransformComponent`, `DurabilityComponent`, and `ContainerComponent`. Entity definitions referencing unknown component types (e.g. `"vehicle"`, `"seat"`) silently returned `null` during `_create_component()`.

**Decision:** Four new components were added: `VehicleComponent` (fuel/engine), `SeatComponent` (occupancy), `ItemComponent` (mass/volume), `StackableComponent` (count/max). All are registered in `EntityRegistry._component_scripts` and follow the same `load_from_dict()` / `save_to_dict()` pattern for serialization readiness.

