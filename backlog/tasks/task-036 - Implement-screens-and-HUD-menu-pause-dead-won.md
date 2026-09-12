---
id: TASK-036
title: 'Implement screens and HUD (menu, pause, dead, won)'
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-12 23:51'
labels: []
milestone: m-5
dependencies:
  - TASK-035
references:
  - reference/snake.html
priority: medium
type: feature
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the presentation screens and HUD: menu, pause, dead, and won states. Port reference/snake.html's showOverlay() content and layout without its innerHTML-based construction (showOverlay() uses innerHTML, which is a documented XSS-shaped hazard in the original — the Godot port uses real Control nodes/scenes instead, never string-built markup). HUD reflects score, best score (per active mode, per the corresponding backlog/decisions/ entry), and status text matching S.status transitions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Menu, pause, dead, and won screens exist as real scenes/Control nodes, not string-built markup
- [x] #2 HUD score and per-mode best score update on the same transitions reference/snake.html uses
- [x] #3 Screen visibility follows S.status equivalent transitions (menu/playing/paused/dead) with a test or documented manual check per transition
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
Implemented as: game_screen_state.gd (pure GameScreenState, screen_for()/overlay_content()), hud.gd (Hud), overlay_panel.gd (OverlayPanel), game_screen.gd (GameScreen orchestrator), seed_source.gd (SeedSource.fresh(), the only randi() caller outside game/simulation/'s own boundary exemption). Tests: test_game_screen_state.gd (8 cases), test_seed_source.gd, test_game_screen.gd (11-case integration test against a real wired GameScreen, SaveStore isolated via save_dir_override). task check green (extension:build + game:import + game:test all pass, 69/69 test cases). Deviations documented in backlog/decisions/decision-024 - Screens-and-HUD-oracle-deviations-TASK-036.md: mode-select scoped to menu-only, HUD scoped to score/best/status, win/die via ABI event kind, board_view.gd's pause-vignette branch stays dead code (pause is app-level only), plain-text overlay content, and the direction-on-start-discard quirk (start()'s reset() clobbers the triggering keypress's direction, faithfully reproduced). docs/build-layout.md updated with a new TASK-036 section and an update to the TASK-035 section noting game_screen.gd is focus_lost's first consumer.
<!-- SECTION:NOTES:END -->
