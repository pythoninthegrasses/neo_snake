// Corpus generator — implementation of docs/corpus-format.md.
//
// Reads every command log under reference/oracle/corpus/commands/, drives it
// through sim.mjs one `advance()` per tick, and (re)writes three artifacts
// from scratch: the JSONL traces under game/tests/corpus/, that directory's
// manifest.json, and core/corpus.zig. None of the three is ever hand-edited;
// `task oracle:regen` is the only supported way to change them.
//
// The whole job is driving and serializing. There is no RNG, canonical-
// encoding, or simulation logic in this file — those live in rng.mjs,
// canon.mjs and sim.mjs, and the trace's per-tick bytes are exactly what
// canon.mjs's encode() produces for the state sim.mjs reached.
//
// Determinism (TASK-014 AC#1): the sim is already fully seeded, so the only
// remaining freedom is iteration order. Command logs are found by a sorted
// directory scan, every trace runs from its own header's seed with no shared
// mutable state across traces, and both the manifest entries and the
// core/corpus.zig entries are sorted lexicographically by trace name. Running
// this script twice over the same command logs produces byte-identical files.
//
// Run: node reference/oracle/regen_corpus.mjs [--check|--verify]
//   --check compares the three artifacts a regen would produce against what is
//   on disk and writes nothing, so a verify task can report drift.
//   --verify additionally recomputes oracle_sha256 from the working tree's
//   reference/oracle/*.mjs files and compares it against the committed
//   manifest.json's value, so a behaviorally-inert oracle edit (a comment, a
//   rename) that leaves every trace byte-identical still fails (TASK-016).

import { createHash } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { initialState, advance, queueDir, rngState, dirName } from './sim.mjs';
import { encode } from './canon.mjs';

// The one u64 the corpus needs: the canonical checksum trailer read as a
// little-endian integer (docs/canonical-state.md). BigInt is the correct type
// for that width — the "no BigInt in the sim" rule in docs/rng.md is about the
// xoshiro128** stream staying bit-exact in float64, and this is not that path.
const U64_MAX = 18446744073709551615n;

// Independent of NS_ABI_VERSION / NS_CANON_VERSION (docs/abi-decisions.md §6).
export const CORPUS_VERSION = 1;

// Where the three artifacts live, relative to the repo root (docs/corpus-format.md).
const COMMAND_DIR = 'reference/oracle/corpus/commands';
const ORACLE_DIR = 'reference/oracle';
const TRACE_DIR = 'game/tests/corpus';
const MANIFEST_PATH = join(TRACE_DIR, 'manifest.json');
const ZIG_PATH = join('core', 'corpus.zig');

const SUFFIX = '.commands.jsonl';
const DIRECTIONS = ['up', 'down', 'left', 'right'];
const HEADER_FIELDS = ['seed', 'cols', 'rows', 'wrap', 'players', 'ticks'];
const EVENT_FIELDS = ['t', 'p', 'in'];

/**
 * A source location for a rejection message, e.g.
 * `tail-chase.commands.jsonl line 2`. The reason alone never identifies the
 * file, which matters when one bad line among twelve logs would otherwise be
 * a mystery.
 */
const at = (file, lineNo) => `${basename(file)} line ${lineNo}`;

/**
 * Parse one command log: the header line, then zero or more input events
 * sorted ascending by `t`, with `p` ascending inside a tie.
 *
 * The field checks exist because every field is a fixed-width integer in the
 * canonical layout — a fractional, out-of-range or extra field here would
 * silently change (or be dropped by) the record the traces are built from.
 * Duplicate `(t, p)` events are rejected loudly rather than deduped: which of
 * two events queued for the same tick on the same player wins is decided by
 * their order in the file, so a dedupe would hide an authoring bug behind an
 * arbitrary choice.
 */
