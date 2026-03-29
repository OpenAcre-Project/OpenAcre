# :package: Items and Inventory System | [Home](../index.md)

The Item and Inventory framework is a robust, systemic solution implemented in Godot 4. This system handles discrete physical items ("Apples") and bulk commodities ("Water").

---

## 1. Data Architecture

!!! gear "Authoritative Logic Layer"
    The architecture draws a strict line between **Static Definitions** and **Runtime Instances**, preventing memory bloat and improving serialization speeds.

### Definitions (`Resource`)
Stored inside `ItemRegistry`. These represent the "idea" of an item or fluid.
- **`ItemDefinition`**: Contains metadata like `id`, `base_mass`, `base_volume`, and the associated `world_scene`.
- **`CommodityDefinition`**: Handles fluid properties and density (`kg/Liter`).

### Instances (`Resource`)
- **`ItemInstance`**: The runtime payload for an item. Holds the `stack` amount and arbitrary `dynamic_data`.

---

## 2. Storage Structures

### `InventoryData`
An advanced inventory handler used by both Player pockets and Vehicle cabin storages. 

!!! success "Smart Stacking"
    When adding items via `try_add_item()`, the system calculates precisely how many units can geometrically fit in the remaining volume.

### `BulkTankData`
Used for vehicle fuel tanks or fluid containers. 

!!! info "allowed_commodities"
    Constrains payloads using a whitelist (e.g., stopping players from pouring water into a diesel tank).

---

## 3. World Interaction & Dropping

### `InteractableItem3D`
Every dropped/spawned item in the 3D world mounts an `InteractableItem3D` component.

!!! gear "Dynamic Physics Mass"
    Any change in its internal `item_data` triggers `sync_physics_mass()`, updating the physics engine body `mass` dynamically.

---

## 4. Encumbrance & Dependencies

### Player Encumbrance
The controller defines a smooth encumbrance curve:
- **Soft Limit (50% max_mass)**: No penalty up to this threshold.
- **Over Soft Limit**: Movement speed gradually eases downwards by tapering the modifier limit towards 0.2 (~20% walk speed).
- **Overencumbered (150% max_mass)**: Jumping becomes wholly disabled.

---

## 🔍 Automated Verification
To ensure future structural integrity, the codebase supports an automated systemic validator:
- **Script**: `Scripts/tests/verify_items.gd`
- **Execution**: `godot --headless -s Scripts/tests/verify_items.gd`
