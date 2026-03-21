# :terminal: Developer Console | [Home](../index.md)

The developer console provides real-time access to the simulation state and commands for debugging the application.

---

## 🏗️ Accessing the Console

!!! tip "Keyboard Shortcut"
    Toggle the console with the backtick (`` ` ``) key.

- **Command Autocomplete**: Start typing a command to see suggestions.
- **Log Observer**: View real-time system logs and simulation errors.

---

## 🛠️ Common Commands

| Command | Purpose |
| --- | --- |
| `tp <x> <y> <z>` | Teleport the player character. |
| `spawn_vehicle <spec_id>` | Spawn a new vehicle from the catalog. |
| `set_time <hour>` | Jump to a specific time of day. |
| `add_item <id> <amount>` | Add items to the player inventory. |

!!! warning "Debug Status"
    Most commands are disabled in production builds to prevent accidental cheating or state corruption.
