---
title: OpenAcre | Hardcore Open-Source Farming & Survival Simulator
description: The OpenAcre project documentation. A systemic, data-driven farming simulation engine for Godot 4. Realistic agriculture mechanics and survival.
---

# :house: OpenAcre Documentation

Welcome to the **OpenAcre** Godot prototype. This project is a data-driven farming simulation engine designed for scalability, persistence, and performance.

!!! info "Architecture at a Glance"
    This project is organized by domain first, then by scene-facing scripts, strictly following a **Logic-Visual Separation** pattern.

---

## :video_game: Game Systems (User & Modder Guide)

If you are looking to understand how the game handles or how to modify existing mechanics, start here:

- **[:tractor: Vehicle Physics & Driving](systems/vehicles.md)**: Handling, realistic steering, and persistence.
- **[:video_camera: Camera System](systems/camera.md)**: Shared OrbitCameraController and GTA-style behaviors.
- **[:clock1: Time & Day/Night Cycle](systems/day_night_cycle.md)**: Time management and visual world transitions.
- **[:package: Items & Inventory](systems/items_and_inventory.md)**: Data-driven items, storage, and mass simulation.

---

## :classical_building: Technical Architecture (Developer Guide)

For developers looking to extend the core engine or understand the data pipeline:

- **[:map: Architecture Overview](architecture/overview.md)**: Our Logic-Visual separation philosophy.
- **[:loop: Core Runtime Flow](architecture/core_runtime.md)**: Simulation sequence and state management.
- **[:window: UI Architecture](architecture/ui_architecture.md)**: Headless data pipeline and decoupled interfaces.
- **[:world_map: Map Fields Logic](architecture/map_fields_architecture.md)**: Data-driven fields and batch rendering.

---

## :art: Rendering & Performance

Low-level systems focusing on visual fidelity and world streaming:

- **[:mountain: Terrain3D Rendering](rendering/terrain3d_rendering.md)**: Heightmaps and live texture painting.
- **[:grid: Chunk & Catch-Up System](rendering/chunk_system.md)**: World-space optimization and logical consistency.

---

## :hammer_and_wrench: Development Workspace

Tools and internal documentation for managing the codebase:

- **[:terminal: Developer Console](dev/developer_console.md)**: Debugging tools and cheat commands.
- **[:memo: Addon Patch Notes](dev/addon_patches.md)**: Modifications made to third-party plugins.

---

### :file_folder: Project Structure Breakdown

| Path | Purpose |
| --- | --- |
| `Scripts/` | Scene-facing scripts used directly by `.tscn` files. |
| `Scripts/simulation/` | Authoritative state resources (`PlayerData`, `VehicleData`). |
| `Singletons/` | Global systems (`TimeManager`, `SimulationCore`) registered in project settings. |
| `Scenes/` | 3D/2D presentation layers. |
