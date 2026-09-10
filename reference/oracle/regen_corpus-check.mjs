// Self-check for regen_corpus.mjs against docs/corpus-format.md — the command
// log schema, the JSONL trace schema, manifest.json and core/corpus.zig. Run:
// node reference/oracle/regen_corpus-check.mjs
//
// TASK-014 AC#1 ("running task oracle:regen twice produces byte-identical
// output") is checked by generating twice from the committed command logs and
// comparing the bytes, including through the real write path in a scratch tree.
// AC#2 is checked against the files on disk, not only the strings in memory, so
// a trace the manifest lists but no run wrote is a failure.
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { advance, initialState, queueDir, rngState } from './sim.mjs';
import { encode, verify } from './canon.mjs';
import {
  CORPUS_VERSION, generate, parseCommandLog, renderTrace,
} from './regen_corpus.mjs';

// The repo whose corpus this checks, resolved from this script's own location
// so the run does not depend on the caller's cwd.
const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const COMMAND_DIR = 'reference/oracle/corpus/commands';
const TRACE_DIR = 'game/tests/corpus';
const MANIFEST = 'game/tests/corpus/manifest.json';
const CORPUS_ZIG = 'core/corpus.zig';

let failed = 0;
const check = (label, actual, expected) => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) console.log(`ok   ${label}`);
  else { failed++; console.log(`FAIL ${label}\n  expected ${e}\n  actual   ${a}`); }
};

const read = (path) => readFileSync(join(ROOT, path), 'utf8');

/** A trace file as [header, tick lines...] with every line already parsed. */
const readTrace = (name) => {
  const lines = read(join(TRACE_DIR, `${name}.jsonl`)).trimEnd().split('\n').map((l) => JSON.parse(l));
  return { header: lines[0], ticks: lines.slice(1) };
};

/** The command log a committed trace was generated from. */
const readLog = (name) => parseCommandLog(
  readFileSync(join(ROOT, COMMAND_DIR, `${name}.commands.jsonl`), 'utf8'),
  `${name}.commands.jsonl`,
);

/** The rejection message for a command log that must not parse. */
const rejected = (text, file = 'bad.commands.jsonl') => {
  try {
    parseCommandLog(text, file);
  } catch (err) {
    return err.message;
  }
  return '(accepted, expected rejection)';
};

/** The 8-byte canonical checksum trailer read as a little-endian u64, decimal. */
const checksum = (bytes) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  .getBigUint64(bytes.byteLength - 8, true).toString();

const manifestFiles = () => JSON.parse(read(MANIFEST)).files;

// --- AC#1: two regens from the committed command logs are byte-identical ---
{
  const first = generate(ROOT);
  const second = generate(ROOT);
  const differs = [];
  for (const [path, bytes] of first.files) {
    if (second.files.get(path) !== bytes) differs.push(path);
  }
  check('two regens produce the same file set',
    [...first.files.keys()].sort(), [...second.files.keys()].sort());
  check('two regens produce byte-identical files', differs, []);

  // And the committed output is those bytes right now, which is the same
  // comparison `regen_corpus.mjs --check` makes.
  check('committed output matches a fresh regen',
    [...first.files].filter(([path, bytes]) => read(path) !== bytes).map(([path]) => path), []);

  const traceFiles = [...first.files.keys()].filter((p) => p.endsWith('.jsonl'));
  check('one trace per command log', traceFiles.length, first.traces.length);
  check('the three artifact kinds are all present',
    [first.files.has(MANIFEST), first.files.has(CORPUS_ZIG), traceFiles.length > 0], [true, true, true]);
}

