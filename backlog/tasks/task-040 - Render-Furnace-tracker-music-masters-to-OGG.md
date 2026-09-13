---
id: TASK-040
title: Render Furnace tracker music masters to OGG
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 01:37'
labels: []
milestone: m-6
dependencies:
  - TASK-039
priority: medium
type: feature
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Author chiptune music masters as Furnace (.fur) trackers and render them offline to OGG for use as Godot audio streams. Furnace version is pinned in tools/game_toolchain.lock, matching the pattern already used for the Godot binary and export templates so the rendering is reproducible across machines. Wire the rendered tracks into an audio bus layout of Master -> Music / SFX / UI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Furnace version is pinned in tools/game_toolchain.lock
- [x] #2 At least one .fur master exists under audio/src/music/ and renders to a committed OGG
- [x] #3 The Master -> Music / SFX / UI bus layout exists in the Godot project and each SFX/music stream routes to the correct bus
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
Furnace 0.6.8.3 pinned in tools/game_toolchain.lock (Linux tarball + macOS DMG, checksum-verified against GitHub's own asset digest). tools/toolchain.py/bootstrap.py/run.py extended symmetrically with the existing Godot pattern (game_tools_xdg_env() generalized from godot_xdg_env(), new furnace component/dispatch verb); `./tools/bootstrap.py game furnace` and `./tools/run.py furnace` verified end-to-end.

audio/src/music/theme.fur hand-authored against Furnace's public format spec (never copied/derived from Furnace's own bundled demo songs, which its demos/README.md states are third-party copyrighted). Verified against the real Furnace binary: -info parses, renders successfully, two renders are byte-identical (deterministic), audio is non-silent (RMS~4888) and non-clipping (peak 16383/32767), ~12.8s long.

Render invocation (no GUI/Xvfb needed for headless render, only for interactive authoring): `furnace -console -view nothing -loglevel warning -output out.wav -loops 0 in.fur`. -safemode is incompatible with -console/-output (Furnace rejects the combination); -loglevel only accepts `warning`, not `warn`.

tools/render_music.py (new, PEP 723 uv run --script, deps=[soundfile, numpy] -- this repo's first script needing non-stdlib deps) renders .fur -> WAV (via furnace) -> committed OGG (via soundfile, no ffmpeg needed). Discovered Ogg container non-determinism: two soundfile encodes of the identical WAV are never byte-identical (libogg randomizes a per-stream serial number in the container -- first diff at byte offset 15), but decoded PCM samples are bit-identical across encodes (numpy.array_equal, max abs diff 0.0). --check therefore compares decoded samples, not raw bytes.

taskfiles/audio.yml gained music-render/music-check tasks mirroring the existing render/check convention; music-check wired into the main `task check` chain (taskfile.yml) on the same precedent as game:test's bootstrapped-Godot-binary dependency.

Bus layout: game/default_bus_layout.tres (Master -> Music/SFX/UI) placed at Godot's documented default auto-load path res://default_bus_layout.tres -- no project.godot edit needed. SfxPlayer routes ui_move/ui_confirm to "UI" and the other six cues to "SFX" (new UI_CUES list, decided autonomously since the task only required correct routing to exist, not a specific split). New MusicPlayer (game/presentation/audio/music_player.gd) plays game/content/audio/music/theme.ogg looping on the "Music" bus, owned by GameScreen and started once in _ready() -- reference/snake.html has no music, so there's no oracle cue-point to gate playback on.

Tests added: game/tests/test_music_player.gd (5 cases: stream loads, loop flag set, routes to Music bus, play()/stop() actually start/stop playback) and two new cases in test_sfx_player.gd (UI-bus vs SFX-bus routing). Full `task check` run green in the task-040 worktree, including the new audio:music-check step (92 total gdUnit4 test cases passing).

No backlog/decisions/ entry needed: decision-018 already establishes reference/snake.html has no audio to diverge from, so both the music track and the bus layout are purely additive.
<!-- SECTION:NOTES:END -->
