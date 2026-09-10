// Self-check for rng.mjs + canon.mjs against the vectors published in
// docs/rng.md and docs/canonical-state.md. Run: node reference/oracle/self-check.mjs
import { createHash } from 'node:crypto';
import { createRng, boundedDraw } from './rng.mjs';
import { encode, decode, verify } from './canon.mjs';

let failed = 0;
const check = (label, actual, expected) => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) console.log(`ok   ${label}`);
  else { failed++; console.log(`FAIL ${label}\n  expected ${e}\n  actual   ${a}`); }
};

// --- docs/rng.md: seed [1,2,3,4], first 8 raw next() outputs ---
{
  const rng = createRng([1, 2, 3, 4]);
  const hex = [];
  for (let i = 0; i < 8; i++) hex.push('0x' + rng.next().toString(16).padStart(8, '0'));
  check('rng first 8 outputs', hex, [
    '0x00002d00', '0x00000000', '0x005a7080', '0x04389d80',
    '0x79199d9b', '0x61963b24', '0x4cb9b57a', '0xde9d7431',
  ]);
  check('rng state after 8 calls', rng.state().map((v) => '0x' + v.toString(16).padStart(8, '0')),
    ['0x3320a290', '0xebdc5e1d', '0x90c43618', '0xe4b42f08']);

  // Same seed, boundedDraw(n=573) for the first 5 draws from a fresh stream.
  const fresh = createRng([1, 2, 3, 4]);
  check('boundedDraw(573) x5', Array.from({ length: 5 }, () => boundedDraw(fresh.next, 573)),
    [0, 0, 0, 9, 271]);
}

// --- docs/canonical-state.md: worked 3-cell, 1-player start state ---
{
  // Byte-for-byte the doc's published 80-byte hex dump, row by row.
  const expected =
    '4e454f534e414b450100180018000000' +
    '0100000000000000' +
    '01000000020000000300000004000000' +
    '00000000' +
    '01030300' +
    '0000000003000000' +
    '00000000' +
    '08000c0007000c0006000c00' +
    '5a33a241af35a7d1';

  const state = {
    cols: 24,
    rows: 24,
    wrap: false,
    tick: 0,
    rngState: [1, 2, 3, 4],
    food: { x: 0, y: 0 },
    players: [{
      status: 'playing',
      dir: 'right',
      nextDir: 'right',
      score: 0,
      cells: [{ x: 8, y: 12 }, { x: 7, y: 12 }, { x: 6, y: 12 }],
    }],
  };

  const bytes = encode(state);
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  check('canon 80-byte worked example', hex, expected);
  check('canon record length', bytes.byteLength, 80);

  const digest = createHash('sha256').update(bytes.subarray(0, 72)).digest('hex');
  check('canon sha256 of [0,72)', digest,
    '5a33a241af35a7d1aad051a37e4ccdf99927cfd40e9ba513a6a50607b0fb0ead');

  check('canon verify()', verify(bytes), true);
  check('canon round-trip', encode(decode(bytes)), bytes);
  check('canon decoded fields', decode(bytes), {
    canonVersion: 1,
    cols: 24,
    rows: 24,
    wrap: false,
    tick: 0,
    rngState: [1, 2, 3, 4],
    food: { x: 0, y: 0 },
    players: [{
      status: 'playing',
      dir: 'right',
      nextDir: 'right',
      score: 0,
      cells: [{ x: 8, y: 12 }, { x: 7, y: 12 }, { x: 6, y: 12 }],
    }],
    checksum: '5a33a241af35a7d1',
  });

  // No-food sentinel round-trips as null.
  const noFood = decode(encode({ ...state, food: null }));
  check('canon food sentinel', [noFood.food, verify(encode({ ...state, food: null }))], [null, true]);
}

console.log(failed === 0 ? 'ALL CHECKS PASSED' : `${failed} CHECK(S) FAILED`);
process.exit(failed === 0 ? 0 : 1);
