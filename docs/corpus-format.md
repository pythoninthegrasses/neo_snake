# Corpus format: command logs, JSONL traces, manifest, and `core/corpus.zig`

This is new design with **no analogue in `reference/snake.html`** (which has no recording/replay
concept at all) — same category as `docs/rng.md` and `docs/canonical-state.md`. It exists to make
`regen_corpus.mjs` (TASK-014) and the traces it produces (TASK-015) unambiguous before either is
implemented, so a from-scratch implementer has an exact schema to target rather than inventing one.

There are two distinct artifacts on either side of `regen_corpus.mjs`:

- **Command logs** — hand-authored or generator-produced *input*, committed under
  `reference/oracle/corpus/commands/`. These describe what a trace does, not what happened.
- **JSONL corpus traces** — *output*, committed under `game/tests/corpus/` (so the GDExtension
  Tier-D suite, TASK-028, can read them via `res://tests/corpus/`). These record every tick's
  checksum and periodic full state, produced by actually running a command log through `sim.mjs`.

`regen_corpus.mjs` (and `task oracle:regen`) reads every command log and (re)writes every trace,
`game/tests/corpus/manifest.json`, and `core/corpus.zig` from scratch — none of the three outputs
is ever hand-edited (TASK-015 AC#3).

## Command log format (input)

One file per trace: `reference/oracle/corpus/commands/<trace-name>.commands.jsonl`, JSONL for the
same reason the output traces are JSONL (TASK-015's description): these are review artifacts, and a
diff-unreadable format defeats the purpose of committing them at all.

**Line 1 (header), exactly once:**

```json
{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":false,"players":1,"ticks":2000}
```

| Field | Type | Notes |
| --- | --- | --- |
| `seed` | `u32[4]` | Initial xoshiro128** state `s0..s3` (`docs/rng.md`) — never a single expandable seed |
| `cols`, `rows` | `u16` | Board dimensions |
| `wrap` | `bool` | Wrap mode |
| `players` | `u8` | Player count (`>= 1`) |
| `ticks` | `u32` | **Upper bound** on ticks to simulate. `regen_corpus.mjs` stops early if `status` becomes `dead` before reaching `ticks` (death/win both set `status = "dead"` per `sim.mjs`) — a trace's actual recorded length can be shorter than its `ticks` cap. This is how a "run off the edge" or "win on full board" trace ends at the natural stopping point instead of padding with post-death no-op ticks |

**Subsequent lines, zero or more, one input event each, sorted ascending by `t` (ties broken by
ascending `p`):**

```json
{"t":5,"p":0,"in":"up"}
```

| Field | Type | Notes |
| --- | --- | --- |
| `t` | `u32` | Tick at which this input is queued — applied via the sim's `queueDir` equivalent *before* that tick's `advance()`, same as a real keypress landing between ticks |
| `p` | `u8` | Player index (`0`-based). Always present, even for single-player traces — no implicit-`p=0` special case, so single- and multi-player command logs share one schema |
| `in` | `string` | One of `"up" \| "down" \| "left" \| "right"` — the same names as `docs/canonical-state.md`'s `dir`/`next_dir` encoding, so `regen_corpus.mjs` passes this string straight to `sim.mjs`'s `queueDir` without translation |

`regen_corpus.mjs` must reject (loudly, not silently dedupe) two events at the same `(t, p)`, and
reject a file whose events are not sorted by `t` — both are authoring bugs, not something to paper
over. A hand-designed trace's events are written directly; a random trace's command log is itself
generated (by a seeded random-input generator, not `Math.random()`) and committed like any other —
"generated" and "hand-edited" are about how the *command log* was produced, TASK-015 AC#3's "not
hand-edited" is about the *JSONL trace* always being `regen_corpus.mjs`'s output, never typed by
hand even for the random traces.

## JSONL trace format (output)

`game/tests/corpus/<trace-name>.jsonl`. Restates TASK-015's description precisely enough to
implement without guessing at encodings.

**Line 1 (header), exactly once:**

```json
{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":false,"players":1,"corpus_version":1}
```

Same fields as the command log header, minus `ticks` (the trace's line count *is* its tick count)
plus `corpus_version` (the `CORPUS_VERSION` this trace was generated under, `docs/abi-decisions.md`
§6).

**One line per simulated tick, `t` from `0` up to the trace's last tick:**

```json
{"t":0,"in":[],"c":"15107102501874316122","s":"4e454f534e414b4501001800..."}
```

| Field | Type | Notes |
| --- | --- | --- |
| `t` | `u32` | Tick number, matching `docs/canonical-state.md`'s `tick` field |
| `in` | `array` | Every input applied to produce *this* tick's state, e.g. `[{"p":0,"dir":"up"}]`, or `[]` if none. Always an array (never `null`/a bare object) so single- and multi-player reader code doesn't branch on shape |
| `c` | `string` | The tick's canonical-state checksum trailer (`docs/canonical-state.md`), as a **decimal string** — the checksum is a `u64` that can exceed `Number.MAX_SAFE_INTEGER` (2^53), so a JSON number would silently lose precision; a decimal string has none |
| `s` | `string`, present only on some ticks | The full canonical-state buffer (`canon.mjs`'s `encode()` output) as a **lowercase hex string, no `0x` prefix**. Present on tick `0`, every tick where `t % 64 === 0`, and the trace's last tick — never on any other tick |

## `game/tests/corpus/manifest.json`

```json
{
  "corpus_version": 1,
  "oracle_sha256": "3f9c1a...ab12",
  "files": [
    {"name": "tail-chase", "file": "tail-chase.jsonl", "ticks": 143, "corpus_version": 1}
  ]
}
```

`files` is sorted lexicographically by `name` (determinism — TASK-014 AC#1 requires byte-identical
output across repeated `task oracle:regen` runs, and `sim.mjs`/the RNG are already fully seeded and
deterministic, so the only remaining nondeterminism to rule out is iteration order). Each entry
repeats `corpus_version` per TASK-014 AC#2's literal wording ("lists every corpus file with its
`CORPUS_VERSION`") even though a full regen always writes every file at the same version — this
guards against a future partial-regen leaving mixed versions undetected.

`oracle_sha256` (TASK-016) is a lowercase hex SHA-256 digest over the concatenated raw bytes of
every `reference/oracle/*.mjs` file — a non-recursive glob of the `oracle/` directory itself,
excluding `corpus/` (data, not source) — sorted ascending by filename, concatenated with no
delimiter between files. `task oracle:regen` computes and writes this field on every run, so it
always reflects whichever oracle source actually produced the committed corpus.

`task oracle:verify` (TASK-016) recomputes the same hash from the current working tree's
`reference/oracle/*.mjs` files and compares it against the committed `manifest.json`'s value. A
mismatch means the oracle source changed since the last `oracle:regen` and fails loudly rather than
trusting a corpus that may now silently disagree with its own generator. This closes a gap
byte-identity alone can't: an oracle edit that happens to be behaviorally inert (a comment, a
variable rename) leaves every regenerated trace byte-identical to what's committed, so a
byte-identity-only check would pass even though the source no longer matches what's recorded.
`oracle_sha256` still goes stale in that case, so `oracle:verify` still fails until `oracle:regen`
is re-run. Scoped to `manifest.json` only — `core/corpus.zig` is an unrelated comptime file listing
and doesn't need this field.

## `core/corpus.zig`

Generated-but-committed because Zig's build graph can't read JSON at graph-construction time
(TASK-014's description). `core/` currently has no scaffolding at all (no `build.zig`, Phase 3 /
TASK-017+) — so this listing is deliberately minimal: enough for a future `build.zig` to iterate a
comptime-known array of corpus files, without guessing at path-resolution or embedding conventions
that don't exist yet. Whichever Phase-3 task actually consumes this file is free to wrap or
reinterpret `entries` as needed; this file only promises a stable, sorted, byte-identical listing.

```zig
// Generated by regen_corpus.mjs — do not edit by hand.

pub const CORPUS_VERSION: u32 = 1;

pub const Entry = struct {
    name: []const u8,
    path: []const u8,
};

pub const entries = [_]Entry{
    .{ .name = "tail-chase", .path = "tests/corpus/tail-chase.jsonl" },
};
```

`entries` is sorted lexicographically by `name`, same order and same set of files as
`manifest.json`'s `files`. `path` is relative to `game/` (matching TASK-028's `res://tests/corpus/`
access), since `core/` and `game/` are sibling directories in this repo's layout.

## `CORPUS_VERSION`

A plain `u32` constant, independent of `NS_ABI_VERSION`/`NS_CANON_VERSION` (`docs/abi-decisions.md`
§6). Starts at `1` for the first committed corpus (TASK-015). Bumped whenever the corpus generation
process changes in a way that makes previously-committed fixtures no longer reproducible from their
recorded seeds — the table in `docs/abi-decisions.md` §6 is the authoritative trigger list; this
document only says where the constant lives (`core/corpus.zig`, mirrored into every trace's header
and `manifest.json`) and its starting value.
