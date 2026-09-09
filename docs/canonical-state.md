# Canonical state format

This is the byte-for-byte wire format used to compare simulation state across independent
implementations (the JS oracle in `reference/oracle/`, `core/canon.zig`, and any future host). It
has **no analogue in `reference/snake.html`**: the reference oracle is single-player, seeds
`Math.random()` implicitly, and has no tick counter or serialized-state concept at all. Everything
here is new design for deterministic replay (TASK-012+) and multiplayer (TASK-051+), laid out by
TASK-007. `docs/rng.md` (TASK-008) documents the xoshiro128** algorithm that fills the RNG-state
field below; this document only reserves its byte width.

All multi-byte integers are **little-endian**. There are **no floating-point fields** anywhere in
the layout. Every byte marked "reserved" below must be written as zero and must be ignored (not
validated) by readers, so the format can grow new flag bits without a version bump.

## Header (44 bytes, fixed)

| Offset | Size | Field | Type | Notes |
| --- | --- | --- | --- | --- |
| 0 | 8 | `magic` | `u8[8]` | ASCII `"NEOSNAKE"`, no NUL terminator |
| 8 | 2 | `canon_version` | `u16` | `NS_CANON_VERSION`; `1` for this layout |
| 10 | 2 | `cols` | `u16` | Board width in cells |
| 12 | 2 | `rows` | `u16` | Board height in cells |
| 14 | 2 | `flags` | `u16` | Bit 0 = wrap mode (`S.wrap`); bits 1-15 reserved, zero |
| 16 | 1 | `player_count` | `u8` | Number of player records that follow (1 for single-player) |
| 17 | 3 | *reserved* | `u8[3]` | Zero. Pads `tick` to a 4-byte offset |
| 20 | 4 | `tick` | `u32` | Simulation tick counter, starts at 0 |
| 24 | 16 | `rng_state` | `u32[4]` | xoshiro128** state words `s0..s3`, see `docs/rng.md` |
| 40 | 2 | `food_x` | `u16` | Food column, or `0xFFFF` if no food is placed (board full / win) |
| 42 | 2 | `food_y` | `u16` | Food row, or `0xFFFF` if no food is placed |

Total header size: 44 bytes (offsets 0-43).

### `status` and direction encodings

Both reuse the reference oracle's own declared ordering so the encoding is traceable to
`reference/snake.html` rather than picked arbitrarily:

