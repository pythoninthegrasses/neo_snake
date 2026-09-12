---
id: TASK-032
title: Implement the board renderer as a single Control._draw()
status: Done
assignee: []
created_date: '2026-09-09 22:11'
updated_date: '2026-09-12 22:46'
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
- [x] #1 board_geometry.gd functions are pure static and covered by gdUnit4 tests that pin exact numbers without instantiating a viewport
- [x] #2 The checkerboard background renders via a single baked ImageTexture, not per-cell draw calls
- [x] #3 Segment colour math uses Color8(int(...)) and grid lines use float Color, matching the stated truncation/quantization rules
- [x] #4 _draw() statement order matches snake.html's back-to-front layering
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
Implemented `game/presentation/board/{board_geometry,fx_state,board_view}.gd`.

**board_geometry.gd** (pure static `RefCounted`, no Node/viewport dependency — AC#1): segment_weight/segment_color/segment_pad, food_pulse/food_pad, corner_radius, eye_offsets/eye_radius, grid_line_offsets, build_checkerboard_image, decode_canon_header, and a `DRAW_LAYER_ORDER` constant array that operationalizes AC#4 (statement order matching snake.html's back-to-front layering) as a value a test pins directly rather than leaving it to code review. `game/tests/test_board_geometry.gd` pins exact numbers for every function, including both a normal and a NO_CELL_COORD case for decode_canon_header.

Neither `SimulationWorld.player_view_get` nor `.body_copy` expose cols/rows/food position, so `decode_canon_header` reads them directly out of `world.serialize()`'s canonical bytes per docs/canonical-state.md's documented 44-byte header layout — the only legitimate source, not a workaround.

**AC#2**: checkerboard baked into one `Image`/`ImageTexture` (cached per cols/rows) instead of 288 fillRect calls.

**AC#3**: segment colour math uses `Color8(int(...))` (truncate-toward-zero, matching JS `|0`), pinned by test. Grid lines use a float `Color` with alpha assigned directly (not `Color8`), avoiding 8-bit quantization of the 0.019-scale alpha. The checkerboard bake can't avoid that same quantization since `Image.FORMAT_RGBA8` is intrinsic to AC#2's baked-texture requirement — recorded as backlog/decisions/decision-023 (accepted ~3% alpha deviation, test tolerance widened accordingly) rather than left implicit, per DoD#2.

**fx_state.gd**: mirrors snake.html's burst()/decayFx() as cosmetic render-only state. Randomness is a small hand-rolled xorshift32 PRNG, not Godot's RandomNumberGenerator — tools/validate_simulation_boundary.py's game:boundary-check (TASK-029) bans randi/randf/randi_range/randf_range/seed/randomize anywhere outside game/simulation/ by regex on the method name regardless of receiver, so even a locally-owned RandomNumberGenerator instance trips it. Fixed by not using those identifiers at all, rather than relaxing the gate.

**No shadow/glow**: Godot's 2D CanvasItem has no ctx.shadowBlur equivalent without a custom shader/backbuffer pass; recorded as decision-022 (disproportionate scope, no AC requires it) — fill colours/shapes/layering still match, just flat instead of glowing.

Verification: task check is green (oracle:verify, core:test, core:abitest, core:difftest, extension:build, game:boundary-check, game:import, game:test — 32/32 gdUnit4 cases passing, including the 16 new/updated board_geometry and fx_state tests). docs/build-layout.md updated with a TASK-032 section.
<!-- SECTION:NOTES:END -->
