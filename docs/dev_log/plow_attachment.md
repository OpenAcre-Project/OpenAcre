# Plow Attachment System — Implementation History

> **Purpose:** This document records every approach tried for attaching implements (plow) to the tractor, what was observed, and why each failed. Use this to avoid repeating failed approaches.

---

## Quick Summary of Trials

| # | Approach | Result | Key Takeaway / Why it Failed |
|:-:|---|---|---|
| 1 | `Generic6DOFJoint3D` + `global_transform` | ❌ **FAILED** | `global_transform` is unreliable on RigidBodies; Joint failed to bind. |
| 2 | Freeze/Unfreeze + Teleport | ❌ **FAILED** | Physics server reverts to pre-freeze transform on unfreeze. |
| 3 | `body_set_state` + Direct Joint | ❌ **FAILED** | Joint between `AnimatableBody3D` and `RigidBody3D` had zero effect. |
| 4 | Kinematic Follow (`body_set_state`) | ❌ **FAILED** | Manual sync in `_physics_process` drifts at high speeds. |
| 4 | Reparenting (Driving follow) | ✅ **SUCCESS** | Engine-native transform propagation is perfectly stable for driving. |
| 5 | Reparenting (Raise/Lower) | ❌ **FAILED** | `RigidBody3D` transform is always owned/reverted by physics server. |
| 6 | Remove from Physics Space | ❌ **FAILED** | `AnimatableBody3D` local transform corrupted by `sync_to_physics`. |
| 7 | Precise Node3D Fix | ❌ **FAILED** | Physics server reverts manual transform writes even if body is unspaced. |
| 8 | Direct Hitch Reparenting | ❌ **FAILED** | Physics engine traversal bug: child RigidBodies of moving RigidBodies fail. |
| 9 | No Reparenting + Per-Frame Sync | ✅ **SUCCESS** | **Architectural Winner.** Outside hierarchy = no engine interference. |
| 10 | **HitchRay Float Mechanic** | ✅ **SUCCESS** | **Active Solution.** Adds terrain-aware vertical oscillation. |

!!! tip "Current Implementation"
    The final, optimized version uses Approach 9 for stability and Approach 10 for realism. For the streamlined guide, see [Advanced Attachments & Float Mechanics](../dev/advanced_attachments.md).

---

## Problem Statement

When the player presses the "Attach Implement" key while the tractor is near the plow, the plow should:

1. Snap to the tractor's rear hitch point
2. Stay rigidly connected while driving
3. Detach cleanly when requested

The `PlowAttachment` is a `RigidBody3D` (100kg, extends `Implement3D`). The `Tractor` extends `Vehicle3D` which extends `Vehicle` (GEVP RigidBody3D). The `RearHitch` is an `AnimatableBody3D` child of the tractor with a `HitchPoint` `Marker3D`.

---

## Approach 1: Generic6DOFJoint3D + `global_transform` Teleport

### What We Did
- Created a `Generic6DOFJoint3D` dynamically in `Vehicle3D._ready()`
- `node_a` = RearHitch (AnimatableBody3D), `node_b` = empty until attachment
- Linear limits disabled (= locked), angular limits enabled (±45°/±60°/±5°)
- On attach: set `implement.global_transform` to hitch position, set `node_b` via `set_deferred()`

### What Happened
```
FRAME 1 => Pos: (105.6554, 29.33351, 127.6489), Vel: (0.078, 0.102, 2.239)
FRAME 2 => Pos: (105.6567, 29.33249, 127.6861), Vel: (0.079, -0.061, 2.235)
FRAME 3 => Pos: (105.658, 29.32874, 127.7233),  Vel: (0.078, -0.225, 2.231)
...
10 sec later => Pos Y = -331.28, Vel Y = -61.94  (freefall)
```

### Root Cause
Two issues stacked:

1. **`set_deferred("node_b", ...)`** means the joint doesn't bind until the next idle frame → 1-2 physics frames where the plow is unconstrained
2. **`global_transform = ...`** on a RigidBody3D does NOT reliably update the physics server (Godot docs explicitly warn against this)

### Key Learning
> Setting `global_transform` on a RigidBody3D leads to "unpredictable behaviors" per Godot docs. The physics server keeps its own copy and overwrites the node.

---

## Approach 2: Freeze/Unfreeze + `global_transform` Teleport + Deferred Joint