// --- AC#2: manifest.json lists every corpus file with its CORPUS_VERSION ---
{
  const manifest = JSON.parse(read(MANIFEST));
  const listed = manifest.files.map((e) => e.file);

  // Read the directory rather than generate(): the point is that the files on
  // disk and the manifest agree, so the manifest cannot be graded against itself.
  const onDisk = readdirSync(join(ROOT, TRACE_DIR)).filter((n) => n.endsWith('.jsonl')).sort();
  check('manifest lists every trace on disk', [...listed].sort(), onDisk);
  check('manifest corpus_version', manifest.corpus_version, CORPUS_VERSION);
  check('every entry repeats corpus_version',
    manifest.files.map((e) => e.corpus_version), manifest.files.map(() => CORPUS_VERSION));
  check('every entry names its own file',
    listed, manifest.files.map((e) => `${e.name}.jsonl`));
  check('manifest files sorted lexicographically by name',
    listed, [...listed].sort());

  // Each entry's tick count is the file's tick line count, and each file's
  // header carries the same version.
  const ticks = [];
  const versions = [];
  for (const entry of manifest.files) {
    const { header, ticks: lines } = readTrace(entry.name);
    ticks.push(lines.length);
    versions.push(header.corpus_version);
  }
  check('manifest ticks equal each trace line count', ticks, manifest.files.map((e) => e.ticks));
  check('every trace header carries corpus_version',
    versions, manifest.files.map(() => CORPUS_VERSION));
  check('CORPUS_VERSION starts at 1', CORPUS_VERSION, 1);

  // core/corpus.zig: the same set in the same order, same version constant,
  // and paths relative to game/ (how the Tier-D suite reads them).
  const zig = read(CORPUS_ZIG);
  const zigEntries = [...zig.matchAll(/\.name = "([^"]+)", \.path = "([^"]+)"/g)]
    .map((m) => ({ name: m[1], path: m[2] }));
  check('corpus.zig entries match the manifest names',
    zigEntries.map((e) => e.name), manifest.files.map((e) => e.name));
  check('corpus.zig paths are relative to game/',
    zigEntries.map((e) => e.path), manifest.files.map((e) => `tests/corpus/${e.file}`));
  check('corpus.zig CORPUS_VERSION',
    zig.match(/pub const CORPUS_VERSION: u32 = (\d+);/)?.[1], String(CORPUS_VERSION));
  check('corpus.zig declares itself generated', zig.startsWith('// Generated by regen_corpus.mjs'), true);
}

// --- trace schema: header fields, per-tick fields, and the anchor rule ---
{
  for (const entry of manifestFiles()) {
    const { header, ticks } = readTrace(entry.name);
    const log = readLog(entry.name);

    // Header: the command log's fields minus `ticks`, plus `corpus_version`.
    const { name: _name, events: _events, file: _file, ticks: _cap, ...fromLog } = log;
    const rest = { ...header };
    delete rest.corpus_version;
    check(`${entry.name}: header restates its command log`, rest, fromLog);
    check(`${entry.name}: header has no fields beyond the schema`,
      Object.keys(header).sort(), ['cols', 'corpus_version', 'players', 'rows', 'seed', 'wrap']);

    const badFields = [];
    const badAnchor = [];
    const badChecksum = [];
    const badOrder = [];
    let prevT = -1;
    for (const tick of ticks) {
      const fields = Object.keys(tick).sort().join(',');
      const wantFields = tick.s === undefined ? 'c,in,t' : 'c,in,s,t';
      if (fields !== wantFields) badFields.push(`t${tick.t}: ${fields}`);

      // Full state on tick 0, on every 64th recorded tick, and on the last tick
      // — never any other tick.
      const isLast = tick === ticks.at(-1);
      const wantState = tick.t === 0 || (tick.t + 1) % 64 === 0 || isLast;
      if ((tick.s !== undefined) !== wantState) badAnchor.push(`t${tick.t}`);
      if (tick.s !== undefined && !/^[0-9a-f]+$/.test(tick.s)) badAnchor.push(`t${tick.t}: non-lowercase-hex state`);

      if (typeof tick.c !== 'string' || !/^\d+$/.test(tick.c) || BigInt(tick.c) > 18446744073709551615n) {
        badChecksum.push(`t${tick.t}: ${tick.c}`);
      }
      if (tick.t !== prevT + 1) badOrder.push(`${prevT} then ${tick.t}`);
      if (!Array.isArray(tick.in)) badOrder.push(`t${tick.t}: in is not an array`);
      prevT = tick.t;
    }
    check(`${entry.name}: every tick line has exactly the schema fields`, badFields, []);
    check(`${entry.name}: state only on tick 0, every 64th tick, and the last tick`, badAnchor, []);
    check(`${entry.name}: every checksum is a decimal u64 string`, badChecksum, []);
    check(`${entry.name}: tick numbers run 0..${ticks.length - 1} with array "in" throughout`, badOrder, []);
    check(`${entry.name}: trace is never longer than its ticks cap`, ticks.length <= log.ticks, true);
    check(`${entry.name}: last tick is a full-state anchor`, ticks.at(-1).s !== undefined, true);
  }
}

