#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13,<3.14"
# ///

"""
Regenerates README.md's download table (between <!-- DOWNLOADS:START --> and
<!-- DOWNLOADS:END --> markers) from a real GitHub release's assets (TASK-050).

Usage:
  ./tools/update_readme_downloads.py <release-tag>

Requires the `gh` CLI, already authenticated (GH_TOKEN/GITHUB_TOKEN in CI).
Queries `gh api repos/{owner}/{repo}/releases/tags/{tag}` for the asset list,
matches each asset to a platform by filename substring, and rewrites only the
marked section of README.md -- everything else is left untouched.

Idempotent by construction (AC#3): platforms are iterated in PLATFORM_MAP's
fixed order (not whatever order the GitHub API happens to return assets in),
so the same release always produces byte-identical table output no matter
how many times this runs.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"

START_MARKER = "<!-- DOWNLOADS:START -->"
END_MARKER = "<!-- DOWNLOADS:END -->"

# (substring to match in the asset filename, case-insensitive) -> platform label.
# Order here is the order rows are emitted in, not release-JSON order.
PLATFORM_MAP = [
    (".dmg", "macOS"),
    ("linux", "Linux (x86_64)"),
    ("windows", "Windows (x86_64)"),
    ("web", "Web"),
]


def gh_repo_slug() -> str:
    result = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def fetch_release_assets(tag: str) -> list[dict]:
    repo = gh_repo_slug()
    result = subprocess.run(
        ["gh", "api", f"repos/{repo}/releases/tags/{tag}"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)["assets"]


def build_table(assets: list[dict]) -> str:
    rows = ["| Platform | Download |", "| --- | --- |"]
    for substring, label in PLATFORM_MAP:
        match = next(
            (a for a in assets if substring.lower() in a["name"].lower()), None
        )
        if match is None:
            continue
        rows.append(f"| {label} | [{match['name']}]({match['browser_download_url']}) |")
    return "\n".join(rows)


def rewrite_readme(table: str) -> bool:
    text = README.read_text()
    pattern = re.compile(
        re.escape(START_MARKER) + r".*?" + re.escape(END_MARKER), re.DOTALL
    )
    if not pattern.search(text):
        sys.exit(f"error: {README} has no {START_MARKER}/{END_MARKER} markers")
    replacement = f"{START_MARKER}\n{table}\n{END_MARKER}"
    new_text = pattern.sub(replacement, text)
    if new_text == text:
        return False
    README.write_text(new_text)
    return True


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <release-tag>")
    tag = sys.argv[1]
    assets = fetch_release_assets(tag)
    table = build_table(assets)
    changed = rewrite_readme(table)
    print("README.md updated" if changed else "README.md already up to date")


if __name__ == "__main__":
    main()
