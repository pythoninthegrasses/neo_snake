# ABI header design notes

`include/neo_snake.h` is the frozen C ABI contract (TASK-023). `docs/abi-decisions.md` and
`docs/canonical-state.md` settle most of its shape; this document records the judgment calls this
header itself had to make that neither of those settle. It has **no analogue in
`reference/snake.html`** — like `docs/canonical-state.md`, this is new design for a boundary the
original single-file game never had.

## No bare C enum crosses the ABI as stored data

Every value embedded in a struct field (`ns_config.speed_source`, `ns_player_view.status`,
`ns_event.kind`, ...) is a fixed-width `typedef` (`uint8_t`/`int32_t`) with an anonymous `enum`
supplying named constants — never a real C `enum` type used as the field's type. A C `enum`'s
underlying integer width is unspecified by the language; across four toolchains touching this one
header (a C/C++ compiler for GDExtension, Zig's own C ABI translation in `core/abi.zig`, and
whatever `@cImport` produces for the Tier-C conformance tests), relying on "whatever `int` this
compiler happens to pick for an enum" is exactly the kind of landmine a contract meant to be frozen
forever cannot afford. Function parameters and return values (`ns_dir dir` as an argument,
`ns_result` as a return value) still use the named typedefs for readability — a single
by-value/by-register argument has no struct-packing ambiguity to worry about.

## `speed_source`

TASK-023's own description requires `ns_config` to carry "a speed_source policy field," with no
prior specification anywhere in `docs/abi-decisions.md`, `docs/canonical-state.md`, or
`core/world.zig`. The only speed policy that exists today is freeze #5's `TICK_PERIOD_US` table,
indexed by score — `core/world.zig`'s `tickPeriodUs(score)`. There is no second policy to choose
between yet.

Given that, `speed_source` is a one-member enum today (`NS_SPEED_SOURCE_SCORE_TABLE = 0`) rather
than an unused/absent field: it exists so a future alternative (e.g. a fixed constant-speed
practice mode, or an externally-driven speed for spectator/replay tooling) is an additive change —
a new enum value plus a branch in `core/abi.zig`, not a config layout break requiring a new
`NS_ABI_VERSION`. `ns_world_init` must reject any value other than
`NS_SPEED_SOURCE_SCORE_TABLE` with `NS_ERR_INVALID_ARGUMENT` until a second policy is actually
designed and documented here.

## How `ns_step`, `ns_queue_dir`, and `ns_pump` relate

`ns_step` is the frozen lockstep primitive name (`backlog/decisions/decision-020`), reserved for
TASK-053's netcode. `ns_queue_dir`/`ns_pump` are explicitly "layered on top as local-play
conveniences" per TASK-023's description. Working out what that layering actually means was the
main design problem this header had to solve, because `core/world.zig`'s existing, already-tested
`queueDir()`/`pump()`/`advance()` behavior has to fall out of it without changing:

- `core/world.zig`'s `advance()` has no internal status gate — it is only ever called from
  `pump()`, which gates on `status == playing` *before* calling it. `queueDir()` never calls
  `advance()` itself, even when it flips `status` from `menu`/`dead` to `playing` (the reference
  oracle's own behavior, kept verbatim per `docs/architecture.md`) — the actual first tick always
  happens on a later, separate call.
- So `ns_queue_dir` is *only* the input-legality/auto-start half of that: it updates the named
  player's queued direction (reversal-rejected, same auto-start quirk) and **never** advances a
  tick, regardless of the resulting status.
- `ns_step` is the atomic "apply this tick's inputs, then advance exactly one tick" primitive a
  netcode peer calls directly, once per confirmed simulation tick, with no accumulator involved
  (network ticks are already discrete events). Its own inputs are applied with the same
  legality/auto-start logic as `ns_queue_dir` — but critically, `ns_step` only performs the actual
  tick-advance if the world's status was **already** `playing` *before* this call's inputs were
  applied. This is what keeps "the call that starts the game from the menu" from also silently
  consuming a tick — a divergence from the oracle's behavior that would otherwise be easy to
  introduce and easy to miss.
- `ns_pump` is `core/world.zig`'s `pump()` unchanged in spirit: it gates on the world already being
  `playing`, then calls `ns_step` with an empty input list once per tick the elapsed `dt_us` and
  the `MAX_STEPS`/`MAX_DT_US` clamps allow. It never takes fresh inputs — a local game loop is
  expected to call `ns_queue_dir` from its input-handling path and `ns_pump` from its per-frame
  timing path, exactly mirroring the separation `tick_driver.gd` (TASK-031) and the input router
  (TASK-033) already assume.

A player dying or winning mid-`ns_step` is a normal simulation outcome, not a failure: it is
reported through `ns_player_view_get` and the event drain, never through `ns_result`.

## The event drain exists so consumers don't diff snapshots

TASK-041 (audio) needs to know "an eat happened" without falling into "diff two snapshots' scores
and guess how many eats happened between them," which breaks the moment more than one eat can occur
between two observed frames (exactly the catch-up/coalescing scenario `ns_pump`'s multi-step clamp
creates). `ns_event_drain` gives a consumer an explicit, ordered list of discrete events instead —
draining removes them, and anything left over after a too-small output buffer stays queued for a
subsequent call rather than being silently dropped.

## Wire-exact structs exist only where a conformance test needs to `@sizeOf`/`@offsetOf` against a real type

`ns_canon_header` (44 bytes) and `ns_player_view` (doubling as the 16-byte per-player fixed block)
are declared byte-exact to `docs/canonical-state.md` specifically because TASK-025's Tier-C
conformance tests are restricted to `@cImport(include/neo_snake.h)` alone — they cannot reach
`core/canon.zig`'s own types directly. Without a real struct declared in this header, there would
be nothing for those tests to introspect. Every other struct in this header (`ns_config`,
`ns_input`, `ns_event`) is a plain ABI-convenience type with no wire-format counterpart to match.
