// task oracle:fuzz (TASK-022): generates N fresh random command logs
// (docs/corpus-format.md's *input* format) and drives each through both
// reference/oracle/sim.mjs (via regen_corpus.mjs's own
// parseCommandLog()/renderTrace() — the same machinery that produces the
// committed corpus, so this is exactly the oracle the corpus already
// trusts) and a live build of core/fuzzrun.zig, diffing every tick's
// checksum.
//
// This is discovery, not regression: every seed is fresh and non-committed,
// generated with node:crypto's real randomness rather than a seeded
// stream — deliberately different from docs/corpus-format.md's committed
// random-NN command logs, which must be reproducible from a recorded seed.
// Only the *log itself* (the meta-level choice of seed/wrap/inputs) is
// fresh here; once generated, the log's own `seed` field still drives both
// sim.mjs's and world.zig's internal RNG deterministically — that stream
// was never the thing this file makes non-deterministic.
//
// Not part of `task check` (taskfiles/oracle.yml) — meant to run nightly in
// CI. See docs/corpus-format.md's "Promoting a fuzz failure" section for
// turning a mismatch into a permanent regression trace via the existing
// task oracle:regen machinery (task-015).
//
// Run: node reference/oracle/fuzz.mjs --count N [--ticks N]
//   Requires core/zig-out/bin/fuzzrun to already be built (taskfiles/oracle.yml's
//   fuzz task runs `zig build fuzzrun` first).

import { randomInt } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { parseCommandLog, renderTrace } from './regen_corpus.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, '..', '..');
const FUZZRUN_BIN = join(REPO_ROOT, 'core', 'zig-out', 'bin', 'fuzzrun');
const PROMOTE_DIR = 'reference/oracle/corpus/commands';

const DIRECTIONS = ['up', 'down', 'left', 'right'];
const DEFAULT_TICKS = 500;
const BOARD_COLS = 24;
const BOARD_ROWS = 24;
const QUEUE_PROBABILITY = 0.25;

function parseArgs(argv) {
  const opts = { count: null, ticks: DEFAULT_TICKS };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--count') opts.count = Number(argv[++i]);
    else if (a === '--ticks') opts.ticks = Number(argv[++i]);
    else throw new Error(`unknown argument "${a}"`);
  }
  if (!Number.isInteger(opts.count) || opts.count < 1) {
    throw new Error('--count N is required (N must be an integer >= 1)');
  }
  if (!Number.isInteger(opts.ticks) || opts.ticks < 1) {
    throw new Error('--ticks N must be an integer >= 1');
  }
  return opts;
}

const randomU32 = () => randomInt(0, 0x100000000);

function randomSeed() {
  for (;;) {
    const seed = [randomU32(), randomU32(), randomU32(), randomU32()];
    if (seed.some((w) => w !== 0)) return seed;
  }
}

/** A short, filesystem- and JSON-safe name derived from the seed itself. */
const nameFor = (seed) => `fuzz-${seed.map((w) => w.toString(16).padStart(8, '0')).join('').slice(0, 16)}`;

/** A fresh random command log's text (docs/corpus-format.md) and its name. */
function generateCommandLog(ticks) {
  const seed = randomSeed();
  const wrap = randomInt(0, 2) === 1;
  const name = nameFor(seed);
  const lines = [JSON.stringify({ seed, cols: BOARD_COLS, rows: BOARD_ROWS, wrap, players: 1, ticks })];
  for (let t = 0; t < ticks; t++) {
    if (randomInt(0, 100) < QUEUE_PROBABILITY * 100) {
      lines.push(JSON.stringify({ t, p: 0, in: DIRECTIONS[randomInt(0, DIRECTIONS.length)] }));
    }
  }
  return { name, text: `${lines.join('\n')}\n` };
}

/** Run the built Zig fuzz-runner over one command log; its per-tick lines land on stderr (fuzzrun.zig's header comment). */
function runZig(commandLogPath) {
  const result = spawnSync(FUZZRUN_BIN, [commandLogPath], { encoding: 'utf8' });
  if (result.error) {
    throw new Error(
      `fuzzrun binary not runnable at ${FUZZRUN_BIN} (run "zig build fuzzrun" in core/ first): ${result.error.message}`,
    );
  }
  if (result.status !== 0) {
    throw new Error(`fuzzrun exited ${result.status}:\n${result.stderr}`);
  }
  return result.stderr
    .split('\n')
    .filter((l) => l.length > 0)
    .map((l) => {
      const [tick, checksum] = l.split('\t');
      return { tick: Number(tick), checksum };
    });
}

/** Compare two tick-checksum sequences; the first divergence (a mismatched checksum, or one side stopping earlier/later) is the report. */
function compare(jsLines, zigLines) {
  const n = Math.min(jsLines.length, zigLines.length);
  for (let i = 0; i < n; i++) {
    if (jsLines[i].tick !== zigLines[i].tick || jsLines[i].checksum !== zigLines[i].checksum) {
      return { ok: false, reason: 'checksum mismatch', tick: i, js: jsLines[i], zig: zigLines[i] };
    }
  }
  if (jsLines.length !== zigLines.length) {
    return { ok: false, reason: 'tick count differs', tick: n, jsTicks: jsLines.length, zigTicks: zigLines.length };
  }
  return { ok: true };
}

function main(argv) {
  const opts = parseArgs(argv);
  const tmpDir = mkdtempSync(join(tmpdir(), 'neo-snake-fuzz-'));
  let mismatches = 0;

  for (let i = 0; i < opts.count; i++) {
    const { name, text } = generateCommandLog(opts.ticks);
    const commandLogPath = join(tmpDir, `${name}.commands.jsonl`);
    writeFileSync(commandLogPath, text);

    const log = parseCommandLog(text, commandLogPath);
    const jsLines = renderTrace(log)
      .slice(1)
      .map((l) => ({ tick: l.t, checksum: l.c }));
    const zigLines = runZig(commandLogPath);

    const result = compare(jsLines, zigLines);
    if (result.ok) {
      console.log(`fuzz: ${name} ok (${jsLines.length} ticks, wrap=${log.wrap})`);
      continue;
    }

    mismatches++;
    console.error(`fuzz: MISMATCH ${name} — seed=${JSON.stringify(log.seed)} wrap=${log.wrap} cols=${log.cols} rows=${log.rows}`);
    console.error(`  ${result.reason} at tick ${result.tick}`);
    if (result.js) console.error(`  js:  ${JSON.stringify(result.js)}`);
    if (result.zig) console.error(`  zig: ${JSON.stringify(result.zig)}`);
    if (result.jsTicks !== undefined) console.error(`  js ran ${result.jsTicks} ticks, zig ran ${result.zigTicks}`);
    console.error(`  command log preserved at: ${commandLogPath}`);
    console.error(`  to promote: cp ${commandLogPath} ${PROMOTE_DIR}/${name}.commands.jsonl && task oracle:regen`);
  }

  if (mismatches > 0) {
    console.error(`fuzz: ${mismatches}/${opts.count} seed(s) mismatched — preserving ${tmpDir}`);
    process.exitCode = 1;
  } else {
    console.log(`fuzz: ${opts.count}/${opts.count} seeds matched`);
    rmSync(tmpDir, { recursive: true, force: true });
  }
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) main(process.argv.slice(2));