// --- every recorded checksum, state and input reproduces from its log ---
{
  // Re-drive sim.mjs from each command log, independently of how the trace was
  // formatted, and compare against the recorded bytes. canon.mjs's own verify()
  // gets the anchor records too, so a trace whose bytes do not hash to their own
  // trailer cannot pass.
  const mismatches = [];
  for (const entry of manifestFiles()) {
    const { ticks } = readTrace(entry.name);
    const log = readLog(entry.name);

    const S = initialState({
      seed: log.seed, status: 'playing', wrap: log.wrap, cols: log.cols, rows: log.rows,
    });
    const queued = new Map();
    for (const ev of log.events) {
      if (!queued.has(ev.t)) queued.set(ev.t, []);
      queued.get(ev.t).push(ev);
    }

    for (const tick of ticks) {
      const applied = (queued.get(tick.t) || []).map((ev) => {
        queueDir(S, ev.in);
        return { p: ev.p, dir: ev.in };
      });
      advance(S);
      const bytes = encode({
        cols: S.cols, rows: S.rows, wrap: S.wrap, tick: S.tick, rngState: rngState(S),
        food: S.food,
        players: [{ status: S.status, dir: S.dir, nextDir: S.nextDir, score: S.score, cells: S.snake }],
      });
      if (checksum(bytes) !== tick.c) mismatches.push(`${entry.name} t${tick.t}: checksum`);
      if (JSON.stringify(applied) !== JSON.stringify(tick.in)) mismatches.push(`${entry.name} t${tick.t}: inputs`);
      if (tick.s !== undefined) {
        if (Buffer.from(bytes).toString('hex') !== tick.s) mismatches.push(`${entry.name} t${tick.t}: state`);
        if (!verify(bytes)) mismatches.push(`${entry.name} t${tick.t}: verify()`);
      }
    }
  }
  check('every trace reproduces tick-for-tick from its command log', mismatches, []);
}

// --- what the fixtures cover: wrap, wall, an early stop, a full-state anchor ---
{
  const names = manifestFiles().map((e) => e.name);
  const headerOf = (name) => readTrace(name).header;
  const capOf = (name) => readLog(name).ticks;
  const ranToCap = (name) => {
    const { ticks } = readTrace(name);
    return ticks.length === capOf(name);
  };

  check('a wrap trace exists', names.some((n) => headerOf(n).wrap), true);
  check('a wall (non-wrap) trace exists', names.some((n) => !headerOf(n).wrap), true);
  check('a trace runs the full length of its ticks cap', names.filter(ranToCap).length >= 1, true);
  check('a trace stops early before its cap', names.filter((n) => !ranToCap(n)).length >= 1, true);
  check('a trace spans more than one 64-tick anchor block',
    names.some((n) => readTrace(n).ticks.filter((t) => t.s !== undefined).length > 2), true);

  // sim.mjs simulates one snake, so every committed trace is single-player;
  // `p` is still explicit on every event rather than implicit.
  check('every committed trace is single-player for now',
    [...new Set(names.map((n) => headerOf(n).players))], [1]);
  const usedP = new Set();
  for (const n of names) for (const t of readTrace(n).ticks) for (const i of t.in) usedP.add(i.p);
  check('every recorded input names player 0 explicitly', [...usedP], [0]);
}

