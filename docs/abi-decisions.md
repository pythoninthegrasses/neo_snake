# ABI decisions

Six things are frozen before any implementation work begins (Phase 4 is when `core/abi.zig` and
the GDExtension boundary get built — see the backlog milestones). Freezing them this early, before
a line of Zig or GDExtension code exists, is deliberate: everything downstream of Phase 4 —
committed oracle corpus fixtures, the GDExtension shim, save-file-adjacent tooling, and eventually
lockstep netcode — takes a byte-exact or behavior-exact dependency on these decisions. Changing any
of them later isn't a refactor, it's a breaking change that invalidates already-committed fixtures
and requires the version-bump discipline in the last section.

## 1. Multiplayer indexing with one shared RNG stream

All players draw from a **single** `xoshiro128**` stream (`docs/rng.md`), consumed in ascending
player index order when multiple draws are needed in the same tick (e.g. simultaneous food
placement). There is no per-player RNG stream.

**Why frozen now:** per-player streams look appealingly simple (each player's randomness is
independent, easy to reason about in isolation) but they make rollback netcode reconstruct-order
dependent — replaying a tick after a rollback requires re-deriving *which* stream's draw happened
at *which* point relative to the other player's actions, which turns a single deterministic replay
into an ordering problem that has to be solved again for every new multiplayer feature. One shared
stream makes "the sequence of `next()` calls up to tick N" a single, total, replayable order with
no reconstruction step. This is far cheaper to guarantee correct once, up front, than to retrofit
after `core/world.zig` and its tests already assume a particular RNG topology.

## 2. Caller-owned memory, no opaque snapshot type

The ABI never hands back an opaque handle/pointer that the caller must free through a matching
library call. State is always a plain byte buffer (the canonical format, `docs/canonical-state.md`)
that the caller allocates, owns, and frees using its own language's normal memory management. The
Zig core reads from and writes into caller-supplied buffers; it never allocates a snapshot object it
then owns the lifetime of.

**Why frozen now:** an opaque-handle ABI needs a paired alloc/free (or ref-count) protocol that
every binding (GDScript via GDExtension today, potentially others later) must implement correctly
or leak/double-free. A flat caller-owned buffer sidesteps that whole class of bug permanently and
composes trivially with the canonical format already being byte-exact and serializable — snapshotting
*is* just copying bytes, not calling into the library. Deciding this before `core/abi.zig` exists
avoids designing an allocator-ownership protocol now and discovering later it fights the
already-frozen canonical format.

## 3. The xoshiro128** PRNG

Specified fully in `docs/rng.md`: the exact `next()` step, seeding rule, and bounded-draw formula.

**Why frozen now:** every committed oracle corpus fixture (TASK-015+) is a recording of this exact
generator's output sequence. Swapping the algorithm — even to another PRNG with equivalent
statistical quality — silently invalidates every fixture generated before the swap, because the
fixtures encode *this generator's* specific output for a given seed, not "a good PRNG's" output.
There is no such thing as a small change here; any change is a breaking change requiring the whole
corpus to be regenerated (see `CORPUS_VERSION` below).

## 4. Canonical format v1

Specified fully in `docs/canonical-state.md`: the exact byte layout, field widths, and checksum
rule.

**Why frozen now:** the canonical format is the wire format every differential test (JS oracle vs
Zig core vs GDExtension-wrapped core) compares against. It is also, per freeze #2, the caller-owned
snapshot representation itself — the *only* representation of "the whole game state" the ABI
knows about. A layout change is not additive-only in the way an API often can be; because there is
no version negotiation inside a single canonical-state buffer beyond `canon_version` (a marker, not
a translator), any layout change requires every producer and consumer to move in lockstep, which is
exactly why the layout was pinned before any producer or consumer existed.

## 5. The integer tick-period table

The five-entry integer microsecond tick-period table (TASK-010 derives and commits the concrete
values into this document, alongside literal copies in the oracle and `core/world.zig`).

**Why frozen now:** `reference/snake.html`'s original tick-period formula
(`max(55, 130 / (1 + min(score,40) * 0.035))`) is a float computation. A float anywhere in the
canonical state or the fixed-timestep accumulator (`ns_pump`) breaks differential testing between
JS, Zig, and GDScript, because float arithmetic is not guaranteed bit-identical across those
runtimes for the same inputs. Evaluating the formula once, at the five score thresholds the
original formula actually changes behavior at, and committing the results as integer microsecond
constants removes floats from the hot path entirely — but only if every implementation reads the
*same* five committed integers instead of each re-deriving them (potentially with different
rounding). That requires the table to exist and be pinned before `core/world.zig`'s accumulator is
written, not after.

## 6. `NS_ABI_VERSION` / `NS_CANON_VERSION` / `CORPUS_VERSION`

Three independent version counters, each answering a different "did something break compatibility"
question:

| Version | Bumped when... | Requires downstream |
| --- | --- | --- |
| `NS_ABI_VERSION` | The C ABI surface changes: function signatures, calling convention, the semantics of an exported function (e.g. what `ns_step`/`ns_pump` guarantee about their inputs/outputs), or freeze #1/#2 themselves | Every binding (the GDExtension shim, and any future native binding) must be rebuilt and relinked against the new header (`include/neo_snake.h`); old compiled `.gdextension` binaries are not compatible with a newer/older core built against a different `NS_ABI_VERSION` |
| `NS_CANON_VERSION` | The canonical byte layout changes (`docs/canonical-state.md`): a field's width, offset, meaning, or the set of fields itself | Every reader/writer of canonical-state buffers (oracle `canon.mjs`, `core/canon.zig`, any tooling that inspects committed corpus files) must be updated together; old canonical-state buffers/files are not parseable as the new version without an explicit migration, which does not exist by default |
| `CORPUS_VERSION` | The corpus generation process changes in a way that makes previously-committed corpus fixtures no longer reproducible from their recorded seeds — this includes, but is not limited to, any `NS_CANON_VERSION` bump (fixtures are serialized in canonical format) or `xoshiro128**`/seeding change (freeze #3) | The entire committed corpus (TASK-015's seed corpus and any later additions) must be regenerated via `task oracle:regen` / `regen_corpus.mjs` (TASK-014) and recommitted; stale fixtures generated under an old `CORPUS_VERSION` must not be diffed against a newer core, since a mismatch would be a version skew, not a real regression |

These three axes are independent — a pure ABI signature change (e.g. adding a new exported
function) can bump `NS_ABI_VERSION` alone without touching `NS_CANON_VERSION` or `CORPUS_VERSION`
— but they are not symmetric: bumping `NS_CANON_VERSION` always forces a `CORPUS_VERSION` bump
(the corpus *is* canonical-format data), while the reverse is not true (a corpus regeneration
triggered by an RNG change does not itself imply the canonical byte layout changed).
