# WARSEED AI Handoff

The authoritative handoff is `docs/STATUS_AND_NEXT_STEPS.md`. Read it before changing the project.

## Reproduction baseline

- Godot: `4.6.3-stable` (Windows Mono build used during development)
- Language: typed GDScript
- Rendering: GL Compatibility, 2D
- Simulation: deterministic authoritative 10 Hz
- Runtime: offline, no LLM, no cloud service, no third-party plugin
- Tests: `WARSEED tests passed: 13 suites`
- Windows debug export: `build/windows/warseed-debug.exe` (generated and ignored)

Clone and open the root `project.godot`. For command-line verification:

```powershell
& <godot-console> --headless --editor --path . --quit
& <godot-console> --headless --path . --script res://tests/test_runner.gd
& <godot-console> --headless --path . --quit-after 3
& <godot-console> --headless --path . --export-debug "Windows Desktop" "build/windows/warseed-debug.exe"
& .\build\windows\warseed-debug.exe --headless --quit-after 3
```

## Implemented

- Unified `GameCommand -> CommandValidator -> CommandQueue -> SimulationWorld -> Snapshot/Event -> Presentation` boundary.
- Point/box/shift selection, control groups, camera, minimap, move, stop, attack and attack-move.
- Grid navigation, formation slots, narrow-corridor column behavior and stuck recovery.
- Typed catalogs for five unit types, combat values and three building types.
- Authoritative projectiles, armor damage, pursuit and deterministic combat.
- Factions, buildings, ore fields, harvesting, production and faction victory state.
- Faction-scoped visibility, stale contacts and `last_seen_tick`; normal UI consumes faction snapshots.
- Task lifecycle, blocked reasons, player takeover, Agent override rejection and path-based explicit rejoin.
- Strategic develop-resource, selected-unit defend-area, attack-target and scout-area orders; pause/resume/cancel controls.
- Mission progress UI, task routes/targets/radius, ESC Continue/Exit menu.
- Rule-driven delayed enemy raid that uses only current visibility or last-seen positions.
- Data-driven Easy/Normal/Hard/Expert enemy profiles, fair-information target/route scoring, bounded pursuit, retreat hysteresis and observed-composition counters.
- Friendly industrial/battlefield authorization levels with command gating, in-game recommendations, assisted/delegated reinforcement differences, runtime explanations and basic autonomous task creation.
- Automated end-to-end slice covering develop, missile takeover/rejoin, defend, attack and mission completion.

## Important limits

This is a technical vertical slice, not the complete MVP. Production queues and building-specific catalogs, unit repair/support logistics, multi-squad task graphs, patrol/escort/hold commands, production art and real 5-8 minute playtest tuning remain.

The next priority is production responsibility/queues, shared tactical hold/patrol/escort behavior, support logistics and multi-squad task planning. Preserve the authoritative boundary and do not commit `.godot/`, `build/`, logs, screenshots or credentials.
