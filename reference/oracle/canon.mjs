// Canonical state serializer — implementation of docs/canonical-state.md.
//
// Every multi-byte write goes through DataView's explicit-width setters with
// an explicit littleEndian=true argument: the setters apply ToUint16/ToUint32
// internally, so no float value and no |0 sign-confusion can reach the byte
// layout. Readers must tolerate the reserved bytes (zero on write, ignored on
// read).

import { createHash } from 'node:crypto';

export const NS_CANON_VERSION = 1;
export const MAGIC = 'NEOSNAKE';
export const HEADER_BYTES = 44;
export const PLAYER_FIXED_BYTES = 16;
export const CHECKSUM_BYTES = 8;

// Cell coordinate sentinel for "no food placed" (board full / win).
export const NO_CELL = 0xffff;

// Encoding tables (docs/canonical-state.md). Both reuse reference/snake.html's
// own declared ordering so the numbers stay traceable to the oracle.
export const STATUS = { menu: 0, playing: 1, paused: 2, dead: 3 };
export const DIR = { up: 0, down: 1, left: 2, right: 3 };

const FLAG_WRAP = 0x0001;

/**
 * Serialize a simulation state to the canonical byte record.
 *
 * `state` shape (all integers; `status`/`dir`/`nextDir` accept the names from
 * STATUS/DIR or their numeric encodings):
 *   { cols, rows, wrap, tick, rngState: [u32 x4],
 *     food: {x, y} | null,
 *     players: [{ status, dir, nextDir, score, cells: [{x, y}, ... head-first] }] }
 */
export function encode(state) {
  const players = state.players;
  if (!Array.isArray(players) || players.length < 1 || players.length > 255) {
    throw new RangeError('players must be 1..255 records');
  }

  let size = HEADER_BYTES;
  for (const p of players) {
    if (!Array.isArray(p.cells)) throw new TypeError('player.cells must be an array');
    size += PLAYER_FIXED_BYTES + 4 * p.cells.length;
  }
  size += CHECKSUM_BYTES;

  const buf = new ArrayBuffer(size);
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);
  let o = 0;

  // --- header (44 bytes) ---
  for (let i = 0; i < MAGIC.length; i++) {
    view.setUint8(o + i, MAGIC.charCodeAt(i));
  }
  o += 8;
  view.setUint16(o, NS_CANON_VERSION, true);
  o += 2;
  view.setUint16(o, state.cols, true);
  o += 2;
  view.setUint16(o, state.rows, true);
  o += 2;
  view.setUint16(o, state.wrap ? FLAG_WRAP : 0, true);
  o += 2;
  view.setUint8(o, players.length);
  o += 1;
  view.setUint8(o, 0); // reserved[0]
  view.setUint8(o + 1, 0); // reserved[1]
  view.setUint8(o + 2, 0); // reserved[2]
  o += 3;
  view.setUint32(o, state.tick, true);
  o += 4;
  for (let i = 0; i < 4; i++) {
    view.setUint32(o, state.rngState[i], true);
    o += 4;
  }
  view.setUint16(o, state.food ? state.food.x : NO_CELL, true);
  o += 2;
  view.setUint16(o, state.food ? state.food.y : NO_CELL, true);
  o += 2;

  // --- per-player records, ascending player index ---
  for (const p of players) {
    view.setUint8(o, encStatus(p.status));
    view.setUint8(o + 1, encDir(p.dir));
    view.setUint8(o + 2, encDir(p.nextDir ?? p.dir));
    view.setUint8(o + 3, 0); // reserved — pads score to a 4-byte offset
    o += 4;
    view.setUint32(o, p.score, true);
    o += 4;
    view.setUint32(o, p.cells.length, true);
    o += 4;
    view.setUint32(o, 0, true); // reserved
    o += 4;
    for (const cell of p.cells) {
      view.setUint16(o, cell.x, true);
      o += 2;
      view.setUint16(o, cell.y, true);
      o += 2;
    }
  }

  // --- checksum trailer: SHA-256 of everything before it, first 8 digest
  // bytes reinterpreted as a little-endian u64, written back little-endian. ---
  const digest = createHash('sha256').update(bytes.subarray(0, o)).digest();
  bytes.set(digest.subarray(0, CHECKSUM_BYTES), o);

  return bytes;
}

