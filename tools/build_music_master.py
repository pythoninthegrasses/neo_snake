#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Emits audio/src/music/theme.fur -- an original Furnace tracker module for the
Intel 8253 PC speaker (chip 0x93, 1 channel) -- straight from the documented
.fur binary layout, using only the stdlib (TASK-040).

There is no tracker GUI in this repo's toolchain, so the module is authored as
data here (NOTES below) and serialized by hand against papers/format.md +
papers/newIns.md for format version 232 (Furnace 0.6.8.3). Nothing is copied
from Furnace's bundled demo songs, which are not GPL.

The file is written uncompressed (Furnace accepts both) so the output bytes are
a pure function of this script -- no zlib level/timestamp drift -- which is what
makes rebuilds byte-identical, matching tools/render_audio.py's determinism
contract for the SFX side.

Verify with the real Furnace binary (-safemode is rejected alongside
-console/-output, so export runs without it; no audio device is opened):
  furnace -info audio/src/music/theme.fur -loglevel warning
  furnace -console -nostatus -view nothing -loops 0 \
      -output /tmp/theme.wav audio/src/music/theme.fur
"""

import argparse
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "audio" / "src" / "music" / "theme.fur"

FORMAT_VERSION = 232
CHIP_INTEL_8253 = 0x93
INS_TYPE_PC_SPEAKER = 21

SONG_NAME = "neo snake theme"
SONG_AUTHOR = "pythoninthegrass"
SONG_COMMENT = "loopable title/gameplay theme for neo_snake"
INS_NAME = "beeper lead"
CHANNEL_NAME = "beeper"

TICKS_PER_SECOND = 60.0
SPEED = 6  # 6 ticks/row at 60Hz = 10 rows/s = 150 BPM on a 16th-note grid
ROWS_PER_PATTERN = 64
ROWS_PER_EIGHTH = 2
NOTE_CUT_TICK = 4  # EC04: gate each note 4/6 of a row so repeats re-attack
# The beeper is a full-scale square; halve it so SFX have room on top.
CHIP_VOLUME = 0.5

SEMITONES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
             "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}

# A natural minor, one voice, eighth notes. "." is a rest. Four bars per
# pattern; pattern B's descent lands on B4 so the loop back into A4 resolves.
NOTES = [
    [
        "A4", "C5", "E5", "C5", "A4", "E5", "D5", "C5",
        "B4", "D5", "F5", "D5", "B4", "D5", "C5", "B4",
        "C5", "E5", "G5", "E5", "C5", "G5", "F5", "E5",
        "D5", "B4", "G4", "B4", "A4", "E4", "A4", ".",
    ],
    [
        "E5", "E5", "D5", "C5", "B4", "C5", "D5", "B4",
        "C5", "C5", "B4", "A4", "G4", "A4", "B4", "G4",
        "A4", "B4", "C5", "D5", "E5", "F5", "G5", "E5",
        "A5", ".", "G5", ".", "E5", "C5", "B4", ".",
    ],
]
ORDERS = [0, 1]


def note_value(name: str) -> int:
    """NOTES uses scientific pitch (A4 = 440Hz); Furnace's own octave numbering
    runs one higher, so A4 here becomes pattern note 105, which Furnace shows as
    "A-3" and renders at 441Hz (the 8253's nearest integer divider)."""
    pitch = name[:-1]
    octave = int(name[-1])
    value = (octave + 4) * 12 + SEMITONES[pitch]
    if not 0 <= value <= 179:
        raise ValueError(f"note {name} out of range")
    return value


def cstr(text: str) -> bytes:
    return text.encode("utf-8") + b"\x00"


def block(ident: bytes, body: bytes) -> bytes:
    return ident + struct.pack("<I", len(body)) + body


def build_pattern_rows(eighths: list[str]) -> bytes:
    """PATN row stream: 0xff ends it, 0x80|(n-2) skips n rows, 0x00 skips one."""
    rows: dict[int, int] = {}
    for i, name in enumerate(eighths):
        if name != ".":
            rows[i * ROWS_PER_EIGHTH] = note_value(name)

    out = bytearray()
    pending = 0
    for row in range(ROWS_PER_PATTERN):
        if row not in rows:
            pending += 1
            continue
        out += encode_skip(pending)
        pending = 0
        # bits 0/1/3/4: note, instrument, effect 0, effect value 0
        out += bytes([0x1B, rows[row], 0, 0xEC, NOTE_CUT_TICK])
    out += b"\xff"
    return bytes(out)


def encode_skip(count: int) -> bytes:
    out = bytearray()
    while count > 0:
        if count == 1:
            out.append(0x00)
            count = 0
        else:
            take = min(count, 129)
            out.append(0x80 | (take - 2))
            count -= take
    return bytes(out)


def build_info(pointers: dict[str, list[int]]) -> bytes:
    body = bytearray()
    body += bytes([0, SPEED, SPEED, 1])  # time base, speed 1, speed 2, arp time
    body += struct.pack("<f", TICKS_PER_SECOND)
    body += struct.pack("<HH", ROWS_PER_PATTERN, len(ORDERS))
    body += bytes([4, 16])  # highlight A/B
    body += struct.pack("<HHH", 1, 0, 0)  # instrument, wavetable, sample counts
    body += struct.pack("<I", len(NOTES))  # global pattern count

    chips = bytearray(32)
    chips[0] = CHIP_INTEL_8253
    body += bytes(chips)
    body += bytes(32)  # chip volumes (reserved >=135)
    body += bytes(32)  # chip panning (reserved >=135)

    flags = bytearray(128)
    struct.pack_into("<I", flags, 0, pointers["flag"][0])
    body += bytes(flags)

    body += cstr(SONG_NAME)
    body += cstr(SONG_AUTHOR)
    body += struct.pack("<f", 440.0)
    body += bytes([
        0,  # limit slides
        2,  # linear pitch: full linear
        2,  # loop modality
        1,  # proper noise layout
        0,  # wave duty is volume
        0,  # reset macro on porta
        0,  # legacy volume slides
        0,  # compatible arpeggio
        1,  # note off resets slides
        1,  # target resets slides
        0,  # arpeggio inhibits portamento
        0,  # wack algorithm macro
        0,  # broken shortcut slides
        0,  # ignore duplicate slides
        0,  # stop portamento on note off
        1,  # continuous vibrato
        0,  # broken DAC mode
        1,  # one tick cut
        1,  # instrument change allowed during porta
        0,  # reset note base on arpeggio effect stop
    ])

    for name in ("instrument", "wavetable", "sample", "pattern"):
        for ptr in pointers[name]:
            body += struct.pack("<I", ptr)

    body += bytes(ORDERS)  # one channel, so orders-then-channels is just orders
    body += bytes([1])  # effect columns
    body += bytes([0])  # channel hide status
    body += bytes([0])  # channel collapse status
    body += cstr(CHANNEL_NAME)
    body += cstr(CHANNEL_NAME)
    body += cstr(SONG_COMMENT)
    body += struct.pack("<f", 1.0)  # master volume

    body += bytes([
        0,  # broken speed selection
        0,  # no slides on first tick
        0,  # next row reset arp pos
        0,  # ignore jump at end
        0,  # buggy portamento after slide
        1,  # new ins affects envelope (Game Boy)
        0,  # ExtCh channel state is shared
        0,  # ignore DAC mode change outside of intended channel
        0,  # E1xy/E2xy priority over Slide00
        1,  # new Sega PCM
        0,  # weird f-num/block-based pitch slides
        0,  # SN duty macro always resets phase
        1,  # pitch macro is linear
        4,  # pitch slide speed in full linear pitch mode
        0,  # old octave boundary behavior
        0,  # disable OPN2 DAC volume control
        1,  # new volume scaling strategy
        1,  # volume macro still applies after end
        0,  # broken outVol
        0,  # E1xy/E2xy stop on same note
        0,  # broken initial position of porta after arp
        0,  # SN periods under 8 treated as 1
        2,  # cut/delay effect policy
        0,  # 0B/0D effect treatment
        1,  # automatic system name detection
        0,  # disable sample macro
        0,  # broken outVol episode 2
        0,  # old arpeggio strategy
    ])

    body += struct.pack("<HH", 150, 150)  # virtual tempo numerator/denominator

    body += cstr("")  # first subsong name
    body += cstr("")  # first subsong comment
    body += bytes([0])  # no additional subsongs
    body += bytes(3)  # reserved

    body += cstr("Intel 8253")  # system name
    body += cstr("neo_snake")  # album/category/game name
    body += cstr("")  # song name (Japanese)
    body += cstr("")  # song author (Japanese)
    body += cstr("")  # system name (Japanese)
    body += cstr("")  # album name (Japanese)

    body += struct.pack("<fff", CHIP_VOLUME, 0.0, 0.0)  # chip volume/panning/front-rear

    # Explicit patchbay: chip 0's two outputs into system outputs 0 and 1.
    connections = [(0x0000 << 16) | 0x0000, (0x0001 << 16) | 0x0001]
    body += struct.pack("<I", len(connections))
    for conn in connections:
        body += struct.pack("<I", conn)
    body += bytes([1])  # automatic patchbay

    body += bytes([
        0,  # broken portamento during legato
        0,  # broken macro during note off in some FM chips
        0,  # pre note (C64) does not compensate for portamento/legato
        0,  # disable new NES DPCM features
        0,  # reset arp effect phase on new note
        0,  # linear volume scaling rounds up
        0,  # legacy "always set volume" behavior
        0,  # legacy sample offset effect
    ])

    body += bytes([1]) + bytes([SPEED]) + bytes(15)  # speed pattern
    body += bytes([0])  # groove list is empty

    for name in ("insdir", "wavedir", "sampledir"):
        body += struct.pack("<I", pointers[name][0])

    return block(b"INFO", bytes(body))


def build_instrument() -> bytes:
    body = bytearray()
    body += struct.pack("<HH", FORMAT_VERSION, INS_TYPE_PC_SPEAKER)
    name = cstr(INS_NAME)
    body += b"NA" + struct.pack("<H", len(name)) + name
    body += b"EN"  # end of features carries no length field
    return block(b"INS2", bytes(body))


def build_patn(index: int, eighths: list[str]) -> bytes:
    body = bytearray()
    body += bytes([0, 0])  # subsong, channel
    body += struct.pack("<H", index)
    body += cstr("")  # pattern name
    body += build_pattern_rows(eighths)
    return block(b"PATN", bytes(body))


def build_adir() -> bytes:
    return block(b"ADIR", struct.pack("<I", 0))


def build_module() -> bytes:
    flag = block(b"FLAG", cstr(""))  # no overrides; chip defaults apply
    instrument = build_instrument()
    patterns = [build_patn(i, eighths) for i, eighths in enumerate(NOTES)]
    adirs = [build_adir() for _ in range(3)]

    zero = {
        "flag": [0],
        "instrument": [0],
        "wavetable": [],
        "sample": [],
        "pattern": [0] * len(patterns),
        "insdir": [0],
        "wavedir": [0],
        "sampledir": [0],
    }
    info_size = len(build_info(zero))

    offset = 32 + info_size
    pointers: dict[str, list[int]] = {key: [] for key in zero}
    pointers["wavetable"] = []
    pointers["sample"] = []

    def place(key: str, payload: bytes) -> bytes:
        nonlocal offset
        pointers[key].append(offset)
        offset += len(payload)
        return payload

    tail = bytearray()
    tail += place("flag", flag)
    tail += place("instrument", instrument)
    # Asset directories precede the patterns because Furnace reads them in that
    # order; trailing them would leave the reader short of EOF and warn.
    for key, adir in zip(("insdir", "wavedir", "sampledir"), adirs):
        tail += place(key, adir)
    for pattern in patterns:
        tail += place("pattern", pattern)

    info = build_info(pointers)
    assert len(info) == info_size

    header = b"-Furnace module-" + struct.pack("<HHI", FORMAT_VERSION, 0, 32) + bytes(8)
    return header + info + bytes(tail)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    data = build_module()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    print(f"wrote {args.out} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
