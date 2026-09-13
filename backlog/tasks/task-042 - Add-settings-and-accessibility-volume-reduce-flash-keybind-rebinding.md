---
id: TASK-042
title: 'Add settings and accessibility (volume, reduce-flash, keybind rebinding)'
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 02:13'
labels: []
milestone: m-6
dependencies:
  - TASK-041
priority: medium
type: feature
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a settings screen and accessibility features: volume controls per bus (Master/Music/SFX/UI), a reduce-flash accessibility gate (per the corresponding backlog/decisions/ entry, guarding the particle/flash effects), persisted mode selection, and keybind rebinding. Rebound keys are stored as stable strings (e.g. "key:KEY_UP"), not raw InputEvent serialization, so save files survive Godot engine/input-system version changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Per-bus volume sliders exist and persist across restarts via save_store.gd
- [x] #2 A reduce-flash toggle exists and, when enabled, suppresses the flash/particle effects gated by it
- [x] #3 Keybind rebinding is stored as stable strings (e.g. "key:KEY_UP"), not raw InputEvent serialization, and round-trips through save/load
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
Implemented as a v2->v3 SaveStore schema migration plus three new/extended units:

- `SaveStore` (`game/platform/save_store.gd`): SCHEMA_VERSION 2->3, adding a `settings` dict (`volume_db` per `AUDIO_BUSES`, `reduce_flash`, `keybinds`) alongside `best_scores`/`last_mode`. `_migrate_v2_to_v3()` fills in `_default_settings()`; `_normalize_settings()` defends against missing buses/actions in hand-edited or older saves the same way `_normalize_v3()` already defends `best_scores`.
- `KeybindCodec` (new, `game/platform/keybind_codec.gd`): encodes a rebound key as `"key:" + OS.get_keycode_string(keycode)` (AC#3's stable-string requirement), decodes via `OS.find_keycode_from_string()` (KEY_NONE on malformed input), and applies keybinds to the live InputMap via `action_erase_events`/`action_add_event` using `physical_keycode` to match the existing convention.
- `FxState.reduce_flash` (`game/presentation/board/fx_state.gd`): gates `burst()` and a new `trigger_flash()` (used by GameScreen's die branch) — no-ops both when true. AC#2.
- `SettingsPanel` (new, `game/presentation/screens/settings_panel.gd`): code-built Control (OverlayPanel/BoardView convention) with per-bus volume sliders, a reduce-flash checkbox, and per-action rebind buttons; pure presentation, emits volume_changed/reduce_flash_changed/keybind_changed/closed. `GameScreen`/`OverlayPanel` wire it in: a persistent "Settings" button on the overlay, `GameScreen._apply_settings()` pushing a settings dict into AudioServer/FxState/KeybindCodec and persisting via `save_store.save()`.

No new backlog/decisions/ entry: reduce-flash rationale is already covered by decision-016; volume persistence and the keybind stable-string format are both directly specified by this task's own AC text, not new judgment calls.

docs/build-layout.md updated with a new TASK-042 section covering all of the above.

Full `task check` gate passes (game:test 119/119 across 20 suites, 0 failures; oracle:verify, core:test, boundary checks, audio:check/music-check all green).
<!-- SECTION:NOTES:END -->
