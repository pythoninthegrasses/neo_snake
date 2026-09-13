#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Renders text-source SFX patches (audio/src/sfx/*.chip.json) to 16-bit mono
WAV using only the Python stdlib (wave, struct, math) -- no third-party
audio dependency (TASK-038).

Patch schema (schema_version 1):
  {
    "schema_version": 1,
    "sample_rate": 44100,
    "duration_ms": 120.0,
    "waveform": "square" | "triangle" | "noise",
    "duty": 0.5,                                    # square only, default 0.5
    "pitch_hz": [[0, 440.0], [60, 880.0]],           # [time_ms, hz] breakpoints
    "volume":   [[0, 0.0], [5, 1.0], [120, 0.0]]     # [time_ms, level 0..1] breakpoints
  }

pitch_hz/volume are piecewise-linear envelopes: held at the first/last
value outside their time range, interpolated linearly between breakpoints.
"noise" clocks a fixed-seed 15-bit Galois LFSR (NES APU style) once per
pitch-phase wrap, so a patch's output depends only on its own JSON content
-- never on wall-clock time or the platform RNG -- which is what makes two
renders of the same patch byte-identical (AC#2).
"""

import argparse
import json
import struct
import sys
import wave
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC_DIR = REPO_ROOT / "audio" / "src" / "sfx"
# Committed under game/content/ (not audio/build/) so Godot's res:// resource
# filesystem can load these WAVs directly, matching the convention
# game/content/{tuning,palette,modes}.json already use for checked-in
# content the presentation layer reads at runtime (TASK-039).
DEFAULT_OUT_DIR = REPO_ROOT / "game" / "content" / "audio" / "sfx"
PATCH_SUFFIX = ".chip.json"

SELF_TEST_PATCH = {
    "schema_version": 1,
    "sample_rate": 44100,
    "duration_ms": 50.0,
    "waveform": "square",
    "duty": 0.5,
    "pitch_hz": [[0, 440.0], [50, 880.0]],
    "volume": [[0, 0.0], [5, 1.0], [45, 1.0], [50, 0.0]],
}


class Lfsr:
    """15-bit Galois LFSR, NES-APU-style noise channel, fixed seed."""

    def __init__(self):
        self.state = 1

    def step(self):
        bit0 = self.state & 1
        bit1 = (self.state >> 1) & 1
        feedback = bit0 ^ bit1
        self.state = (self.state >> 1) | (feedback << 14)
        return bit0


def interp(breakpoints, t):
    if t <= breakpoints[0][0]:
        return breakpoints[0][1]
    if t >= breakpoints[-1][0]:
        return breakpoints[-1][1]
    for (t0, v0), (t1, v1) in zip(breakpoints, breakpoints[1:]):
        if t0 <= t <= t1:
            if t1 == t0:
                return v1
            return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
    return breakpoints[-1][1]


def triangle(phase):
    if phase < 0.5:
        return -1.0 + 4.0 * phase
    return 3.0 - 4.0 * phase


def validate_patch(patch):
    if patch.get("schema_version") != 1:
        raise ValueError(f"unsupported schema_version: {patch.get('schema_version')!r}")
    if patch.get("waveform") not in ("square", "triangle", "noise"):
        raise ValueError(f"unknown waveform: {patch.get('waveform')!r}")
    for key in ("pitch_hz", "volume"):
        points = patch.get(key)
        if not points or points[0][0] != 0:
            raise ValueError(f"{key} must be a non-empty breakpoint list starting at time 0")
    if patch.get("sample_rate", 0) <= 0:
        raise ValueError("sample_rate must be > 0")
    if patch.get("duration_ms", 0) <= 0:
        raise ValueError("duration_ms must be > 0")


def render_patch(patch):
    validate_patch(patch)
    sample_rate = patch["sample_rate"]
    waveform = patch["waveform"]
    duty = patch.get("duty", 0.5)
    pitch_hz = patch["pitch_hz"]
    volume = patch["volume"]
    total_samples = round(patch["duration_ms"] * sample_rate / 1000.0)

    lfsr = Lfsr()
    phase = 0.0
    noise_bit = 0
    samples = []
    for i in range(total_samples):
        t_ms = i * 1000.0 / sample_rate
        freq = interp(pitch_hz, t_ms)
        vol = interp(volume, t_ms)
        prev_phase = phase
        phase = (phase + freq / sample_rate) % 1.0

        if waveform == "square":
            value = 1.0 if phase < duty else -1.0
        elif waveform == "triangle":
            value = triangle(phase)
        else:  # noise
            if phase < prev_phase:
                noise_bit = lfsr.step()
            value = 1.0 if noise_bit == 0 else -1.0

        amplitude = max(-1.0, min(1.0, value * vol))
        sample_val = int(round(amplitude * 32767))
        sample_val = max(-32768, min(32767, sample_val))
        samples.append(sample_val)

    return sample_rate, samples


def write_wav(path, sample_rate, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def render_to_bytes(patch):
    import io

    sample_rate, samples = render_patch(patch)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    return buf.getvalue()


def run_self_test():
    first = render_to_bytes(SELF_TEST_PATCH)
    second = render_to_bytes(SELF_TEST_PATCH)
    if first != second:
        print("render_audio: self-test FAILED -- two renders of the same patch differ", file=sys.stderr)
        return 1
    print(f"render_audio: self-test PASSED ({len(first)} bytes, byte-identical across two renders)")
    return 0


def discover_patches(src_dir):
    return sorted(src_dir.glob(f"*{PATCH_SUFFIX}"))


def stem_for(patch_path):
    name = patch_path.name
    if name.endswith(PATCH_SUFFIX):
        return name[: -len(PATCH_SUFFIX)]
    return patch_path.stem


def render_all(src_dir, out_dir):
    patches = discover_patches(src_dir)
    for patch_path in patches:
        patch = json.loads(patch_path.read_text())
        sample_rate, samples = render_patch(patch)
        write_wav(out_dir / f"{stem_for(patch_path)}.wav", sample_rate, samples)
    return patches


def check_all(src_dir, committed_dir):
    patches = discover_patches(src_dir)
    if not patches:
        print(f"render_audio: no {PATCH_SUFFIX} patches under {src_dir} -- nothing to check")
        return 0
    failures = []
    for patch_path in patches:
        patch = json.loads(patch_path.read_text())
        rendered = render_to_bytes(patch)
        committed_path = committed_dir / f"{stem_for(patch_path)}.wav"
        if not committed_path.exists():
            failures.append(f"{committed_path} does not exist (run `task audio:render` and commit it)")
            continue
        committed_bytes = committed_path.read_bytes()
        if rendered != committed_bytes:
            failures.append(f"{committed_path} does not match a fresh render of {patch_path}")
    if failures:
        print("render_audio: check FAILED", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"render_audio: {len(patches)} patch(es) match their committed WAV byte-for-byte")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", nargs="?", type=Path, help="a single .chip.json patch to render")
    parser.add_argument("output", nargs="?", type=Path, help="output .wav path for the single-patch mode")
    parser.add_argument("--all", action="store_true", help=f"render every patch in --src-dir (default {DEFAULT_SRC_DIR})")
    parser.add_argument("--check", action="store_true", help="with --all, diff fresh renders against --out-dir instead of writing")
    parser.add_argument("--src-dir", type=Path, default=DEFAULT_SRC_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--self-test", action="store_true", help="render an embedded fixture twice and assert byte-identical output")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    if args.all:
        if args.check:
            return check_all(args.src_dir, args.out_dir)
        render_all(args.src_dir, args.out_dir)
        return 0

    if not args.input or not args.output:
        parser.error("input and output are required unless --all or --self-test is given")
    patch = json.loads(args.input.read_text())
    sample_rate, samples = render_patch(patch)
    write_wav(args.output, sample_rate, samples)
    return 0


if __name__ == "__main__":
    sys.exit(main())
