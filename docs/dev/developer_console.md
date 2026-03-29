# Developer Console | [Home](../index.md)

The developer console is the in-game runtime tool for inspecting simulation state,
spawning entities, and validating save/load behavior.

---

## Access

- Toggle key: backtick key.
- Close console with `Esc` while console is focused.
- Console runs with `PROCESS_MODE_ALWAYS` so it remains responsive when the tree is paused.

---

## Command Reference

Commands are implemented in `Scripts/debug/DeveloperConsole.gd`.

| Command | Purpose |
| --- | --- |
| `help` | Print command list and usage hints. |
| `clear` | Clear current console output. |
| `copy` | Copy console text to clipboard. |
| `time now` / `time set <day> <hour> <minute>` | Inspect or set simulation time. |
| `ff <value>[m|h|d]` | Fast-forward simulation time. |
| `spawn list` | List scene aliases and loaded entity definitions. |
| `spawn <alias_or_def> [count]` | Spawn UESS entities (`EntityRegistry` + `EntityManager`). |
| `spawn_scene <res://...tscn> [count]` | Spawn raw scene instances (non-UESS). |
| `st [vehicle_def] [implement_def]` | Quick tractor + implement test rig spawn. |
| `sim catchup <seconds>` | Apply farm simulation catch-up for testing. |
| `chunks` / `chunks info` | Toggle chunk overlay or print chunk metrics. |
| `farmable` | Toggle farmable overlay. |
| `godmode` | Toggle player noclip/free-fly mode. |
| `inv` | Print player pocket inventory contents. |
| `keybinds` | Print current effective keybindings. |
| `save [slot]` | Save to slot (default 1). |
| `load [slot]` | Load from slot (default 1). |
| `saves [max_slots]` | List slot metadata summaries. |

---

## Save/Load QA Commands

Recommended loop while developing persistence:

1. `save 1`
2. mutate world state (move player, time jump, spawn/despawn)
3. `load 1`
4. `saves 8` to verify slot metadata remains sane

For full validation matrix, see [Save/Load QA Protocol](save_load_qa.md).

---

## UESS Spawn Rule

Use `spawn` for gameplay-valid persistence/streaming tests:

- `spawn vehicle.truck`
- `spawn truck`
- `spawn vehicle.plow`

Alias resolution tries:

1. `<alias>`
2. `vehicle.<alias>`
3. `item.<alias>`

---

## `spawn` vs `spawn_scene`

- `spawn ...` creates UESS-owned entities and participates in streaming/despawn/save.
- `spawn_scene ...` instantiates a scene directly and bypasses UESS lifecycle.

Use `spawn_scene` only for isolated visual checks.

---

## Logging

Console output mirrors `EventBus.log_message`, including warn/error coloring.
This makes it the fastest way to observe persistence and streaming diagnostics in runtime.
