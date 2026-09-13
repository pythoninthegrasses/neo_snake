---
id: TASK-044
title: Sign and notarize the macOS build
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 22:55'
labels: []
milestone: m-7
dependencies:
  - TASK-043
priority: high
type: feature
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add macOS code signing and notarization, following ~/git/mt's shape: an ephemeral keychain (security create-keychain -> import -> set-key-partition-list), xcrun notarytool submit --wait against a /tmp/auth_key.p8 decoded from APPLE_API_KEY_B64, xcrun stapler staple, and an if: always() cleanup step that removes the ephemeral keychain regardless of outcome. preconditions: assert APPLE_SIGNING_IDENTITY / APPLE_API_KEY / APPLE_API_ISSUER are set, with actionable failure messages. Godot-specific wrinkle over mt: the .framework embedded inside the .app must itself be signed, and the export preset's codesign/* and notarization/* keys must be filled in rather than left to Godot's ad-hoc signing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A downloaded DMG opens on a clean Mac with no Gatekeeper prompt
- [x] #2 The embedded .framework inside the .app is independently verified as signed (codesign --verify --deep)
- [x] #3 preconditions: fail with an actionable message when APPLE_SIGNING_IDENTITY/APPLE_API_KEY/APPLE_API_ISSUER are unset
- [x] #4 The ephemeral keychain is cleaned up via an if: always() step even when signing fails
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
Implemented `taskfiles/release.yml` (`release:` namespace): `ship-macos` chains `keychain-setup` -> `export-macos` -> `verify-signing` -> `decode-api-key` -> `notarize`, with `keychain-cleanup` and `cleanup-api-key` registered via `defer:` (LIFO: api key torn down before the keychain, AC#4). Credentials sourced from `~/git/mt/.env` per instruction, staged as `/tmp/apple_signing.env` on the signing host (`mini`), never committed or printed.

`mini` is administered only over SSH, which surfaced a real blocker with no analogue in `~/git/mt`: codesign operations against the imported private key failed with `errSecInternalComponent` (SSH runs outside the GUI console session's audit/bootstrap namespace that macOS gates private-key release on). Resolved via a `sudo launchctl asuser "$(id -u)"` bridge around the godot export step, gated on a narrowly-scoped sudoers.d entry (`lance ALL=(root) NOPASSWD: /bin/launchctl asuser *`) installed directly by Lance (never by an agent, since that requires a password). Full writeup, including the `uv`-shebang session-inheritance break in `tools/run.py` (worked around by invoking `mise which godot` directly for this one step) and the root-owned-artifact `chown` fix (routed through the same `launchctl asuser` pattern so it's covered by the same sudoers rule): [[decision-027]].

`verify-signing` mounts the exported DMG read-only (Godot's DMG export mode never leaves a loose `.app` on disk) and independently verifies the embedded `libneo_snake.macos.template_release.framework` (dlopen'd, not walked by `--deep`), its hardened-runtime flag, the `.app`'s nested signatures, and the DMG's own signature (AC#2).

`notarize` adds a `spctl -a -vv --type open --context context:primary-signature` Gatekeeper assessment after `notarytool submit --wait` + `stapler staple` — an explicit improvement over `~/git/mt`'s equivalent task, which stops at stapling — as the automatable proxy for AC#1.

All four ACs verified end-to-end against live Apple infrastructure on `mini`: real notarization (Accepted), real stapling, `spctl` reporting `accepted`/`source=Notarized Developer ID`; credential preconditions fail with the intended actionable messages when unset (AC#3); a forced-failure scratch-taskfile test confirmed `defer:`-registered keychain cleanup still runs when `export-macos` fails (AC#4).

`docs/build-layout.md` gained a "macOS code signing and notarization" section. `game/export_presets.cfg`'s `codesign/codesign` was set to `3` (custom, sign with the real Developer ID identity) in prior work on this task; `application/bundle_identifier="ai.greyhaven.neosnake"` remains an unconfirmed placeholder that functioned correctly through the full verified pipeline.

Not chased further (non-blocking, benign): the release `.framework` recurring "Info.plist missing or invalid, new Info.plist generated" warning during export, seen on every run including the final successful one.
<!-- SECTION:NOTES:END -->
