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

Also dispatches the pinned Furnace tracker binary (TASK-040), bootstrapped
by `tools/bootstrap.py game furnace` under .tools/game/furnace -- there is
no mise/aqua package for Furnace, so unlike godot there is no
system-package fallback to check first.

Usage:
    ./tools/run.py godot [args...]
    ./tools/run.py godot --headless --version
    ./tools/run.py furnace [args...]
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain import (  # noqa: E402
    furnace_binary_path,
    game_tools_xdg_env,
    godot_fallback_binary_path,
    load_pins,
    resolve_mise_godot,
)


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


def resolve_furnace() -> Path:
    binary = furnace_binary_path(load_pins())
    if os.access(binary, os.X_OK):
        return binary
    die("furnace is not bootstrapped. Run ./tools/bootstrap.py game furnace")


def run_godot(args: list[str]) -> None:
    binary = resolve_godot()
    os.environ.update(game_tools_xdg_env())
    os.execv(str(binary), [str(binary), *args])


def run_furnace(args: list[str]) -> None:
    binary = resolve_furnace()
    os.environ.update(game_tools_xdg_env())
    os.execv(str(binary), [str(binary), *args])


COMMANDS = {
    "godot": run_godot,
    "furnace": run_furnace,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        die(f"Usage: {sys.argv[0]} <{'|'.join(COMMANDS)}> [arguments...]")
    COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
