---
title: OpenAcre | Hardcore Open-Source Farming & Survival Simulator
description: The OpenAcre project documentation. A systemic, data-driven farming simulation engine for Godot 4. Realistic agriculture mechanics and survival.
---

# 🏠 OpenAcre Documentation

Welcome to the **OpenAcre** Godot prototype. This project is a data-driven farming simulation engine designed for scalability, persistence, and performance.

!!! info "Architecture at a Glance"
    This project is organized by domain first, then by scene-facing scripts, strictly following a **Logic-Visual Separation** pattern.

---

## 🎮 Game Systems (User & Modder Guide)

If you are looking to understand how the game handles or how to modify existing mechanics, start here: 

- **[🚜 Vehicle Physics](systems/vehicles.md)**: Handling, persistence, and vehicle-level attachment architecture.
- **[🧩 Implements, Ground Arbitrator, and Plowing](systems/ground_effectors_and_plowing.md)**: Canonical source for work contracts, arbitrator flow, implement setup, hitch rigidity tuning, and drag behavior.
- **[🎥 Camera System](systems/camera.md)**: Shared OrbitCameraController and GTA-style behaviors.
- **[🕐 Time & Day/Night Cycle](systems/day_night_cycle.md)**: Time management and visual world transitions.
- **[📦 Items & Inventory](systems/items_and_inventory.md)**: Data-driven items, storage, and mass simulation.

---

## 🏛️ Technical Architecture (Developer Guide)

For developers looking to extend the core engine or understand the data pipeline:

- **[🗺️ Architecture Overview](architecture/overview.md)**: Our Logic-Visual separation philosophy.
- **[🏭 Universal Entity Streaming System Blueprint](architecture/uess_architecture.md)**: Data-driven Component/Entity architecture and Spatial Hash chunking planner.
- **[📖 UESS Technical Reference](architecture/uess_technical_reference.md)**: Architectural decisions and deep-dive logic for the UESS implementation.
- **[🔁 Core Runtime Flow](architecture/core_runtime.md)**: Simulation sequence and state management.
- **[💾 Save/Load Runtime](architecture/save_load_runtime.md)**: Atomic slot saves, hydration pipeline, blackout windows, and farm layer persistence.
- **[🪟 UI Architecture](architecture/ui_architecture.md)**: Headless data pipeline and decoupled interfaces.
- **[🗺️ Map Fields Logic](architecture/map_fields_architecture.md)**: Data-driven fields and batch rendering.

---

## 🎨 Rendering & Performance

Low-level systems focusing on visual fidelity and world streaming:

- **[⛰️ Terrain3D Rendering](rendering/terrain3d_rendering.md)**: Heightmaps and live texture painting.
- **[📐 Chunk & Catch-Up System](rendering/chunk_system.md)**: World-space optimization and logical consistency.

---

## 🛠️ Development Workspace

Tools and internal documentation for managing the codebase:

- **[🔗 Advanced Attachments](dev/advanced_attachments.md)**: High-fidelity hitch models and exact-force joints.
- **[📝 Plow Attachment Dev Log](dev_log/plow_attachment.md)**: Implementation history and iterations for towing systems.
- **[💻 Developer Console](dev/developer_console.md)**: Debugging tools and cheat commands.
- **[🧪 Save/Load QA Protocol](dev/save_load_qa.md)**: Repeatable verification for atomicity, visual rebuild, blackout safety, and crop catch-up.
- **[📝 Addon Patch Notes](dev/addon_patches.md)**: Modifications made to third-party plugins.

---

### 📁 Project Structure Breakdown

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

