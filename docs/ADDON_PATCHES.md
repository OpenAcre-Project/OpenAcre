# Addon Patch Notes

This project does not git-track addon sources, so this file records local addon modifications for reproducibility and community sharing.

## GEVP Vehicle Addon (`addons/gevp`)

### Modified File

- `addons/gevp/scripts/wheel.gd`

### Summary of Local Changes

1. Added visual steering controls for wheel meshes:
- `@export var visual_steering_multiplier: float = 1.0`
- `@export_enum("X", "Y", "Z") var visual_steering_axis: int = 1`

2. Added visual spin axis control:
- `@export_enum("X", "Y", "Z") var visual_spin_axis: int = 0`

3. Reworked visual wheel rotation composition to avoid axis wobble:
- Replaced direct per-axis Euler mutation with quaternion composition.
- New composition order:
- base mesh orientation
- steering rotation
- beam axle roll correction
- wheel spin rotation

4. Added persistent visual state fields:
- `_visual_base_quaternion`
- `_visual_spin_angle`

5. Added axis helper:
- `_axis_from_enum(axis: int) -> Vector3`

6. Hardened wheel surface detection against unknown/internal node groups:
- Added `_resolve_surface_type(...)` to scan collider groups and pick only valid surface keys.
- Added `_is_valid_surface(...)` to validate all required dictionaries before use.
- Added `_apply_surface_parameters(...)` with safe `.get(...)` defaults.
- Replaced direct dictionary indexing from `surface_groups[0]` path to validated lookup flow.

### Why These Changes Were Needed

- Some vehicle meshes have wheel nodes outside the wheel raycast hierarchy, so visual steering did not always match physics steering.
- Directly accumulating wheel rotation via Euler channels caused visible precession/wobble when alternating steering input (`A`/`D`) at low speed or standstill.
- Quaternion composition keeps steering and rolling around stable, isolated axes.
- Some colliders can include internal groups (example pattern: `_vp_input...`) that are not terrain surface keys. Validating keys prevents runtime dictionary-access crashes.

### Integration Notes for Vehicle Scenes

For any vehicle using this addon, configure visual axes on wheel nodes to match mesh rig orientation:

- Front wheels:
- assign `wheel_node`
- set `visual_steering_axis`
- set `visual_steering_multiplier` (`1` or `-1` based on rig orientation)

- All driven wheels:
- set `visual_spin_axis` to the actual wheel roll axis for your mesh

### Tractor-Specific Setup in This Project

- Tractor now inherits from `Scenes/Vehicle3D.tscn`.
- Tractor wheel visual node paths and steering axis are configured through inherited scene properties on `Scenes/Tractor.tscn`:
- `wheel_front_left_visual_path = TractorVisual/Wheels/WheelFL`
- `wheel_front_right_visual_path = TractorVisual/Wheels/WheelFR`
- `wheel_rear_left_visual_path = TractorVisual/Wheels/WheelRL`
- `wheel_rear_right_visual_path = TractorVisual/Wheels/WheelRR`
- `front_visual_steering_axis` and `visual_spin_axis` are set on the tractor root.

- Default steering direction in this project is configured so `A` turns visuals left and `D` turns visuals right.

### Upstreaming / Porting

If you update or reinstall the GEVP addon, reapply this file's changes to `addons/gevp/scripts/wheel.gd` or copy your patched version from backup.
