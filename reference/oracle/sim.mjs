// Headless simulation oracle — the DOM-free extraction of `reference/snake.html`'s
// queueDir() / reset() / placeFood() / advance() / frame() logic. This is the
// pre-port reference the Zig core is differentially tested against, so the
// statement order below mirrors the oracle line-for-line: the `advance()`
// order (input commit -> move -> collision against the tail minus the cell it
// is about to vacate -> unshift/pop) is load-bearing, and the oracle's
// registered quirks (decision-015's menu-direction overwrite) are faithful
// behavior, not bugs to fix here.
//
// Divergences from the oracle, each forced by the headless context and
// covered by an existing record rather than left implicit:
//   - `Math.random()` in placeFood() is replaced by the seeded xoshiro128**
//     stream from rng.mjs via boundedDraw (decision-003; draw order per
//     docs/rng.md "Food placement").
//   - `best` (localStorage) and the eat-flash/best-score bookkeeping are
//     dropped — presentation/persistence state with no canonical byte in
//     docs/canonical-state.md.
//   - Presentation extras with no canonical state — flash, particles/burst,
//     the overlay/HUD sync, and the blur-to-pause listener — have no analogue
//     here.
//
// `advance(S)` is the primary entry point: a true single simulation step.
// `step(S, now)` is `frame()`'s accumulator loop as a pure function of
// (state, timestamp) -> state, driven by a caller-supplied clock (no clock, no
// renderer of its own).
//
// TASK-052 (backlog/decisions/decision-034) generalized this from a single
// scalar player to a `players` array of 1 or 2, mirroring core/world.zig's own
// generalization line for line: one shared board/food/tick/rng (`S.status`,
// `S.food`, `S.tick`, `S.rng`), each player its own `{dir, nextDir, score,
// alive, snake}` record. A one-player `S` reproduces the original scalar
// behavior byte-for-byte (decision-034's starting-row formula reduces to the
// same row, and every cross-player step in `advance()` is a no-op with no
// other player) — the two-player path is purely additive, same as the Zig
// side.

import { createRng, boundedDraw } from './rng.mjs';

export const COLS = 24, ROWS = 24;

// Same vectors and declaration order as the oracle's DIRS.
export const DIRS = {
  up:    { x:  0, y: -1 },
  down:  { x:  0, y:  1 },
  left:  { x: -1, y:  0 },
  right: { x:  1, y:  0 },
};

/**
 * The DIRS name for a vector a player's dir/nextDir holds (`{x,y}`, not a string) —
 * canon.mjs's encode() takes the name (docs/canonical-state.md's encoding),
 * so any caller serializing sim.mjs state must go through this first.
 */
export function dirName(d) {
  for (const [name, v] of Object.entries(DIRS)) {
    if (v.x === d.x && v.y === d.y) return name;
  }
  throw new RangeError(`not a DIRS vector: ${JSON.stringify(d)}`);
}

// Oracle timing constants (docs/architecture.md "The two loops").
export const BASE_MS = 130;      // tick at 1.0x
export const MIN_MS  = 55;
const MAX_DT_MS = 64;            // frame()'s clamp: a long dt can't fast-forward the sim
const MAX_STEPS = 6;             // frame()'s catch-up guard

// The oracle's status machine verbatim — `menu | playing | paused | dead`.
// A full-board win is `dead` in the oracle too, so it stays `dead` here (the
// canonical encoding has no separate win code).
export const STATUSES = ['menu', 'playing', 'paused', 'dead'];

// --- oracle speed(tickMs)/speedMul(), over explicit values so a test can fix
// the score and still read the same formula the oracle uses ---
export const speedMulAt = (score) => 1 + Math.min(score, 40) * 0.035;
export const tickMsAt = (score) => Math.max(MIN_MS, BASE_MS / speedMulAt(score));
// Tier period is read from player 0's score, matching core/world.zig's
// pump(): speed is not a per-player notion (decision-034 didn't need one —
// a solo game and a two-player match share one clock either way).
export const tickMs = (S) => tickMsAt(S.players[0].score);

/**
 * A fresh state with the oracle's `reset()` starting position: a `players`
 * array (default length 1) of 3-cell snakes head-first at (8, cy), (7, cy),
 * (6, cy), each moving right, spaced per decision-034's `cy(i) = rows*(i+1) /
 * (players+1)` (at `players=1` this is `rows/2`, the original single-player
 * row — byte-identical). Food is drawn once from `seed` after every player is
 * placed. `status` chooses the initial state-machine position; the oracle's
 * own `reset()` never sets status itself (`start()` does, after calling it).
 */
export function initialState({ seed, status = 'menu', wrap = false,
                               cols = COLS, rows = ROWS, players = 1 } = {}) {
  const S = {
    cols, rows, wrap,
    tick: 0,
    food: null,
    players: Array.from({ length: players }, () => ({
      dir: DIRS.right, nextDir: DIRS.right, score: 0, alive: true, snake: [],
    })),
    status,
    acc: 0,
    last: undefined,
    rng: null,
  };
  const rng = createRng(seed);
  reset(S, rng);
  Object.defineProperty(S, 'rng', { value: rng, enumerable: false });
  return S;
}

