---
id: decision-001
title: Pin godot-cpp to a master commit SHA, not a tag
date: '2026-09-09 22:54'
status: Accepted
---
## Context

TASK-004 vendors `third_party/godot-cpp` as a git submodule to build the
GDExtension boundary against Godot 4.7.1-stable. godot-cpp's tagged releases
track Godot's stable branches (`godot-4.5-stable` is the newest tag at
execution time, verified via `git ls-remote --tags`); 4.7 API bindings exist
only on `master`. This is a toolchain/build-dependency choice, not a change to
`reference/snake.html`'s observed gameplay behavior, but `backlog/decisions/`
is the only decision-log convention this repo has, so it is recorded here per
TASK-004's Definition of Done rather than left implicit.

## Decision

Pin `third_party/godot-cpp` to master's commit `6cceaf6a5f8b0d78ac5d71c139fd7fabba43b918`
(detached HEAD), not a floating branch or a tag. The SHA is re-verified live at
each pin-bump (`git ls-remote --tags`/`--heads`) rather than trusted from any
other source. `tools/game_toolchain.lock`'s `GODOT_CPP_COMMIT` is the single
source of truth for this pin; the submodule gitlink and the lock entry are
updated together whenever the pin changes.

## Consequences

Bumping godot-cpp requires an explicit, reviewed pin change (edit the lock
file, `git -C third_party/godot-cpp checkout <new-sha>`, rebuild, commit) —
never an implicit `git submodule update --remote`. Once a `godot-4.7-stable`
tag is published upstream, a follow-up task should re-evaluate switching to
tag-tracking, but that is not required by this decision.
