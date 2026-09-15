#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Bootstrap pinned local game tooling: git submodules (third_party/godot-cpp),
Godot export templates, (only if mise's godot asset is not usable headless on
this platform) a checksum-verified fallback Godot binary, the gdUnit4 test
framework addon, and the Furnace tracker binary.

Submodules are initialized via `git submodule update --init --recursive`,
needed because neither a plain clone nor `git worktree add` checks them out
automatically. Godot itself is installed via mise (this repo's
.tool-versions pins godot@<GODOT_RELEASE>) -- not by this script -- unless
bootstrap finds that asset unusable headless, in which case it downloads the
pinned fallback binary under .tools/game/godot instead. Export templates are
never distributed by mise, so they are always fetched here as a
checksum-verified download. gdUnit4 is likewise a checksum-verified
download, extracted to game/addons/gdUnit4 (not committed to git). Furnace
(TASK-040) has no mise/aqua package at all, so it is always this script's
checksum-verified download, extracted to .tools/game/furnace. All pins live
in tools/game_toolchain.lock, overridable per-entry via same-named
environment variables.

Usage:
    ./tools/bootstrap.py game [all|submodules|godot|gdunit4|furnace]
"""

import hashlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from toolchain import (
    GAME_TOOLS,
    REPO_ROOT,
    furnace_binary_path,
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
        with urllib.request.urlopen(url) as response:
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


def install_gdunit4(pins: dict[str, str]) -> None:
    downloads = GAME_TOOLS / "downloads"
    version = require_pin(pins, "GDUNIT4_VERSION")
    archive = downloads / f"gdUnit4-{version}.zip"
    download_verified(require_pin(pins, "GDUNIT4_URL"), require_pin(pins, "GDUNIT4_SHA256"), archive)

    addon_dir = REPO_ROOT / "game" / "addons" / "gdUnit4"
    staging = downloads / f".staging-gdUnit4-{version}"
    shutil.rmtree(staging, ignore_errors=True)
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(staging)
    source_dir = next(staging.glob("gdUnit4-*/addons/gdUnit4"))
    addon_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(addon_dir, ignore_errors=True)
    shutil.move(str(source_dir), str(addon_dir))
    shutil.rmtree(staging, ignore_errors=True)
    print(f"gdUnit4 {version} is ready beneath {addon_dir}")


def install_furnace_linux(pins: dict[str, str]) -> None:
    downloads = GAME_TOOLS / "downloads"
    archive = downloads / Path(require_pin(pins, "FURNACE_LINUX_URL")).name
    download_verified(require_pin(pins, "FURNACE_LINUX_URL"), require_pin(pins, "FURNACE_LINUX_SHA256"), archive)
    with tarfile.open(archive) as bundle:
        bundle.extractall(GAME_TOOLS, filter="data")


def install_furnace_macos(pins: dict[str, str]) -> None:
    downloads = GAME_TOOLS / "downloads"
    archive = downloads / Path(require_pin(pins, "FURNACE_MACOS_URL")).name
    download_verified(require_pin(pins, "FURNACE_MACOS_URL"), require_pin(pins, "FURNACE_MACOS_SHA256"), archive)

    app_root = GAME_TOOLS / "furnace"
    mount_point = GAME_TOOLS / ".furnace-dmg-mount"
    mount_point.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["hdiutil", "attach", "-nobrowse", "-quiet", "-mountpoint", str(mount_point), str(archive)],
        check=True,
    )
    try:
        app_bundle = next(mount_point.glob("*.app"))
        shutil.rmtree(app_root, ignore_errors=True)
        app_root.mkdir(parents=True, exist_ok=True)
        shutil.copytree(app_bundle, app_root / "furnace.app")
    finally:
        subprocess.run(["hdiutil", "detach", "-quiet", str(mount_point)], check=True)


def install_furnace(pins: dict[str, str]) -> None:
    binary = furnace_binary_path(pins)
    if sys.platform == "darwin":
        install_furnace_macos(pins)
    elif sys.platform.startswith("linux"):
        install_furnace_linux(pins)
    else:
        die(f"No pinned Furnace asset for platform {sys.platform!r}.")
    binary.chmod(0o755)
    print(f"Furnace {require_pin(pins, 'FURNACE_VERSION')} is ready at {binary}.")


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


def install_submodules() -> None:
    subprocess.run(
        ["git", "submodule", "update", "--init", "--recursive"],
        cwd=REPO_ROOT,
        check=True,
    )


def bootstrap_game(component: str) -> None:
    if component not in ("all", "submodules", "godot", "gdunit4", "furnace"):
        die("Usage: bootstrap.py game [all|submodules|godot|gdunit4|furnace]")
    if component in ("all", "submodules"):
        install_submodules()
    if component in ("all", "godot"):
        install_godot()
    if component in ("all", "gdunit4"):
        install_gdunit4(load_pins())
    if component in ("all", "furnace"):
        install_furnace(load_pins())


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
