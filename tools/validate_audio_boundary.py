#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Fails if include/neo_snake.h or any file under core/ names an audio-related
symbol (TASK-041 AC#1): the Zig core and its C ABI must never know audio
exists, so nothing in this boundary may use an audio concept as an
identifier or token in actual code.

Comments are stripped before scanning (C block/line comments for
include/neo_snake.h and core/*.c, Zig line comments for core/*.zig) so that
documentation *referencing* audio as a downstream reason -- e.g.
include/neo_snake.h's own "A consumer (e.g. audio, TASK-041) drains
discrete, ordered events" comment about ns_event -- doesn't itself trip the
check. Only code tokens are checked.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HEADER_PATH = REPO_ROOT / "include" / "neo_snake.h"
CORE_DIR = REPO_ROOT / "core"

BANNED_RE = re.compile(r"(?i)\b(audio|sound|sfx|music)\w*")

C_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
C_LINE_COMMENT_RE = re.compile(r"//.*")


def strip_c_comments(text: str) -> str:
    # Replace block comments with the same number of newlines they spanned
    # so reported line numbers still line up with the original file.
    text = C_BLOCK_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    return C_LINE_COMMENT_RE.sub("", text)


def strip_zig_comments(text: str) -> str:
    return "\n".join(C_LINE_COMMENT_RE.sub("", line) for line in text.splitlines())


def scan(path: Path, code: str) -> list[str]:
    violations = []
    for line_no, line in enumerate(code.splitlines(), start=1):
        match = BANNED_RE.search(line)
        if match:
            violations.append(f"{path}:{line_no}: audio-related symbol {match.group(0)!r}")
    return violations


def main() -> int:
    violations = []

    violations.extend(scan(HEADER_PATH, strip_c_comments(HEADER_PATH.read_text())))

    for path in sorted(CORE_DIR.rglob("*.c")):
        violations.extend(scan(path, strip_c_comments(path.read_text())))
    for path in sorted(CORE_DIR.rglob("*.zig")):
        violations.extend(scan(path, strip_zig_comments(path.read_text())))

    for violation in violations:
        print(violation, file=sys.stderr)

    if violations:
        print(f"{len(violations)} audio-related symbol(s) found in the core/ABI boundary", file=sys.stderr)
        return 1

    print("core/ABI boundary: no audio-related symbols (TASK-041 AC#1)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
