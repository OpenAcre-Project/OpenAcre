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

- **[:tractor: Vehicle Physics & Implements](systems/vehicles.md)**: Handling, persistence, and component-based attachments (HitchSocket3D / Implement3D).
- **[:video_camera: Camera System](systems/camera.md)**: Shared OrbitCameraController and GTA-style behaviors.
- **[:clock1: Time & Day/Night Cycle](systems/day_night_cycle.md)**: Time management and visual world transitions.
- **[:package: Items & Inventory](systems/items_and_inventory.md)**: Data-driven items, storage, and mass simulation.

---

## :classical_building: Technical Architecture (Developer Guide)

For developers looking to extend the core engine or understand the data pipeline:

- **[:map: Architecture Overview](architecture/overview.md)**: Our Logic-Visual separation philosophy.
- **[:factory: Universal Entity Streaming System Blueprint](architecture/uess_architecture.md)**: Data-driven Component/Entity architecture and Spatial Hash chunking planner.
- **[:book: UESS Technical Reference](architecture/uess_technical_reference.md)**: Architectural decisions and deep-dive logic for the UESS implementation.
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

- **[:link: Advanced Attachments](dev/advanced_attachments.md)**: High-fidelity hitch models and exact-force joints.
- **[:memo: Plow Attachment Dev Log](dev_log/plow_attachment.md)**: Implementation history and iterations for towing systems.
- **[:terminal: Developer Console](dev/developer_console.md)**: Debugging tools and cheat commands.
- **[:memo: Addon Patch Notes](dev/addon_patches.md)**: Modifications made to third-party plugins.

---

### :file_folder: Project Structure Breakdown

| Path | Purpose |
| --- | --- |
| `Scripts/` | Scene-facing scripts used directly by .tscn files. |
| `Scripts/simulation/` | Authoritative state (EntityData, Components, EntityManager). |
| `Scripts/simulation/components/` | Pure data Components (TransformComponent, VehicleComponent, etc.). |
| `Scripts/streaming/` | GridManager and StreamSpooler for chunk-based entity streaming. |
| `Scripts/views/` | EntityView3D base class for streamed 3D representations. |
| `Scripts/core/` | EntityRegistry autoload and core game services. |
| `Singletons/` | Global systems (EventBus, GameManager) registered in project settings. |
| `Data/Entities/` | JSON entity definitions (truck.json, test_apple.json, etc.). |
| `Scenes/` | 3D/2D presentation layers. |

