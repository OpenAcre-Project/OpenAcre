# :mountain: Terrain3D Rendering | [Home](../index.md)

The application leverages the **Terrain3D** plugin to manage highly optimized heightmaps and material textures natively within the 3D space. 

---

## 🏗️ Terrain Management

!!! abstract "Collision & Alignment"
    The system handles map collisions, camera alignments, and live texture rendering (e.g., painting soil paths) through the Terrain3D engine integrations.

- **Heightmaps**: Optimized for large-scale maps.
- **Material Textures**: Supports multi-layer painting for diverse environments.

---

## :art: Live Texture Painting

!!! gear "SoilLayerService.gd"
    A specialized service that interacts with the Terrain3D Storage to update the control map (the "painting" layer) in real-time.

- **Plowed Fields**: When a field is plowed, the system paints a specific texture index into the storage.
- **Decoupled Logic**: The painting indices are mapped to the simulation grid logic coordinates.

!!! success "Performance Tip"
    The system uses batching to prevent individual pixel updates from overwhelming the GPU during large-scale field generation.