/**
 * The rng stream that mutates `S`, either attached by initialState or
 * supplied by the caller for a state decoded from canonical bytes (canon.mjs
 * carries the four state words; this reattaches the stream they describe).
 */
export function attachRng(S, seed) {
  if (!Array.isArray(seed) || seed.length !== 4) {
    throw new TypeError('seed must be four u32 values [s0, s1, s2, s3]');
  }
  Object.defineProperty(S, 'rng', { value: createRng(seed), enumerable: false, configurable: true });
  return S;
}

/** The four current rng state words (the canonical `rng_state` field). */
export const rngState = (S) => S.rng.state();

/**
 * snake.html's reset(): a 3-cell snake per player, head at (8, cy) head-first,
 * dir/nextDir forced to right, score cleared, every player marked alive,
 * accumulator/tick cleared, food placed. Callers transitioning through
 * start() must set status after this returns (start() does exactly that).
 * `wrap` is a caller-provided setting here instead of the overlay's mode
 * <select>.
 *
 * decision-034's starting-row formula, `cy(i) = rows*(i+1) / (players+1)`,
 * spaces `S.players.length` players evenly down the board; at length 1 it
 * reduces to `rows/2` (integer division), the oracle's own row, unchanged.
 */
export function reset(S, rng = S.rng) {
  const n = S.players.length;
  for (let i = 0; i < n; i++) {
    const cy = Math.floor((S.rows * (i + 1)) / (n + 1));
    const p = S.players[i];
    p.snake = [ { x: 8, y: cy }, { x: 7, y: cy }, { x: 6, y: cy } ];
    p.dir = p.nextDir = DIRS.right;
    p.score = 0;
    p.alive = true;
  }
  S.acc = 0;
  S.tick = 0;
  if (rng) placeFood(S, rng);
}

/** The oracle's start(): reset() first, then status = "playing". */
export function start(S, rng = S.rng) {
  reset(S, rng);
  S.status = 'playing';
}

/**
 * snake.html's occupied(), extended (decision-034) to every player's body,
 * dead or alive: an eliminated player's corpse is a permanent obstacle, never
 * cleared, and the single shared food cell can never land on anyone's snake,
 * living or eliminated.
 */
function occupied(S, x, y) {
  return S.players.some((p) => p.snake.some((c) => c.x === x && c.y === y));
}

/**
 * snake.html's placeFood(): free cells enumerated in the same row-major order,
 * but indexed with a boundedDraw from the seeded stream instead of
 * `Math.random()` (docs/rng.md "Food placement").
 */
export function placeFood(S, rng = S.rng) {
  const free = [];
  for (let y = 0; y < S.rows; y++)
    for (let x = 0; x < S.cols; x++)
      if (!occupied(S, x, y)) free.push({ x, y });
  S.food = free.length ? free[boundedDraw(rng.next, free.length)] : null;
}

/**
 * snake.html's queueDir(): the single choke point for input legality. The
 * 180-degree guard reads the player's dir while playing and nextDir in every
 * other status; a direction queued from menu/dead starts the game (or
 * restarts a finished match — decision-015's quirk, kept verbatim and, per
 * decision-034, whole-world: any one player's first legal input starts or
 * restarts the shared match for everyone). `player` defaults to 0, so every
 * existing single-player call site is unchanged.
 */
export function queueDir(S, name, player = 0) {
  const d = DIRS[name];
  if (!d) return;
  const p = S.players[player];
  const ref = S.status === 'playing' ? p.dir : p.nextDir;
  if (d.x === -ref.x && d.y === -ref.y) return;   // no instant 180
  p.nextDir = d;
  if (S.status === 'menu' || S.status === 'dead') start(S);
}

/** snake.html's togglePause(): a no-op outside playing/paused. */
export function togglePause(S) {
  if (S.status === 'playing') {
    S.status = 'paused';
  } else if (S.status === 'paused') {
    S.status = 'playing';
  }
}

/**
 * Per-player phase-1 (read-only) result: mirrors core/world.zig's PlayerMove —
 * where advance() would move this player's head, whether that move eats the
 * shared food, or whether it is already fatal — computed against the tick's
 * *starting* snapshot (nobody else has moved yet), so visitation order can
 * never change the outcome.
 */
function planMove(S, i) {
  const p = S.players[i];
  const head = p.snake[0];
  let nx = head.x + p.dir.x;
  let ny = head.y + p.dir.y;

  if (S.wrap) {
    // The oracle's own expression, kept verbatim: adding COLS/ROWS first is
    // what keeps JS's sign-of-dividend remainder non-negative for a head at
    // x=0 moving left.
    nx = (nx + S.cols) % S.cols;
    ny = (ny + S.rows) % S.rows;
  } else if (nx < 0 || ny < 0 || nx >= S.cols || ny >= S.rows) {
    return { dies: true };
  }

  // Tail vacates this tick unless we eat: self-collision is tested against
  // the body minus the cell it is about to vacate.
  const eating = S.food && nx === S.food.x && ny === S.food.y;
  const body = eating ? p.snake : p.snake.slice(0, -1);
  if (body.some((c) => c.x === nx && c.y === ny)) return { dies: true };

  // decision-034: colliding with any *other* player's full, pre-tick body
  // (dead or alive) is fatal too — their tail's fate is unresolved until
  // phase 2, so their whole pre-tick body is treated as solid.
  for (let j = 0; j < S.players.length; j++) {
    if (j === i) continue;
    if (S.players[j].snake.some((c) => c.x === nx && c.y === ny)) return { dies: true };
  }

  return { dies: false, newHead: { x: nx, y: ny }, eats: eating };
}