/**
 * Parse a canonical byte record back into a plain state object. Throws on
 * magic/version/length mismatch; the checksum is not verified here (the
 * record's own bytes are needed to recompute it — see verify()).
 */
export function decode(bytes) {
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const view = new DataView(buf);
  const size = bytes.byteLength;
  if (size < HEADER_BYTES + CHECKSUM_BYTES) throw new RangeError('record too short');
  if (ascii(view, 0, 8) !== MAGIC) throw new RangeError('bad magic');

  const canonVersion = view.getUint16(8, true);
  if (canonVersion !== NS_CANON_VERSION) throw new RangeError(`unsupported canon_version ${canonVersion}`);

  const playerCount = view.getUint8(16);
  if (playerCount < 1) throw new RangeError('player_count must be >= 1');

  const players = [];
  let o = HEADER_BYTES;
  for (let i = 0; i < playerCount; i++) {
    if (o + PLAYER_FIXED_BYTES > size - CHECKSUM_BYTES) throw new RangeError('truncated player record');
    const bodyLen = view.getUint32(o + 8, true);
    if (o + PLAYER_FIXED_BYTES + 4 * bodyLen > size - CHECKSUM_BYTES) {
      throw new RangeError('truncated cell list');
    }
    const cells = [];
    let c = o + PLAYER_FIXED_BYTES;
    for (let j = 0; j < bodyLen; j++, c += 4) {
      cells.push({ x: view.getUint16(c, true), y: view.getUint16(c + 2, true) });
    }
    players.push({
      status: decStatus(view.getUint8(o)),
      dir: decDir(view.getUint8(o + 1)),
      nextDir: decDir(view.getUint8(o + 2)),
      score: view.getUint32(o + 4, true),
      cells,
    });
    o = c;
  }
  if (o + CHECKSUM_BYTES !== size) throw new RangeError('trailing bytes after last record');

  const foodX = view.getUint16(40, true);
  const foodY = view.getUint16(42, true);
  return {
    canonVersion,
    cols: view.getUint16(10, true),
    rows: view.getUint16(12, true),
    wrap: (view.getUint16(14, true) & FLAG_WRAP) !== 0,
    tick: view.getUint32(20, true),
    rngState: [
      view.getUint32(24, true),
      view.getUint32(28, true),
      view.getUint32(32, true),
      view.getUint32(36, true),
    ],
    food: foodX === NO_CELL || foodY === NO_CELL ? null : { x: foodX, y: foodY },
    players,
    checksum: digestHex(view, o),
  };
}

/** Recompute the checksum over a whole record and compare it to the trailer. */
export function verify(bytes) {
  const body = bytes.subarray(0, bytes.byteLength - CHECKSUM_BYTES);
  const digest = createHash('sha256').update(body).digest();
  const expected = bytes.subarray(bytes.byteLength - CHECKSUM_BYTES);
  for (let i = 0; i < CHECKSUM_BYTES; i++) {
    if (digest[i] !== expected[i]) return false;
  }
  return true;
}

/** The 8-byte trailer as the hex string SHA-256 produces it (digest order). */
function digestHex(view, offset) {
  let out = '';
  for (let i = 0; i < CHECKSUM_BYTES; i++) {
    out += view.getUint8(offset + i).toString(16).padStart(2, '0');
  }
  return out;
}

const ascii = (view, offset, len) => {
  let out = '';
  for (let i = 0; i < len; i++) out += String.fromCharCode(view.getUint8(offset + i));
  return out;
};

const encStatus = (v) => (typeof v === 'number' ? v : STATUS[v]);
const encDir = (v) => (typeof v === 'number' ? v : DIR[v]);

const STATUS_NAMES = ['menu', 'playing', 'paused', 'dead'];
const DIR_NAMES = ['up', 'down', 'left', 'right'];
const decStatus = (v) => STATUS_NAMES[v];
const decDir = (v) => DIR_NAMES[v];
