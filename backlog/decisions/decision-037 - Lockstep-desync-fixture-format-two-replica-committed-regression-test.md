---
id: decision-037
title: Lockstep desync fixture format -- two-replica committed regression test
date: '2026-09-14 00:00'
status: Accepted
---
## Context

TASK-054's AC ask for a checksum mismatch to be captured as a committed fixture that "then fails
[the relevant regression tier] until the underlying bug is fixed," turning every desync into a
permanent regression test the same way `task oracle:fuzz`'s promotion step (`docs/corpus-format.md`
"Promoting a fuzz failure") turns a discovered mismatch into a committed corpus trace. But the
existing oracle-corpus format (`docs/corpus-format.md`, consumed by Tier-D's
`game/tests/test_corpus_replay.gd`) is single-actor only: one shared-RNG-stream world timeline per
fixture, even when `players > 1` (still one world, not independent replicas). A lockstep desync is
inherently a two-replica artifact -- `decision-036`'s `LockstepSession` drives two independent
`LockstepPeer`/`SimulationWorld` instances that, by definition, disagree from the divergence tick
onward. There is no existing format slot for "two world states that are expected to differ," and
extending the single-actor JSONL trace schema to carry two parallel state/checksum columns would
conflate two purposes the oracle corpus deliberately keeps separate: one committed trace format
whose entire value proposition is "the checksum column is the one true answer," now made to also
represent "two answers that disagree on purpose."

## Decision

**A new, separate fixture type, not an extension of the oracle-corpus JSONL schema.** Lockstep
desync fixtures live under `game/tests/desync_fixtures/*.json` (a sibling of, not nested under,
`game/tests/corpus/`), one JSON object per fixture (not JSONL -- this is a single captured event
with two full logs attached, not a streamed per-tick trace). `LockstepSession.capture_fixture(tick,
checksum_a, checksum_b)` (the seam `decision-036`'s Consequences section named for this task) builds
the JSON-safe payload from data already owned by the session and its two peers:

```json
{
  "config": {"cols": 24, "rows": 24, "player_count": 2, "wrap": false, "rng_seed": [1,2,3,4],
             "speed_source": 0, "input_delay": 3, "checksum_interval": 30},
  "tick": 78,
  "latency_a_to_b": 1,
  "latency_b_to_a": 1,
  "peer_a": {"checksum": "5563161792446346117", "input_log": [{"tick":0,"player":0,"dir":3}, ...],
             "state_bytes": [78, 69, 79, ...]},
  "peer_b": {"checksum": "...", "input_log": [...], "state_bytes": [...]}
}
```

`capture_fixture()` itself only knows peer/session-level data (both peers' `checksum()`,
`input_log()`, `world.serialize()["bytes"]`, and the two link latencies); `config` -- the
board-construction parameters needed to reconstruct equivalent fresh worlds -- is supplied
separately by whichever caller built those worlds in the first place, since `LockstepSession` is
handed already-constructed `SimulationWorld` instances and never sees their `init()` arguments.
Checksums are stored as decimal strings, not JSON numbers, for the same reason
`docs/corpus-format.md`'s `"c"` field is a string: a `u64` checksum can exceed
`Number.MAX_SAFE_INTEGER` (2^53), and Godot's `JSON` parser produces `float` for every JSON number
(no integer type in JSON) -- round-tripping a large integer through a JSON number risks silent
precision loss that a string sidesteps entirely.

**Generation is deliberately manual and opt-in, matching `oracle:fuzz`'s promotion step exactly.**
`game/tests/test_desync_fixture.gd` reuses the exact corrupted-peer injection technique already
proven in `test_lockstep_session.gd`'s
`test_a_corrupted_remote_input_produces_a_checksum_mismatch_and_emits_desync_detected` (AC#2's "e.g."
is explicit that any concrete corruption suffices; inventing a second, novel corruption method here
would only be new surface to get wrong for no added coverage). Every ordinary `task game:test` run
re-derives the fixture live from that scenario and deep-compares it against the committed file;
setting `DESYNC_FIXTURE_REGEN=1` additionally (re)writes the committed file from that live run.
Regeneration is never a side effect of a normal test run -- the same posture
`reference/oracle/fuzz.mjs` takes (deliberately excluded from `task check`, run manually/nightly
instead).

**The committed fixture is the regression contract, not the capture mechanism's only proof of
existence.** Because the test always re-derives the fixture live and diffs it field-by-field against
the committed file, a future change to `core/world.zig`, the checksum algorithm, `INPUT_DELAY`, or
the lockstep protocol itself that alters the recorded checksums, state bytes, or input log makes this
test fail -- exactly AC#2's "fails ... until the underlying bug is fixed," verified directly: hand-
corrupting one field of the committed fixture and rerunning `task game:test` reproduces a failure
(`live desync capture no longer matches the committed fixture`), and restoring the file makes it
pass again.

## Consequences

- `LockstepSession` gained two public fields (`latency_a_to_b`, `latency_b_to_a`, stored at
  construction) and one method (`capture_fixture`) with no other behavioral change; `advance_round()`
  and the checksum-comparison cadence from `decision-036` are untouched.
- `game/tests/desync_fixtures/` is a new, permanent top-level fixture directory alongside
  `game/tests/corpus/` -- a future second desync fixture (a different corruption shape, a different
  board config) is added the same way: run the scenario once with `DESYNC_FIXTURE_REGEN=1`, commit
  the resulting file, and give it its own comparison test function (or generalize
  `test_desync_fixture.gd` to iterate a directory once there is more than one fixture to justify
  that generalization -- YAGNI for a single fixture today).
- This format has no relationship to `core/corpus.zig` or `manifest.json`; Zig's build graph never
  needs to know about desync fixtures, since nothing in `core/` consumes them -- they are purely a
  GDScript/`game/tests/`-side regression artifact.
