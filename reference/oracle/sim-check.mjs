// Self-check for sim.mjs against `reference/snake.html`'s behavior and the
// quirks recorded in backlog/decisions/. Run: node reference/oracle/sim-check.mjs
import {
  COLS, ROWS, DIRS, BASE_MS, MIN_MS,
  speedMulAt, tickMsAt, initialState, attachRng, rngState, reset, start,
  queueDir, togglePause, placeFood, advance, step,
} from './sim.mjs';
import { createRng, boundedDraw } from './rng.mjs';

let failed = 0;
const check = (label, actual, expected) => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) console.log(`ok   ${label}`);
  else { failed++; console.log(`FAIL ${label}\n  expected ${e}\n  actual   ${a}`); }
};

// A bare playing state with an attached rng stream; `over` patches fields
// before driving it. `dir`/`nextDir` are copies, not the shared DIRS objects:
// a fixture whose snake occupies a whole board would otherwise hand DIRS.right
// to advance() as a body cell and have unshift/pop mutate the constant. Each
// AC below is its own named block so a reviewer can find "the tail-chase test"
// by name.
const playingState = (over = {}) => {
  const S = {
    cols: COLS, rows: ROWS, wrap: false, tick: 0, score: 0,
    food: null, snake: [{ x: 5, y: 5 }, { x: 4, y: 5 }, { x: 3, y: 5 }],
    dir: { ...DIRS.right }, nextDir: { ...DIRS.right },
    status: 'playing', acc: 0, last: undefined,
  };
  attachRng(S, [1, 2, 3, 4]);
  return Object.assign(S, over);
};

// --- AC#1: the tail-chase split, `eating ? S.snake : S.snake.slice(0, -1)` ---
{
  // Not eating: the collision body is the snake minus the tail cell it is
  // about to vacate, so moving into that cell is legal. Head (5,5) moving left
  // onto the tail at (4,5).
  const chase = playingState({
    snake: [{ x: 5, y: 5 }, { x: 10, y: 5 }, { x: 4, y: 5 }],
    dir: DIRS.left, nextDir: DIRS.left,
  });
  advance(chase);
  check('tail-chase split: advancing into the vacating tail survives',
    [chase.status, chase.snake, chase.score, chase.tick],
    ['playing', [{ x: 4, y: 5 }, { x: 5, y: 5 }, { x: 10, y: 5 }], 0, 1]);

  // The same cell one segment deeper is still fatal.
  const mid = playingState({
    snake: [{ x: 5, y: 5 }, { x: 4, y: 5 }, { x: 9, y: 5 }, { x: 10, y: 5 }],
    dir: DIRS.left, nextDir: DIRS.left,
  });
  advance(mid);
  check('tail-chase split: mid-body self-hit dies', mid.status, 'dead');

  // The other end of the tail: a length-4 snake whose body fills the row so
  // the tail is not at the cell being entered. Head (5,5) moving left onto
  // (4,5), which is now mid-body (the tail is (2,5), two cells away) — fatal.
  const long = playingState({
    snake: [{ x: 5, y: 5 }, { x: 4, y: 5 }, { x: 3, y: 5 }, { x: 2, y: 5 }],
    dir: DIRS.left, nextDir: DIRS.left,
  });
  advance(long);
  check('tail-chase split: entering what is mid-body at length 4 dies', long.status, 'dead');

  // Eating side of the split: the tail does NOT vacate, so a head entering a
  // cell occupied anywhere on the (now full) body collides. Reachable on a
  // 2x3 wrap board — the only free cell is behind the head, but the food sits
  // on the tail, and the tail cannot move because eating pins it.
  const eatBody = playingState({
    cols: 2, rows: 3, wrap: true,
    snake: [{ x: 1, y: 1 }, { x: 0, y: 1 }, { x: 0, y: 0 }],
    dir: DIRS.left, nextDir: DIRS.left,
    food: { x: 0, y: 1 },
  });
  advance(eatBody);
  check('tail-chase split: eating keeps the whole body, so the tail cell collides',
    eatBody.status, 'dead');
}