/**
 * snake.html's advance(), generalized to `S.players.length` players
 * (decision-034), mirroring core/world.zig's advance() line for line: phase 1
 * (`planMove`, above) is read-only and order-independent; phase 2 always
 * mutates in ascending player-index order, so a permuted visitation order can
 * never change the result. At one player every cross-player/head-to-head step
 * below is a no-op, reproducing the original single-player advance()
 * byte-for-byte, including its die()/win()-before-the-tick-increment quirk:
 * `S.tick` only advances when at least one player is still alive afterward.
 */
export function advance(S) {
  const n = S.players.length;
  const dies = new Array(n).fill(false);
  const newHead = new Array(n);
  const eats = new Array(n).fill(false);

  // Phase 1: commit dir and plan each still-alive player's move against the
  // tick's starting snapshot.
  for (let i = 0; i < n; i++) {
    const p = S.players[i];
    if (!p.alive) continue;
    p.dir = p.nextDir;
    const move = planMove(S, i);
    dies[i] = move.dies;
    if (!move.dies) { newHead[i] = move.newHead; eats[i] = move.eats; }
  }

  // Head-to-head: two still-surviving players landing on the same cell this
  // tick mutually kill each other (decision-034) — symmetric, order-independent.
  for (let i = 0; i < n; i++) {
    if (!S.players[i].alive || dies[i]) continue;
    for (let j = i + 1; j < n; j++) {
      if (!S.players[j].alive || dies[j]) continue;
      if (newHead[i].x === newHead[j].x && newHead[i].y === newHead[j].y) {
        dies[i] = true;
        dies[j] = true;
      }
    }
  }

  // Phase 2 (fixed ascending index): mutate bodies, resolve the shared food,
  // and — only if something was eaten — draw the one shared-RNG replacement
  // food (docs/rng.md "Food placement" point 3's ascending-index rule).
  let ateThisTick = false;
  for (let i = 0; i < n; i++) {
    const p = S.players[i];
    if (!p.alive) continue;
    if (dies[i]) {
      // decision-034: a corpse is left exactly where it fell — never cleared.
      p.alive = false;
      continue;
    }
    p.snake.unshift(newHead[i]);
    if (eats[i]) {
      p.score += 10;
      ateThisTick = true;
    } else {
      p.snake.pop();
    }
  }
  if (ateThisTick) {
    placeFood(S);
    if (!S.food) {
      // Board full: whoever just ate won (decision-034 keeps the
      // single-player win()-is-a-flavor-of-die() sentinel).
      for (let i = 0; i < n; i++) {
        if (S.players[i].alive && eats[i]) S.players[i].alive = false;
      }
    }
  }

  if (S.players.some((p) => p.alive)) {
    S.tick += 1;
  } else {
    S.status = 'dead';
  }
}

/**
 * snake.html's frame() loop, minus clock and renderer: `now` is the caller's
 * timestamp (dt clamped to 64 ms, first frame's dt 0), and the accumulator
 * runs at most MAX_STEPS advances with tickMs() re-read each iteration
 * because eating raises the speed mid-frame.
 *
 * First frame has dt 0 (`S.last` undefined until a frame stamps it); later
 * frames advance by at most 64 ms of dt.
 */
export function step(S, now) {
  // The oracle reads dt as `now - (S.last || now)` with `S.last = 0`; that
  // truthiness sentinel works only because a browser's first rAF timestamp is
  // never 0. A headless caller's clock legitimately starts at t=0, so the
  // sentinel here is `undefined` ("no previous frame" -> dt 0) and a real
  // timestamp is never mistaken for it. Behaviorally identical to the oracle
  // for every non-zero timestamp; not a divergence to record.
  const dt = S.last === undefined ? 0 : Math.min(MAX_DT_MS, now - S.last);
  S.last = now;

  if (S.status === 'playing') {
    S.acc += dt;
    let stepMs = tickMs(S);
    let guard = 0;
    // The oracle's condition verbatim: at most MAX_STEPS advances per frame,
    // with tickMs() re-read each iteration because eating can raise the speed
    // mid-frame. In practice the 64 ms dt clamp keeps `acc` below one extra
    // tick most frames, so the guard rarely binds; it bounds the worst-case
    // catch-up the same way the oracle does.
    while (S.acc >= stepMs && S.status === 'playing' && guard++ < MAX_STEPS) {
      S.acc -= stepMs;
      advance(S);
      stepMs = tickMs(S);
    }
  }
  return S;
}
