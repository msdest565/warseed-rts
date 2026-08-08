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
- Harvesters reject active attack orders and retaliate only against visible in-range units currently attacking them; starter and newly produced harvester input paths are regression-tested.
- Factions, buildings, 10000-primary/8000-expansion ore fields per side, harvesting, production and faction victory state.
- Building-specific production catalogs, five-item FIFO queues, full/partial cancellation refunds and editable production rally points.
- One-second bilingual cursor-following descriptions for units, buildings and ore fields.
- Faction-scoped visibility, stale contacts and `last_seen_tick`; normal UI consumes faction snapshots.
- Task lifecycle, blocked reasons, player takeover, Agent override rejection and path-based explicit rejoin.
- Strategic develop-resource, selected-unit defend-area, attack-target and scout-area orders; pause/resume/cancel controls.
- Mission progress UI, task routes/targets/radius, ESC Continue/Exit menu.
- Rule-driven delayed enemy raid that uses only current visibility or last-seen positions.
- Data-driven Easy/Normal/Hard/Expert enemy profiles, fair-information target/route scoring, bounded pursuit, retreat hysteresis and observed-composition counters.
- Friendly industrial/battlefield authorization levels with command gating, in-game recommendations, assisted/delegated reinforcement differences, runtime explanations and basic autonomous task creation.
- Friendly autonomous battlefield decisions every five ticks, with reachable frontier scouting, concurrent scout/defense ownership, emergency base defense, observed-contact counterattacks and explicit same-Agent task replacement.
- Autonomous scouts evade nearby visible contacts through legal stop/move commands, never convert reconnaissance into an attack, and resume frontier scouting after reaching safety.
- Contact presentation distinguishes surviving last-seen intelligence silhouettes from confirmed wrecks, with minimap pings and bilingual alerts; observer loss cannot turn every hostile into a death marker.
- Under full takeover, Strategic Headquarters is the sole proactive production planner. It deduplicates cross-domain commitments, exposes pending/reserved/available ore, prioritizes economic recovery, releases the 400-ore reserve only for visible base threats, leaves one production slot for the player and applies bounded observed-composition adjustments.
- The bottom General Staff selector directly issues balanced, economy-first, defensive or offensive takeover directives. A directive enables both friendly supervisors at autonomous authority, safely replaces old proactive battlefield tasks, adjusts force targets, and changes whether distant contacts trigger defense or attack.
- Friendly attack tasks investigate the target's last confirmed position after visibility loss, reacquire through legal attack commands, and terminate after a bounded search instead of stalling or reading hidden truth.
- Proactive development tasks execute harvesting and verify production instead of competing with Headquarters; explicit player development can still request a harvester and automatically resumes after a temporary resource or production block.
- Presentation targets 120 FPS with VSync while authoritative simulation remains 10 Hz; proxy/HUD synchronization occurs once per new snapshot and render frames perform interpolation only.
- First-tick formation target assignment, independent mixed-range firing, bounded stationary repathing, stalled-scout replanning and cleanup of empty temporary formations.
- Automated end-to-end slice covering develop, missile takeover/rejoin, defend, attack and mission completion.

## Important limits

This is a technical vertical slice, not the complete MVP. Unit repair/support logistics, multiple combat squads and general task graphs, patrol/escort/hold commands, construction/repair commitments, cancellable multi-step production plans and real 5-8 minute playtest tuning remain.

The next priority is shared tactical hold/patrol/escort behavior, support logistics, resource reservation priorities and multi-squad task planning. Preserve the authoritative boundary and do not commit `.godot/`, `build/`, logs, screenshots or credentials.
