# WARSEED AI Handoff

This file is the short English entry point for an AI that cannot read Chinese immediately. The authoritative handoff is `docs/STATUS_AND_NEXT_STEPS.md`.

## Current state

WARSEED is a Godot 4.6.3 stable Mono, typed GDScript, Windows-first 2D RTS project. The engine executable is:

`D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64_console.exe`

The repository already has:

- Godot project bootstrap and ignored `.godot/` / `build/` output;
- a successful headless editor import;
- a successful Windows debug export and exported executable startup;
- a typed command boundary: `GameCommand -> CommandValidator -> CommandQueue`;
- a deterministic 10 Hz `SimulationWorld`;
- `WorldSnapshot` and basic simulation events;
- one visible primitive-drawn vehicle (`EntityId = 1`);
- left-click selection and right-click movement;
- snapshot-driven presentation interpolation and debug HUD;
- an independent logic grid and `AStarGrid2D` static-obstacle navigation;
- structured `PATH_UNAVAILABLE` rejection and visible planned routes;
- five authoritative units with stable formation slots;
- deterministic separation, stuck recovery, and narrow-passage column degradation;
- path-history column following that avoids obstacle-corner deadlocks in both travel directions;
- immediate same-frame pending-intent feedback and deterministic repeated-click supersession;
- static path caching with revision invalidation;
- immutable formation snapshots and visible formation mode/slot debug state;
- camera pan/zoom with shared screen/world coordinate conversion;
- point/box/Shift selection and numeric control groups;
- formation-atom selection with deduplicated authoritative movement commands;
- an expanded 96x64-cell / 3072x2048 authoritative test arena;
- authoritative `StopCommand` and movement-intent `AttackMoveCommand`;
- a bottom-right snapshot-driven minimap with obstacle/friendly blips and camera navigation;
- player-accessible X Stop and T AttackMove targeting controls;
- a minimal authoritative combat loop: formation attack commands, fixed-tick range/cooldown/damage resolution, destruction tombstones and combat events;
- one visible enemy target with snapshot-driven faction colors, health bars, target line, wreck state and minimap blip;
- typed combat data for health, armor, attack power, range, fire rate and projectile speed;
- authoritative projectile snapshots with visible flight, armored impact damage and deterministic IDs;
- explicit attack pursuit plus AttackMove automatic acquisition, engagement and route resumption;
- fullscreen startup with a compact click-through combat HUD anchored at the top-right;
- a project-owned headless runner with nine passing suites;
- deterministic simulation/path/command/event metrics and host-only tick timing diagnostics;
- a typed `UnitDefinition` Resource plus committed `.tres` catalog validation spike.

Last known test output:

`WARSEED tests passed: 4 suites`

Generated outputs exist under `build/windows/` but are ignored and must not be committed.

## User expectation

The user wants the AI to keep implementing the entire planned MVP autonomously, with no need for the user to supervise every command. Do not stop after writing code. For each increment, run headless parsing, the project test runner, the real graphical game, the new interaction path, export, and the exported executable. Fix failures and continue until the current roadmap exit condition is actually met.

Do not ask for routine approval. Ask only for product scope changes, engine/architecture changes, credentials, external publication, paid or unclear-license assets, or destructive Git actions.

## Architecture rules

`SimulationWorld` is the only authoritative battle state. Godot nodes, HUD, animation, input, and agents must not directly modify position, health, resources, tasks, or control ownership.

All UI and future Agent actions must use:

`GameCommand -> CommandValidator -> CommandQueue -> SimulationWorld -> SimulationEvent/WorldSnapshot -> Presentation`

MVP is offline and does not depend on an LLM. Keep typed GDScript. Keep the exact Godot patch locked. Do not enable Git LFS yet.

## What remains

The current slice is not the complete MVP. Continue in this order:

1. Phase 1 technical baseline is closed. Begin the manual RTS prototype: camera, box selection, control groups, `StopCommand`, `AttackCommand`, and `AttackMoveCommand`.
2. Build the manual RTS prototype: camera, box selection, control groups, stop/attack/attack-move, five unit types, three buildings, ore economy, production, construction, repair, combat, fog of war, victory conditions.
3. Build task/control ownership: strategic goals, task lifecycle, player takeover, no Agent override during takeover, explicit rejoin modes, safe rejoin points, task recovery and visible obstruction reasons.
4. Build the three high-level commands: develop mining, hold area, attack target, with Industrial Director, Battlefield Commander and Chief of Staff roles.
5. Add information boundaries and rule-driven enemy AI, then complete the 5–8 minute vertical slice including missile vehicle takeover and rejoin.
6. Only after Gate G passes, expand to the 15–20 minute full MVP, deputy mode, teaching, balance, CI and release quality.

Read `docs/ROADMAP.md`, `docs/TECHNICAL_PLAN.md`, `docs/SYSTEM_DESIGN.md`, `docs/MVP_SCOPE.md`, and the full Chinese handoff for exact exit criteria.

## First actions

1. Preserve the current uncommitted worktree; do not reset it.
2. Run the known Godot import, tests, headless launch, export, and exported-exe commands.
3. Start camera pan/zoom and point/box selection while preserving snapshot-based coordinate conversion.
4. Add direct Stop/Attack/Attack-Move commands through the shared authoritative pipeline.
5. Continue autonomously and update `docs/STATUS_AND_NEXT_STEPS.md` after each verified increment.
