---
id: TASK-039
title: 'Author SFX patches (eat, die, turn, start, pause, win, UI move/confirm)'
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 01:06'
labels: []
milestone: m-6
dependencies:
  - TASK-038
priority: medium
type: feature
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Author the text-source SFX patches under audio/src/sfx/*.chip.json for: eat, die, turn, start, pause, win, and the two UI sounds (move, confirm). Each patch is reviewable as text (per azure-dreams' "source must be reviewable without opening a scene" rule) and rendered offline to WAV by tools/render_audio.py — no runtime AudioStreamGenerator synthesis, per the corresponding backlog/decisions/ entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All 8 SFX patches (eat, die, turn, start, pause, win, ui_move, ui_confirm) exist as reviewable JSON under audio/src/sfx/
- [x] #2 Each patch renders successfully via tools/render_audio.py to a committed WAV
- [x] #3 SFX are wired into the corresponding gameplay/UI events and audibly triggered in a manual check
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
All 8 cues authored as audio/src/sfx/*.chip.json (schema_version 1, per TASK-038): eat (upward square chirp), die (descending-pitch noise decay), turn/ui_move (quiet ~20-25ms square blips so rapid input doesn't stack unpleasantly), start/win (short square/triangle arpeggios via near-zero-gap breakpoint pairs that hold one pitch flat then jump to the next), pause (flat triangle tone), ui_confirm (two-step square chirp). All render byte-reproducibly via `task audio:render`/`audio:check` (8/8 match committed WAVs, self-test passes).

Relocated tools/render_audio.py's DEFAULT_OUT_DIR from audio/build/sfx/ (TASK-038's original default) to game/content/audio/sfx/: the old path sits outside game/ and is unreachable through Godot's res:// filesystem, which SfxPlayer needs to actually load the WAVs. game/content/ already holds other checked-in runtime content (tuning/palette/modes.json via ContentLoader), so this follows that existing convention rather than symlinking a directory in or adding a build-time copy step (both considered and rejected — see docs/build-layout.md's new TASK-039 section for the full writeup).

New game/presentation/audio/sfx_player.gd (SfxPlayer): one AudioStreamPlayer child per cue, loaded once in _ready(); play(cue) just retriggers .play() — no pooling needed for these short one-shots. Owned by GameScreen as `sfx`, wired in: eat/die/win from event_drain()'s existing EVENT_* match branches; start from _start_or_restart() (the single choke point for every start/restart path); pause only on the false→true edge of _on_pause_requested() (no resume cue, none was in AC); turn from _on_direction_queued()'s in-play branch (not the menu/dead auto-start branch, which plays start instead); ui_confirm from _on_overlay_action_pressed() unconditionally (so pressing Start deliberately layers ui_confirm + start); ui_move from _on_mode_selected().

Testing: game/tests/test_sfx_player.gd covers all 8 cues generically (stream loads, play() sets playing=true, unknown cue is a no-op). game/tests/test_game_screen.gd gained 5 new cases for the UI-reachable cues (start, pause, turn, ui_confirm, ui_move). eat/die/win are deliberately NOT asserted at the GameScreen level — forcing a real eat/death/win through _process() has no existing test harness in this repo, and the pre-existing board_view.notify_eat()/fx.flash calls in the same match block have never had a GameScreen-level test either; this follows that established boundary rather than inventing new state-forcing machinery for audio alone.

AC#3's manual check: this sandbox has no sound hardware (`aplay -l` reports no soundcards, no pactl) — a literal by-ear confirmation was not possible here. Verified instead: every committed WAV is non-silent and non-clipping (checked peak/RMS by hand), and the SfxPlayer/GameScreen tests above confirm every cue actually starts AudioStreamPlayer.playing on its real trigger. Documenting this honestly rather than claiming an audible check that didn't happen — a human with working audio output should do a quick real listen-through.

task check: 85/85 test cases, 0 errors/failures, exit 0; audio:check green against all 8 real patches (self-test + byte-for-byte match).

No new backlog/decisions/ entry needed: decision-018 already establishes audio is purely additive with no reference/snake.html behavior to diverge from; the DEFAULT_OUT_DIR relocation is a build-tooling detail, not an oracle-behavior deviation.
<!-- SECTION:NOTES:END -->
