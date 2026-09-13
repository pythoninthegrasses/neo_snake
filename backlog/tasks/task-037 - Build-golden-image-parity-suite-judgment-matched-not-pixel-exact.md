---
id: TASK-037
title: 'Build golden-image parity suite (judgment-matched, not pixel-exact)'
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 00:39'
labels: []
milestone: m-5
dependencies:
  - TASK-036
references:
  - reference/snake.html
priority: medium
type: feature
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a non-headless golden-image parity suite, run under xvfb-run, comparing the Godot game against captures from reference/snake.html. Documented explicitly as judgment-matched review, not an exact-pixel assertion, since shadowBlur (canvas Gaussian glow) and StyleBoxFlat's integer corner radii are already registered as accepted, permanent visual divergences in backlog/decisions/ rather than bugs to chase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Capture tooling produces comparable screenshots from both reference/snake.html and the Godot build for the same game states
- [x] #2 The suite runs headless-adjacent via xvfb-run in task check or a documented separate task
- [x] #3 The comparison methodology and its judgment-matched (not pixel-exact) nature is documented, cross-referencing the shadowBlur and corner-radius decision entries
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
Capture tooling: tools/capture_parity.sh + taskfiles/parity.yml (task parity:capture), Linux-only, not part of `task check` (same "documented separate task" precedent as oracle:fuzz). Uses the sway+wtype+grim headless-Wayland stack proven in ~/git/zelda3's task-005 in place of xvfb-run, since this machine is Wayland-native with no Xvfb -- see backlog/decisions/decision-025.

Godot's own menu/playing/paused/dead states are driven by a small debug-only hook in game_screen.gd (_maybe_drive_capture_state(), gated behind --capture-state=), calling GameScreen's own already-tested handlers directly, because real wtype key injection reaches Godot's Wayland thread (confirmed via WAYLAND_DEBUG=1) but never changes game state -- a Godot/Wayland-backend-specific bug, not a wtype problem (wtype works fine against Firefox and zelda3's SDL2 app). The oracle side (reference/snake.html, never edited) is driven by real wtype key injection into a fresh Firefox instance per state.

Comparison methodology and the accepted shadowBlur/corner-radius divergences are documented in docs/build-layout.md's new TASK-037 section, cross-referencing decision-006/007/022.

task check: 77/77 test cases passed, 0 errors/failures.
<!-- SECTION:NOTES:END -->
