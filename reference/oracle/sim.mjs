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
 * The DIRS name for a vector S.dir/S.nextDir holds (`{x,y}`, not a string) —
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
export const tickMs = (S) => tickMsAt(S.score);

/**
 * A fresh state with the oracle's `reset()` starting position: 3-cell snake
 * head-first at (8, 12), (7, 12), (6, 12), moving right, food drawn from
 * `seed`. `status` chooses the initial state-machine position; the oracle's
 * own `reset()` never sets status itself (`start()` does, after calling it).
 * The starting food draw is part of reset, so the rng stream continues from
 * here.
 */
export function initialState({ seed, status = 'menu', wrap = false,
                               cols = COLS, rows = ROWS } = {}) {
  const S = {
    cols, rows, wrap,
    tick: 0,
    score: 0,
    food: null,
    snake: [],
    dir: DIRS.right,
    nextDir: DIRS.right,
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
 * snake.html's reset(): 3-cell snake at row (rows/2)|0, dir/nextDir forced to
 * right, score and accumulator cleared, food placed. Callers transitioning
 * through start() must set status after this returns (start() does exactly
 * that). `wrap` is a caller-provided setting here instead of the overlay's
 * mode <select>.
 */
export function reset(S, rng = S.rng) {
  const cy = (S.rows / 2) | 0;
  S.snake = [ { x: 8, y: cy }, { x: 7, y: cy }, { x: 6, y: cy } ];
  S.dir = S.nextDir = DIRS.right;
  S.score = 0;
  S.acc = 0;
  S.tick = 0;
  if (rng) placeFood(S, rng);
}

/** The oracle's start(): reset() first, then status = "playing". */
export function start(S, rng = S.rng) {
  reset(S, rng);
  S.status = 'playing';
}

/** snake.html's occupied(). */
function occupied(S, x, y) {
  return S.snake.some((p) => p.x === x && p.y === y);
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
 * 180-degree guard reads S.dir while playing and S.nextDir in every other
 * status; a direction queued from menu/dead starts the game, whose reset()
 * then overwrites that direction — decision-015, kept verbatim.
 */
export function queueDir(S, name) {
  const d = DIRS[name];
  if (!d) return;
  const ref = S.status === 'playing' ? S.dir : S.nextDir;
  if (d.x === -ref.x && d.y === -ref.y) return;   // no instant 180
  S.nextDir = d;
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
 * snake.html's advance(): one simulation step. The die()/win() overlays are
 * presentation-only, so those transitions set status and return.
 */
export function advance(S) {
  S.dir = S.nextDir;
  const head = S.snake[0];
  let nx = head.x + S.dir.x;
  let ny = head.y + S.dir.y;

  if (S.wrap) {
    // The oracle's own expression, kept verbatim: adding COLS/ROWS first is
    // what keeps JS's sign-of-dividend remainder non-negative for a head at
    // x=0 moving left.
    nx = (nx + S.cols) % S.cols;
    ny = (ny + S.rows) % S.rows;
  } else if (nx < 0 || ny < 0 || nx >= S.cols || ny >= S.rows) {
    return die(S);
  }

  // Tail vacates this tick unless we eat.
  const eating = S.food && nx === S.food.x && ny === S.food.y;
  const body = eating ? S.snake : S.snake.slice(0, -1);
  if (body.some((p) => p.x === nx && p.y === ny)) return die(S);

  S.snake.unshift({ x: nx, y: ny });
  if (eating) {
    S.score += 10;
    placeFood(S);
    if (!S.food) return win(S);
  } else {
    S.snake.pop();
  }
  S.tick += 1;
}

/** The oracle's die(): status dead (its overlay is presentation). */
function die(S) {
  S.status = 'dead';
}

/** The oracle's win(): the same `dead` status die() sets (its overlay differs; the status does not). */
function win(S) {
  S.status = 'dead';
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
