---
id: decision-032
title: CI wiring is locally verifiable now without a live self-hosted runner or Apple secrets
status: Accepted
date: 2026-09-13
---

## Context

TASK-049 wires GitHub Actions CI: a self-hosted `[macOS, ARM64]` job that builds, tests, signs,
and notarizes; a Linux job running the Docker build (TASK-045); and a nightly `task oracle:fuzz`
job — following `~/git/mt`'s model. Two things this repo does not yet have looked, at first
glance, like they could block this task:

- `gh api repos/pythoninthegrasses/neo_snake/actions/runners` returns `{"total_count":0,"runners":[]}`
  — no self-hosted runner is registered on this GitHub repo, unlike `~/git/mt`, which has a real,
  live macOS ARM64 self-hosted runner backing its own `[macOS, ARM64]` jobs.
- `gh secret list` returns nothing — none of the seven Apple signing secrets
  (`APPLE_SIGNING_IDENTITY`, `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`,
  `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_B64`, `APPLE_API_KEY`, `APPLE_API_ISSUER`) that
  `task release:ship-macos` (TASK-044) requires are configured on this repo yet.

## Decision

Neither is a blocker for this task, and neither is fixable by an agent anyway (registering a
self-hosted runner and adding repo secrets are both actions Lance has to take in GitHub's own UI).
TASK-049's four Acceptance Criteria are all satisfiable through local/static verification alone:

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

**What still needs Lance, before this workflow does anything for real on GitHub**: register a
self-hosted macOS ARM64 runner on `pythoninthegrasses/neo_snake` (`gh api` or Settings -> Actions ->
Runners), and add the seven Apple signing secrets under Settings -> Secrets and variables ->
Actions. Until then, pushes to `main` will queue the `macos` job forever (or it will simply never
pick up, depending on GitHub's queueing behavior for a job with no matching runner) — this does not
block any merge, since `gh api repos/pythoninthegrasses/neo_snake/branches/main/protection` returns
404 ("Branch not protected"): no required status checks exist on `main`.

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