// --- AC#2: wrap is the oracle's `(v + COLS) % COLS` remainder, not true modulo ---
{
  // JS's remainder takes the sign of the dividend: `-1 % 24 === -1`. The
  // oracle adds COLS/ROWS first, and sim.mjs keeps that exact expression.
  const S = playingState({ wrap: true, snake: [{ x: 0, y: 5 }, { x: 1, y: 5 }, { x: 2, y: 5 }] });
  S.dir = S.nextDir = DIRS.left;
  advance(S);
  check('wrap (+COLS remainder): x=0 moving left lands on x=23', S.snake[0], { x: 23, y: 5 });

  const back = playingState({ wrap: true, snake: [{ x: 23, y: 5 }, { x: 22, y: 5 }, { x: 21, y: 5 }] });
  advance(back);
  check('wrap (+COLS remainder): x=23 moving right lands on x=0', back.snake[0], { x: 0, y: 5 });

  const vert = playingState({ wrap: true, snake: [{ x: 5, y: 0 }, { x: 4, y: 0 }, { x: 3, y: 0 }] });
  vert.dir = vert.nextDir = DIRS.up;
  advance(vert);
  check('wrap (+ROWS remainder): y=0 moving up lands on y=23', vert.snake[0], { x: 5, y: 23 });

  const down = playingState({ wrap: true, snake: [{ x: 5, y: 23 }, { x: 4, y: 23 }, { x: 3, y: 23 }] });
  down.dir = down.nextDir = DIRS.down;
  advance(down);
  check('wrap (+ROWS remainder): y=23 moving down lands on y=0', down.snake[0], { x: 5, y: 0 });

  // The naive remainder this expression avoids, recorded as a number so the
  // contrast is explicit rather than implied.
  check('naive remainder would go negative', (-1) % COLS, -1);

  // Wall mode is the contrast for the same head/step.
  const wall = playingState({ snake: [{ x: 0, y: 5 }, { x: 1, y: 5 }, { x: 2, y: 5 }] });
  wall.dir = wall.nextDir = DIRS.left;
  advance(wall);
  check('wall mode: the same step dies instead of wrapping', wall.status, 'dead');
}

// --- AC#3: 180-degree reject — reference is dir while playing, nextDir otherwise ---
{
  const S = playingState();
  queueDir(S, 'left');    // exact opposite of dir=right -> rejected
  check('180 reject (playing): opposite of dir rejected', S.nextDir, DIRS.right);

  queueDir(S, 'up');      // legal against dir=right
  queueDir(S, 'right');   // opposite of nextDir=up, but dir is still right -> accepted
  check('180 reject (playing): reference is dir, not nextDir', S.nextDir, DIRS.right);
  advance(S);
  check('180 reject (playing): queued dir commits on advance', S.dir, DIRS.right);

  // A committed right leaves left as the exact opposite, rejected against dir.
  queueDir(S, 'left');
  check('180 reject (playing): left rejected once dir is right', S.nextDir, DIRS.right);

  // Paused: the guard reads nextDir, and queueing never starts the game nor
  // advances a tick.
  const paused = playingState({ status: 'paused' });
  queueDir(paused, 'up');     // nextDir=right -> legal
  queueDir(paused, 'down');   // opposite of nextDir=up -> rejected
  check('180 reject (paused): reference is nextDir', paused.nextDir, DIRS.up);
  check('180 reject (paused): stays paused', paused.status, 'paused');

  // togglePause covers playing <-> paused only.
  togglePause(paused);
  check('togglePause resumes', paused.status, 'playing');
  togglePause(paused);
  check('togglePause pauses', paused.status, 'paused');
  const deadPause = playingState({ status: 'dead' });
  togglePause(deadPause);
  check('togglePause ignores dead', deadPause.status, 'dead');

  // An unknown direction name is ignored by the same choke point.
  const unknown = playingState();
  queueDir(unknown, 'diagonal');
  check('queueDir ignores unknown direction names', unknown.nextDir, DIRS.right);
}

