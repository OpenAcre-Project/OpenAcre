# Developer Console

The developer console provides real-time access to the simulation state and commands for debugging the application.

## Core Features & Integration

The Developer Console (`Scripts/debug/DeveloperConsole.gd`) operates on a detached global layer independent of the main `3D_World`.

- **Crash Resistance:** The console node enforces `Node.PROCESS_MODE_ALWAYS`. This ensures the console remains active and responsive even when the main scene tree pauses due to game mechanics, debug breakpoints, or system halting errors.
- **Log Aggregation:** It binds directly to the `GameLog` singleton to intercept and colorize game output (INFO, WARN, ERROR).
- **History Tracking:** The input log records up to 220 executed commands dynamically navigable with arrow keys.
- **Detached Production Usage:** By default, the developer console can be omitted or stripped during production builds. If it is disabled or removed in a release environment, the core simulation and `GameLog` continue uninterrupted. No simulation systems, singletons, or game models depend on `DeveloperConsole.gd` to function—avoiding any lingering side effects or crashes in production.

## Essential Commands

These commands directly interact with the simulation or the developer overlays.

### Time & Simulation
- `time now` / `time set <day> <hour> <min>`: Immediately changes the simulation time.
- `ff <value>[m|h|d]`: Fast forward absolute time (e.g., `ff 6h`). Automatically hooks into `FarmData.simulate_passage_of_time()`.
- `sim catchup <seconds>`: Force the simulation singleton to perform a bulk recalculation over an elapsed second delta.

### Environment Control
- `chunks`: Toggles the visual rendering of the chunk streaming borders in 3D space.
- `chunks info`: Reports currently stream-loaded visual chunks versus total populated logic data chunks.
- `farmable`: Toggles the overlay highlighting farmable terrain IDs defined by `MapRegionMask`.

### Entities
- `spawn <alias>`: Generates entities at an offset based on the camera view forward vector (aliases: apple, tractor, player).
- `spawn_scene <res_path>`: Loads a target `.tscn` file onto the root scene.
- `godmode` / `fly`: Toggles a kinematic free-flight mechanism by adjusting `collision_layer` out of bounds.

### Utility
- `copy`: Extracts all console log contents recursively into the platform clipboard.
- `clear`: Purges visual log history.