export function parseCommandLog(text, file = '<command log>') {
  const lines = text.split('\n');
  if (lines.at(-1) === '') lines.pop();          // the file's trailing newline
  if (lines.length === 0) throw error(`${at(file, 1)}: empty command log`, 1);

  const header = parseLine(lines[0], file, 1);
  rejectUnknown(header, HEADER_FIELDS, file, 1);
  for (const field of HEADER_FIELDS) {
    if (header[field] === undefined) fail(`${at(file, 1)}: header missing "${field}"`, 1);
  }
  const seed = header.seed;
  if (!Array.isArray(seed) || seed.length !== 4 || seed.some((w) => !isU32(w)) || seed.every((w) => w === 0)) {
    fail(`${at(file, 1)}: seed must be four u32 values [s0, s1, s2, s3], not all zero`, 1);
  }
  if (!isU16(header.cols) || !isU16(header.rows) || header.cols < 1 || header.rows < 1) {
    fail(`${at(file, 1)}: cols/rows must be u16 >= 1`, 1);
  }
  if (typeof header.wrap !== 'boolean') fail(`${at(file, 1)}: wrap must be a boolean`, 1);
  if (!isU8(header.players) || header.players < 1) {
    fail(`${at(file, 1)}: players must be a u8 >= 1`, 1);
  }
  if (!isU32(header.ticks)) fail(`${at(file, 1)}: ticks must be a u32`, 1);

  const events = [];
  for (let i = 1; i < lines.length; i++) {
    const ev = parseLine(lines[i], file, i + 1);
    rejectUnknown(ev, EVENT_FIELDS, file, i + 1);
    for (const field of EVENT_FIELDS) {
      if (ev[field] === undefined) fail(`${at(file, i + 1)}: event missing "${field}"`, i + 1);
    }
    if (!isU32(ev.t)) fail(`${at(file, i + 1)}: event t must be a u32`, i + 1);
    if (!isU8(ev.p)) fail(`${at(file, i + 1)}: event p must be a u8`, i + 1);
    if (ev.p >= header.players) {
      fail(`${at(file, i + 1)}: event p ${ev.p} is outside the ${header.players}-player game`, i + 1);
    }
    if (!DIRECTIONS.includes(ev.in)) {
      fail(`${at(file, i + 1)}: event in must be one of ${DIRECTIONS.join('|')}`, i + 1);
    }
    const prev = events.at(-1);
    if (prev) {
      if (ev.t < prev.t) {
        fail(`${at(file, i + 1)}: events must be sorted ascending by t (${prev.t} then ${ev.t})`, i + 1);
      }
      if (ev.t === prev.t && ev.p <= prev.p) {
        fail(`${at(file, i + 1)}: two events at t=${ev.t} for p=${ev.p} (same tick and player)`, i + 1);
      }
    }
    events.push(ev);
  }

  return {
    name: basename(file).slice(0, -SUFFIX.length),
    seed, cols: header.cols, rows: header.rows,
    wrap: header.wrap, players: header.players, ticks: header.ticks,
    events,
  };
}

/**
 * Drive one command log and return its trace lines: the trace header, then
 * `{"t","in","c"}` per simulated tick, carrying the full canonical state as
 * lowercase hex on tick 0, on every 64th recorded tick (t = 63, 127, ... — the
 * 64th line is t = 63, so the rule is `(t + 1) % 64`), and on the trace's last
 * tick.
 *
 * Events are applied *before* the tick's `advance()` — a keypress landing
 * between ticks, which is when a real one reaches `queueDir`. The loop stops
 * at the first tick whose status is not `playing` (death and the full-board
 * win both set `dead`), so a trace ends at its natural stopping point instead
 * of padding with post-death no-op ticks; `header.ticks` is only the cap.
 */
