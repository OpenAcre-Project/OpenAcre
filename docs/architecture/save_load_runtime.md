# Save/Load Runtime | [Home](../index.md)

This page is the source of truth for OpenAcre save/load behavior.

---

## Save Directory And Slot Layout

Save root is hardcoded in `SaveManager`:

- `user://Saves`

Slot naming:

- `Slot_01`, `Slot_02`, ... (`%02d` formatting)

Per-slot payload:

```text
user://Saves/
  Slot_01/
    metadata.json
    entities.json
    FarmLayers/
      soil_state.png
      crop_type.png
      planted_time.exr
      planted_time.json   # optional fallback when EXR write fails
```

---

## Atomic Save Transaction

Save target uses three directories:

- Live: `Slot_XX`
- Temp: `Slot_XX_TMP`
- Backup: `Slot_XX_BAK`

Flow:

1. Recover interrupted prior save/load state (`_recover_interrupted_slot`).
2. Emit `EventBus.pre_save_flush` so active views call `extract_data()` before serialization.
3. Recreate temp directories and write all payloads to temp only.
4. Atomic promotion:
   1. Move live -> backup.
   2. Move temp -> live.
   3. Delete backup after successful promotion.
5. On promotion failure, attempt rollback backup -> live.

This guarantees no partial-write live slot is ever considered valid.

---

## Interrupted Save Recovery Rules

On every slot access (`save_slot`, `load_slot`, metadata reads), recovery runs first.

Recovery behavior:

- Live exists:
  - delete temp and backup leftovers.
- Live missing + backup and temp exist:
  - treat as interrupted swap; restore backup to live and delete temp.
- Live missing + backup only:
  - restore backup to live.
- Live missing + temp only:
  - promote temp to live (new slot case).

---

## Serialized Data Contracts

`metadata.json` includes:

- save version
- slot id
- unix save timestamp
- map id
- simulation time (`total_minutes`, `day`, `hour`, `minute`)
- player state snapshot (transform, stats, pockets, equipped item)
- crop lookup table (`id -> crop StringName`)

`entities.json` includes:

- all `EntityData` records
- each component payload via `Component.save_to_dict()`
- `__last_simulated_minute` per component
- entity streaming-group assignments

`FarmLayers` image payloads include:

- soil state (L8)
- crop id (L8)
- planted minute (RF EXR, with JSON sparse fallback)

---

## Load Pipeline

Load is async and coordinated with streaming.

1. Recover interrupted slot.
2. Read metadata/entities payloads.
3. Pause tree (`SceneTree.paused = true`).
4. If `StreamSpooler` exists:
   - disable streaming
   - begin physics blackout window (`begin_load_blackout(3)`)
   - flush and clear runtime views (`clear_runtime_view_state(true)`)
5. If no spooler, clear world entity container directly.
6. Await one frame to allow `queue_free()` completion before hydration.
7. Reset runtime dictionaries (`EntityManager`, `FarmData`).
8. Restore time, entities, player, repair orphan links.
9. Import farm layers and rebuild world farm visuals.
10. Teleport player node to restored transform.
11. Re-enable streaming and refresh active chunks.
12. Unpause tree.
13. Finalize blackout and release rigid bodies after settle frames.
14. Emit `EventBus.game_loaded_successfully`.

---

## Physics Blackout Window

`StreamSpooler` load blackout prevents physics explosions and falls during hydration.

- During spawn, rigid bodies are frozen/sleeping and original velocities/sleep states are captured.
- On finalize, spooler waits the configured physics frames, then restores each body.

Default blackout frame count from `SaveManager` is `3`.

---

## Farm Layer Import Rules

`FarmData.import_heatmap_layers(...)` behavior:

- Clears prior farm runtime state.
- Rehydrates tiles from heatmaps.
- Resolves crop id via metadata lookup.
- Applies offline crop catch-up immediately:
  - `HARVESTABLE` if elapsed minutes >= growth requirement.
  - otherwise `SEEDED`.
- Rebuilds simulation chunk indices.

This ensures crop progression stays consistent across long offline gaps.

---

## Visual Rebuild After Load

After farm import:

- `SoilLayerService.rebuild_visuals_from_data()` is invoked if present.
- `GridManager.rebuild_farm_visuals_after_load()` is invoked if present.

This avoids stale crop/soil view state after world hydration.

---

## Orphaned Entity Failsafe

After restoring entities, `SaveManager` repairs invalid parent links:

- If parent id points to missing entity, orphan is detached to world near player.
- If parent indicates player inventory but player pockets do not include that entity, orphan is detached.

This prevents hard-to-debug invisible inventory/world desync.
