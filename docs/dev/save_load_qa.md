# Save/Load QA Protocol | [Home](../index.md)

This checklist validates persistence integrity, load safety, and post-load visual/simulation coherence.

---

## Prerequisites

Use an existing gameplay scene with:

- player movement active
- at least one vehicle entity
- some plowed/seeded farm tiles

Console helpers:

- `save [slot]`
- `load [slot]`
- `saves [max_slots]`
- `time now`
- `ff <value>[m|h|d]`

---

## 1. Slot Metadata Sanity

1. Open pause menu with `Esc`.
2. Save to slot `1`.
3. Change time and player position.
4. Save to slot `2`.
5. Run `saves 8`.

Expected:

- both slots listed
- timestamps differ
- map/day/hour/minute fields match in-game state at save time

---

## 2. Atomicity Under Repeated Writes

1. In same slot, run save repeatedly while moving/turning.
2. Immediately load the same slot after each save.

Expected:

- no partial-slot failure
- no malformed metadata/entities parse errors
- slot remains loadable every cycle

---

## 3. Load Blackout Stability

1. Stand near active physics entities (vehicle + attached implement if available).
2. Load a slot repeatedly.

Expected:

- no body explosions at load frame
- no objects tunneling through terrain after load
- no immediate violent velocity spikes

---

## 4. Deferred Wipe Safety

1. Save with many active streamed views nearby.
2. Load immediately.

Expected:

- no duplicate-name/node-collision errors
- no residual stale views from pre-load world
- entities appear once after spool refresh

---

## 5. Crop Offline Catch-Up

1. Seed crops and save.
2. Fast-forward significant time (`ff 1d`, `ff 2d`, etc.) and save another slot.
3. Load earlier slot.

Expected:

- crop state is recomputed from planted minute and current total minutes
- matured crops appear as harvestable when expected
- no frozen-in-time seeded tiles after long jumps

---

## 6. Visual Rebuild Coherence

1. Save in a region with visible soil and crops.
2. Change area and force chunk transitions.
3. Load prior slot.

Expected:

- soil visuals match loaded farm state
- crop nodes respawn with correct growth visuals
- no stale overlays from pre-load world

---

## 7. Input Regression Guard

After any save/load refactor, verify:

- `F1` toggles help UI
- `F2` toggles full UI
- `F3` toggles debug overlay
- backtick toggles developer console
- `Esc` opens pause menu and allows save/load actions

Expected:

- all keybinds work both before and after multiple loads

---

## 8. Orphan Repair Validation

1. Create inventory/world interactions (pick up, drop, attach, detach).
2. Save and load during mixed parent-child states.

Expected:

- entities with invalid parent links are detached safely to world
- no permanently hidden or inaccessible entities

---

## Fast Failure Signals

Investigate immediately if any occur:

- load reports missing `metadata.json`/`entities.json` unexpectedly
- post-load duplicated entities at same transform
- rigid bodies frozen permanently after load
- pause/menu keybinds stop responding
- crop visuals mismatch crop simulation state
