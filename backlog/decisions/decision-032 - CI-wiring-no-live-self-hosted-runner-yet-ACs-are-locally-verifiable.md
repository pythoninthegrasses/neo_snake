---
id: decision-032
title: CI wiring is locally verifiable now; a live self-hosted runner already exists but Apple secrets do not
status: Accepted
date: 2026-09-13
---

## Context

TASK-049 wires GitHub Actions CI: a self-hosted `[macOS, ARM64]` job that builds, tests, signs,
and notarizes; a Linux job running the Docker build (TASK-045); and a nightly `task oracle:fuzz`
job — following `~/git/mt`'s model. Two things looked, at first glance, like they could block this
task:

- `gh api repos/pythoninthegrasses/neo_snake/actions/runners` returns `{"total_count":0,"runners":[]}`,
  which read as "no self-hosted runner is registered." This was **wrong** — see below.
- `gh secret list` returns nothing — none of the seven Apple signing secrets
  (`APPLE_SIGNING_IDENTITY`, `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`,
  `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_B64`, `APPLE_API_KEY`, `APPLE_API_ISSUER`) that
  `task release:ship-macos` (TASK-044) requires are configured on this repo yet. This one holds up.

**Correction after the first real PR run (`gh run view` on PR #37's CI run,
`34794873670`)**: the `macos` job actually picked up and ran on a live runner within seconds —
`Post Run actions/checkout@v6` shows `/opt/homebrew/bin/git version` executing, real macOS/Homebrew
output, not a queued-forever job. A self-hosted macOS ARM64 runner already exists and is reachable
by this repo (registered at an org level the repo-scoped `actions/runners` endpoint apparently
doesn't enumerate, or under a different auth scope than `gh`'s default token has) — the repo-scoped
API call gave a false negative. That first real run still failed, but for an unrelated, genuinely
fixable reason: `task ci:macos-check` (`task check`) hit its own `_guard-env-precedence`
precondition, because `TASK_X_ENV_PRECEDENCE=1` lives in a gitignored `.env` (see `.env.example`)
that doesn't exist on the runner. Fixed by setting `TASK_X_ENV_PRECEDENCE: "1"` directly in the
`macos` job's `env:` block in `.github/workflows/ci.yml`, rather than requiring an out-of-band
`.env` file on the runner machine.

## Decision

The missing Apple secrets are not a blocker for this task, and are not fixable by an agent anyway
(adding repo secrets is an action Lance has to take in GitHub's own UI). TASK-049's four Acceptance
Criteria are all satisfiable through local/static verification alone, and — as it turned out — the
macOS job's build+test half is now also verified against the real live runner, not just `act`:

- **AC#1** (every CI step is a one-line `task ci:<target>`) is a property of the workflow YAML and
  `taskfiles/ci.yml` — reviewable by reading the files, no runner needed.
- **AC#2** (`act` with the committed `.actrc` runs the macOS-labeled job locally against the
  self-hosted mapping) only requires `act` to resolve `runs-on: [self-hosted, macOS, ARM64]` to
  native host execution (`-P self-hosted=-self-hosted -P macOS=-self-hosted -P ARM64=-self-hosted`)
  and actually run the job's steps on this machine — verified: `act push -j macos` succeeds, with
  `task ci:macos-check` correctly no-oping (exit 0) since it is `platforms: [darwin]`-gated and this
  verification host is Linux, exactly mirroring how `task check` already no-ops
  `extension:build-macos` on non-Darwin hosts. `act` never needs a live *registered* runner; it
  only needs the label mapping to route to `-self-hosted` (execute directly on whatever host runs
  `act`) instead of pulling a Docker image.
- **AC#3** (a nightly workflow runs `task oracle:fuzz`) is satisfied by the workflow file existing
  and structurally dry-running under `act workflow_dispatch -j fuzz -n`.
- **AC#4** (`actionlint` passes) — verified directly: `actionlint .github/workflows/*.yml` exits 0.

