# Executive Blueprint: Project OpenFarm Survival

## 1. The Core Vision (The Elevator Pitch)

*Project OpenFarm Survival* is an open-source, hardcore farming and survival simulator built in Godot 4. Unlike traditional farming games where money is the only goal, here, **survival is the metric**. Players must manage their personal needs (hunger, energy, health), maintain complex machinery, and build a functioning power grid to automate their agricultural empire. If the tractor breaks down, the crops die; if the crops die, the player starves.

## 2. The Four Pillars of Gameplay

Every feature we add must support one of these four pillars. If it doesn't, we cut it.

* **Pillar 1: Systemic Survival.** The player is a biological engine. Calories burned working must be replaced by calories grown. Sleep, hygiene, and body temperature matter.
* **Pillar 2: Mechanical Realism.** Vehicles aren't just fast boxes. They require fuel, oil, and parts. Pushing a tractor too hard in deep mud will burn out the transmission.
* **Pillar 3: The Grid.** A modern farm needs power. Players must wire generators, solar panels, and batteries to run water pumps for irrigation and refrigerators to keep food from spoiling.
* **Pillar 4: Open-Source Modularity.** The underlying code must be highly separated and clean, allowing the community to easily swap in new 3D models, add new crops, or write new AI routines without breaking the core game.

---

## 3. Core Game Loops

To make the game addictive, we need to design loops that keep the player engaged at different time scales.

* **Minute-to-Minute (The Action):** Driving vehicles, attaching implements, managing stamina while performing manual labor (chopping wood, carrying feed), and monitoring vehicle gauges (fuel, engine temp).
* **Day-to-Day (The Chores):** Sleeping to restore energy, eating cooked meals, feeding animals before their health drops, and ensuring the power grid has enough fuel to survive the night.
* **Season-to-Season (The Strategy):** Prepping soil, planting specific crops at the right time of year, repairing machinery during the winter downtime, and expanding the farm's infrastructure.

---

## 4. Key Systems Breakdown (The Logic Framework)

This is the actual invisible math we will be programming into Godot 4 using GDScript.

### A. The Master Clock (`TimeManager.gd`)

* **Function:** Controls the flow of time (Seconds, Minutes, Hours, Days, Seasons).
* **Interactions:** Sends signals to every other system. Dictates when crops grow, when the player gets hungry, and when engines cool down.

### B. Player Survival Stats (`SurvivalNode.gd`)

* **Calories/Hunger:** Depletes slowly over time, depletes rapidly during heavy labor (sprinting, axe swinging).
* **Hydration:** Depletes faster in hot weather. Sourced from wells or purified water.
* **Energy/Fatigue:** Determines max stamina. Restored only by sleeping in a bed.

### C. The Agricultural Grid (`FarmData.gd`)

* **Function:** A 2D array mapped over the terrain.
* **Soil States:** Tracks if a 1x1 meter tile is *Wild, Cleared, Plowed, Seeded, or Harvestable*.
* **Nutrients & Moisture:** Tracks if the tile needs water or fertilizer, directly impacting the final crop yield.

### D. Vehicle Physics & Maintenance (`VehicleSystem.gd`)

* **Physics:** Powered by the Godot Jolt plugin for stable trailer towing and implement dragging.
* **Wear & Tear:** Tracks individual part health (Engine, Transmission, Tires). Taking damage reduces vehicle efficiency or leaves it completely dead in the field.
* **PTO (Power Take-Off):** Logic that allows the tractor's engine to power attached implements (like a wood chipper or baler), consuming extra fuel.

### E. The Power & Resource Grid (`GridManager.gd`)

* **Producers:** Generators (consume diesel to produce watts), Solar Panels (produce watts during daylight).
* **Consumers:** Lights, water pumps, refrigerators.
* **Storage:** Batteries that store excess watts. If consumption exceeds production/storage, the grid trips and shuts down.

---

## 5. Development Roadmap (How We Actually Build It)

Since we are prioritizing engine logic over graphics, here is the exact order we will build the game.

* **Phase 1: The Naked Survivalist (Weeks 1-2)**
* Set up Godot 4 and the Jolt Physics plugin.
* Build the `TimeManager` clock.
* Build the player controller (a gray pill shape) with movement, stamina, hunger, and a basic interaction system (picking up a gray box "apple" and eating it to restore hunger).


* **Phase 2: The Dirt & The Seed (Weeks 3-4)**
* Implement the `FarmData` grid array.
* Create a simple tool (a gray stick) that turns a grid square from "grass" to "plowed".
* Plant a seed, tie it to the `TimeManager`, and watch a green cube (the crop) grow over several in-game days.


* **Phase 3: The Machine Engine (Weeks 5-6)**
* Build the first `VehicleBody3D` tractor (a collection of boxes and cylinders).
* Program basic driving, fuel consumption, and implement attachment physics.
* Make the tractor interact with the `FarmData` grid (plowing multiple squares at once).


* **Phase 4: Power & Livestock (Weeks 7-8)**
* Code the `GridManager` for electricity.
* Implement simple state-machine AI for a basic animal (a gray box cow that needs food and water).


* **Phase 5: Refinement & Open-Source Release**
* Clean up the code, document everything clearly, and push the gray-box framework to GitHub for modders and 3D artists to start dressing it up.