# Core Runtime Flow | [Home](../index.md)

OpenAcre runtime is split into authoritative data state and streamed visual state.
The logic side remains valid even when view nodes are unloaded.

---

## Runtime Entry Points

Main boot starts from `Scenes/Main.tscn` with these persistent autoloads:

- `GameManager`
- `EventBus`
- `SaveManager`
- `ItemRegistry`
- `EntityRegistry`

`GameInput.ensure_default_bindings()` provides default key mappings used by UI and debug tools.

---

## Authoritative Data Layer

Core authoritative state is held by `GameManager.session`:

- `TimeManager` for calendar/time progression.
- `EntityManager` for runtime entity/component graph.
- `FarmData` for tile state and growth simulation.

The data layer is not tied to scene-node lifetime.
View nodes can be despawned and recreated from stored components and farm tiles.

---

## Streamed View Layer

Two streaming concerns run in parallel:

- UESS entity views via `Scripts/streaming/StreamSpooler.gd`.
- Farm/crop chunk visuals via `Scripts/farm/GridManager.gd` and `Scripts/farm/CropNode.gd`.

At runtime, both systems hydrate from the same authoritative state and can be rebuilt after load.

---

## Save And Load Integration

`SaveManager` is the persistence coordinator.
For the full persistence contract see [Save/Load Runtime](save_load_runtime.md).

At a high level:

1. Save emits `EventBus.pre_save_flush` so active streamed views flush current physics state back into components.
2. Save writes a temp slot payload, then promotes it with an atomic directory swap.
3. Load pauses the tree, freezes streaming, wipes runtime views safely, restores data, rebuilds visuals, and resumes.
4. Load emits `EventBus.game_loaded_successfully` after hydration completes.

---

## Runtime Signal Boundaries

`EventBus` is the cross-system contract for save/load orchestration:

- `save_game_requested`
- `pre_save_flush`
- `load_game_requested`
- `game_loaded_successfully`

UI and console invoke `SaveManager` directly for explicit slot control, while these signals remain available as global hooks.
