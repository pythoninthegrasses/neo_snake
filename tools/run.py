#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Unified dispatcher for the pinned Godot binary.

Resolves to whichever binary `tools/bootstrap.py game godot` decided is
headless-capable: mise's godot package by default, or the pinned fallback
download under .tools/game/godot if that asset does not run headless on
this platform. Execs directly (no subprocess wrapper) so interactive tools
(the Godot editor) keep normal stdio/tty/signal behavior.

Usage:
    ./tools/run.py godot [args...]
    ./tools/run.py godot --headless --version
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain import godot_fallback_binary_path, godot_xdg_env, load_pins, resolve_mise_godot  # noqa: E402


def die(message: str) -> None:
    raise SystemExit(message)


def resolve_godot() -> Path:
    fallback = godot_fallback_binary_path(load_pins())
    if os.access(fallback, os.X_OK):
        return fallback
    mise_binary = resolve_mise_godot()
    if mise_binary is not None:
        return mise_binary
    die("godot is not bootstrapped. Run ./tools/bootstrap.py game godot")


def run_godot(args: list[str]) -> None:
    binary = resolve_godot()
    os.environ.update(godot_xdg_env())
    os.execv(str(binary), [str(binary), *args])


COMMANDS = {
    "godot": run_godot,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        die(f"Usage: {sys.argv[0]} <{'|'.join(COMMANDS)}> [arguments...]")
    COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