// --- parseCommandLog: the schema and the rejections the spec requires ---
{
  const H = '{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":false,"players":1,"ticks":200}';
  const parsed = parseCommandLog(`${H}\n{"t":5,"p":0,"in":"up"}\n{"t":9,"p":0,"in":"left"}\n`, 'ok.commands.jsonl');
  check('a valid log parses to header + events',
    [parsed.name, parsed.seed, parsed.cols, parsed.wrap, parsed.players, parsed.ticks, parsed.events.length],
    ['ok', [1, 2, 3, 4], 24, false, 1, 200, 2]);
  check('a header-only log is legal', parseCommandLog(`${H}\n`, 'none.commands.jsonl').events, []);
  check('a log without a trailing newline is legal', parseCommandLog(H, 'bare.commands.jsonl').ticks, 200);

  // Two events for the same tick and player are an authoring bug: rejected with
  // the file and line named, never silently deduped.
  check('duplicate (t, p) rejected with file:line',
    rejected(`${H}\n{"t":5,"p":0,"in":"up"}\n{"t":5,"p":0,"in":"down"}\n`),
    'bad.commands.jsonl line 3: two events at t=5 for p=0 (same tick and player)');
  check('events not sorted by t rejected with file:line',
    rejected(`${H}\n{"t":9,"p":0,"in":"up"}\n{"t":5,"p":0,"in":"down"}\n`),
    'bad.commands.jsonl line 3: events must be sorted ascending by t (9 then 5)');
  check('same t with ascending p is the legal multiplayer tie-break',
    parseCommandLog(
      `${H.replace('"players":1', '"players":2')}\n{"t":5,"p":0,"in":"up"}\n{"t":5,"p":1,"in":"down"}\n`,
      'two.commands.jsonl',
    ).events.map((e) => e.p), [0, 1]);

  check('descending p at the same t rejected',
    rejected(`${H.replace('"players":1', '"players":2')}\n{"t":5,"p":1,"in":"up"}\n{"t":5,"p":0,"in":"down"}\n`)
      .includes('two events at t=5 for p=0'), true);
  check('unknown direction rejected', rejected(`${H}\n{"t":1,"p":0,"in":"diagonal"}\n`).includes('event in must be one of'), true);
  check('missing event field rejected', rejected(`${H}\n{"t":1,"p":0}\n`).includes('event missing "in"'), true);
  check('unknown event field rejected', rejected(`${H}\n{"t":1,"p":0,"in":"up","extra":true}\n`).includes('unknown field(s) extra'), true);
  check('event player outside the game rejected', rejected(`${H}\n{"t":1,"p":1,"in":"up"}\n`).includes('outside the 1-player game'), true);
  check('event t above u32 rejected', rejected(`${H}\n{"t":4294967296,"p":0,"in":"up"}\n`).includes('event t must be a u32'), true);
  check('event p above u8 rejected', rejected(`${H.replace('"players":1', '"players":255')}\n{"t":1,"p":300,"in":"up"}\n`).includes('event p must be a u8'), true);
  check('header missing a field rejected',
    rejected('{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":false,"players":1}\n').includes('header missing "ticks"'), true);
  check('header with an unknown field rejected',
    rejected(H.replace('"ticks":200', '"ticks":200,"speed":2')).includes('unknown field(s) speed'), true);
  check('seed must be four u32 values',
    rejected('{"seed":[1,2,3],"cols":24,"rows":24,"wrap":false,"players":1,"ticks":1}\n').includes('seed must be four u32'), true);
  check('all-zero seed rejected (rng precondition)',
    rejected('{"seed":[0,0,0,0],"cols":24,"rows":24,"wrap":false,"players":1,"ticks":1}\n').includes('not all zero'), true);
  check('wrap must be a boolean',
    rejected('{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":"yes","players":1,"ticks":1}\n').includes('wrap must be a boolean'), true);
  check('players must be >= 1',
    rejected('{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":false,"players":0,"ticks":1}\n').includes('players must be a u8 >= 1'), true);
  check('fractional ticks rejected',
    rejected('{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":false,"players":1,"ticks":1.5}\n').includes('ticks must be a u32'), true);
  check('cols above u16 rejected',
    rejected('{"seed":[1,2,3,4],"cols":70000,"rows":24,"wrap":false,"players":1,"ticks":1}\n').includes('cols/rows must be u16'), true);
  check('zero-sized board rejected',
    rejected('{"seed":[1,2,3,4],"cols":0,"rows":24,"wrap":false,"players":1,"ticks":1}\n').includes('cols/rows must be u16 >= 1'), true);
  check('non-object line rejected', rejected('[1,2,3]\n').includes('expected a JSON object'), true);
  check('unparseable line rejected', rejected('{oops\n').includes('not JSON'), true);
  check('empty log rejected', rejected('').includes('empty command log'), true);
}

