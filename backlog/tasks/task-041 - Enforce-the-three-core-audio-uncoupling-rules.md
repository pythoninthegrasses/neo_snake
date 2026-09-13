---
id: TASK-041
title: Enforce the three core/audio uncoupling rules
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 01:53'
labels: []
milestone: m-6
dependencies:
  - TASK-040
priority: medium
type: feature
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Enforce three rules that keep audio from leaking into the deterministic core: (1) the Zig core never knows audio exists — no audio-related symbols cross include/neo_snake.h; (2) catch-up coalescing is presentation policy, not simulation policy — when ns_pump advances six ticks in one frame (e.g. after a hitch), that must produce one eat sound, not six; (3) set_replaying(true) suppresses audio entirely during replay and rollback playback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A boundary check confirms include/neo_snake.h and core/ carry no audio-related symbols
- [x] #2 A test drives six ticks in one frame and asserts exactly one eat sound fires, not six
- [x] #3 A test confirms set_replaying(true) suppresses all SFX/music triggers during a corpus replay
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
AC#1: new `tools/validate_audio_boundary.py`, wired as `core:audio-boundary-check` in `taskfiles/core.yml` (in `check:` right after `core:abi-header-check`). Strips C/Zig comments before scanning so `include/neo_snake.h`'s own "e.g. audio, TASK-041" comment about ns_event consumers doesn't trip it, then greps remaining code in `include/neo_snake.h` and `core/*.c`/`*.zig` for `audio|sound|sfx|music` tokens. A dedicated script rather than an extension of `validate_simulation_boundary.py` (TASK-029) — that tool scans the opposite direction (outside `game/simulation/`) for an unrelated concern.

AC#2: new pure static helper `AudioEventCoalescer` (`game/presentation/audio/audio_event_coalescer.gd`), `cues_for(events) -> {"eat": bool, "die": bool, "win": bool}`. `core/abi.zig`'s `ns_pump` genuinely can advance several ticks per call after a hitch (loops `stepOneTick` under the `MAX_STEPS`/`acc_us` budget), each eating tick pushing its own `NS_EVENT_EAT` — the old `GameScreen._process()` played `sfx.play("eat")` once per event, a real multi-eat-sound bug on a catch-up frame. `_process()` now calls `sfx.play()` at most once per cue per frame, gated on the coalesced result. Die/win need no coalescing: `ns_pump`'s loop already stops the instant status leaves `.playing`, so at most one appears per drain. Tested with synthetic event arrays (`test_audio_event_coalescer.gd`, 5 cases) rather than forcing a real hitch through `GameScreen` — same "no existing harness for forcing food/snake state" precedent TASK-039 already recorded in `docs/build-layout.md`.

AC#3: `set_replaying(bool)` added to both `SfxPlayer` and `MusicPlayer` (presentation-layer only); `play()`/`play(cue)` no-op while `_replaying` is true. No `GameScreen.set_replaying()` forwarding method added — no rollback/replay driver exists yet (deferred to TASK-051+ per docs/canonical-state.md), so a forwarding method with no caller would be speculative. Verified via direct unit tests on each player (`test_sfx_player.gd`, `test_music_player.gd`, +2 cases each) plus a corpus-wide integration test in `test_corpus_replay.gd`: `_replay()` gained an optional `on_tick: Callable` parameter, and a new test drives every corpus trace except the ABI-unrepresentable `win-full-board` through it with both players suppressed and an `on_tick` closure that unconditionally calls `play()` per drained event, asserting no `AudioStreamPlayer` ever reports `playing` across the whole corpus.

`task check`: green end-to-end (`task game:test`: 102/102, up from 92 — the expected +10). No `backlog/decisions/` entry needed: this task enforces existing architectural rules rather than introducing new reference/snake.html-observable behavior, same reasoning as decision-018/TASK-039/TASK-040. `docs/build-layout.md` gained a TASK-041 section covering all three mechanisms and the design choices above.
<!-- SECTION:NOTES:END -->
