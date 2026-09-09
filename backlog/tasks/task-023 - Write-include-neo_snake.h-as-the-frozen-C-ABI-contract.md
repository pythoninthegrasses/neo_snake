---
id: TASK-023
title: Write include/neo_snake.h as the frozen C ABI contract
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
labels: []
milestone: m-4
dependencies:
  - TASK-009
  - TASK-022
documentation:
  - docs/abi-decisions.md
  - docs/canonical-state.md
priority: high
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hand-write include/neo_snake.h and review it as an API, not an afterthought. Must carry: ns_config (with abi_version, player_count, rng_seed[4], speed_source policy); ns_world_size/ns_world_align/ns_world_init/ns_world_reset (deliberately no ns_world_destroy — adding one later is additive, removing one later is not); ns_step as the lockstep primitive with ns_queue_dir/ns_pump layered on top as local-play conveniences; per-player POD view structs read via ns_player_view_get (present even at player_count == 1, per the multiplayer-shaped-ABI decision in docs/abi-decisions.md); ns_body_copy using a length-then-copy two-call contract; an explicit ordered event drain (not snapshot diffing); and ns_serialize/ns_deserialize/ns_checksum. All _pad fields must be named and specified-zero.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ns_player_view_get exists and is exercised even when player_count == 1
- [ ] #2 ns_world_destroy does not exist anywhere in the header
- [ ] #3 Every _pad field is explicitly named and documented as specified-zero
- [ ] #4 The header is reviewed against docs/abi-decisions.md's six freezes before being merged
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->