// --- renderTrace: the ticks cap, the early stop, and the anchor rule ---
{
  const log = (over = {}) => ({
    name: 'synthetic', seed: [1, 2, 3, 4], cols: 24, rows: 24, wrap: false,
    players: 1, ticks: 100, events: [], ...over,
  });

  // Straight into the right wall with no input: 16 ticks, then the trace ends
  // rather than padding to the cap with post-death no-op ticks.
  const died = renderTrace(log({ ticks: 100 }));
  check('death ends the trace before the cap', [died.length - 1, died.at(-1).t], [16, 15]);
  check('the early stop really is shorter than the cap', died.length - 1 < 100, true);

  // On a wrap board with no input the snake cannot die, so the cap binds.
  check('ticks is an upper bound the trace may reach',
    renderTrace(log({ wrap: true, ticks: 9 })).length - 1, 9);
  check('a one-tick trace is header + t0', renderTrace(log({ wrap: true, ticks: 1 })).length, 2);

  // Anchors: t=0, every 64th recorded tick (t=63 and t=127), and the last tick
  // (t=129 is anchored only because it is last).
  const long = renderTrace(log({ wrap: true, ticks: 130 }));
  check('anchors are t=0, every 64th recorded tick, and the last tick',
    long.slice(1).filter((l) => l.s !== undefined).map((l) => l.t), [0, 63, 127, 129]);

  // An event lands on the tick it names, and only that tick reports it. The two
  // anchors at either end of it let the head coordinates be read back out of the
  // canonical hex: cells start at byte 60 of the record (char 120 of the hex),
  // head-first, as {x: u16, y: u16} little-endian.
  const turned = renderTrace(log({ ticks: 3, events: [{ t: 1, p: 0, in: 'up' }] }));
  check('the tick line reports the input applied to produce it',
    [turned[1].in, turned[2].in, turned[3].in], [[], [{ p: 0, dir: 'up' }], []]);
  const headOf = (line) => {
    const cell = Buffer.from(line.s.slice(120, 136), 'hex');
    return { x: cell.readUint16LE(0), y: cell.readUint16LE(2) };
  };
  check('t0 records the state the first advance produced', headOf(turned[1]), { x: 9, y: 12 });
  check('the last line records the state after the turn, two ticks past the start',
    headOf(turned.at(-1)), { x: 9, y: 10 });
}

// --- the write path: regenerating over its own output changes nothing ---
{
  const dir = mkdtempSync(join(tmpdir(), 'neo-snake-corpus-'));
  try {
    mkdirSync(join(dir, COMMAND_DIR), { recursive: true });
    writeFileSync(join(dir, COMMAND_DIR, 'only.commands.jsonl'),
      '{"seed":[1,2,3,4],"cols":24,"rows":24,"wrap":true,"players":1,"ticks":3}\n');
    const first = generate(dir);
    check('generate resolves paths relative to its root', [...first.files.keys()].sort(),
      [join(TRACE_DIR, 'only.jsonl'), MANIFEST, CORPUS_ZIG].sort());

    for (const [path, bytes] of first.files) {
      const target = join(dir, path);
      mkdirSync(join(target, '..'), { recursive: true });
      writeFileSync(target, bytes);
    }
    const second = generate(dir);
    check('regenerating over its own output is byte-identical',
      [...second.files.values()], [...first.files.values()]);

    // A trace file no command log produces is stale corpus output, not part of
    // the corpus, so a regen removes it.
    writeFileSync(join(dir, TRACE_DIR, 'stale.jsonl'), '{}\n');
    const third = generate(dir);
    check('generate emits only the traces its logs describe',
      [...third.files.keys()].filter((p) => p.endsWith('.jsonl')), [join(TRACE_DIR, 'only.jsonl')]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

console.log(failed === 0 ? 'ALL CHECKS PASSED' : `${failed} CHECK(S) FAILED`);
process.exit(failed === 0 ? 0 : 1);
