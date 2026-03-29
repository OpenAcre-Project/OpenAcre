# 🎥 Camera System | [Home](../index.md)

The project uses a unified, shared camera system to ensure a consistent feel across all third-person entities (Players and Vehicles).

## OrbitCameraController.gd

All third-person cameras are powered by the **`OrbitCameraController`** component. This is a standalone `Node` that attaches to any entity with a `SpringArm3D` and `Camera3D`.

!!! gear "Core Features"
    - **World-Stable Orbit**: The camera's global heading (yaw) is maintained independently of its parent's rotation. This prevents the camera from "snapping" or "smacking" when the vehicle or player turns.
    - **Smooth Height & Zoom**: Uses `lerp` for vertical position and spring length adjustments, providing a premium feel.
    - **Constraints**: Includes built-in clamping for pitch, height, and zoom distances.

---

## 🚜 Vehicle Camera (GTA-Style)

The vehicle camera is configured to prioritize **Visibility and Ease of Driving**.

!!! success "Auto-Follow Mode"
    Enabled via `is_auto_center_enabled`. After 1 second of mouse inactivity, the camera smoothly rotates back to align with the vehicle's forward vector.

### ⚙️ Configuration:
- `camera_auto_center_delay`: Time before the camera starts returning.
- `camera_auto_center_speed`: How fast the camera rotates back.

---

## 🚶 Player Camera (Action-Style)

The player camera is configured to prioritize **User Direction**.

!!! info "Independent Orbit"
    Auto-centering is **disabled**. The camera stays exactly where the user puts it.

### ⚙️ Movement Basis:
The `PlayerMovementController` uses the camera's global yaw as the "Forward" reference. Pressing 'W' always moves the player character "away" from the camera view, regardless of where they were facing previously.

---

## 🛠️ Implementation Details

To use the camera controller in a new script:

```gdscript
var _camera_controller: OrbitCameraController

func _ready():
    _camera_controller = OrbitCameraController.new()
    add_child(_camera_controller)
    _camera_controller.setup(spring_arm, camera)
    
    # Configure for vehicles
    _camera_controller.is_auto_center_enabled = true
```

!!! tip "Input Delegation"
    In `_unhandled_input`, delegate mouse motion:
    ```gdscript
    if event is InputEventMouseMotion:
        _camera_controller.handle_mouse_motion(event.relative)
    ```