export function renderTrace(log) {
  const S = initialState({
    seed: log.seed, status: 'playing', wrap: log.wrap, cols: log.cols, rows: log.rows,
  });

  // Events keyed by tick; the parser guarantees at most one per (t, p), and
  // ascending p within a tick, which is the order they must be queued in.
  const queued = new Map();
  for (const ev of log.events) {
    if (!queued.has(ev.t)) queued.set(ev.t, []);
    queued.get(ev.t).push(ev);
  }

  const lines = [{
    seed: log.seed, cols: log.cols, rows: log.rows,
    wrap: log.wrap, players: log.players, corpus_version: CORPUS_VERSION,
  }];
  const record = { t: 0, in: [] };
  let t = 0;
  for (; ; t++) {
    const applied = (queued.get(t) || []).map((ev) => {
      queueDir(S, ev.in);                 // the log's names are sim.mjs's, untranslated
      return { p: ev.p, dir: ev.in };
    });

    advance(S);
    record.t = t;
    record.in = applied;
    // The loop ends on a death or on the cap, so `last` is known here rather
    // than patched onto the line afterwards.
    const last = S.status !== 'playing' || t + 1 >= log.ticks;
    lines.push(traceLine(S, record, last || t === 0 || (t + 1) % 64 === 0));
    if (last) break;
  }
  return lines;
}

/**
 * One tick's line. The checksum is the record's own 8-byte trailer read as a
 * little-endian u64 — the same reinterpretation docs/canonical-state.md's
 * worked example applies to `5a 33 a2 41 af 35 a7 d1` — printed as a decimal
 * string because a u64 of that size cannot be a JSON number without losing
 * precision.
 */
function traceLine(S, record, showState) {
  const bytes = encode(canonical(S));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const line = {
    t: record.t,
    in: record.in,
    c: (view.getBigUint64(bytes.byteLength - 8, true) & U64_MAX).toString(),
  };
  if (showState) line.s = Buffer.from(bytes).toString('hex');
  return line;
}

/**
 * sim.mjs's single-snake state in the shape canon.mjs's encode() expects.
 * `S.dir`/`S.nextDir` are DIRS vectors (`{x,y}`), not the name encode() wants
 * (docs/canonical-state.md) — dirName() translates them.
 */
const canonical = (S) => ({
  cols: S.cols, rows: S.rows, wrap: S.wrap, tick: S.tick, rngState: rngState(S),
  food: S.food,
  players: [{
    status: S.status, dir: dirName(S.dir), nextDir: dirName(S.nextDir), score: S.score, cells: S.snake,
  }],
});

/**
 * oracle_sha256 (docs/corpus-format.md, TASK-016): lowercase hex SHA-256 over
 * the concatenated raw bytes of every `reference/oracle/*.mjs` file — a
 * non-recursive scan of the oracle directory itself, so `corpus/` (data, not
 * source) is excluded — sorted ascending by filename and joined with no
 * delimiter. Whichever oracle source is on disk when a regen runs is the
 * source recorded in the manifest, check scripts included.
 */
