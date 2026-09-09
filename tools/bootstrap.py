#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Bootstrap pinned local game tooling: Godot export templates, and (only if
mise's godot asset is not usable headless on this platform) a
checksum-verified fallback Godot binary.

Godot itself is installed via mise (this repo's .tool-versions pins
godot@<GODOT_RELEASE>) -- not by this script -- unless bootstrap finds that
asset unusable headless, in which case it downloads the pinned fallback
binary under .tools/game/godot instead. Export templates are never
distributed by mise, so they are always fetched here as a checksum-verified
download. All pins live in tools/game_toolchain.lock, overridable per-entry
via same-named environment variables.

Usage:
    ./tools/bootstrap.py game godot
"""

import hashlib
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain import (  # noqa: E402
    GAME_TOOLS,
    godot_fallback_binary_path,
    godot_is_headless_capable,
    godot_templates_dir,
    load_pins,
    require_pin,
    resolve_mise_godot,
)


def die(message: str) -> None:
    raise SystemExit(message)


def download_verified(url: str, sha256: str, destination: Path) -> None:
    if destination.exists():
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        if digest == sha256:
            print(f"Reusing verified {destination.name}")
            return
        destination.unlink()
    print(f"Downloading {url}")
    try:
        with urllib.request.urlopen(url) as response:  # noqa: S310
            data = response.read()
    except OSError as e:
        die(f"Could not download {url}: {e}")
    digest = hashlib.sha256(data).hexdigest()
    if digest != sha256:
        die(f"Checksum mismatch for {url}\n  expected {sha256}\n  got      {digest}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def install_godot_fallback(pins: dict[str, str]) -> Path:
    downloads = GAME_TOOLS / "downloads"
    binary = godot_fallback_binary_path(pins)
    app_root = GAME_TOOLS / "godot"

    if sys.platform == "darwin":
        url, sha256 = require_pin(pins, "GODOT_MACOS_URL"), require_pin(pins, "GODOT_MACOS_SHA256")
    elif sys.platform.startswith("linux"):
        url, sha256 = require_pin(pins, "GODOT_LINUX_URL"), require_pin(pins, "GODOT_LINUX_SHA256")
    else:
        die(f"No pinned Godot fallback asset for platform {sys.platform!r}.")

    archive = downloads / Path(url).name
    download_verified(url, sha256, archive)
    app_root.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(app_root)
    binary.chmod(0o755)
    return binary


def install_godot_templates(pins: dict[str, str]) -> None:
    downloads = GAME_TOOLS / "downloads"
    templates_dir = godot_templates_dir(pins)
    template_version = require_pin(pins, "GODOT_TEMPLATE_VERSION")
    archive = downloads / Path(require_pin(pins, "GODOT_TEMPLATES_URL")).name
    download_verified(require_pin(pins, "GODOT_TEMPLATES_URL"), require_pin(pins, "GODOT_TEMPLATES_SHA256"), archive)

    if (templates_dir / "version.txt").exists():
        if (templates_dir / "version.txt").read_text().strip() == template_version:
            print(f"Reusing verified export templates {template_version}")
            return

    staging = templates_dir.parent / f".staging-{templates_dir.name}"
    shutil.rmtree(staging, ignore_errors=True)
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(staging)
    templates_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(templates_dir, ignore_errors=True)
    (staging / "templates").rename(templates_dir)
    shutil.rmtree(staging, ignore_errors=True)

    version_marker = (templates_dir / "version.txt").read_text().strip()
    if version_marker != template_version:
        die(f"Export templates report {version_marker}, expected {template_version}")


def install_godot() -> None:
    pins = load_pins()

    mise_binary = resolve_mise_godot()
    if mise_binary is None:
        print("mise does not provide a godot binary on this host; using pinned fallback download.")
        binary = install_godot_fallback(pins)
    elif godot_is_headless_capable(mise_binary):
        print(f"mise's godot ({mise_binary}) runs headless; no fallback download needed.")
        binary = mise_binary
    else:
        print(f"mise's godot ({mise_binary}) failed the --headless check; using pinned fallback download.")
        binary = install_godot_fallback(pins)

    if not godot_is_headless_capable(binary):
        die(
            f"{binary} does not run headless after bootstrap. Update tools/game_toolchain.lock's "
            "GODOT_MACOS_URL/GODOT_LINUX_URL pins after validating a working release."
        )

    install_godot_templates(pins)
    print(f"Godot ({binary}) and export templates {require_pin(pins, 'GODOT_TEMPLATE_VERSION')} are ready.")


def bootstrap_game(component: str) -> None:
    if component not in ("all", "godot"):
        die("Usage: bootstrap.py game [all|godot]")
    install_godot()


COMMANDS = {
    "game": lambda args: bootstrap_game(args[0] if args else "all"),
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        die(f"Usage: {sys.argv[0]} <{'|'.join(COMMANDS)}> [component]")
    COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    try:
        main()
    except (OSError, zipfile.BadZipFile) as e:
        die(str(e))