// --- AC#4: decision-015 — the menu-direction-overwrite quirk reproduces exactly ---
{
  // From menu, Up: queueDir sets nextDir=up and calls start(), whose reset()
  // then forces dir=nextDir=right, clobbering the direction the same keypress
  // queued. The snake moves right on the first tick — the oracle's bug, kept.
  const S = initialState({ seed: [1, 2, 3, 4], status: 'menu' });
  queueDir(S, 'up');
  check('menu overwrite (decision-015): start via Up lands in playing', S.status, 'playing');
  check('menu overwrite (decision-015): dir/nextDir are right, not up',
    [S.dir, S.nextDir], [DIRS.right, DIRS.right]);
  advance(S);
  check('menu overwrite (decision-015): first tick moves right', S.snake[0], { x: 9, y: 12 });

  // Every direction that passes the 180-degree guard is clobbered the same
  // way. Left is the exception that proves both rules: from a right-facing
  // start it is rejected outright, so it never even triggers the start (the
  // snake does not reverse into itself) — the quirk only ever manifests for
  // inputs that would have taken effect.
  for (const name of ['up', 'down', 'right']) {
    const fromMenu = initialState({ seed: [1, 2, 3, 4], status: 'menu' });
    queueDir(fromMenu, name);
    check(`menu overwrite (decision-015): start via ${name} forced right`,
      [fromMenu.status, fromMenu.dir, fromMenu.nextDir], ['playing', DIRS.right, DIRS.right]);
  }

  const fromLeft = initialState({ seed: [1, 2, 3, 4], status: 'menu' });
  queueDir(fromLeft, 'left');
  check('menu overwrite (decision-015): Left is 180-rejected, so menu is unchanged',
    [fromLeft.status, fromLeft.dir, fromLeft.nextDir], ['menu', DIRS.right, DIRS.right]);

  // The dead-state counterpart behaves identically.
  const fromDead = initialState({ seed: [1, 2, 3, 4], status: 'dead' });
  queueDir(fromDead, 'up');
  check('menu overwrite (decision-015): dead-state start forced right too',
    [fromDead.status, fromDead.dir, fromDead.nextDir], ['playing', DIRS.right, DIRS.right]);

  // The clobber needs the start transition: already playing, Up from dir=right
  // is a plain legal turn that survives to the next advance.
  const playing = playingState();
  queueDir(playing, 'up');
  check('menu overwrite (decision-015): no clobber while playing', playing.nextDir, DIRS.up);

  // Non-directional starts (the overlay button / Space) go through start()
  // directly, where right is simply the intended direction.
  const btn = initialState({ seed: [1, 2, 3, 4], status: 'menu' });
  start(btn);
  check('start() from menu plays with dir right', [btn.status, btn.dir], ['playing', DIRS.right]);
}

// --- initialState/reset: the oracle's reset() starting position and food draw ---
{
  const S = initialState({ seed: [1, 2, 3, 4] });
  check('reset starting position',
    [S.status, S.score, S.tick, S.wrap, S.snake, S.dir, S.nextDir],
    ['menu', 0, 0, false,
     [{ x: 8, y: 12 }, { x: 7, y: 12 }, { x: 6, y: 12 }], DIRS.right, DIRS.right]);

  // First food draw at reset: boundedDraw over 573 free cells (576 - 3), whose
  // first value on a fresh [1,2,3,4] stream is 0 per docs/rng.md -> (0, 0).
  const drawn = boundedDraw(createRng([1, 2, 3, 4]).next, 573);
  check('reset food draw matches docs/rng.md boundedDraw(573)', [drawn, S.food], [0, { x: 0, y: 0 }]);
  check('reset consumes exactly one rng draw', rngState(S), [7, 0, 1026, 12288]);

  // attachRng re-seeds a decoded state to the same stream initialState builds
  // (the four canonical rng_state words reproduce the stream).
  const detached = { ...S };
  attachRng(detached, rngState(S));
  check('attachRng restores the stream', rngState(detached), rngState(S));

  // reset() re-draws food and re-centers the snake, preserving `wrap`.
  const re = initialState({ seed: [1, 2, 3, 4], status: 'playing', wrap: true });
  re.score = 90;
  re.snake = [{ x: 1, y: 1 }, { x: 2, y: 2 }, { x: 3, y: 3 }];
  reset(re);
  check('reset clears score and restores the start position',
    [re.score, re.tick, re.wrap, re.snake],
    [0, 0, true, [{ x: 8, y: 12 }, { x: 7, y: 12 }, { x: 6, y: 12 }]]);

  // Food enumeration is row-major (outer y, inner x), so a caller that knows
  // the draw index can predict the cell: index 9 on an empty board is (9, 0).
  const row = playingState({ snake: [] });
  placeFood(row);
  const idx = boundedDraw(createRng([1, 2, 3, 4]).next, COLS * ROWS);
  check('placeFood indexes the row-major free list', row.food, { x: idx % COLS, y: 0 });
}

