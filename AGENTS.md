# WEEDCRAFT Agent Guide

These instructions apply to the entire repository. Optimize for correct, verified progress per token: keep context small, avoid repeated exploration, and prefer one focused agent unless parallel work is clearly independent.

## Project Reality

- `GDD.md` is the product authority: WEEDCRAFT / Weed Factory is a first-person 3D voxel factory builder with deterministic single-player and cooperative simulation.
- The current repository is still largely inherited from the TRUMANCRAFT 3D voxel prototype. `project.godot`, `README_MVP.md`, `src/main.gd`, scenes, and existing tests describe that implementation state, not the final WEEDCRAFT architecture.
- Do not pretend planned factory systems already exist. For every task, distinguish current behavior from the GDD target and migrate only the requested slice.
- The product and checked-in project use Godot 4.7. Do not change the engine version unless the user explicitly requests it.
- The current main scene is `res://scenes/main.tscn`. Read only relevant GDD/README sections and inspect the real owning code before proposing changes.
- Search with `rg` and targeted file reads. Preserve user changes in the dirty worktree; never discard, overwrite, or reformat unrelated work.

## Product Invariants

- The simulation must support both single-player and coop; single-player is the same deterministic simulation with one player.
- Use a fixed simulation tick, integer/fixed-point state, stable IDs, deterministic random seeds, and explicitly ordered iteration. Never put authoritative simulation state in frame-rate-dependent Godot physics or floating-point visual code.
- The lockstep invariant is: identical ordered inputs produce an identical state hash on every peer at every tick.
- Keep simulation, presentation, input collection, networking, persistence, and data definitions separate. Godot renders and interpolates authoritative state; visuals do not decide gameplay outcomes.
- Items are tagged by product and strain/category. Recipes should be data-driven and parameterized rather than duplicated per strain.
- Transparent item tubes are discrete voxel-cell simulations; fluid networks use shared network volume; energy is global; machines and processing are physical 3D grid entities.
- The threat system is suspicion/heat and economic loss, not police combat. Do not introduce combat that contradicts the GDD.
- Art is clean, readable 3D voxel. Developer-provided meshes, materials, textures, particles, and effects must remain replaceable without simulation changes.

## Working Method

1. Identify the concrete outcome, the current implementation path, and the relevant GDD invariant.
2. Inspect callers, shared state, scenes/resources, data files, and the nearest regression test before editing.
3. Make the smallest coherent root-cause change. Reuse existing helpers and Godot-native features; do not add speculative abstractions or dependencies.
4. Do not perform a broad TRUMANCRAFT-to-WEEDCRAFT rewrite during a bounded feature task. Introduce only the seam required by the requested migration slice.
5. Keep one agent as the sole code-writing owner. Parallel agents should normally be read-only.
6. Run the narrowest relevant regression first, then broader smoke or determinism coverage when risk warrants it.
7. Report the outcome, changed files, verification performed, and real remaining migration work. Do not dump raw logs.

## Context and Usage Efficiency

- Keep prompts, summaries, and tool output concise. Return distilled evidence with file/symbol references instead of full files or logs.
- Do not repeatedly reread unchanged files or rerun passing checks without a concrete reason.
- Avoid broad recursive scans when the relevant path or symbol is already known.
- Keep the main thread focused on requirements, architectural decisions, integration, and final results. Move noisy exploration or test-log analysis to a bounded subagent only when that saves main-thread context.
- Do not manually tune context-window or compaction thresholds unless diagnosing a demonstrated problem; use Codex/model defaults.

## Subagents

- Stay single-agent for small, sequential, tightly coupled, or one-file work.
- Delegate only independent work such as mapping inherited voxel dependencies, researching Godot APIs, checking determinism risks, running targeted tests, analyzing logs, or completing a final read-only review.
- Use at most two subagents concurrently. Never allow recursive delegation; children must not spawn children.
- Give every child a narrow self-contained task, explicit paths, constraints, relevant GDD invariants, and a concise return format.
- Prefer `gpt-5.6-luna` at `xhigh` effort for exploration, tests, documentation, and routine review when explicit child routing is available. Use Sol/high only for genuinely difficult architecture, implementation, security, deterministic-networking, or final integration decisions.
- If child model or reasoning selection is unavailable, say so and avoid silently fanning out multiple expensive Sol/high children.
- When supported, use `fork_turns = "none"`; otherwise pass only the few recent turns the child truly needs. Do not copy the full parent history by default.
- Wait for completion notifications. When a timed wait is needed, use about 10 minutes; use shorter polling only for a concrete reason. Do not poll active subagents every few seconds.
- Ask children for conclusions and evidence, not narration. Close completed agent threads after collecting results.

## GDScript, Simulation, and Scene Changes

- Preserve typed GDScript and the established style in touched files.
- Do not add unrelated responsibilities to the existing large `src/main.gd`. New authoritative factory simulation should live in focused units with explicit inputs/outputs, but do not refactor untouched legacy systems merely to create a cleaner shape.
- Authoritative simulation code must not read wall-clock time, frame delta, unordered collection order, global RNG state, node transforms, or physics results.
- Use integer ticks and deterministic commands for construction, movement, machines, item tubes, fluids, power, economy, and heat. Presentation may interpolate but must never feed interpolated values back into simulation.
- When changing node paths, signals, exported properties, input actions, resources, or scene structure, inspect both scripts and `.tscn`/resource consumers.
- Avoid editing generated `.godot` content. Keep `.uid` files only when Godot generated or requires them for a real asset.
- For UI/visual changes, verify the configured 1280x720 viewport and keep visuals replaceable independently from game logic.

## Verification

- Run relevant scripts with an available Godot 4.7 executable using:
  `godot --headless --path . --script res://tests/<relevant_test>.gd`
- Existing regressions currently cover inherited voxel/gameplay systems: `tests/voxel_regression.gd`, `tests/gameplay_systems_smoke.gd`, `tests/combat_creatures_regression.gd`, and `tests/main_smoke.gd`. Use them only when the changed path still depends on those systems.
- New authoritative simulation behavior requires a deterministic regression: run identical inputs at least twice and compare final state/hash. For coop-sensitive changes, vary irrelevant presentation timing without changing the result.
- Run `tests/main_smoke.gd` when scene startup or integration changes. Add broader coverage only when the risk justifies it.
- A pre-existing, environment-dependent, or legacy mismatch is not a pass: report it precisely and distinguish it from regressions caused by the change.
- Never claim verification that was not run.

## Safety and Scope

- Ask before destructive operations, installing dependencies, changing external services, or expanding beyond the requested feature.
- Do not commit, push, publish, or rewrite history unless explicitly requested.
- Do not expose secrets or print sensitive configuration values.
