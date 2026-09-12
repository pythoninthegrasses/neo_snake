---
id: TASK-033
title: 'Implement platform input routing (keyboard, swipe, analog)'
status: Done
assignee: []
created_date: '2026-09-09 22:11'
updated_date: '2026-09-12 23:01'
labels: []
milestone: m-5
dependencies:
  - TASK-030
priority: medium
type: feature
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement platform/{input_router,input_defaults,swipe_gesture,analog_latch}.gd. Declare the InputMap in project.godot (not built up in code) so bindings are reviewable in a diff. Use _unhandled_input, not _input, so focused UI controls get first refusal of an event. analog_latch.gd implements 0.55 fire / 0.35 release hysteresis to avoid stick-drift double-fires. swipe_gesture.gd is pure logic with a board-scaled threshold max(24, board_px*24/520), matching the corresponding backlog/decisions/ entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 InputMap actions are declared in project.godot, not constructed at runtime in code
- [x] #2 input_router.gd uses _unhandled_input, not _input
- [x] #3 analog_latch.gd tests confirm 0.55 fire / 0.35 release hysteresis with no double-fire under stick jitter
- [x] #4 swipe_gesture.gd is pure (no Node dependency) and its threshold formula is covered by a test
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
Implemented game/platform/{input_router,input_defaults,swipe_gesture,analog_latch}.gd.

- project.godot gained an [input] section (move_up/down/left/right, pause, restart) with keyboard bindings mirroring the oracle's KEY table (arrows + WASD, snake.html:578-582) plus Space/R (snake.html:584-591) -- AC#1. Declared directly as project.godot resource literals, not built at runtime. Verified by headless `godot --import` (parses and registers cleanly) and by game/tests/test_input_defaults.gd, which asserts the loaded InputMap matches InputDefaults.ACTION_PHYSICAL_KEYCODES exactly in both directions.
- InputRouter (Node) uses _unhandled_input, not _input (AC#2), so a focused UI control gets first refusal. It emits direction_queued/pause_requested/restart_requested signals rather than calling SimulationWorld directly -- "no instant 180" reversal legality already lives in core/world.zig's queue_dir (confirmed by direct grep), so this stays a pure translation layer, matching tick_driver.gd's thin-forwarding precedent. No scene wires it up yet, consistent with every other platform/presentation script landed so far (board_view.gd, tick_driver.gd) -- that wiring is a later screens/app task's job.
- AnalogLatch implements 0.55 fire / 0.35 release hysteresis per stick axis; game/tests/test_analog_latch.gd confirms jitter anywhere between the two thresholds cannot double-fire, and that dropping below release re-arms a fresh fire (AC#3).
- SwipeGesture is a pure RefCounted port of snake.html's touchstart/touchmove/touchend (snake.html:603-618), no Node dependency (AC#4). Its threshold reuses content/tuning.json's already-wired input.swipe_threshold_cell_fraction (0.5, decision-011) as cell_px * fraction, floored at the oracle's original 24px -- reconciling this task's own inline "max(24, board_px*24/520)" suggestion with the already-accepted decision-011/tuning.json cell-fraction mechanism rather than adding a second, conflicting formula. game/tests/test_swipe_gesture.gd covers the threshold formula and all four fire directions plus the no-refire-after-consume and touchend-abandons-without-firing cases.
- DoD#2: the swipe-threshold deviation from the oracle's fixed 24px constant is already recorded in decision-011 (pre-existing); AnalogLatch's hysteresis is a wholly new capability (reference/snake.html has no gamepad support at all), so per DoD#2 there is nothing to record as a deviation -- same "no analogue" reasoning TASK-031 used for its own running/gate design.
- docs/build-layout.md updated with a new section for these four files (DoD#3).
- Verification: task extension:build, then TASK_X_ENV_PRECEDENCE=1 task check green end-to-end (oracle:verify, core:test, core:abi-header-check, core:abi-symbols, core:abitest-purity, core:abitest, core:difftest, extension:build, game:boundary-check [OK, no violations from the new platform/ files], game:import, game:test [53 test cases, 0 errors/failures/flaky/skipped/orphans across all 10 suites]).
<!-- SECTION:NOTES:END -->
