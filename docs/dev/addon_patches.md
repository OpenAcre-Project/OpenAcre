# 📝 Addon Patch Notes | [Home](../index.md)

This project does not git-track addon sources, so this file records local addon modifications for reproducibility and community sharing.

---

## 🛠️ GEVP (Godot Easy Vehicle Physics)

!!! abstract "Core Modifications"
    The base GEVP plugin was patched to support the **OpenAcre** deterministic steering and state persistence architecture.

- **`vehicle.gd` Patch**: Exposed internal torque and suspension parameters to the `Vehicle3D` wrapper.
- **Steering Fix**: Added a safety clamp to the steering speed correction denominator in `process_steering()` to prevent division by zero when the vehicle is stationary.
- **Wheel Raycast Fix**: Modified the raycast calculation to handle [Terrain3D](../rendering/terrain3d_rendering.md) positive coordinate grids more accurately.

!!! warning "Reproducibility"
    If you reinstall the GEVP addon, you must re-apply these patches documented in this section to avoid breaking the vehicle physics integration.

---

## 🎨 Terrain3D

!!! success "Performance Patch"
    Added a `_batch_painting` flag to the internal storage API to allow for localized suppression of GPU updates during large-scale field generation.