### What We Did
- Before teleporting: `rb.freeze = true`, `rb.freeze_mode = FREEZE_MODE_KINEMATIC`
- Teleport via `global_transform`
- Set `node_b` via `set_deferred()`
- After joint binds: `call_deferred("_on_hitch_joint_ready")` which sets `freeze = false`

### What Happened
```
FRAME 1 (frozen): Pos Z = 125.592 (at hitch) ✓, sleeping: true
Joint bound, unfrozen: Pos Z = 125.592 ✓
FRAME 2 (unfrozen): Pos Z = 127.055 ← SNAPPED BACK to pre-teleport position!
FRAME 3-5: stays at Z = 127.055, vel ≈ 0 (stuck at original position)
```

### Root Cause
When `freeze = true` (KINEMATIC mode), `global_transform` appears to update the node's position, but the **physics server reverts to the pre-freeze position** when `freeze` is set back to `false`. The physics server has its own internal state that `global_transform` doesn't update.

### Key Learning
> Freezing → moving → unfreezing a RigidBody3D does NOT teleport it. The physics server remembers the old position.

---

## Approach 3: `PhysicsServer3D.body_set_state()` Teleport + Direct Joint Binding

### What We Did
- Teleport via `PhysicsServer3D.body_set_state(rb.get_rid(), BODY_STATE_TRANSFORM, desired_xform)` — the documented correct way
- Removed `set_deferred`: set `hitch_joint.node_b = b_path` directly (we're in `_input`, not in physics)
- No freeze/unfreeze — left implement as dynamic RigidBody3D

### What Happened
```
Post-attach cross-check: Node pos: (105.47, 30.15, 129.37) | PhysicsServer pos: (105.58, 29.32, 128.10) | Match: false
FRAME 1:  NodePos = (105.58, 29.32, 128.10) = ServerPos ✓ (teleport worked!)
FRAME 2:  Vel Y = -0.041  (gravity starting)
FRAME 5:  Vel Y = -0.531  (accelerating downward)
FRAME 10: Vel Y = -1.340  (freefall)
FRAME 15: Vel Y = -2.143  (freefall)
10 sec:   Pos Y = -331, Vel Y = -61.93  (terminal freefall)
```

### Root Cause
The `PhysicsServer3D.body_set_state()` teleport **worked perfectly** (NodePos = ServerPos from frame 1). However, the `Generic6DOFJoint3D` had **absolutely zero constraining effect**. The plow was in pure gravitational freefall despite the joint being configured with valid `node_a` and `node_b`.

### Key Learning
> `Generic6DOFJoint3D` between an `AnimatableBody3D` (RearHitch, collision_layer=0) and a `RigidBody3D` (PlowAttachment) does NOT produce any constraint in Godot 4.6.1. The joint exists in the node tree but has no physics effect. Possible causes: AnimatableBody3D with zero collision layers, or internal Godot limitation with dynamically created joints between these body types.

---

## Approach 4 (Working): Kinematic Follow via `PhysicsServer3D`

### What We Did
- **Removed `Generic6DOFJoint3D` entirely** — no joint creation, no joint binding
- On attach: freeze implement as `FREEZE_MODE_KINEMATIC`, teleport via `PhysicsServer3D.body_set_state()`
- **Every `_physics_process` frame**: compute desired transform from hitch point, move implement via `PhysicsServer3D.body_set_state()`
- On detach: unfreeze, inherit tractor velocity

### Key Functions
- `_compute_implement_world_transform()` — calculates world transform aligned to hitch
- `_sync_attached_implement_to_hitch()` — called each `_physics_process`, moves the implement

### What We Did (v3.1 Sync Fix)
- Used `PhysicsServer3D.body_get_state(tractor_rid, BODY_STATE_TRANSFORM)` to get the "true" tractor position.
- Manually calculated the hitch world position and moved the implement via `body_set_state` every `_physics_process`.

### What Happened
```
FRAME 1-15: Almost perfect follow ✓
High Speed (30km/h+): Drifts by 5-10 meters.
10 Seconds later: ImplementPos: (338, ...), VehiclePos: (384, ...) -> 46 meter gap! ❌
```

### Root Cause
Directly setting `body_set_state` every frame competes with the Node tree's automatic `sync_to_physics` behavior for kinematic bodies. At high speeds or under load, the GEVP physics engine moves the tractor far away between frames, and the manual sync in `_physics_process` is always slightly out of phase with the engine's internal transform propagation.

### Key Learning
> Manual transform syncing in `_physics_process` is inherently fragile when parent and child are both physics bodies managed by different systems (GEVP vs manual).

---

## Approach 4 (WORKING): Reparenting

### What We Did
- **Freeze as kinematic** (`freeze_mode = KINEMATIC`, `freeze = true`).
- **Reparent** the implement node to be a child of the `RearHitch` node at runtime.
- **`reparent(new_parent, true)`**: The `true` argument (keep_global_transform) ensures it doesn't jump during handoff.
- **Zero code sync**: Remove all `_physics_process` sync math. Godot's engine handles the parent-child transform hierarchy natively.

### Why this might works
- **Engine-Native**: Parent-child transform propagation is calculated by Godot's C++ core at the exact right moment in the frame lifecycle.
- **Rigorously Tied**: If the hitch node moves 1cm, the child moves 1cm instantly with zero lag.
- **Automatic Y-Offset**: Raising/lowering the hitch point automatically moves the plow child.

---

## Approach 5: Reparenting — Raise/Lower Sub-Attempts (ALL FAILED)

Approach 4 (Reparenting) solved the **driving follow** problem perfectly. However, **raise/lower (X key)** did not work — the plow stayed at the same Y position relative to the tractor regardless of hitch state.

### Sub-attempt 5a: Reparent to RearHitch + `body_set_state()` after pose change
- After `_apply_hitch_pose()` changed `rear_hitch.position.y`, called `PhysicsServer3D.body_set_state()` with the implement's updated `global_transform`.
- **Result**: Jitter for 1 frame, then reverted to old position.

### Sub-attempt 5b: Reparent to `AttachmentSockets` (plain Node3D) instead of `RearHitch`
- Changed reparent target from `RearHitch` (AnimatableBody3D) to `AttachmentSockets` (plain Node3D).
- Added `_align_implement_to_hitch()` to compute `rear_hitch.transform * HitchPoint.transform.affine_inverse()`.
- Called `_align_implement_to_hitch()` from `_toggle_hitch()` after pose change.
- **Result**: No change. Physics server still overrides node-level transform.

### Sub-attempt 5c: Disable collision shapes on implement
- Set `CollisionShape3D.disabled = true` on all implement children when attached.
- **Result**: No change. Physics server still manages the body's transform even without collision shapes.

### Root Cause (shared across all sub-attempts)
> A `RigidBody3D` — even frozen kinematic, even with disabled collision shapes, even reparented to a plain Node3D — has its transform **owned by the physics server**. Node tree `transform =` changes are silently overridden. No amount of freezing, collision disabling, or reparenting changes this.

---

## Approach 6 (Current): Reparenting + Remove from Physics Space

### What We Did
- Froze implement as kinematic
- **`PhysicsServer3D.body_set_space(rb.get_rid(), RID())`** — removes the body from the physics world **entirely**
- Reparented to `AttachmentSockets` (plain Node3D)
- `_align_implement_to_hitch()` computes local transform from `rear_hitch.transform`
- On toggle hitch (X): `_apply_hitch_pose()` changes `rear_hitch.position.y`, then `_align_implement_to_hitch()` recalculates
- On detach: `PhysicsServer3D.body_set_space(rb.get_rid(), get_world_3d().space)` restores the body + `body_set_state()` teleports it to current `global_transform`

### Key Insight
> `body_set_space(rid, RID())` is the **only** way to make the physics server release ownership of a RigidBody3D's transform. After this call, the node is purely visual — transform changes via the node tree work exactly as they do for a plain Node3D.

### Status: FAILED (Raise/Lower)
Driving follow was perfect, but the plow would not translate vertically when pressing X. 

### Root Cause
Debug logs revealed that `rear_hitch.transform.origin` was being corrupted by `AnimatableBody3D.sync_to_physics`. When the tractor moved, X and Z coordinates in the local transform would shift by meters even though only Y was being modified by code.

## Approach 7: Precise Node3D Fix (Success)

### What We Did
- **Scene Change**: Converted `RearHitch` from `AnimatableBody3D` to a plain `Node3D`. Removed its `CollisionShape3D` and `HitchJoint`.
- **Script Simplification**: Updated `Vehicle3D.gd` to treat `rear_hitch` as a `Node3D`. Simplified `_align_implement_to_hitch` to use the hitch's `transform` directly, as it is no longer corrupted by physics synchronization.
- **Plowing Logic Fix**: Updated `PlowAttachment.gd` to use the attached vehicle's `linear_velocity` for movement detection, since the plow itself is removed from physics space while attached.

### Why this might works
- **Eliminating Corruption**: `AnimatableBody3D` with `sync_to_physics` was the source of transform jitter and drift. A plain `Node3D` is 100% stable in the node hierarchy.
- **Authoritative Transforms**: By removing the implement from physics space and using a stable `Node3D` parent/reference, the engine-native transform propagation works perfectly.
- **Velocity Inheritance**: Explicitly checking the vehicle's velocity ensures that implements can still perform speed-based logic (like plowing) even when they aren't technically "moving" in the physics server's eyes.

### Status: FAILED (Physics Server Reversion)
Even though the alignment math was correct and `rear_hitch.position.y` was changing, the implement's `global_position` snapped back to the base `0.5` offset when the tractor moved. This is because a `RigidBody3D` (even when frozen and removed from physics space via `body_set_space(..., RID())`) still attempts to sync its local `transform` from the physics server caching, rejecting our `implement.transform = ...` manual overrides during raise/lower.

---

## Approach 8: Direct Hitch Reparenting (The Real Fix)

### What We Did
- **Direct Child**: Changed `_attach_implement_simple` to reparent the implement **directly** to the `rear_hitch` (Node3D), rather than to its static parent `AttachmentSockets`.
- **Zero Realignment**: Removed the `_align_implement_to_hitch` call from `_toggle_hitch`. Since the implement is now a direct child of the moving piece (`rear_hitch`), raising or lowering the hitch natively moves the child without EVER altering the child's local `transform`.
- **Immediate Server Sync**: Added a single `PhysicsServer3D.body_set_state` call inside `_align_implement_to_hitch` to definitively lock in the initial relative alignment when attaching.

### Why this might works
Godot's physics server aggressively reverts manual `transform = ...` writes to frozen `RigidBody3D` nodes over time because it maintains its own state cache. However, Godot **fully respects** global transform changes that cascade down naturally from a node's parent moving. By making the implement a child of the `Node3D` hitch, its local `transform` remains static forever. The hitch moves, the node hierarchy propagates the movement, and the physics server never fights it because the implement's local `transform` never mutates.

### Status: FAILED (Physics Engine Traversal Bug)
Even when reparented directly to the `rear_hitch`, Godot's physics engine has a known issue where `RigidBody3D` nodes (even when frozen and removed from physics space via `body_set_space(RID())`) do NOT behave correctly when they are descendants of a moving `RigidBody3D` (such as the `Vehicle3D` tractor). The physics engine continues to perform internal transform propagation/sync on any descendant `RigidBody3D`, completely overriding the parent-driven global transform at runtime.

---

## Approach 9: No Reparenting + Per-Frame Global Transform Sync (Success)

### What We Did
- **No Reparenting**: Modified `_attach_implement_simple` to keep the implement in the scene root. It is NEVER made a child of the `Vehicle3D` or its `RearHitch`.
- **Space Removal**: Retained the `freeze` and `body_set_space(RID())` calls to fully release physics engine ownership of the node.
- **Manual Sync**: Added a new method `_sync_implement_transform()` that accurately calculates the world transform from the hitch point.
- **Per-Frame Enforcement**: Called `_sync_implement_transform()` inside the vehicle's `_physics_process` (every frame) and instantly on `_toggle_hitch()` to enforce the positional lock.

### Why this might works
By keeping the frozen `RigidBody3D` completely OUTSIDE the vehicle's node hierarchy, we bypass Godot's buggy descendant-transform-override logic entirely. Since it is removed from the physics space, the node-level `global_transform` assignment in `_physics_process` sticks perfectly. There is no physics engine fighting, no snap-back, and no drift at any speed.

### Status: SUCCESS
This is the proven pattern for "pick up / carried objects" in Godot.

> **Note:** The final, optimized version of this system utilizes a `RayCast3D` (HitchRay) to seamlessly handle ground collision and mathematical floating. For details on the streamlined, active implementation, please read: [Advanced Attachments & Float Mechanics](../dev/advanced_attachments.md).
