---
id: TASK-044
title: Sign and notarize the macOS build
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
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
- [ ] #1 A downloaded DMG opens on a clean Mac with no Gatekeeper prompt
- [ ] #2 The embedded .framework inside the .app is independently verified as signed (codesign --verify --deep)
- [ ] #3 preconditions: fail with an actionable message when APPLE_SIGNING_IDENTITY/APPLE_API_KEY/APPLE_API_ISSUER are unset
- [ ] #4 The ephemeral keychain is cleaned up via an if: always() step even when signing fails
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->
