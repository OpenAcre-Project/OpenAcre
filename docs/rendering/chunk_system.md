# :triangular_ruler: Chunk & Catch-Up System | [Home](../index.md)

The project uses separate systems for simulation chunks, visual streaming, and Terrain3D collision. Fall-through prevention depends on all three being aligned.

---

## Runtime Sources Of Truth

Primary runtime files:

- `Scripts/streaming/StreamSpooler.gd`: UESS visual load/unload logic and Terrain3D collision coupling.
- `Scripts/streaming/GridManager.gd`: chunk math for active-chunk sets and deltas.
- `Scripts/farm/GridManager.gd`: map simulation chunk streaming (`streamed_chunk_radius`).
- `Scripts/core/MapManager.gd`: runtime bootstrap for `WorldEntityContainer` and `StreamSpooler`.

---

## What Controls Fall-Through Distance

Three bounds matter:

1. Simulation chunk radius (`Scripts/farm/GridManager.gd`) controls farm/chunk simulation loading.
2. Terrain3D collision radius (`Terrain3D.collision_radius`) controls where wheel/ground physics exists.
3. StreamSpooler load/unload radii control when UESS views are instantiated/despawned.

`StreamSpooler` couples #2 and #3 so unload happens before collision disappears.

---

## StreamSpooler Coupling Formula

When `auto_configure_radii_from_chunks = true`:

```gdscript
chunk_radius = GridManager(stream target).get_stream_radius()
chunk_size_meters = GameManager.session.farm.simulation_chunk_size_tiles
chunk_collision_edge = (chunk_radius + 0.5) * chunk_size_meters

if auto_sync_terrain_collision_radius_from_chunks:
    terrain.collision_radius = max(min_terrain_collision_radius_meters,
                                   round(chunk_collision_edge + terrain_collision_padding_meters))

effective_collision_edge = min(chunk_collision_edge, terrain.collision_radius)
unload_radius = max(min_auto_unload_radius_meters,
                    effective_collision_edge - collision_edge_margin_meters)
load_radius = max(min_auto_load_radius_meters,
                  unload_radius - stream_hysteresis_meters)
```

This keeps despawn/freeze bounded by available terrain collision.

---

## Critical Startup Sequence

`MapManager.populate_world()` enforces this order:

1. Spawn player and publish player transform to `GameManager.session.entities`.
2. Ensure `WorldEntityContainer` exists.
3. Ensure `StreamSpooler` node exists and prime it with current player position.
4. Register map vehicles into `EntityManager`.
5. Force `StreamSpooler.refresh_from_current_chunks("post_register_vehicles")`.

This prevents startup race conditions where entities exist in data but were never queued for visual load.

---

## UESS Ownership Rule

Despawn only applies to UESS-owned views.

- Correct path: spawn/register entities through `EntityRegistry` + `EntityManager`.
- Incorrect path: instantiate raw vehicle scenes directly in the scene tree for gameplay entities.

Scene-spawned vehicles bypass StreamSpooler ownership and therefore bypass UESS despawn guarantees.

---

## Streaming Groups Behavior

Group integrity is preserved during distance gating:

- Load a group if any member is inside load radius.
- Unload a group only if all members are outside unload radius.
- If the player is actively driving a vehicle, unload is blocked for that vehicle and all members of its streaming group.

This prevents hitch-chain breakage at chunk/collision boundaries.

---

## Active Vehicle Safety Rules

To prevent camera-loss soft locks and stale-chunk despawns, runtime now enforces:

1. `EntityView3D.extract_data()` writes transforms through `EntityManager.update_entity_transform(...)`.
2. Large movement deltas bypass sync throttle to force immediate chunk reassignment.
3. During unload execution, a driven `Vehicle3D` is force-ejected synchronously before `queue_free()`.
4. Spawn application is tree-safe: generic entities may pre-apply data before parenting only under identity parent transforms, while `Vehicle3D` always applies data after parenting.

These rules protect both spatial indexing and player control continuity during aggressive streaming churn.

---

## Tuning Guidance

Increase safe far distance:

1. Increase `streamed_chunk_radius` in `Scripts/farm/GridManager.gd`.
2. Keep `auto_sync_terrain_collision_radius_from_chunks = true` in `StreamSpooler`.
3. Increase `terrain_collision_padding_meters` slightly for faster vehicles.
4. Keep `collision_edge_margin_meters` high enough that unload happens before collision cutoff.

Reduce cost:

1. Decrease `streamed_chunk_radius`.
2. Decrease `terrain_collision_padding_meters`.
3. Keep `stream_hysteresis_meters` large enough to avoid churn near edges.

Manual mode (`auto_configure_radii_from_chunks = false`):

- Ensure `load_radius < unload_radius`.
- Ensure `unload_radius` remains inside Terrain3D collision coverage.

---

## Troubleshooting

### Vehicles never despawn

Check:

1. Vehicle was created as UESS entity (not direct scene spawn).
2. `StreamSpooler` exists at runtime.
3. `WorldEntityContainer` exists at runtime.
4. `entity_registered` connection is active in `StreamSpooler`.

### Active driven vehicle despawns or camera is lost

Check:

1. `PlayerData.active_vehicle_id` is set while seated.
2. Active vehicle and implement share the same `StreamingGroup` when attached.
3. `EntityView3D.extract_data()` routes through `EntityManager.update_entity_transform(...)`.
4. `Vehicle3D.force_eject()` is called before destruction in spooler unload path.

### `!is_inside_tree()` errors during spawn

Check:

1. `EntityView3D.apply_data()` does not read `global_position`/`global_transform` while node is outside tree.
2. `Vehicle3D` follows parent-first spawn (`add_child` before `apply_data`).
3. `Vehicle3D.reset_physics_state()` guards non-tree usage.

### Changing chunk radius has little effect

Check:

1. `auto_sync_terrain_collision_radius_from_chunks` is enabled.
2. Terrain3D collision mode is enabled (dynamic/full game mode).
3. Active camera is correctly bound to Terrain3D.

---

## Catch-Up Reminder

Unloaded entities remain in data and continue logically via catch-up processing when they return to active visual range.

---

## Save/Load Coupling

Streaming and persistence are explicitly coupled through `EventBus` + `SaveManager`:

1. `SaveManager.save_slot()` emits `pre_save_flush`.
2. `StreamSpooler._on_pre_save_flush()` runs `flush_active_views_to_data()` so serialized components include latest runtime transforms/state.
3. During load, `SaveManager` temporarily disables streaming, clears runtime views, and starts a blackout window.
4. After data hydration and chunk refresh, blackout is released after settle frames.

This coupling is required to avoid stale pre-save transforms and to prevent load-frame physics instability.

For full load contract details, see [Save/Load Runtime](../architecture/save_load_runtime.md).
