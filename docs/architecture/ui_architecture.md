# UI Architecture | [Home](../index.md)

OpenAcre UI uses a scene-level `MasterUI` plus event-driven data hooks.
Gameplay logic stays authoritative in data systems, while UI reflects current state.

---

## EventBus Contract

`EventBus.gd` exposes cross-layer signals for UI, logs, and save/load flow.

Relevant UI/persistence signals:

- `log_message`
- `update_crosshair_prompt`
- `save_game_requested`
- `pre_save_flush`
- `load_game_requested`
- `game_loaded_successfully`

---

## MasterUI Runtime Role

`Scenes/UI/MasterUI.tscn` + `Scenes/UI/MasterUI.gd` provides:

- main HUD zones (top-left, top-right, bottom-left, bottom-right)
- contextual prompt surfaces
- pause overlay with save/load controls

`MasterUI` runs with `PROCESS_MODE_ALWAYS` so pause/menu key handling remains alive while the tree is paused.

---

## Pause Menu And Persistence UX

Pause menu is toggled through `GameInput.ACTION_TOGGLE_PAUSE_MENU` (default `Esc`).

Pause overlay includes:

- slot picker (`SlotSpinBox`)
- slot metadata preview (`SlotMetaLabel`)
- `Save Game` button
- `Load Game` button
- `Resume` button
- status/error text (`PauseStatusLabel`)

Behavior:

- opening menu pauses scene tree and releases mouse capture
- save calls `SaveManager.save_slot(slot)`
- load awaits `SaveManager.load_slot(slot)`
- closing menu restores gameplay pause/mouse state

---

## Input Routing Rules

Input actions are centralized in `Scripts/core/GameInput.gd`.

Key defaults:

- `F1` help toggle
- `F2` UI visibility toggle
- `F3` debug overlay toggle
- backtick console toggle
- `Esc` pause menu toggle

Gameplay consumers (player controllers) respect `GameInput.is_gameplay_input_blocked(...)` so open UI/console states block gameplay-only controls.

---

## Debug Surfaces

- [Developer Console](../dev/developer_console.md) for runtime commands and logs
- `SimulationDebugOverlay` (project-setting gated)

Both are designed to remain interactive during pause or non-gameplay states.
