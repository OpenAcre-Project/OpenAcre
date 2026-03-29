# :terminal: Developer Console | [Home](../index.md)

The developer console is the primary runtime debugging surface for simulation state, chunk behavior, and UESS entity spawning.

---

## Access

Toggle key: backtick (`).

The console stays active even when gameplay input is blocked, and it streams messages emitted through `EventBus.log_message`.

---

## Command Model

Commands are registered in `Scripts/debug/DeveloperConsole.gd` and dispatched through aliases.

Notable commands:

| Command | Purpose |
| --- | --- |
| `help` | Show all registered commands and usage. |
| `time now` / `time set <day> <hour> <minute>` | Inspect or set simulation time. |
| `ff <value>[m|h|d]` | Fast-forward simulation time. |
| `spawn list` | List scene aliases and loaded entity definitions. |
| `spawn <alias_or_def> [count]` | Spawn UESS entities via `EntityRegistry` + `EntityManager`. |
| `spawn_scene <res://...tscn> [count]` | Spawn raw scene instances directly (non-UESS path). |
| `chunks info` | Print visual/simulation chunk counts and stream center. |
| `godmode` | Toggle player noclip mode. |
| `inv` | Show player pocket inventory. |

---

## UESS Spawn Rule

For gameplay-valid vehicle tests, use UESS entity IDs (or aliases that resolve to them), for example:

- `spawn vehicle.truck`
- `spawn truck`
- `spawn vehicle.plow`

Alias resolution is definition-first:

1. `<alias>`
2. `vehicle.<alias>`
3. `item.<alias>`

So `spawn truck` resolves to `vehicle.truck` when that definition exists.

---

## Important Distinction

`spawn` and `spawn_scene` are intentionally different:

- `spawn ...` -> UESS-owned entities (eligible for StreamSpooler load/unload/despawn).
- `spawn_scene ...` -> direct scene instances (not tracked by UESS entity data lifecycle).

Use `spawn_scene` only for isolated visual/debug checks. For streaming/despawn validation, always use `spawn`.

---

## Debug Workflow Example

1. `spawn vehicle.truck`
2. `chunks info`
3. Drive across chunk boundaries.
4. Verify unload/reload behavior without losing authoritative state.

For chunk/collision tuning details, see [Chunk & Catch-Up System](../rendering/chunk_system.md).
