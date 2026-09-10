"""
Shared access to the pinned game-toolchain versions.

tools/game_toolchain.lock is the single source of truth; environment
variables of the same name override individual entries. Imported by
tools/run.py and tools/bootstrap.py (both run from tools/, so a plain
`import toolchain` resolves).

Godot's binary comes from mise's aqua package by default (see
.tool-versions) -- tools/game_toolchain.lock only carries the
GODOT_LINUX_URL/GODOT_MACOS_URL fallback pair, used by tools/bootstrap.py
if mise's asset fails a --headless smoke test, plus the export template
archive, which mise does not provide on any platform.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LOCK_FILE = Path(__file__).resolve().parent / "game_toolchain.lock"
GAME_TOOLS = REPO_ROOT / ".tools" / "game"


def load_pins() -> dict[str, str]:
    pins: dict[str, str] = {}
    for line in LOCK_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        pins[key.strip()] = value.strip().strip('"')
    for key in pins:
        if key in os.environ:
            pins[key] = os.environ[key]
    return pins


def require_pin(pins: dict[str, str], key: str) -> str:
    if key not in pins:
        raise SystemExit(f"{key} is not set in tools/game_toolchain.lock (or the environment).")
    return pins[key]


def resolve_mise_godot() -> Path | None:
    mise = shutil.which("mise")
    if mise is None:
        return None
    result = subprocess.run([mise, "which", "godot"], cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    path = Path(result.stdout.strip())
    return path if path.is_file() else None


def godot_fallback_binary_path(pins: dict[str, str]) -> Path:
    release = require_pin(pins, "GODOT_RELEASE")
    if sys.platform == "darwin":
        return GAME_TOOLS / "godot" / "Godot.app" / "Contents" / "MacOS" / "Godot"
    return GAME_TOOLS / "godot" / f"Godot_v{release}_linux.x86_64"


def godot_templates_dir(pins: dict[str, str]) -> Path:
    return GAME_TOOLS / "xdg-data" / "godot" / "export_templates" / require_pin(pins, "GODOT_TEMPLATE_VERSION")


def godot_xdg_env() -> dict[str, str]:
    return {
        "XDG_DATA_HOME": str(GAME_TOOLS / "xdg-data"),
        "XDG_CONFIG_HOME": str(GAME_TOOLS / "xdg-config"),
        "XDG_CACHE_HOME": str(GAME_TOOLS / "xdg-cache"),
    }


def godot_is_headless_capable(binary: Path) -> bool:
    try:
        subprocess.run(
            [str(binary), "--headless", "--version"],
            capture_output=True,
            timeout=30,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False
    return True
