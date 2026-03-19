# Core Runtime Flow

The application boots from `Scenes/Main.tscn` which immediately establishes the split between logic and visual rendering.

## Simulation Sequence

1. `Main.tscn` serves as the root container (`Simulation_Core`, `View_Manager`, `UI_Layer`).
2. `Singletons/SimulationCore.gd` owns player/vehicle logical state (`PlayerData`, `VehicleData`).
3. `Singletons/FarmData.gd` owns map tile/crop state and deterministic catch-up logic.
4. The **View Layer** (3D puppets like `Player` and vehicles) push their transform and statistical data to `SimulationCore` every physics frame.
5. Tools (e.g. `HoeTool`, `SeedTool`) write tile/crop simulation updates through `FarmData`.
6. Visual systems (like `GridManager.gd` and `CropNode.gd`) only respond to state changes to render map state.

## Simulation Rules (Virtual Layer)

- **Pure State Separation:** Map/crop truth exclusively lives in `FarmData` + `FarmTileData`. Player/vehicle truth lives in `SimulationCore` + `PlayerData`/`VehicleData`.
- **Data-Driven Entities:** 
  - Vehicle static configuration relies on `VehicleSpec` in a `VehicleCatalog` resource.
  - Vehicle runtime placement relies on `VehicleSpawnEntry` in a `VehicleSpawnTable`.
- **Decoupled Visuals:** Visual nodes can be created or deleted freely without affecting the logic. (`CropNode` must not tick growth; it merely reflects `FarmData`).
- Methods added to simulation systems should act as pure functions accepting explicit time deltas.

## Extension Guidelines

- Implement new tools by inheriting `Scripts/core/Tool.gd` and register them via `Scripts/player/Player.gd` inventory.
- Keep state inside singletons and restrict visuals to scene scripts.
- Prioritize typed data structures (`FarmTileData`) over generic dictionaries.
