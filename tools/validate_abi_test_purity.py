#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Fails if core/abitest.zig imports anything besides "std".

Tier-C conformance tests (TASK-025) must reach core/abi.zig exclusively
through @cImport(include/neo_snake.h) -- never by @import()ing
rng.zig/canon.zig/world.zig/corpus.zig directly. Without this guard,
Tier-C could silently degrade into a second copy of Tier-A.
"""

import re
import sys
from pathlib import Path

TEST_FILE = Path(__file__).resolve().parent.parent / "core" / "abitest.zig"
IMPORT_RE = re.compile(r'@import\(\s*"([^"]*)"\s*\)')


def main() -> None:
    text = TEST_FILE.read_text()
    bad = sorted({name for name in IMPORT_RE.findall(text) if name != "std"})
    if bad:
        print(f"{TEST_FILE}: @import of non-std module(s): {', '.join(bad)}", file=sys.stderr)
        print("Tier-C tests may only @import \"std\" -- reach abi.zig via @cImport instead.", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
