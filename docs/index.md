# Open Farm Documentation

Welcome to the Open Farm Godot prototype documentation. This project is organized by domain first, then by scene-facing scripts.

## Architecture Philosophy

The runtime is strictly split into logic and view layers:
- **Logic** (`Singletons/*`): headless simulation and authoritative state.
- **View** (`Scenes/*` + `Scripts/*`): 3D/2D presentation and player-facing physics.

The primary boot target is `project.godot` which runs `Scenes/Main.tscn`.

### Scene Ownership Hierarchy

- `Main` (Node)
  - `Main/View_Manager/3D_World/WorldMap` (3D world instance)
  - `Main/UI_Layer/*` (UI, debug tools, developer console independent of the 3D world)

## Folder Layout

- `Scripts/`: Scene-facing scripts used directly by `.tscn` files.
- `Scripts/farm/`: Core farm domain models and helpers.
- `Scripts/farm/tools/`: Farm interaction tools (hoe, seeds, etc.).
- `Scripts/player/`: Player controllers split by responsibility.
- `Scripts/vehicles/`: Shared vehicle logic and GEVP integrations.
- `Scripts/interactables/`: World objects the player can interact with.
- `Scripts/core/`: Shared base abstractions.
- `Scripts/simulation/resources/`: Typed state resources (`PlayerData`, `VehicleData`).
- `Singletons/`: Global systems (`TimeManager`, `FarmData`, `SimulationCore`) registered in `project.godot`.

Use the sidebar navigation to explore specific systems in depth.
