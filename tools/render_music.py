#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# dependencies = ["soundfile", "numpy"]
# ///

"""
Renders Furnace tracker masters (audio/src/music/*.fur) to committed OGG
Vorbis streams under game/content/audio/music/ (TASK-040), so Godot's
res:// filesystem can load them directly -- same convention TASK-039
established for game/content/audio/sfx/*.wav.

Two chained external steps, neither of them ffmpeg (unavailable on this
host without adding an unconfigured system repo):

  1. the pinned `furnace` binary (tools/game_toolchain.lock, fetched by
     `tools/bootstrap.py game furnace`) renders a .fur to WAV via its
     built-in console/export mode:
       furnace -console -view nothing -loglevel warning \\
           -output out.wav -loops 0 in.fur
     `-safemode` must NOT be combined with `-console`/`-output` -- Furnace
     refuses that combination outright ("you can't use safe mode and
     console/export mode together").
  2. `soundfile` re-encodes that WAV to OGG. Its bundled libsndfile has
     Vorbis support compiled in, so no ffmpeg/oggenc/sox is needed.

Confirmed by hand: two furnace renders of the same .fur are byte-identical
WAVs (Furnace's renderer has no wall-clock/RNG dependence for this song),
so --self-test renders the same master twice and diffs the WAV bytes.

The committed .ogg files are NOT byte-reproducible across renders --
libvorbis/libogg embeds a randomized per-stream serial number in the
container, confirmed by hand (two encodes of the identical WAV differ at
byte 15, the Ogg page header). What is reproducible is the decoded PCM:
two independent encodes of the same WAV decode back to bit-identical
samples (confirmed with numpy.array_equal). So --check decodes both the
committed .ogg and a fresh render's .ogg with soundfile and compares
sample arrays, not raw bytes.
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain import furnace_binary_path, game_tools_xdg_env, load_pins  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC_DIR = REPO_ROOT / "audio" / "src" / "music"
DEFAULT_OUT_DIR = REPO_ROOT / "game" / "content" / "audio" / "music"
MASTER_SUFFIX = ".fur"


def die(message: str) -> None:
    raise SystemExit(message)


def resolve_furnace() -> Path:
    binary = furnace_binary_path(load_pins())
    if not binary.is_file():
        die(f"furnace is not bootstrapped at {binary}. Run ./tools/bootstrap.py game furnace")
    return binary


def render_fur_to_wav(furnace: Path, fur_path: Path, wav_path: Path) -> None:
    env = {**os.environ, **game_tools_xdg_env()}
    result = subprocess.run(
        [
            str(furnace),
            "-console",
            "-view", "nothing",
            "-loglevel", "warning",
            "-output", str(wav_path),
            "-loops", "0",
            str(fur_path),
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode != 0 or not wav_path.exists():
        die(f"furnace failed to render {fur_path}:\n{result.stdout}\n{result.stderr}")


def wav_to_ogg_bytes(wav_path: Path) -> bytes:
    data, sample_rate = sf.read(str(wav_path))
    ogg_path = wav_path.with_suffix(".ogg")
    sf.write(str(ogg_path), data, sample_rate, format="OGG", subtype="VORBIS")
    return ogg_path.read_bytes()


def render_master(furnace: Path, fur_path: Path) -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{fur_path.stem}.wav"
        render_fur_to_wav(furnace, fur_path, wav_path)
        return wav_to_ogg_bytes(wav_path)


def ogg_samples(ogg_bytes: bytes) -> np.ndarray:
    with tempfile.NamedTemporaryFile(suffix=".ogg") as tmp:
        tmp.write(ogg_bytes)
        tmp.flush()
        data, _ = sf.read(tmp.name)
    return data


def discover_masters(src_dir: Path) -> list[Path]:
    return sorted(src_dir.glob(f"*{MASTER_SUFFIX}"))


def render_all(furnace: Path, src_dir: Path, out_dir: Path) -> list[Path]:
    masters = discover_masters(src_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for fur_path in masters:
        ogg_bytes = render_master(furnace, fur_path)
        (out_dir / f"{fur_path.stem}.ogg").write_bytes(ogg_bytes)
    return masters


def check_all(furnace: Path, src_dir: Path, committed_dir: Path) -> int:
    masters = discover_masters(src_dir)
    if not masters:
        print(f"render_music: no {MASTER_SUFFIX} masters under {src_dir} -- nothing to check")
        return 0
    failures = []
    for fur_path in masters:
        rendered = render_master(furnace, fur_path)
        committed_path = committed_dir / f"{fur_path.stem}.ogg"
        if not committed_path.exists():
            failures.append(f"{committed_path} does not exist (run `task audio:music-render` and commit it)")
            continue
        # Raw .ogg bytes are never equal across encodes (libogg randomizes the
        # per-stream serial number in the container) -- compare decoded PCM,
        # which two independent encodes of the same WAV DO reproduce exactly.
        if not np.array_equal(ogg_samples(rendered), ogg_samples(committed_path.read_bytes())):
            failures.append(f"{committed_path} does not decode to the same samples as a fresh render of {fur_path}")
    if failures:
        print("render_music: check FAILED", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"render_music: {len(masters)} master(s) decode identically to a fresh render of their .fur source")
    return 0


def run_self_test(furnace: Path, src_dir: Path) -> int:
    masters = discover_masters(src_dir)
    if not masters:
        die(f"render_music: no {MASTER_SUFFIX} masters under {src_dir} to self-test against")
    fur_path = masters[0]
    with tempfile.TemporaryDirectory() as tmp:
        wav_a = Path(tmp) / "a.wav"
        wav_b = Path(tmp) / "b.wav"
        render_fur_to_wav(furnace, fur_path, wav_a)
        render_fur_to_wav(furnace, fur_path, wav_b)
        if wav_a.read_bytes() != wav_b.read_bytes():
            print(f"render_music: self-test FAILED -- two renders of {fur_path} differ", file=sys.stderr)
            return 1
    print(f"render_music: self-test PASSED ({fur_path.name}, byte-identical WAV across two renders)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help=f"render every master in --src-dir (default {DEFAULT_SRC_DIR})")
    parser.add_argument("--check", action="store_true", help="with --all, diff fresh renders against --out-dir instead of writing")
    parser.add_argument("--src-dir", type=Path, default=DEFAULT_SRC_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--self-test", action="store_true", help="render the first master twice and assert byte-identical WAV output")
    args = parser.parse_args()

    furnace = resolve_furnace()

    if args.self_test:
        return run_self_test(furnace, args.src_dir)
    if args.all:
        if args.check:
            return check_all(furnace, args.src_dir, args.out_dir)
        render_all(furnace, args.src_dir, args.out_dir)
        return 0

    parser.error("one of --all or --self-test is required")


if __name__ == "__main__":
    sys.exit(main())
