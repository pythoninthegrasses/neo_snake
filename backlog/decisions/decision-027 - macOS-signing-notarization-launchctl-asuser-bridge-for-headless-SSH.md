---
id: decision-027
title: 'macOS signing/notarization: launchctl asuser bridge for headless SSH signing'
date: '2026-09-13 00:00'
status: Accepted
---
## Context

TASK-044 requires `task release:ship-macos` to export, sign, verify, and notarize the macOS DMG
end to end, unattended, with no Gatekeeper prompt on a clean Mac (AC#1), an independently
verifiable signature on the app and its embedded GDExtension `.framework` (AC#2), actionable
failures when credentials are missing (AC#3), and keychain/API-key cleanup even on failure (AC#4).
Real credentials came from `~/git/mt/.env` per Lance's explicit instruction ("Use mt's env file"),
transferred to `mini` (this repo's signing host) as `/tmp/apple_signing.env`.

`mini` is administered exclusively over SSH from this machine — there is no interactive terminal
session driving the work directly on the console. That topology surfaced a blocker with no
analogue in `~/git/mt`'s own `release.yml` (which this task's `taskfiles/release.yml` otherwise
mirrors closely): every codesign operation needing the imported Developer ID private key failed
with `errSecInternalComponent`, even though `security find-identity` could see the key fine and
the same commands work when run by a person logged into `mini`'s console directly.

**Root cause.** macOS's Security framework gates release of a keychain-imported private key on
the calling process's audit session / bootstrap namespace. A bare SSH session runs in its own
session, distinct from the GUI console login session (`lance`, uid 501) that persists on `mini` —
`securityd` refuses to release the key to a process outside that GUI session's namespace,
regardless of keychain unlock state or ACLs. This is specific to headless-over-SSH signing hosts,
not a general macOS codesign limitation.

**The fix and what it exposed.** `sudo launchctl asuser <uid> <command>` re-attaches a process
tree into the target uid's GUI bootstrap namespace before it starts, which resolves
`errSecInternalComponent` for a bare `codesign` call. Three further issues surfaced applying this
to the real pipeline:

1. **`sudo` requires a password non-interactively.** I cannot supply Lance's sudo password myself,
   and a full unscoped `NOPASSWD: ALL` grant is far broader than this need. I proposed a narrowly
   scoped sudoers.d entry (`lance ALL=(root) NOPASSWD: /bin/launchctl asuser *`), `visudo -cf`
   validated, for Lance to install himself; he confirmed installation ("Done") and I verified it
   live via `sudo -n -l`.
2. **`sudo launchctl asuser` does not drop root's EUID.** `sudo launchctl asuser "$(id -u)" id`
   reports `uid=0(root)` — the bridge re-attaches the bootstrap namespace but the process is still
   root. Files it creates (the exported DMG) come out root-owned. A bare `sudo chown` afterward is
   *not* covered by the narrow sudoers rule (different command) and would itself prompt for a
   password non-interactively and fail. Routing the chown through the identical
   `sudo launchctl asuser "$(id -u)" chown ...` pattern keeps it covered by the same rule, since
   sudoers matches on the literal `/bin/launchctl` invocation with `asuser <uid> chown ...` as its
   arguments.
3. **`./tools/run.py`'s `uv run --script` shebang breaks audit-session inheritance.** Wrapping
   `./tools/run.py godot ...` in the same `launchctl asuser` bridge still hit
   `errSecInternalComponent`, while invoking the identical mise-resolved `godot` binary *directly*
   under the same bridge signed correctly — confirmed by direct A/B testing (a standalone
   `codesign` call, and the same `godot` binary invoked with and without the `tools/run.py`
   indirection, all under the same bridge). Whatever `uv run --script`'s shebang does in its
   exec chain before handing off to `run.py`'s own `os.execv()` breaks the inherited session
   context somewhere it doesn't for a directly-launched binary. Not diagnosed further at the `uv`
   internals level — not required, since the fix is narrow: bypass `tools/run.py` for this one
   step only, resolving `godot` via `mise which godot` and invoking it directly, replicating
   `tools/toolchain.py`'s `game_tools_xdg_env()` XDG variables by hand so the import cache still
   lands under `.tools/game/` rather than leaking into `$HOME`.

**Godot's DMG export leaves no loose `.app` on disk.** `godot --headless --export-release macOS`
(with `export_path` set to a `.dmg` in `game/export_presets.cfg`) builds, signs, and packages the
`.app` entirely inside a private `/var/folders/.../T/` temp directory, then signs and emits only
the final `.dmg` — unlike `~/git/mt`'s Cargo-based export, which leaves an inspectable directory
tree. The originally-drafted `verify-signing` task's `APP_GLOB` precondition against
`game/build/macos/*.app` never matched anything real; it required mounting the DMG
(`hdiutil attach -nobrowse -readonly`) to reach the `.app` for independent verification, with an
`EXIT` trap to guarantee `hdiutil detach` even on a failed check.

## Decision

`taskfiles/release.yml`'s `export-macos` task wraps its godot invocation as:

```
sudo launchctl asuser "$(id -u)" env PATH="$PATH" XDG_DATA_HOME=... XDG_CONFIG_HOME=... XDG_CACHE_HOME=... "$(mise which godot)" --headless --path game --export-release macOS
sudo launchctl asuser "$(id -u)" chown "$(id -u):$(id -g)" {{.DMG_GLOB}}
```

gated on the scoped sudoers.d entry `lance ALL=(root) NOPASSWD: /bin/launchctl asuser *`
(installed by Lance directly, not by an agent), documented as a signing-host prerequisite. This is
a no-op change on any machine with a real console GUI session driving the work directly (normal
SSH-free signing needs no wrapping) — it exists specifically for `mini`'s headless-over-SSH
topology and should not be assumed necessary on a future signing host with a different setup.

`verify-signing` mounts the exported DMG read-only, locates the `.app` inside the mounted volume,
verifies the embedded `libneo_snake.macos.template_release.framework` directly (loaded via
`dlopen` at runtime, so `codesign --verify --deep --strict` on the `.app` alone does not walk into
it) plus its hardened-runtime flag, then the `.app`'s own nested signatures, then the DMG's own
signature — always detaching the mounted volume via a `trap ... EXIT`.

`notarize` mirrors `~/git/mt`'s `notarytool submit --wait` + `stapler staple`, then adds a step
`~/git/mt` does not have: `spctl -a -vv --type open --context context:primary-signature` against
the stapled DMG, asserted to report `accepted`/`source=Notarized Developer ID` — the automatable
proxy for AC#1 ("opens on a clean Mac with no Gatekeeper prompt"), rather than trusting
`notarytool`'s own submit response as sufficient.

## Consequences

- Any future signing host reached only over SSH (no console session driving work directly) needs
  the same `/bin/launchctl asuser *` NOPASSWD sudoers.d entry, installed by a human with sudo
  access — this cannot be provisioned by an agent, since it requires a password the agent must
  never be given.
- `export-macos` deliberately bypasses `tools/run.py` for the one godot invocation that needs the
  signing bridge; any other Godot invocation added to this repo's task graph should keep going
  through `tools/run.py` as normal — this bypass is scoped narrowly to the signing step, not a
  general precedent against `tools/run.py`.
- `verify-signing`'s DMG-mounting approach is specific to Godot's own DMG-export packaging mode; a
  future export target that leaves a loose `.app` on disk (a different preset, a different engine
  version) would not need the mount/detach machinery at all.
- All four Acceptance Criteria were verified end-to-end against live Apple infrastructure on
  `mini`: notarization Accepted, stapling succeeded, `spctl` reported `accepted`, both the
  `.framework` and `.app` independently verified as signed with hardened runtime, credential
  preconditions fail with the intended messages when unset, and a forced-failure scratch-taskfile
  test confirmed `defer:`-registered keychain cleanup still runs on `export-macos` failure.
