#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Fails if any .gd file outside game/simulation/ crosses the simulation
boundary, or if game/bin/neo_snake.gdextension claims a platform binary
that isn't actually on disk (TASK-029).

Mirrors azure-dreams' validate_simulation_boundary.py with the failure
direction flipped: there the sim itself is GDScript and must stay
engine-free; here the real simulation lives in core/*.zig, reached only
through the GDExtension, and game/simulation/world.gd is the one .gd file
allowed to reference NeoSnakeWorld (TASK-027). So this scans every OTHER
.gd file in game/ and fails on:
  - a NeoSnakeWorld reference (instantiating it or touching a static
    member) -- the one narrow, already-existing exception is
    game/tests/test_gdextension_present.gd's ClassDB.class_exists("NeoSnakeWorld")
    registration check, which names the class without depending on its API
  - a sim-verb name call -- reference/snake.html's own internal simulation
    function names (advance, placeFood/place_food, tickMs/tick_ms,
    speedMul/speed_mul). world.gd's actual public wrapper API (init,
    reset, queue_dir, step, pump, player_view_get, body_copy) is
    deliberately NOT banned: that's the sanctioned way the rest of the
    game talks to the sim, and this task's own examples list omits it.
  - global RNG usage (Godot's randomize/randi/randf/seed/etc.) -- the sim
    has its own seeded RNG (core/rng.zig); nothing outside the sim should
    reach for the engine's global RNG instead

game/addons/ (vendored gdUnit4, which legitimately uses global RNG in its
own fuzzers) and generated directories (.godot/, reports/) are excluded --
they are not this repo's own game code.

The .gdextension check is a separate, non-regex parse via configparser
(the file is INI-formatted). It walks game/bin/ for actual platform binary
artifacts (.so/.dylib/.dll files, .framework directories) and asserts each
one is referenced by some platform key -- not the other direction (key ->
binary must exist), since a single dev/CI machine only ever builds its own
host's binary and would always fail that direction for every other
platform. This direction is also the one the task's own AC actually
exercises: "removing a platform key while the binary still exists on disk"
only has something to fail on if the check is driven by binaries found on
disk, not by the key list.
"""

import configparser
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_DIR = REPO_ROOT / "game"
SIM_DIR = GAME_DIR / "simulation"
EXCLUDED_DIRS = {GAME_DIR / "addons", GAME_DIR / ".godot", GAME_DIR / "reports"}
GDEXTENSION_PATH = GAME_DIR / "bin" / "neo_snake.gdextension"

SIM_VERB_NAMES = ["advance", "place_food", "placeFood", "tick_ms", "tickMs", "speed_mul", "speedMul"]

# Sanctioned exception: checking whether the class is registered by name
# (TASK-027 AC#1) does not depend on NeoSnakeWorld's API the way
# instantiating or calling it does.
ALLOWED_LINE = re.compile(r'''ClassDB\.class_exists\(\s*["']NeoSnakeWorld["']\s*\)''')

RULES: list[tuple[str, re.Pattern[str]]] = [
    ("neo-snake-world", re.compile(r"\bNeoSnakeWorld\b")),
    ("sim-verb", re.compile(r"\b(" + "|".join(SIM_VERB_NAMES) + r")\s*\(")),
    ("global-rng", re.compile(r"\b(randomize|randi|randf|randi_range|randf_range|seed)\s*\(")),
]


@dataclass(frozen=True)
class Violation:
    path: Path
    line_no: int
    rule: str
    text: str


def scan_file(path: Path) -> list[Violation]:
    violations = []
    for line_no, raw_line in enumerate(path.read_text().splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or ALLOWED_LINE.search(raw_line):
            continue
        for rule, pattern in RULES:
            if pattern.search(raw_line):
                violations.append(Violation(path, line_no, rule, stripped))
    return violations


def gd_files_outside_simulation() -> list[Path]:
    files = []
    for path in sorted(GAME_DIR.rglob("*.gd")):
        if path.is_relative_to(SIM_DIR) or any(path.is_relative_to(d) for d in EXCLUDED_DIRS):
            continue
        files.append(path)
    return files


def check_boundary() -> list[Violation]:
    violations = []
    for path in gd_files_outside_simulation():
        violations.extend(scan_file(path))
    return violations


BINARY_ARTIFACT_RE = re.compile(r"\.(so|dylib|dll)$|\.framework$")


def check_gdextension_platforms() -> list[str]:
    parser = configparser.ConfigParser()
    read = parser.read(GDEXTENSION_PATH)
    if not read:
        return [f"{GDEXTENSION_PATH}: could not be read"]

    declared_targets = set()
    for raw_value in parser["libraries"].values():
        rel_path = raw_value.strip().strip('"')
        target = (GAME_DIR / rel_path.removeprefix("res://")).resolve()
        declared_targets.add(target)

    problems = []
    for entry in sorted(GAME_DIR.glob("bin/*")):
        if not BINARY_ARTIFACT_RE.search(entry.name):
            continue
        if entry.resolve() not in declared_targets:
            problems.append(f"{entry}: platform binary present on disk but not referenced by any key in {GDEXTENSION_PATH}")
    return problems


def main() -> int:
    violations = check_boundary()
    for v in violations:
        print(f"{v.path}:{v.line_no}: [{v.rule}] {v.text}", file=sys.stderr)

    platform_problems = check_gdextension_platforms()
    for problem in platform_problems:
        print(problem, file=sys.stderr)

    if violations or platform_problems:
        print(
            f"{len(violations)} simulation-boundary violation(s), "
            f"{len(platform_problems)} .gdextension platform problem(s)",
            file=sys.stderr,
        )
        return 1

    print("simulation boundary and neo_snake.gdextension platform keys: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
