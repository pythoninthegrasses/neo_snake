---
id: TASK-031
title: Implement simulation/tick_driver.gd with injected dt
status: Done
assignee: []
created_date: '2026-09-09 22:11'
updated_date: '2026-09-12 22:24'
labels: []
milestone: m-5
dependencies:
  - TASK-030
priority: high
type: feature
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement tick_driver.gd as a RefCounted that never reads a clock itself: advance_frame(world, raw_frame_ms, running, gate) forwards the given dt straight to ns_pump. Explicitly not _physics_process (variable step re-read after each tick, engine-owned catch-up cap, forces the sim to be a Node) and not a Timer (no accumulator — it discards the remainder, so a 200ms hitch would yield 1 tick where the original yields 3). application/run/delta_smoothing must stay false or the ns_pump 64ms clamp measures a smoothed number instead of the real frame time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tick_driver.gd contains no calls to OS.get_ticks_usec, Time, or any other clock read
- [x] #2 A gdUnit4 test feeds a synthetic dt sequence including a 200ms hitch and asserts the exact resulting tick count matches ns_pump's documented clamp behavior
- [x] #3 advance_frame is a pure forwarding call to ns_pump with no additional catch-up logic layered on top
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Implementation

`game/simulation/tick_driver.gd` (`class_name TickDriver`, `RefCounted`):
`advance_frame(world: SimulationWorld, raw_frame_ms: float, running: bool, gate: bool) -> Dictionary`.
No clock read, no world/game-state introspection — `running` and `gate` are both caller-supplied
preconditions. Either being false returns `{"result": SimulationWorld.OK, "steps": 0}` without
calling `world.pump()` at all, discarding that frame's dt outright rather than banking it for a
later call. Otherwise converts `raw_frame_ms` to integer microseconds
(`int(round(raw_frame_ms * 1000.0))`) and forwards straight to `SimulationWorld.pump(dt_us)`
(`ns_pump`) — no loop, no additional catch-up logic (AC#3).

## `running` vs `gate` — a mechanism decision with no oracle analogue

The task description's signature (`advance_frame(world, raw_frame_ms, running, gate)`) names both
parameters but doesn't define them further, and nothing elsewhere in the repo (docs/abi-header.md,
docs/architecture.md, other TASK-03x descriptions) pins down what they mean. Decided: two
independent boolean preconditions rather than one combined flag, matching this codebase's existing
"inject everything, read nothing ambient" style (the same principle "with injected dt" already
names in this task's own title):
- `running` — whether the app/scene tree is currently processing frames at all (false while
  engine-paused, e.g. a modal settings/quit overlay TASK-042 will add).
- `gate` — whether the game's own state currently permits ticking (e.g. world status is playing).

Both being caller-supplied (rather than tick_driver peeking at `world.player_view_get()` or
`get_tree().paused` itself) keeps `advance_frame` fully pure plumbing with no world/engine
introspection of its own, consistent with "never reads a clock itself" extended one step further.
This is a new abstraction with no `reference/snake.html` analogue (the oracle reads
`performance.now()` and the DOM `blur` event directly in its own `frame()` loop, since it has no ABI
boundary to keep pure across) — not a behavioral deviation from the oracle's simulation logic, so no
new `backlog/decisions/` entry: the actual accumulator/clamp math is unchanged from `ns_pump`
(already decided, `docs/abi-decisions.md` freeze #5), only the Godot-side plumbing around it is new
design, the same category `docs/abi-header.md`'s own "no analogue in reference/snake.html" sections
already cover without a decision entry each.

## Verification

`game/tests/test_tick_driver.gd`: `test_advance_frame_never_reads_a_clock` greps the source text for
`OS.get_ticks`/`Time.get_ticks`/`Time.get_unix_time` (operationalizes AC#1 rather than leaving it to
code review alone). `test_advance_frame_matches_ns_pumps_clamp_behavior_across_a_hitch` drives a
real `SimulationWorld` (score 0, so `TICK_PERIOD_US[0]` = 130000us) through a synthetic per-frame
sequence including a 200ms hitch (clamped to `MAX_DT_US` = 64000us) and two frames gated closed
(`running=false`, then `gate=false`), asserting the exact tick count at every step. The hitch's
clamped contribution and the 62000us carried remainder are chosen to match
`core/world.zig`'s own already-verified `"pump clamps to MAX_STEPS per call and carries the
remainder over"` test numbers exactly, rather than inventing new arithmetic — and the two
gated-closed frames are proven non-leaking by the final two real frames landing on an exact
zero-remainder tick boundary that only holds if no discarded dt was silently banked. A final
`player_view_get(0).score == 0` check guards against the fixed seed having eaten food mid-test,
which would have (invisibly) changed the tick period partway through and invalidated the arithmetic.

`task check` green in a fresh worktree (`extension:build`, `game:boundary-check`,
`game:import`, `game:test`: 16 test cases, 0 failures across 5 suites).

## Docs touched

- `docs/build-layout.md`: new `game/simulation/tick_driver.gd (TASK-031)` section.
- `docs/architecture.md`: cross-reference from the oracle's own accumulator description to
  `tick_driver.gd`/`ns_pump`, mirroring the TASK-030 precedent of pointing the oracle-architecture
  doc at its Godot-side successor rather than duplicating the description.
<!-- SECTION:NOTES:END -->
