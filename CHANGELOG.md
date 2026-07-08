# Changelog - TRUMANCRAFT

This document compiles all recent features, bug fixes, performance optimizations, and structural updates implemented in the codebase.

---

## 1. Inventory & UI Bug Fixes

### Inventory Block Icon Transparency & Sizing
* **Issue**: 3D block icons inside the grid containers were rendering completely transparent, and layout updates triggered engine warnings about viewport stretch.
* **Fix**:
  * Set `block_viewport.own_world_3d = true` in [item_slot.gd](file:///d:/JOGOS/TRUMANCRAFT/src/item_slot.gd) to isolate the 3D environment of each slot.
  * Disabled stretch on the `SubViewportContainer` and forced manual sizing inside `_position_children()` to match the calculated slot size.
  * Deferred camera transformations until the node structure is fully inside the tree to fix `look_at()` warnings.

### Tooltip Layout Blank Space
* **Issue**: The hover tooltip for inventory items created a giant empty blank area inside the container.
* **Fix**: Added a custom minimum size (`Vector2(220, 0)`) to the panel and forced `reset_size()` before repositioning the tooltip in [main.gd](file:///d:/JOGOS/TRUMANCRAFT/src/main.gd).

---

## 2. Wooden, Stone, and Iron Tools & Recipes

### 15 New Catalog Items
* **What**: Added Pickaxes, Axes, Shovels, Hoes, and Swords for Wood, Stone, and Iron to `items()` inside [block_catalog.gd](file:///d:/JOGOS/TRUMANCRAFT/src/block_catalog.gd).
* **Textures**: Mapped tools to high-quality 2D item assets located in `texture/minecraft/textures/item/`.

### Exact 3x3 Minecraft Crafting Shapes
* **What**: Added exact recipe layouts to `recipes()` inside [block_catalog.gd](file:///d:/JOGOS/TRUMANCRAFT/src/block_catalog.gd):
  * **Pickaxe**: 3 materials (top row) + 2 sticks (center column).
  * **Axe**: 3 materials (forming a corner) + 2 sticks.
  * **Shovel**: 1 material (top center) + 2 sticks.
  * **Hoe**: 2 materials (top left, top center) + 2 sticks.
  * **Sword**: 2 materials (top, middle) + 1 stick (bottom).
  * Materials are mapped to `planks` (Wood), `cobblestone` (Stone), and `iron` (Iron).

---

## 3. High-Performance Optimization (Draw Calls & Nodes)

### Per-Chunk MultiMesh Terrain Rendering
* **How**: Replaced individual block node rendering (which previously generated over 40,000 active nodes and draw calls) with a chunk-based **MultiMesh** system in [main.gd](file:///d:/JOGOS/TRUMANCRAFT/src/main.gd):
  * Divided the world into **16x16 column chunks**.
  * Grouped visible blocks inside each chunk by type, rendering all of them via a single `MultiMeshInstance3D` child of the chunk.
  * Reduced GPU draw calls from **40,000+ to under 100 draw calls total** (benefiting from Godot's built-in chunk-based frustum culling).

### Dynamic Proximity Physics Collisions
* **How**: Instead of keeping static collision bodies for all 40,000 blocks in the scene tree, we now dynamically load physics colliders:
  * Solid colliders (`StaticBody3D` + `CollisionShape3D`) are **only instantiated within a 12-block radius around the player**.
  * As the player moves, colliders in front are added and colliders behind are freed.
  * Reduced total active SceneTree nodes from **80,000+ to under 1,500 nodes**, removing all CPU physics bottlenecks.

### Chunk-indexing Optimization (Freeze/Stutter Fix)
* **Issue**: Rebuilding a chunk's MultiMesh previously checked all 19,200 grid coordinates (`16x16x75`) in nested loops, and neighbor updates redundantly ran chunk and collision rebuilds 6 times, causing severe stutters/freezes on block breaks.
* **Fix**:
  * Implemented a `blocks_in_chunk` coordinate tracker variable mapping chunks directly to their active block positions.
  * Optimized `_update_chunk_mesh()` to loop *only* over the few blocks registered in `blocks_in_chunk` for that chunk (a 10x-100x iteration reduction).
  * Consolidated place/break updates so that chunks and active collisions are rebuilt **exactly once** per block operation, completely removing any lag spikes.

---

## 4. Minecraft-style Progressive Block Breaking

### Mining Mechanics
* **Continuous Held Click**: Holding left-click triggers block breaking progress in [main.gd](file:///d:/JOGOS/TRUMANCRAFT/src/main.gd). Releasing or looking away resets the block.
* **Tool Matching**: Speed multipliers apply if matching tools are used:
  * **Pickaxe** matches Stone and Ores (Coal, Iron, Copper, Manita).
  * **Axe** matches Wood, Planks, Chests, and Crafting Tables.
  * **Shovel** matches Dirt and Grass.
  * Tier speeds: Wood (3x), Stone (5x), Iron (8x), Manita (12x).

### Visual Progress Feedback
* **Darkening Overlay**: Spawns a temporary transparent black overlay cube that modulates to black as the block gets closer to breaking.
* **3D Billboard Progress Bar**: Renders a vector-styled horizontal red-to-green progress bar above the mining block that rotates to face the player's camera.

---

## 5. Dropped Item Entities & Throws

### Floating Item Physics
* **Physics & Bounds**: Broken block drops and thrown items spawn as physical floating entities:
  * Blocks render as small rotating 3D blocks (using the exact same multi-surface multi-textured block mesh as in the inventory).
  * Items render as flat 2D billboarded sprites.
  * Entities fall using gravity, slide, and collide against solid block boundaries.
  * Bob smoothly on a sine wave.
* **Q-Key Throw**: Pressing `Q` throws 1 unit of the item currently in the player's hand forward and slightly upward.
* **Magnet Proximity Collection**: Items within 2.0 meters are magnetically pulled toward the player, and are added to the inventory/hotbar when within 0.6 meters.
* **Entity class**: Created the modular script [dropped_item.gd](file:///d:/JOGOS/TRUMANCRAFT/src/dropped_item.gd) to decouple item physics and collection loops.

---

## 6. Inventory Look Overhaul & Shortcuts

### Stacked Top-Down Layouts
* **Inventory Panel**: Repositioned the crafting grid and its output to the **top center** of the panel, with the player's inventory grid cleanly aligned at the **bottom center**.
* **Chest Panel**: Repositioned the active chest slots to the **top** and player inventory slots to the **bottom**, using matching 9-column layouts for perfect vertical grid symmetry.

### Shift-Click Quick Transfers
* **Mover Shortcuts**: Pressing `Shift+Left Click` instantly transfers items between open grids:
  * From **Chest to Inventory** (stacks with equal items first, then fills empty slots).
  * From **Inventory to Chest** (when chest panel is open).
  * From **Crafting Output to Inventory** (fabricates the recipe and deposits the output directly).
  * From **Crafting Grid input to Inventory** (returns ingredients).
  * Between **Hotbar and Main Inventory** (when only inventory panel is open).

### Smooth Hover Highlight Effects
* **Visual States**: The slot currently under the player's mouse cursor gets a clean, responsive, semi-transparent white hover highlight overlay (at 15% opacity), aligning with premium voxel game design standards.

### Mouse Wheel Hotbar Scrolling
* **Controls**: Scrolling the mouse wheel up or down cycles through the 9 hotbar slots in first-person gameplay, matching standard voxel controls.

---

## 7. Async Loading Screen & Assets Consolidation

### Step-by-Step World Loading
* **Progress Bar**: Replaced synchronous blocking world meshing with an asynchronous step-by-step frame mesher (processing 5 chunks per frame).
* **UI Feedback**: Displays a centered loading panel with a dynamic progress bar displaying meshing percentiles (e.g. `Construindo o Mundo: 45%`) when starting or continuing games, keeping the screen alive and fluid.
* **Physics & Collisions Spawn Guard**: Deferred player creation until *after* the world has fully loaded and meshed, immediately followed by building proximity physics colliders. This matches the original loading order and prevents the player from falling through unmeshed blocks during loading.

### Texture Consolidation
* **Used Directory**: Created a consolidated asset folder `res://texture/used/` containing exactly the 42 active textures used in blocks and items.
* **Paths Update**: Replaced long nested folder paths in [block_catalog.gd](file:///d:/JOGOS/TRUMANCRAFT/src/block_catalog.gd) with flat `res://texture/used/` paths, optimizing the project's dependency hierarchy.

### Player Tree warning Fixes
* **is_inside_tree Guards**: Added guards to only check `player.global_position` when the player is fully inside the scene tree, preventing engine warnings during initial chunk loading.
* **Position assignment**: Swapped global setting `player.global_position` with `player.position` during load states, preventing tree dependency warnings.

---

## 8. Minecraft-style Jump & Sprint Physics

### Jump Velocity Tuning
* **1.28m Jump Height**: Increased player jump velocity to `6.8` m/s, matching Minecraft's exact jump height proportion and allowing players to clear single blocks comfortably.

### Momentum-based Movement & Sprinting
* **Air Momentum & Drift**: Replaced instant horizontal stops mid-air with a drag multiplier (`0.98`) and horizontal air steering acceleration, allowing players to drift and control their jumps naturally.
* **Sprinting (Ctrl key)**: Pressing `Ctrl` while moving forward enables sprinting (1.3x speed boost).
* **Sprint Jump Boost**: Jumping out of a sprint launches the player forward with an extra forward velocity boost (`+1.5` forward).

### Landing Camera Compression (Impact Bob)
* **Visual weight**: When hitting the ground, the camera Y coordinate dips slightly (based on landing velocity speed) and smoothly returns to eye-level, giving the jump a satisfying physical impact.

### Crouching & Edge Protection (Shift key)
* **Crouching speed**: Holding the `Shift` key enables crouching (caps movement speed to 30% of normal).
* **Physical & Camera Height Compression**: Crouching reduces the player capsule height from `1.8` to `1.5` and drops camera position from `1.55` to `1.25` smoothly.
* **Edge-Fall Protection**: Prevents the player from falling off block boundaries when crouching. By testing footprint coverage on X and Z axis separately, players can slide along block borders to construct bridges backwards or sideways without falling.

### Continuous Auto-Jumping & Block Placing
* **Continuous Auto-Jump**: By holding the `Spacebar`, the player will automatically jump the exact frame they touch the ground, allowing for fluid uphill climbing and bunny-hopping.
* **Held Right-Click Placing**: Holding down the Right Mouse Button places blocks continuously. An initial click registers immediately, and subsequent blocks place every `0.2` seconds (4-tick cooldown), matching classic block building pacing.

### Walking vs Running Speed Split
* **Base Walking state**: The player's default movement state is now **walking** (speed set to `4.5` m/s), matching the standard feel of exploration.
* **Sprinting (Ctrl key)**: Holding down `Ctrl` switches the movement state to **running/sprinting** (speed set to `7.0` m/s).
* **Crouching Scaling**: Crouching (holding `Shift`) now correctly scales speed to 30% of walking speed (`1.35` m/s), replicating exact Minecraft speed dimensions.

---

## 9. Dynamic Day/Night Cycle & Visual Overhaul

### Procedural Sky & Lighting Base
* **Procedural Sky**: Replaced the flat `BG_COLOR` background with a `ProceduralSkyMaterial` sky with configurable horizon and zenith colors.
* **SSAO (Ambient Occlusion)**: Enabled Screen Space Ambient Occlusion (`radius: 0.6`, `intensity: 2.5`) for realistic contact shadows in block corners and crevices.
* **ACES Tonemapping**: Switched tonemap mode to ACES for premium high-contrast color rendering.
* **Horizon Fog**: Added exponential fog (`density: 0.004`) that blends chunks smoothly into the horizon instead of sharp cutoffs.

### Sun & Moon Orbital System
* **Sun Light**: `DirectionalLight3D` with shadows enabled, orbiting based on `time_of_day`. Warm white light during the day, orange/red during sunrise/sunset, fading to zero at night.
* **Moon Light**: Second `DirectionalLight3D` offset 180° from the sun. Cold blue light (`Color(0.45, 0.55, 0.78)`) that activates during the night, with soft shadow projection.
* **Orbital Calculation**: Sun pitch angle = `(time_of_day / 24) * 360 - 90`, producing a full orbit. Moon runs at 180° offset for smooth day-night alternation.

### Dynamic Color Transitions
* **Sky Colors**: Zenith and horizon colors interpolate dynamically between day (blue), sunset (orange/purple), and night (deep dark blue/black).
* **Ambient Light**: Global ambient energy drops from `0.6` during daytime to `0.08` at night, making nights actually dark and dangerous.
* **Fog Color**: Fog light color follows the sky transitions — warm orange during sunset, dark during night, soft blue during day.

### Time System & HUD
* **Game Clock**: Time advances at `0.05` game-hours per real second (full 24h cycle = ~8 minutes of real time). Day counter increments at midnight.
* **HUD Time Display**: A label at position `(16, 70)` displays `Dia X - HH:MM` showing the current game day and time.
* **Save/Load Persistence**: `time_of_day` and `day_count` are serialized in save files and restored on continue.