// --- advance: eat, wall death, and the full-board win ---
{
  const S = playingState({ food: { x: 6, y: 5 } });
  const before = rngState(S);
  advance(S);
  check('eat grows, scores, and advances the tick',
    [S.snake.length, S.score, S.tick, S.status], [4, 10, 1, 'playing']);
  check('eat consumes one rng draw for the new food',
    JSON.stringify(rngState(S)) !== JSON.stringify(before), true);
  check('new food is not on the snake',
    S.snake.some((p) => p.x === S.food.x && p.y === S.food.y), false);

  // Wall death in each direction.
  for (const [dir, head] of [['left', { x: 0, y: 5 }], ['right', { x: 23, y: 5 }],
                             ['up', { x: 5, y: 0 }], ['down', { x: 5, y: 23 }]]) {
    const tail1 = { x: head.x - 1, y: head.y };
    const tail2 = { x: head.x - 2, y: head.y };
    const wall = playingState({ snake: [head, tail1, tail2] });
    wall.dir = wall.nextDir = DIRS[dir];
    advance(wall);
    check(`wall death: ${dir}`, wall.status, 'dead');
  }

  // Full board: the snake occupies every cell except (0,0), the food sits on
  // (0,0), and the head moves onto it. Because it is eating, the collision
  // body is the full snake (tail does not vacate), and the only cell entered
  // is the free food cell, so no hit; the eat then finds no free cell,
  // placeFood yields null, and advance reports the win.
  const cells = [];
  for (let y = 0; y < ROWS; y++)
    for (let x = 0; x < COLS; x++)
      if (!(x === 0 && y === 0)) cells.push({ x, y });   // (0,0) left free for food
  const full = playingState({ wrap: true, snake: cells.map((c) => ({ ...c })), food: { x: 0, y: 0 } });
  // Reorder so the head is (0,1): stepping up into (0,0) is the eating move.
  const hi = full.snake.findIndex((c) => c.x === 0 && c.y === 1);
  full.snake.unshift(...full.snake.splice(hi, 1));
  full.dir = { ...DIRS.up };
  full.nextDir = { ...DIRS.up };
  advance(full);
  check('win: filling the board ends the game (dead, like the oracle)',
    [full.status, full.score, full.food, full.snake.length], ['dead', 10, null, 576]);
}

