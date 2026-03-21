# :clock1: Day/Night Cycle | [Home](../index.md)

The Day/Night cycle in Open Farm is split into a logical simulation (tracking time) and a visual controller (animating light and environment).

---

## :timer_clock: Logical Simulation

!!! abstract "TimeManager.gd"
    A headless Autoload that manages the passage of time. It is the authoritative source for the current game hour and minute.

- **Signals**: Emits `minute_passed(total_minutes)` and `day_passed(total_days)`.
- **Speed**: Time scale can be adjusted dynamically for fast-forwarding or sleeping.

---

## :sunny: Visual Controller

!!! success "DayNightController.gd"
    A world-space actor that listens to the `TimeManager` and rotates the `DirectionalLight3D` (Sun) and updates the `WorldEnvironment`.

### Key Features:
- **Sun/Moon Orbit**: Rotates the sun based on the 24-hour clock.
- **Environment Blending**: Smoothly transitions between day and night skybox settings.
- **Performance**: Only updates the environment energy and colors when significant time has passed to save CPU cycles.

!!! warning "Visual Sync"
    Ensure the `DayNightController` is present in the `WorldMap.tscn` to witness the visual transitions. Without it, the time will still pass logically but the world will remain static.