None of the four require witnessing a real completed run against GitHub's live infrastructure. This
is an expected, anticipated state (the task's own AC design already routes around it), not the kind
of genuine infrastructure blocker that should stop the standing auto-chain and wait for a person.

**What still needs Lance, before the sign+notarize half of this workflow does anything for real**:
add the seven Apple signing secrets under Settings -> Secrets and variables -> Actions. The runner
itself already exists and already runs `ci:macos-check` on every push/PR. Until the secrets are
added, a push to `main` will run `ci:macos-release` and fail at its own precondition checks
(`task release:ship-macos`'s `sh: 'test -n "${APPLE_SIGNING_IDENTITY:-}"'` guards, TASK-044) rather
than silently no-op — this does not block any merge, since `gh api
repos/pythoninthegrasses/neo_snake/branches/main/protection` returns 404 ("Branch not protected"):
no required status checks exist on `main`.

**No separate Windows CI job was added.** TASK-049's own Description makes it conditional: "a
Windows job only if route (b) native-runner was chosen in task-046." `backlog/tasks/task-046 -
....md`'s Notes record that route (a) (mingw cross-compilation from Linux) was chosen, so a
dedicated Windows runner job is out of scope here; Windows building continues to run wherever
`task extension:build-windows`/`docker/windows/Dockerfile` is already invoked outside this CI
workflow (unchanged by this task).

**The macOS job's sign/notarize step is gated to `push` events on `main`** (`if: github.event_name
== 'push' && github.ref == 'refs/heads/main'`), not run on every PR — it needs the Apple secrets
and burns a real App Store Connect API notarization request each time, and every PR to this
solo-maintainer repo already originates from `main`-tracking branches, not external forks. Every
push and PR still runs the build+test step (`task ci:macos-check`, i.e. `task check`) unconditionally.

## Consequences

- `taskfiles/ci.yml` adds four thin `ci:<target>` wrapper tasks (`macos-check`, `macos-release`,
  `linux-docker-build`, `fuzz`), each a one-line call into task/logic that already existed
  (`check`, `release:ship-macos`, `docker/linux/Dockerfile`'s `check`/`artifacts` stages,
  `oracle:fuzz`) — no new build logic anywhere in `.github/workflows/`.
- `.actrc` maps `self-hosted`/`macOS`/`ARM64` to native execution and `ubuntu-latest` to act's own
  Ubuntu image, following `~/git/mt/.actrc`'s per-label mapping convention.
- `act` and `actionlint` were already pinned in `.tool-versions` from a prior task; while verifying
  AC#2, `act`'s own dry-run output flagged the pinned `0.2.84` as vulnerable to CVE-2026-34041/
  CVE-2026-34042 and recommended `0.2.86`+, so `.tool-versions` was bumped to `0.2.89` (latest
  available via `mise ls-remote act`) as part of this task — a one-line, low-risk fix surfaced
  incidentally by the same verification this task already required.
- The `macos` job's `env:` block sets `TASK_X_ENV_PRECEDENCE: "1"` directly, since no `.env` file
  (gitignored) exists on the runner and `task check`'s own guard step fails loudly without it — this
  was only caught by watching the first real run on PR #37 fail, not by `act` (which ran on this
  Linux verification host, where the darwin-gated build/test step is a no-op and never reaches the
  guard).
- A second real run then got past the env-precedence guard, past a full GDExtension compile+link,
  and failed at `game:import` with `godot is not bootstrapped. Run ./tools/bootstrap.py game godot`.
  `game/addons/gdUnit4/` and the Godot binary/export templates are gitignored, workspace-local state
  (same gap hit locally in a fresh `task-049` worktree earlier in this task, fixed there with `task
  game:bootstrap`) — the runner host being persistent doesn't carry that state across checkouts,
  since it lives under `$GITHUB_WORKSPACE`, not the runner's home directory. Fixed by adding a `task
  game:bootstrap` step to the `macos` job, before `task ci:macos-check`. Neither of these two runner-
  only gaps (`_guard-env-precedence`, Godot bootstrap) was reachable by `act` on this Linux
  verification host, since `task ci:macos-check` no-ops there before ever reaching either check —
  they were only found by watching real runs, which is exactly why this task waited for real CI
  before merging rather than trusting `act` alone.