// --- step: frame()'s accumulator as a pure function of (state, timestamp) ---
{
  const mk = () => initialState({ seed: [1, 2, 3, 4], status: 'playing' });

  // No previous frame yet (`S.last` unset), so the first step reads dt 0
  // regardless of the timestamp it is handed.
  const first = mk();
  step(first, 5_000);
  check('step: first frame on a fresh state has dt 0', [first.tick, first.acc, first.last], [0, 0, 5_000]);

  // dt is clamped to 64 ms per frame, so no single frame can contribute more
  // than 64 ms no matter how long the real gap was — the sim never
  // fast-forwards. (This is why a single BASE_MS tick needs several frames.)
  const clamped = mk();
  step(clamped, 0);
  step(clamped, 60_000);
  check('step: dt clamped to 64 ms per frame', [clamped.tick, clamped.acc], [0, 64]);

  // The accumulator carries a partial step across frames, and one advance runs
  // once 130 ms has been accumulated (at 64 ms/frame that is frame three).
  const acc = mk();
  step(acc, 0);
  step(acc, 64);
  check('step: partial frames accumulate without advancing', [acc.tick, acc.acc], [0, 64]);
  step(acc, 128);
  check('step: 128 ms still short of one BASE_MS tick', [acc.tick, acc.acc], [0, 128]);
  step(acc, 192);
  check('step: crossing BASE_MS advances exactly one tick',
    [acc.tick, acc.snake[0], acc.acc], [1, { x: 9, y: 12 }, 192 - BASE_MS]);

  // The fixed timestep is framerate-independent: 20 frames of 100/6 ms (~16.7,
  // i.e. 60 fps over ~333 ms) is the same 2 ticks the accumulator budget
  // allows, not 20.
  const fps = mk();
  for (let i = 1; i <= 20; i++) step(fps, (100 * i) / 6);
  check('step: 60 fps over ~333 ms is two ticks', fps.tick, 2);

  // The catch-up guard bounds a frame at 6 advances, but dt is clamped to 64
  // ms first — so even a 32 s gap contributes one 64 ms frame, and 64 ms is
  // only just over one MIN_MS tick (score 40): 1 advance, 9 ms left over. The
  // guard would only bite if dt were unclamped; the clamp is the real bound.
  const guard = mk();
  guard.score = 40;
  step(guard, 0);
  step(guard, 32_000);
  check('step: dt clamp (not the guard) bounds a huge gap to one advance',
    [guard.tick, guard.acc, guard.status], [1, 64 - MIN_MS, 'playing']);

  // start() is the transition into playing; frames spent in menu contributed
  // nothing, and playing begins from the frame after it.
  const armed = initialState({ seed: [1, 2, 3, 4], status: 'menu' });
  step(armed, 1_000);
  check('menu frames stamp the clock without advancing', [armed.tick, armed.acc, armed.last], [0, 0, 1_000]);
  start(armed);
  step(armed, 1_064);
  check('first playing frame after start accumulates from its own clock', [armed.tick, armed.acc], [0, 64]);

  // Speed curve and the tick-period floor.
  check('speedMul saturates at score 40',
    [speedMulAt(0), speedMulAt(20), speedMulAt(40), speedMulAt(100)],
    [1, 1 + 20 * 0.035, 1 + 40 * 0.035, 1 + 40 * 0.035]);
  check('tickMs = BASE_MS / speedMul, floored at MIN_MS',
    [tickMsAt(0), tickMsAt(20), tickMsAt(40), tickMsAt(100)],
    [BASE_MS, BASE_MS / (1 + 20 * 0.035), MIN_MS, MIN_MS]);

  // Paused sim accumulates nothing; resuming continues from the same state.
  const p = mk();
  step(p, 0);
  step(p, 100);
  p.status = 'paused';
  const held = JSON.stringify([p.tick, p.acc, p.snake]);
  step(p, 5_000);
  check('step: paused frames do not advance', JSON.stringify([p.tick, p.acc, p.snake]), held);
}

// Determinism: the same seed and the same inputs produce the same run, and a
// different seed produces a different food placement.
{
  const run = (seed) => {
    const S = initialState({ seed, status: 'playing' });
    const dirs = ['down', 'right', 'up', 'right', 'down', 'down', 'left', 'up'];
    for (let i = 1; i <= 600; i++) {
      if (i % 15 === 0) queueDir(S, dirs[(i / 15) | 0]);
      step(S, i * 16);
      if (S.status !== 'playing') break;
    }
    return { status: S.status, tick: S.tick, score: S.score, food: S.food,
             head: S.snake[0], rngState: rngState(S) };
  };
  const a = run([9, 8, 7, 6]);
  check('same seed + inputs reproduce the same run', run([9, 8, 7, 6]), a);
  check('different seed diverges', JSON.stringify(run([1, 1, 1, 2])) !== JSON.stringify(a), true);
}

console.log(failed === 0 ? 'ALL CHECKS PASSED' : `${failed} CHECK(S) FAILED`);
process.exit(failed === 0 ? 0 : 1);
