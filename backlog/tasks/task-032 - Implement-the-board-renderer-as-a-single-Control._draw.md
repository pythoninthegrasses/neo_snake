---
id: TASK-032
title: Implement the board renderer as a single Control._draw()
status: To Do
assignee: []
created_date: '2026-09-09 22:11'
labels: []
milestone: m-5
dependencies:
  - TASK-031
references:
  - reference/snake.html
priority: high
type: feature
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement presentation/board/{board_view,board_geometry,fx_state}.gd rendering the board in one Control._draw(), with statement order matching snake.html's back-to-front drawing order exactly (this is why _draw() was chosen over TileMapLayer or MultiMesh: TileMapLayer is disqualified because body colour and pad size are both continuous functions of segment index k = 1 - i/max(1,n-1), changing every tick as the snake grows, and MultiMesh is premature for ~1200 primitives). board_geometry.gd must be pure static functions with no viewport dependency, so its numbers can be pinned by tests directly. Bake the checkerboard background into a single 24x24 ImageTexture (1 draw call instead of 288 individual rect draws). Use Color8(int(...)) rather than roundi for colour channel math, matching JS |0 truncate-toward-zero semantics; draw grid lines as 1px draw_rect calls with a float Color(1,1,1,0.019), not Color8, since Color8's 0-255 quantization of 0.019 (4.845) rounds wrong.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 board_geometry.gd functions are pure static and covered by gdUnit4 tests that pin exact numbers without instantiating a viewport
- [ ] #2 The checkerboard background renders via a single baked ImageTexture, not per-cell draw calls
- [ ] #3 Segment colour math uses Color8(int(...)) and grid lines use float Color, matching the stated truncation/quantization rules
- [ ] #4 _draw() statement order matches snake.html's back-to-front layering
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->