- `status` (`docs/architecture.md`'s documented order `menu | playing | paused | dead`): `0` = menu,
  `1` = playing, `2` = paused, `3` = dead.
- `dir` / `next_dir` (`snake.html`'s `DIRS` object key order: `up, down, left, right`): `0` = up,
  `1` = down, `2` = left, `3` = right.

## Per-player record (16-byte fixed block + variable-length cell list)

`player_count` records follow the header back-to-back, in ascending player index, starting at
offset 44. Each record is:

| Offset (within record) | Size | Field | Type | Notes |
| --- | --- | --- | --- | --- |
| 0 | 1 | `status` | `u8` | See encoding above |
| 1 | 1 | `dir` | `u8` | See encoding above |
| 2 | 1 | `next_dir` | `u8` | See encoding above |
| 3 | 1 | *reserved* | `u8` | Zero. Pads to a 4-byte offset |
| 4 | 4 | `score` | `u32` | |
| 8 | 4 | `body_len` | `u32` | Number of cells in `cells` below |
| 12 | 4 | *reserved* | `u32` | Zero. All four fixed fields are 4 bytes wide for a uniform 16-byte header per player |
| 16 | `4 * body_len` | `cells` | `{x: u16, y: u16}[body_len]` | Head-first (`cells[0]` is the snake's head), each cell 4 bytes (`x` then `y`) |

A record's total size is `16 + 4 * body_len` bytes. Records are read sequentially — there is no
per-record length prefix beyond `body_len` itself, so a reader must fully consume one record
(including its cells) before the next record begins.

## Checksum trailer (8 bytes, after the last player record)

| Field | Type | Notes |
| --- | --- | --- |
| `checksum` | `u64` | First 8 bytes of `SHA-256(header \|\| player_record_0 \|\| ... \|\| player_record_{n-1})`, interpreted as a little-endian `u64` |

Precise algorithm, stated so it is unambiguous in any of the four target languages (JS, Zig,
GDScript, and whatever the ABI-conformance harness uses):

1. Compute `digest = SHA256(bytes)`, where `bytes` is every byte of the record **from offset 0 up
   to but not including the checksum field itself** — i.e. the header plus all player records,
   exactly as laid out above, with the checksum field absent from the hashed input.
2. Take `digest[0..8]` — the first 8 bytes of the 32-byte SHA-256 digest, in the order SHA-256
   produces them (SHA-256 output is a fixed big-endian byte sequence; do not reverse it before
   slicing).
3. Interpret those 8 bytes as an unsigned 64-bit integer in **little-endian** order (i.e.
   `digest[0]` is the least-significant byte of the resulting `u64`). This is a byte
   reinterpretation of the digest bytes, not a numeric-value truncation of the 256-bit digest
   treated as a big number — the two only coincide if you also treat the digest as little-endian
   throughout, which this spec does.
4. Write that `u64` as the 8-byte trailer, little-endian, immediately after the last player
   record.

A verifier recomputes the same digest over the same byte range and compares the resulting `u64`
for equality; it never compares raw digest bytes against the 8-byte trailer without going through
this same reinterpretation.

## Worked example: 3-cell, 1-player start state

State: `cols=24, rows=24`, no wrap, one player, `tick=0`, illustrative RNG state
`s0..s3 = 1,2,3,4`, food at `(0,0)`, player `status=playing`, `dir=next_dir=right`, `score=0`,
3-cell snake head-first at `(8,12), (7,12), (6,12)` (`reference/snake.html`'s `reset()`, with
`cy = (24/2)|0 = 12`).

Full 80-byte record (16 bytes per row, offset in the left column, hex bytes space-separated):

```
  0  4e 45 4f 53 4e 41 4b 45 01 00 18 00 18 00 00 00
 16  01 00 00 00 00 00 00 00 01 00 00 00 02 00 00 00
 32  03 00 00 00 04 00 00 00 00 00 00 00 01 03 03 00
 48  00 00 00 00 03 00 00 00 00 00 00 00 08 00 0c 00
 64  07 00 0c 00 06 00 0c 00 5a 33 a2 41 af 35 a7 d1
```

Field-by-field:

- `magic` (0-7): `4e 45 4f 53 4e 41 4b 45` = `"NEOSNAKE"`
- `canon_version` (8-9): `01 00` = 1
- `cols` (10-11): `18 00` = 24
- `rows` (12-13): `18 00` = 24
- `flags` (14-15): `00 00` = 0 (no wrap)
- `player_count` (16): `01` = 1
- reserved (17-19): `00 00 00`
- `tick` (20-23): `00 00 00 00` = 0
- `rng_state` (24-39): `01 00 00 00  02 00 00 00  03 00 00 00  04 00 00 00` = `[1, 2, 3, 4]`
- `food_x` (40-41): `00 00` = 0
- `food_y` (42-43): `00 00` = 0
- player 0 `status` (44): `01` = playing
- player 0 `dir` (45): `03` = right
- player 0 `next_dir` (46): `03` = right
- reserved (47): `00`
- player 0 `score` (48-51): `00 00 00 00` = 0
- player 0 `body_len` (52-55): `03 00 00 00` = 3
- reserved (56-59): `00 00 00 00`
- player 0 `cells[0]` (60-63, head): `08 00 0c 00` = `(x=8, y=12)`
- player 0 `cells[1]` (64-67): `07 00 0c 00` = `(x=7, y=12)`
- player 0 `cells[2]` (68-71): `06 00 0c 00` = `(x=6, y=12)`
- `checksum` (72-79): `5a 33 a2 41 af 35 a7 d1` → `SHA-256` of bytes `[0, 72)` is
  `5a33a241af35a7d1aad051a37e4ccdf99927cfd40e9ba513a6a50607b0fb0ea`; its first 8 bytes read as a
  little-endian `u64` are `0xd1a735af41a2335a` (`15107102501874316122`)

This example (construction, hex dump, and checksum) is generated and verified by a script, not
hand-typed; see the task's implementation notes for how to regenerate it if the layout changes.
