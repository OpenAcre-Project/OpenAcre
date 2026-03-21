# :window: UI Architecture | [Home](../index.md)

To maintain a clean separation between the 3D world and the user interface, the project strictly enforces an event-driven UI pipeline: **Headless Data -> Signal Bus -> UI/Visuals**.

---

## :broadcast: The EventBus Singleton

!!! gear "Central Nervous System"
    An Autoload `EventBus.gd` serves as the central bridge between logic and visuals.

- **Data/Logic Nodes**: (like `SimulationCore`, `PlayerInteractionController`) *emit* signals. They never reference the UI directly.
- **Visual Nodes**: (like `ToolUI`, `MasterUI`) *listen* to this bus and react.

---

## :desktop: MasterUI
`MasterUI` is a global Autoload (`CanvasLayer`) that completely decouples the interface from the local Player node.

!!! info "Responsive Zoning"
    It uses Godot's `MarginContainer` and `VBoxContainer` elements to create strict layout zones (Top-Left, Bottom-Right, etc.), preventing text overlap and ensuring responsive anchoring.

### Components
UI elements are broken down into isolated components instantiated into the `MasterUI` zones:
- `TimeUI`: Listens to **[TimeManager](../systems/day_night_cycle.md)**.minute_passed and updates the time display independently.
- `ToolUI`: Listens to `EventBus.player_tool_equipped`.
- `HelpUI`: Contextual control lists bound to the UI toggle keys (Default: F1).

---

## :eye: Contextual Interaction (Hover)

Instead of casting a ray exclusively on click, the `PlayerInteractionController` continuously casts a hover physics-raycast periodically. When it hits a valid object, it emits `EventBus.update_crosshair_prompt("Interact [E]")`. The UI center container passively displays this.

---

## :bug: Debugging Ecosystem

!!! success "Plug-and-Play Debugging"
    The system supports a fully dynamic debug overlay that can be toggled via project settings or the developer console.

- **[Developer Console](../dev/developer_console.md)**: Toggled with the backtick (`` ` ``) key.
- **Simulation Debug Overlay**: A deep simulation observer (chunk grid stats, current physics raycast targets, etc.). It is dynamically injected into the `MasterUI` and can be completely excluded in production builds.
