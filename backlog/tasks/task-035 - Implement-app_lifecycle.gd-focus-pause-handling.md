---
id: TASK-035
title: Implement app_lifecycle.gd focus-pause handling
status: Done
assignee: []
created_date: '2026-09-09 22:14'
updated_date: '2026-09-12 23:16'
labels: []
milestone: m-5
dependencies:
  - TASK-034
priority: medium
type: feature
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement platform/app_lifecycle.gd, handling focus-out auto-pause. Defensively handle all four of NOTIFICATION_APPLICATION_FOCUS_OUT / NOTIFICATION_WM_WINDOW_FOCUS_OUT and their _IN counterparts, since which of these actually fire on Godot 4.7 across desktop, mobile, and web is unconfirmed at design time. This mirrors reference/snake.html's original focus-out pause behavior, extended to cover Android per the corresponding backlog/decisions/ entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 app_lifecycle.gd listens for both NOTIFICATION_APPLICATION_FOCUS_OUT/_IN and NOTIFICATION_WM_WINDOW_FOCUS_OUT/_IN
- [x] #2 A focus-out notification pauses gameplay exactly once, not once per notification type that happens to fire
- [x] #3 Behavior is verified on desktop via a test or documented manual check; Android/web coverage is documented if it cannot be automated
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
Implemented as game/platform/app_lifecycle.gd (class_name AppLifecycle extends Node), porting reference/snake.html's window-blur auto-pause (snake.html:620) onto Godot's _notification() MainLoop callback.

AC#1: _notification(what) branches on both NOTIFICATION_APPLICATION_FOCUS_OUT and NOTIFICATION_WM_WINDOW_FOCUS_OUT (and their _IN counterparts), since which pair actually fires is unconfirmed across desktop/mobile/web at design time.

AC#2: a _focused boolean ensures the focus_lost signal emits at most once per genuine focus-loss transition even if both _OUT constants fire for the same underlying event -- covered by test_both_focus_out_notifications_firing_for_the_same_transition_emits_once. The _IN notifications only reset _focused for the next transition (test_focus_in_resets_tracking_so_a_later_focus_out_fires_again confirms a later _OUT after an _IN fires again); there is no focus-regained signal, matching the oracle exactly (it has no resume-on-focus behavior, only pause-on-blur).

AC#3: game/tests/test_app_lifecycle.gd (6 test cases) calls _notification() directly with Godot's own NOTIFICATION_* constants -- the same values the engine delivers to a live node -- verifying the dedup logic on desktop without needing a real window-manager focus change. Android/web coverage is not automatable (no harness can simulate OS-level backgrounding) and is documented instead, consistent with decision-012's own note that correctness there relies on manual/platform testing.

DoD#2: no new backlog/decisions/ entry needed. decision-012 (Focus-out pause covering Android) already fully covers this task's oracle-behavior deviation (multiple platform-appropriate lifecycle signals instead of solely a blur-equivalent) -- this task implements that already-accepted decision. Linked from docs/build-layout.md's new section.

DoD#3: docs/build-layout.md updated with a new "## game/platform/app_lifecycle.gd (TASK-035)" section.

task check: full pipeline green (oracle:verify, core:test, core:abi-header-check, core:abi-symbols, core:abitest-purity, core:abitest, core:difftest, extension:build, game:boundary-check, game:import, game:test [57 test cases, 0 errors/failures/flaky/skipped/orphans across 12 suites]). Exit 0.
<!-- SECTION:NOTES:END -->
