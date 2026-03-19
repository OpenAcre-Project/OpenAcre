# Vehicle Physics

Vehicles within the ecosystem utilize Godot Easy Vehicle Physics (GEVP) coupled with custom deterministic simulation systems.

## Separation of Concerns

- **Physical Rendering:** Base logic handling camera setups, user inputs, interpolation, and wheel raycast rendering occupies `Vehicle3D.gd`. Specific assets (like `Tractor.tscn`) inherit from the base class to modify meshes or colliders.
- **Physics Abstraction:** `ArcadeDriveMechanics.gd` separates the driving inputs strictly from visual processing arrays.
- **Authoritative State:** `VehicleData.gd` inside `SimulationCore` contains purely persistent values (transform coordinates, fuel metrics, maintenance logs) decoupled from a rendered 3D instance. 
- **Streaming Context:** As vehicles move through proximity limits, `VehicleManager.gd` catalogs logical vehicles from `VehicleSpawnTable` entries and streams visible scenes incrementally. When instances sleep out of render range, tracking defaults to logical calculations overhead exclusively.