export function oracleSha256(root) {
  const names = readdirSync(join(root, ORACLE_DIR), { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.mjs'))
    .map((e) => e.name)
    .sort();
  const hash = createHash('sha256');
  for (const name of names) hash.update(readFileSync(join(root, ORACLE_DIR, name)));
  return hash.digest('hex');
}

/**
 * manifest.json: the CORPUS_VERSION, the oracle_sha256 of the sources that
 * produced it, and every corpus file with the CORPUS_VERSION it was generated
 * under (TASK-014 AC#2), sorted lexicographically by `name`. Each entry
 * repeats the version even though a full regen always writes one version, so a
 * future partial regen cannot leave mixed versions undetected.
 */
export function renderManifest(traces, oracleSha256Hex) {
  return `${JSON.stringify({
    corpus_version: CORPUS_VERSION,
    oracle_sha256: oracleSha256Hex,
    files: traces.map((t) => ({
      name: t.name,
      file: `${t.name}.jsonl`,
      ticks: t.ticks,
      corpus_version: CORPUS_VERSION,
    })),
  }, null, 2)}\n`;
}

/**
 * core/corpus.zig: the same set of files, in the same order, as a
 * comptime-known array a future build.zig can iterate (Zig's build graph
 * cannot read JSON). `path` is relative to game/, matching how the Tier-D
 * suite reads them via res://tests/corpus/.
 */
export function renderCorpusZig(traces) {
  const entries = traces.map((t) =>
    `    .{ .name = "${t.name}", .path = "tests/corpus/${t.name}.jsonl" },`).join('\n');
  return `// Generated by regen_corpus.mjs — do not edit by hand.

pub const CORPUS_VERSION: u32 = ${CORPUS_VERSION};

pub const Entry = struct {
    name: []const u8,
    path: []const u8,
};

pub const entries = [_]Entry{
${entries}
};
`;
}

/**
 * Generate everything from the command logs under `root`: a map of repo-root-
 * relative path to the exact bytes to write, plus the trace summaries. Throws
 * on the first malformed command log rather than emitting a partial corpus.
 */
export function generate(root) {
  const logs = findCommandLogs(join(root, COMMAND_DIR));
  if (logs.length === 0) throw new Error(`no command logs found under ${COMMAND_DIR}`);

  const files = new Map();
  const traces = [];
  for (const [name, file] of logs) {
    const lines = renderTrace(parseCommandLog(readFileSync(file, 'utf8'), file));
    traces.push({ name, ticks: lines.length - 1 });
    files.set(join(TRACE_DIR, `${name}.jsonl`), jsonl(lines));
  }
  traces.sort(byName);

  files.set(MANIFEST_PATH, renderManifest(traces, oracleSha256(root)));
  files.set(ZIG_PATH, renderCorpusZig(traces));
  return { files, traces };
}

/**
 * Command logs under `dir` as [trace name, path] pairs, sorted by path so a
 * filesystem's listing order never leaks into the output. Two logs reducing to
 * the same trace name (e.g. `a.commands.jsonl` and `a.b.commands.jsonl`, whose
 * extra dot the name slice cannot tell apart) would silently overwrite each
 * other, so that is rejected up front.
 */
function findCommandLogs(dir) {
  const byName_ = new Map();
  const walk = (sub) => {
    for (const entry of readdirSync(sub, { withFileTypes: true })) {
      const path = join(sub, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name.endsWith(SUFFIX)) {
        const name = entry.name.slice(0, -SUFFIX.length);
        const clash = byName_.get(name);
        if (clash) {
          throw new Error(`${basename(clash)} and ${basename(path)} both name the trace "${name}"`);
        }
        byName_.set(name, path);
      }
    }
  };
  walk(dir);
  return [...byName_.entries()].sort((a, b) => (a[1] < b[1] ? -1 : 1));
}

/**
 * The committed .jsonl traces currently in TRACE_DIR that no command log
 * produces anymore. Left in place they would stay part of the corpus the
 * manifest does not list, so a regen removes them.
 */
function orphanTraces(root, files) {
  const expected = new Set();
  for (const path of files.keys()) {
    if (path.startsWith(`${TRACE_DIR}/`)) expected.add(path);
  }
  let names;
  try {
    names = readdirSync(join(root, TRACE_DIR));
  } catch {
    return [];
  }
  return names
    .filter((n) => n.endsWith('.jsonl'))
    .map((n) => join(TRACE_DIR, n))
    .filter((p) => !expected.has(p));
}

/** Lexicographic by name — the ordering rule docs/corpus-format.md fixes for both listings. */
function byName(a, b) {
  if (a.name < b.name) return -1;
  return a.name > b.name ? 1 : 0;
}

/** One `JSON.stringify` per object, plus the trailing newline the files end with. */
const jsonl = (lines) => lines.map((line) => JSON.stringify(line)).join('\n') + '\n';

/**
 * Write `files` under `root`, creating TRACE_DIR (which holds committed corpus
 * output for the first time). Returns the paths actually changed, so the
 * caller can report what a regen did.
 */
function writeFiles(root, files) {
  const changed = [];
  for (const [path, content] of files) {
    const target = join(root, path);
    let before;
    try {
      before = readFileSync(target);
    } catch {
      mkdirSync(dirname(target), { recursive: true });
    }
    if (before?.equals(Buffer.from(content))) continue;
    writeFileSync(target, content);
    changed.push(path);
  }
  for (const path of orphanTraces(root, files)) {
    unlinkSync(join(root, path));
    changed.push(path);
  }
  return changed;
}

/** Exit 1 with this diff when `root`'s artifacts do not match a fresh regen. */
function checkAgainst(root, files) {
  const stale = [];
  for (const [path, content] of files) {
    let before = null;
    try {
      before = readFileSync(join(root, path), 'utf8');
    } catch {
      /* missing counts as drift below */
    }
    if (before !== content) stale.push(path);
  }
  stale.push(...orphanTraces(root, files));
  if (stale.length === 0) {
    console.log(`corpus up to date (${files.size - 2} traces, CORPUS_VERSION ${CORPUS_VERSION})`);
    return;
  }
  console.error(`corpus drift under ${TRACE_DIR}:`);
  for (const path of stale.sort()) console.error(`  ${path}`);
  process.exitCode = 1;
}

/**
 * Exit 1 unless the committed manifest's oracle_sha256 equals the hash of the
 * oracle sources currently on disk. A mismatch means the oracle changed since
 * the last `task oracle:regen` — even if every trace still regenerates
 * byte-identically (docs/corpus-format.md: why two checks, not one), the
 * corpus on record no longer names its own generator.
 */
function verifyOracleHash(root, files) {
  const actual = JSON.parse(files.get(MANIFEST_PATH)).oracle_sha256;
  let recorded = null;
  try {
    recorded = JSON.parse(readFileSync(join(root, MANIFEST_PATH), 'utf8')).oracle_sha256;
  } catch {
    /* missing or unreadable manifest counts as a mismatch below */
  }
  if (recorded === actual) {
    console.log(`oracle_sha256 matches the committed manifest (${actual})`);
    return;
  }
  console.error('oracle_sha256 mismatch: the oracle sources in reference/oracle/ '
    + 'have changed since the committed corpus was regenerated. Run task oracle:regen.');
  console.error(`  committed manifest: ${recorded ?? '(missing)'}`);
  console.error(`  current sources:    ${actual}`);
  process.exitCode = 1;
}

function main(argv) {
  const check = argv.includes('--check');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const { files, traces } = generate(root);
  if (check || argv.includes('--verify')) {
    if (argv.includes('--verify')) verifyOracleHash(root, files);
    checkAgainst(root, files);
    return;
  }
  const changed = writeFiles(root, files);
  const total = traces.reduce((sum, t) => sum + t.ticks, 0);
  console.log(`generated ${traces.length} traces, ${total} tick lines ` +
    `(${changed.length} file(s) changed) at CORPUS_VERSION ${CORPUS_VERSION}`);
  for (const t of traces) console.log(`  ${t.name}.jsonl  ticks=${t.ticks}`);
}

const parseLine = (raw, file, lineNo) => {
  let value;
  try {
    value = JSON.parse(raw);
  } catch (cause) {
    fail(`${at(file, lineNo)}: not JSON (${cause.message})`, lineNo);
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail(`${at(file, lineNo)}: expected a JSON object`, lineNo);
  }
  return value;
};

const rejectUnknown = (obj, known, file, lineNo) => {
  const extra = Object.keys(obj).filter((k) => !known.includes(k));
  if (extra.length) fail(`${at(file, lineNo)}: unknown field(s) ${extra.join(', ')}`, lineNo);
};

const isU8 = (v) => Number.isInteger(v) && v >= 0 && v <= 255;
const isU16 = (v) => Number.isInteger(v) && v >= 0 && v <= 65535;
const isU32 = (v) => Number.isInteger(v) && v >= 0 && v <= 4294967295;

function fail(message, lineNo) {
  throw error(message, lineNo);
}

function error(message, lineNo) {
  const err = new Error(message);
  err.lineNo = lineNo;
  return err;
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) main(process.argv.slice(2));
