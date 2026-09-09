---
id: TASK-031
title: Implement simulation/tick_driver.gd with injected dt
status: To Do
assignee: []
created_date: '2026-09-09 22:11'
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
- [ ] #1 tick_driver.gd contains no calls to OS.get_ticks_usec, Time, or any other clock read
- [ ] #2 A gdUnit4 test feeds a synthetic dt sequence including a 200ms hitch and asserts the exact resulting tick count matches ns_pump's documented clamp behavior
- [ ] #3 advance_frame is a pure forwarding call to ns_pump with no additional catch-up logic layered on top
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->
