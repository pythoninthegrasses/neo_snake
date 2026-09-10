---
name: gnhf
description: >
  Launch a bounded, low-supervision overnight (or long-unattended) coding
  agent run against one well-specced task, in an isolated worktree, using
  whichever agent CLI and model is currently configured — not a hardcoded
  one. By default, once a task merges it automatically chains to the next
  eligible backlog task (pass --single to disable). Use when the user
  says "gnhf", "good night have fun", "run this overnight", "let an agent
  work on this while I'm away/asleep", "burn this task unattended", or
  asks to set up a long-running agent session bounded by a time or turn
  budget with minimal check-ins.
argument-hint: "<task-id-or-description> [ttl] [max-turns] [--single]"
---

# gnhf

## Resolve `SKILL_DIR` (do this before running the bundled script)

`scripts/smoke-test.sh` is a direct sibling of this file in every install
layout. Set `SKILL_DIR` to the absolute path of the directory containing
THIS SKILL.md you just Read (your harness told you that path in the Read
result), e.g.:

```
Read ~/.claude/skills/gnhf/SKILL.md → SKILL_DIR=~/.claude/skills/gnhf
Read .agents/skills/gnhf/SKILL.md   → SKILL_DIR=.agents/skills/gnhf
```

Note: this is a personal, from-scratch skill, unrelated to the `gnhf` npm
package (`kunchenguid/gnhf`) that also occupies this name. Don't adopt that
tool's CLI, config file, or Companion/Hands-Off skill — this one is simpler
and modeled on how this user actually runs unattended agents (manual git
worktree, a Herdr-managed pane when available (see step 5) or a plain
background process otherwise, `timeout` for the wall-clock bound either
way).

## Overview

One agent, one task, one isolated worktree, bounded by a TTL (wall clock)
or a turn count, minimally supervised until it finishes, bails, or the
bound expires. The agent CLI and model must be resolved from whatever is
currently configured — never hardcode a specific agent/model pairing,
because both get rotated over time.

Every environment-specific path mentioned below (config repos, worktree
conventions, prompt templates) is a signal to check *if present*, not a
requirement. Test for existence before reading; treat a missing one as
"skip and fall through," not a failure. This is what keeps the skill
working on a machine that doesn't have this user's particular config repos
checked out.

**Chaining to the next task is the default.** Once one task's cycle ends
(merged, or a bail/escalation the user has seen and responded to), don't
stop — go back to step 2, pick the next eligible task, and repeat steps
2-7 for it. Keep going until no eligible task remains, the user stops it,
or genuine progress requires the user (see step 8). Pass `--single`, or
have the user say "just this one," to run exactly one task and stop
normally at step 7 instead. Chaining is strictly serial — one agent, one
task, one worktree at a time, the same as a single run; the point is
unattended endurance across many tasks, not concurrency. Step 8 covers
the chaining mechanics in full, including how monitoring has to work
differently to survive across tasks unattended.

## 1. Resolve the current agent + model (don't hardcode)

Resolution order — try the CLI's own current default FIRST, unconditionally;
only fall back to inspecting config repos if that default doesn't actually
work. Don't reverse this: checking `pi_config`/`opencode_config` before ever
trying the CLI's own default means testing a config the CLI might not even be
using, and skips over whatever it's already pointed at (some qwen3.8 variant,
another open-weight model, whatever) without ever asking it.

1. `which pi opencode claude codex copilot 2>/dev/null` — which agent CLIs
   are actually on `PATH` right now. If none are found, stop here and
   report that no supported agent CLI is installed; don't guess or try to
   install one. Default to `pi` if more than one is found and nothing else
   disambiguates (matches this user's usual setup).
2. **First pass — the CLI's own unmodified default.** Smoke-test it with no
   `--provider`/`--model` overrides:

   ```bash
   "${SKILL_DIR}/scripts/smoke-test.sh" pi
   # or:
   "${SKILL_DIR}/scripts/smoke-test.sh" opencode
   ```

   Whatever the CLI does with zero model flags *is* "currently configured"
   on this machine — don't second-guess it by reading a config repo first.
   If this passes, you're done resolving: confirm which model actually
   served the request via the CLI's own introspection (`pi --list-models`
   marks the active default; opencode's model can be read back from
   `opencode.jsonc`/`opencode models` or from the run's own session
   metadata) so you can report a concrete model name, not just "default."
3. **Only if step 2 fails** (non-zero exit, timeout, or wrong reply — read
   the smoke-test's own tail-of-output diagnosis first, this step is not
   for "it was slow"): inspect the config repos below, each existence-gated
   — a missing path is routine, not an error, just "skip this signal, fall
   through to the next one." These are this user's personal setup, not a
   guaranteed environment; none may exist on a collaborator's machine or a
   fresh install, and if none do, that itself is the bail condition (step
   5).
   - If `~/git/pi_config` exists (`test -d ~/git/pi_config`): read `.env`
     (or `~/.pi/agent/.env` if already rendered) for `PI_DEFAULT_PROVIDER` /
     `PI_DEFAULT_MODEL`, falling back to the "Active default is set per
     machine via..." line in `AGENTS.md` if `.env` alone doesn't explain
     the setup (e.g. multi-machine defaults).
   - If `~/git/opencode_config` exists: read `opencode.jsonc.tpl`'s `model`
     / `agent.build.model` field for opencode's current default.
   - If `~/git/tailscale_config` exists: check `aperture.hujson` (or
     whatever gateway config is live) for which model IDs a shared
     remote/self-hosted backend actually serves right now — a model
     referenced elsewhere may have been rotated out, which is itself a
     likely explanation for why step 2 failed.
4. **Retry the smoke test** with whatever explicit provider/model step 3
   turned up:

   ```bash
   "${SKILL_DIR}/scripts/smoke-test.sh" pi --provider aperture --model "qwen3.8-flash-next-iq4:builder"
   "${SKILL_DIR}/scripts/smoke-test.sh" opencode --model "aperture/qwen3.8-flash-next-iq4:builder"
   ```

   If this passes, resolve to this explicit value for the real run.
5. **Only if step 4 also fails, or step 3 found no config repos at all**:
   bail out cleanly. Report the specific blocker (which command failed, what
   it printed) rather than launching the real task on a guess.

Always say which agent+model you resolved and from where ("CLI default, no
override needed" vs. a specific config-repo file), so a stale assumption is
easy to catch.

Each smoke-test invocation sends one prompt, waits up to `--timeout` seconds
(default 300 — observed cold-start latency on a fresh backend has run into
minutes; don't treat a slow first response as a functional failure), and
checks for the expected reply. Exit 0 with `PASS: ...` means that candidate
works. A non-zero exit means don't use that candidate — read the tail of
output it prints to understand why (agent not installed, backend
unreachable, wrong model id) before moving to the next step.

## 2. Pick a task that's actually a good candidate for this

Do not launch against just any open task. Require, in order:

- **Well-specced**: concrete Acceptance Criteria, not vague/exploratory
  ones; the Description pins down scope with specifics (file paths, line
  ranges, function/symbol names) rather than "figure out a good approach."
  If a real candidate task isn't there yet, that's normal, not a reason to
  stop — see "Research and decide" below.
- **Prior art**: a structurally similar task has already landed in this
  repo — check recent commits / closed tasks with the same label or
  pattern. If nothing comparable has ever been done successfully, this is
  not yet a good unattended-run candidate as written; narrow it until it
  is (see "Research and decide" below) rather than running it supervised
  instead — supervised is the fallback only when the user isn't chaining.
- **Never touch gating/verification tooling**: the one absolute, non-
  negotiable reject condition. If a task cannot be attempted without
  relaxing or editing the repo's own gates (`tools/validate_*`, any
  `task game:*`/equivalent target, lint config, CI), that candidate is
  out, full stop — no research or decision-making gets around this one.

Reject and pick something else only for the gating-tooling condition.
Everything else below ("well-specced", "prior art") is a scoping problem
to solve, not a reason to reject — that's what "Research and decide" is
for.

**Research and decide, don't stop the chain over a design/mechanism
question.** A task needing a *value* pick (a damage number, a cost, a
stacking policy) was already solved by AD-003.06 onward: pick the smallest
defensible candidate with some textual/content-reference source, name it
candidate-not-parity, move on. Apply that same discipline one level up,
to *mechanism* questions (how does a cadence work, what's the shape of a
new subsystem, how should a vague two-line AC decompose into slices) —
research it with the same rigor you'd want from the launched run itself:
read every doc/fixture the task references and any it doesn't but plainly
bears on it, check how this codebase already resolved a structurally
similar ambiguity (grep prior task Notes sections — they are a decision
log), and pick the option best supported by what you find. Write the
decision and its justification into the new subtask's Description exactly
like a launched run writes one into its own Notes, so it's reviewable, not
just asserted. If the first reasonable slice is still too big once you've
made the mechanism decision, split again — recursively, as many times as
it takes to reach something the step 2 checklist actually passes. None of
this is a reason to stop and ask; it's the work chaining is for. The
*only* thing that still stops the chain over a task's own content is the
gating-tooling condition above — see step 8 for the complete, narrow list
of real stops.

Find the task through whatever this repo actually uses (Backlog.md MCP
task, `TODO.md` entry, a GitHub issue) — don't assume one system across
repos.

**Picking the next task automatically while chaining (step 8).** Don't
stop to ask the user which task comes next. Walk the backlog in its own
priority/ordinal order, and **exhaust the current task family before
moving to the next one**: if you were handed (or previously split out of)
AD-NNN.MM, keep working through AD-NNN.MM's remaining slices — split
further, research mechanism questions, whatever it takes — until that
whole parent is genuinely done, before advancing to AD-NNN.(MM+1) or the
next top-level AD-(NNN+1). Run this checklist against each candidate in
turn until one passes.

If a candidate fails the checklist for being too broad/vague (concrete
Acceptance Criteria missing, no prior art), don't stop to ask what to do
about it either — apply the recommended fix yourself: split it into a
narrower, concretely-scoped first subtask the way AD-003.07 was split
into AD-003.07.01 (mirror the specificity of an already-landed sibling
task, name in the new subtask exactly what's deferred and why), leave a
short note on the parent task pointing at the split, then launch on that
subtask instead of the original. If the broadness is because the slice
needs a mechanism decision, not just a narrower value pick, that is not a
reason to reject it either — see "Research and decide" above: make the
call, document it in the new subtask, and proceed the same way.

The only thing chaining still stops and asks a person about, for a
task's own content, is the gating-tooling condition above (needs to
relax or edit the repo's own gates, no matter how it's split or
redesigned). Everything else — including "this needs a real design
decision" — gets solved by research and a documented choice, not by
escalating. See step 8 for the complete, narrow list of real stops
(it is not this one).

## 3. Isolate in a worktree

Create a dedicated git worktree for this run rather than working in the
main checkout or an existing feature branch. Follow the repo's own
established convention if it has one; otherwise a plain sibling directory
named after the task/branch is fine:

```bash
git worktree add /path/to/worktrees/<TASK-ID> -b <TASK-ID>
```

**In this repo specifically**: use `~/git/manual-wt/<TASK-ID>` (and
`~/git/manual-wt/logs/` for the prompt/events/status/control files) — NOT
`~/git/worktrees/`, which belongs to the separate `burnkit`/`dsh`
automated driver (`scripts/burn/driver.py`; see
`docs/development.md#autonomous-dsh-headless-sessions`). The two drivers
don't share worktree state or a lock protocol with each other, so keeping
them in visibly separate sibling directories is what actually prevents a
collision, not a naming convention alone. Confirmed as the real path in
practice, not just a placeholder: AD-003.08.04 (2026-09-10) ran from
`~/git/manual-wt/AD-003.08.04`.

If the model backing this run is local/self-hosted (nothing leaves the
box), and the task needs gitignored source material the repo normally
keeps out of remote-model reach, symlink those directories into the
worktree from the main checkout. If the model is a remote/hosted one,
don't — respect whatever privacy boundary the repo documents (this is
usually spelled out per-backend, e.g. a "local vs remote planner" split in
existing driver prompt templates).

## 4. Build the prompt

Prefer the repo's own prompt conventions if any exist (grep for something
like a driver/burn prompt template) and adapt it rather than inventing new
rules from scratch. Otherwise use this minimal skeleton. **If the resolved
agent (step 1) is `pi`**, use the ASK-aware variant below — step 5 launches
it through `rpc-bridge.py`, which gives it a real (if narrow) live channel
back. For every other resolved agent, use the template exactly as it reads
in the "non-pi variant" section — unchanged, no live channel exists for
those.

### pi variant (ASK-aware)

Identical to the non-pi skeleton below except for the framing paragraph and
STUCK POLICY:

```text
You are working alone in this repository checkout, a dedicated git
worktree on branch <TASK-ID>. Complete exactly ONE task, given in full
below, end to end. An orchestrator is watching this session
asynchronously and CAN research and answer a live question — but it isn't
a person, knows nothing about this task beyond what you tell it, and
won't check in on a fixed schedule; treat that exactly like the "nobody is
watching" case below, except for the one narrow case STUCK POLICY's
second bullet describes. If you find yourself wanting to ask a clarifying
question or unsure which of several reasonable interpretations to pick,
that feeling is not by itself grounds to ask — resolve it yourself from
the repo/task evidence whenever you genuinely can. Reserve the ASK marker
strictly for the same rare case that would otherwise be a BAIL.

HARD RULES:
- Never relax or edit this repo's own verification/gating tooling to make
  a stuck task pass. If something genuinely can't be verified with the
  existing gates, that's a BAIL — name the blocker and stop.
- Never fabricate a passing check you did not just run. If a tool/pipeline
  fails repeatedly and you work around it by hand, say so plainly — that's
  an accepted outcome here, but claiming a run that didn't happen is not.
- Match the surrounding code/prose style; comments explain WHAT or WHY,
  never "improved"/"fixed"/"new".

STUCK POLICY — two distinct outcomes, don't guess and don't keep spinning:
- The same blocker persists across ~3 distinct fix attempts with no
  genuine progress, and no genuine ambiguity behind it (just repeated
  failure): BAIL. Write the blocker into the task's notes, print a line
  starting `MANUAL_RUN: BAILED —` describing it, and end your turn.
- A single genuine ambiguity that would change scope or behavior and
  isn't settled by the task text, the referenced docs/fixtures, or
  existing repo precedent (a coin-flip you'd normally ask a human about):
  ASK. Print a line starting `MANUAL_RUN: ASK —` with a concise question
  AND what you already tried/considered/ruled out, then end your turn
  normally — do not also print a BAILED marker in the same breath, ASK and
  BAIL are different outcomes. Ending your turn is what signals the
  question; stop there and wait rather than continuing to work past it. If
  an answer arrives, it comes as the next message in this same session —
  treat it as authoritative and continue. This is not an invitation to ask
  more often: the bar is exactly the same as the BAIL bullet above, only
  the outcome changed from a dead end to a live answer.
In either case: do this BEFORE your last message, never instead of it — a
turn that ends on plain text with no marker is indistinguishable from a
crash to whoever reviews this run later.

FINISH PROTOCOL: when every Acceptance Criteria item is genuinely
satisfied, update the task's status/notes, commit locally on this branch
(no push, no PR — a human reviews the worktree directly), then print a
line starting `MANUAL_RUN: DONE —` summarizing what landed.

Your diff should touch only what this task's Acceptance Criteria describe.

---

<full task description + acceptance criteria, verbatim>
```

### non-pi variant

```text
You are working alone in this repository checkout, a dedicated git
worktree on branch <TASK-ID>. Complete exactly ONE task, given in full
below, end to end. Nobody is watching this session and no one will answer
a question you ask — there is no user to reply. If you find yourself
wanting to ask a clarifying question or unsure which of several reasonable
interpretations to pick, that feeling IS the stuck condition below, not a
reason to stop and wait for input: resolve it yourself from the repo/task
evidence if you genuinely can, and BAIL if you can't — never end your turn
on an open question with no BAIL marker.

HARD RULES:
- Never relax or edit this repo's own verification/gating tooling to make
  a stuck task pass. If something genuinely can't be verified with the
  existing gates, that's a BAIL — name the blocker and stop.
- Never fabricate a passing check you did not just run. If a tool/pipeline
  fails repeatedly and you work around it by hand, say so plainly — that's
  an accepted outcome here, but claiming a run that didn't happen is not.
- Match the surrounding code/prose style; comments explain WHAT or WHY,
  never "improved"/"fixed"/"new".

STUCK POLICY: BAIL (don't guess and don't keep spinning) on either of
these:
- the same blocker persists across ~3 distinct fix attempts with no
  genuine progress, or
- a single genuine ambiguity that would change scope or behavior and
  isn't settled by the task text, the referenced docs/fixtures, or
  existing repo precedent (a coin-flip you'd normally ask a human about).
In both cases: write the blocker/ambiguity into the task's notes, print a
line starting `MANUAL_RUN: BAILED —` describing it, and end your turn.
Do this BEFORE your last message, never instead of it — a turn that ends
on plain text with no marker is indistinguishable from a crash to whoever
reviews this run later.

FINISH PROTOCOL: when every Acceptance Criteria item is genuinely
satisfied, update the task's status/notes, commit locally on this branch
(no push, no PR — a human reviews the worktree directly), then print a
line starting `MANUAL_RUN: DONE —` summarizing what landed.

Your diff should touch only what this task's Acceptance Criteria describe.

---

<full task description + acceptance criteria, verbatim>
```

## 5. Launch, bounded

The wall-clock bound (TTL) is the primary and simplest bound — wrap the
launch in `timeout`.

**If this session is itself running inside a Herdr-managed pane**
(`test "${HERDR_ENV:-}" = 1`), launch the run in its own Herdr workspace
(a genuinely separate window, not a split or a tab in the caller's
window — the user's preference, confirmed 2026-09-10) instead of a bare
detached process, so it shows up in Herdr's own agent list/panel like any
other agent session:

```bash
ws=$(herdr workspace create --cwd /path/to/worktrees/<TASK-ID> \
    --label "<TASK-ID>" --no-focus)
pane_id=$(printf '%s\n' "$ws" | jq -r '.result.root_pane.pane_id')
```

Do not use `herdr agent start` for this (its `--timeout` is only a
3-300s startup-readiness wait, not a run-length bound, and it won't take
a `timeout`-wrapped command line).

**If the resolved agent (step 1) is `pi`**, run it through `rpc-bridge.py`
here too (same flags as the bare-background form below), so the ASK
live-channel and `--plan` auto-execute both work inside Herdr as well —
**crucially, do NOT redirect its stdout away** (no trailing `>
.../logs/<TASK-ID>.log 2>&1`, unlike every other launch form on this
page):

```bash
herdr pane run "$pane_id" \
  "timeout <TTL_SECONDS> '${SKILL_DIR}/scripts/rpc-bridge.py' \
      --session-id <task-id>-run \
      --prompt-file /path/to/prompt.md \
      --control-file /path/to/logs/<TASK-ID>.control.jsonl \
      --events-log /path/to/logs/<TASK-ID>.log \
      --status-file /path/to/logs/<TASK-ID>.status \
      --cwd /path/to/worktrees/<TASK-ID> \
      --extension '${SKILL_DIR}/scripts/pi-extensions/plan-mode/index.ts' \
      --plan"
```

Leaving stdout unredirected does two things at once, both confirmed live
(2026-09-10, three trials): it makes the run's progress genuinely visible
in the pane in real time (`rpc-bridge.py` echoes a human-readable line for
each state transition, tool call, and completed assistant message — see
"What the pane shows" below), **and** it fixes Herdr's own agent
detection. Earlier testing with output redirected away (the events/status
files still worked, but the pane itself stayed blank) found detection
unreliable — one fluke `"agent":"pi"` sighting, then a longer trial that
never registered at all sampled repeatedly across its whole duration.
With output left visible, three separate trials all registered reliably
(`"agent":"pi"`, `agent_status` moving `unknown` → `idle`/`working`) —
Herdr's detector reads visible pane text, not the process tree, so a
silent process (redirected or not producing real stdout at all) is
invisible to it regardless of what it's actually doing internally.

**What the pane shows**: `[bridge] launching: ...` at spawn, `[bridge]
status -> <STATE>` on every real state transition (not the ~10s
heartbeat's repeats of the same state), `[tool] bash: <command>` / `[tool]
edit: <path>` / etc. for each tool call, and each completed assistant
message's text. This is the same information the raw `--events-log` JSONL
carries, reformatted for a human watching the window rather than a
monitor scanning the file — use whichever fits the moment.

**Every other resolved agent** keeps the existing plain form, output
redirected as before:

```bash
herdr pane run "$pane_id" \
  "timeout <TTL_SECONDS> <agent> <agent-specific-flags> --session-id <task-id>-run -p '@/path/to/prompt.md' > /path/to/logs/<TASK-ID>.log 2>&1"
```

Record `pane_id` — it's the handle for step 6's monitoring and stands in
for the PID below.

**If `HERDR_ENV` is unset** (not running inside Herdr, or Herdr isn't
installed), fall back to the plain background form. **If the resolved
agent (step 1) is `pi`**, launch through `rpc-bridge.py` instead of a bare
`pi -p` invocation, so the ASK live-channel (step 6) and the plan-mode
auto-execute dialog (`--plan`, vendored at
`scripts/pi-extensions/plan-mode/index.ts`) both work. Every other
resolved agent keeps the plain form unchanged:

```bash
# pi:
cd /path/to/worktrees/<TASK-ID>
nohup timeout <TTL_SECONDS> "${SKILL_DIR}/scripts/rpc-bridge.py" \
    --session-id <task-id>-run \
    --prompt-file /path/to/prompt.md \
    --control-file /path/to/logs/<TASK-ID>.control.jsonl \
    --events-log /path/to/logs/<TASK-ID>.log \
    --status-file /path/to/logs/<TASK-ID>.status \
    --cwd /path/to/worktrees/<TASK-ID> \
    --extension "${SKILL_DIR}/scripts/pi-extensions/plan-mode/index.ts" \
    --plan \
    [--provider <provider> --model <model>] \
    > /path/to/logs/<TASK-ID>.readable.log 2>&1 &

# any other agent:
cd /path/to/worktrees/<TASK-ID>
nohup timeout <TTL_SECONDS> <agent> <agent-specific-flags> \
    --session-id <task-id>-run \
    -p "@/path/to/prompt.md" \
    > /path/to/logs/<TASK-ID>.log 2>&1 &
```

Default `TTL_SECONDS` to 10800 (3h) unless the user gives a different
budget. Record the PID (or `pane_id` for the Herdr path) — for pi this is
`rpc-bridge.py`'s own PID, not `pi`'s; killing it also kills the `pi`
child (confirmed: `timeout` on this machine kills the whole process group,
and the bridge's own shutdown path closes `pi`'s stdin, which `pi --mode
rpc` treats as a clean-exit request before any signal is needed).

A pi run therefore leaves three logs, not one: `<TASK-ID>.log` (raw
JSONL, `--events-log`, every RPC event verbatim), `<TASK-ID>.bridge.log`
(the bridge's own diagnostics plus `pi`'s stderr), and
`<TASK-ID>.readable.log` (the same human-readable echo the Herdr pane
shows live above — `tail -f` this one for a quick "what's it doing"
check without parsing JSONL).

A turn/iteration bound (`max-turns`) only applies when the agent is
literally invoked once per turn with session continuation (e.g. opencode's
`--continue <session-id>` pattern, or repeated `pi -p --session-id`
calls) — most agent CLIs (including `pi -p`) run their own internal
multi-step tool-call loop inside a single invocation, so `timeout` alone
already bounds that. Only build an external per-turn loop-and-check
wrapper if the user explicitly wants turn-level granularity (e.g. to
inspect/steer between turns) rather than a single long-lived process.

## 6. Monitor with minimal oversight

For a single (`--single`) run with the user present in the conversation,
`ScheduleWakeup` (not a blocking sleep) is enough to check back
periodically (every 15-20 minutes is reasonable). For chaining (step 8),
prefer invoking the `loop` skill right after launch instead of calling
`ScheduleWakeup` standalone: `ScheduleWakeup`'s own contract is written
for "`/loop` dynamic mode" specifically, and a bare call outside that
context is not guaranteed to actually wake this session on its own later
— it may just as easily depend on the user prompting again, which defeats
the "unattended" point of chaining. `/loop` (no fixed interval, so the
model self-paces) is the mechanism actually meant to survive across turns
without a person driving it; hand it a prompt describing this run's
monitor-then-chain job (log path, PID/pane_id, and: on completion, do the
step-7 review/merge, then step 2's auto-pick, then relaunch and loop
again) rather than trying to keep the loop alive by hand.

**If the resolved agent is `pi`** (launched through `rpc-bridge.py`, step
5), check its status file instead of grepping the log for a marker:

```bash
head -n1 /path/to/logs/<TASK-ID>.status   # RUNNING | ASK | DONE | BAILED | PROCESS_EXITED | BRIDGE_ERROR | KILLED
```

- `DONE` / `BAILED`: proceed to step 7 exactly as with the marker-based
  flow below.
- `ASK`: read the rest of the status file (question text, on lines after
  the timestamp) or `tail` the events log for the model's own `MANUAL_RUN:
  ASK —` line, research/decide an answer the same way step 2's "Research
  and decide" does for a mechanism question, then append the answer to
  the control file so the bridge delivers it live:
  ```bash
  printf '%s\n' '{"type":"answer","message":"<your answer>"}' \
      >> /path/to/logs/<TASK-ID>.control.jsonl
  ```
  Then keep monitoring — the run continues from wherever it paused.
- `PROCESS_EXITED` / `BRIDGE_ERROR`: treat like the "silent exit" case
  below — read the tail of the events/bridge logs for what happened,
  report it as the blocker, don't relaunch on a guess.
- `KILLED`: the bridge received SIGTERM (TTL expiry, most likely) — same
  handling as a `timeout`-killed run in the non-pi flow.
- `RUNNING` with the status file's timestamp itself frozen (`rpc-bridge.py`
  heartbeats it every ~10s while genuinely RUNNING, so no movement at all
  for several minutes means the bridge process itself likely died or
  hung) is a hard stop — check `ps -p <PID>` and the bridge log
  immediately, this is a different and more serious signal than the next
  bullet.
- `RUNNING` with the timestamp still ticking but no real progress for a
  long stretch (skim recent tool-call content in the events log, don't
  just trust the timestamp) is the pi-run equivalent of the thrashing
  signal below: worth a closer look before deciding whether to nudge (via
  the control file, a raw passthrough command like
  `{"type":"steer","message":"..."}`) or let it keep running. **The
  heartbeat is a liveness signal, not a progress signal** — it ticks every
  ~10s purely from wall-clock time as long as the bridge's own loop is
  alive, so a single long-running tool call (a slow test suite, a big
  build) looks identical in the timestamp to genuine thrashing. Telling
  the two apart still means reading what the run is actually doing, the
  same as the non-pi flow below.

**For every other resolved agent**, each check, whether from a `/loop`
firing or a manual look, should be non-blocking:

```bash
tail -n 40 /path/to/logs/<TASK-ID>.log
ps -p <PID> -o pid,etime,stat
cd /path/to/worktrees/<TASK-ID> && git log --oneline -5 && git status --short
```

If launched via a Herdr pane (step 5), also check the agent's live
lifecycle state alongside the log/git checks:

```bash
herdr agent get "$pane_id"
herdr agent read "$pane_id" --source recent-unwrapped --lines 120
```

`agent_status: idle` or `done` after the process has exited corroborates
the log's own finish marker. `blocked` means Herdr detected an
approval/question prompt in the pane — a headless `-p` invocation should
never hit one, so treat `blocked` as a possible stuck/thrashing signal
worth a closer look via `agent read`, not a routine state.

**Silent exit is its own case, distinct from thrashing** (non-pi agents
only — any pi run, bare-background or through a Herdr pane, always goes
through `rpc-bridge.py` now and gets this as an explicit `PROCESS_EXITED`
status above instead). If
`ps`/`herdr agent get` shows the process/pane is no longer running (not
killed by
`timeout` — `etime` well under the TTL) and the log has neither
`MANUAL_RUN: DONE —` nor `MANUAL_RUN: BAILED —`, the model ended its turn
without a marker — most likely it asked a question or hedged instead of
following the STUCK POLICY. Treat this exactly like a `BAILED` in step 7
(no push, no PR): read the last ~50 lines of the log for whatever the
model actually said before it stopped, and report that as the blocker —
don't relaunch on a guess at what it meant, and don't treat the absence of
a marker as silent success.

Only intervene (nudge the run, or kill it) on genuine thrashing signals:
the same failing command repeating verbatim, no commits after a long
stretch with the identical error recurring, or the log showing an obvious
loop. A run that's slow but making incremental progress (new draft
attempts, changing error messages, partial test passes) is not thrashing —
let it continue.

Otherwise let it run until a `MANUAL_RUN: DONE —` / `MANUAL_RUN: BAILED —`
marker appears, the process exits (including via `timeout` killing it at
the TTL), or you've confirmed real thrashing.

## 7. Finish

On `MANUAL_RUN: BAILED —`, a silent marker-less exit (non-pi agents; step
6), a `PROCESS_EXITED`/`BRIDGE_ERROR` status (pi via `rpc-bridge.py`; step
6), TTL expiry, or a thrashing kill: don't push anything. Report the
blocker and the worktree + log paths for manual review (plus the
status/control file paths for a pi run).

On `MANUAL_RUN: DONE —`: the launched agent commits locally only (per its
own FINISH PROTOCOL, step 4 above) and never pushes or opens a PR itself —
that's deliberate, so nothing goes further before a review step happens.
That review step is yours, not optional, and not the same as trusting the
run's own self-report:

1. `git diff --stat <base>..<head>` — confirm the diff touches only what
   the task's Acceptance Criteria describe (task file, the specific
   ref/tools paths named in the task), not unrelated trees. Confirm any
   untracked entries are pre-existing gitignored symlinks (`analysis`,
   `extracted`), not real content that should've been `.gitignore`d or
   was accidentally staged.
2. Check the task file's Acceptance Criteria are actually checked `[x]`,
   not just claimed done in prose.
3. Once the diff passes review, push the branch and open a PR (`gh pr
   create`, following whatever title/body convention recent merged PRs in
   this repo already use) — then **merge it by default** (`gh pr merge
   --squash`, matching this repo's established merge style) rather than
   leaving it open for a separate human pass. Fast-forward the local
   `main` checkout (`git fetch && git merge --ff-only origin/main`) so the
   next task's worktree branches off a `main` that includes it.

Only skip the push/merge and escalate instead if review turns up a real
problem (scope violation, an unchecked AC, fabricated evidence) — report
that plainly rather than merging over it. Always report back:
DONE/BAILED/TTL-expired/killed-for-thrashing, what actually landed (from
`git log`/`git diff`, not from the run's own self-report), and the PR/merge
outcome.

**A merge/push itself can get blocked by the environment's own permission
classifier**, independent of anything above — this is a hard external
stop, not a decision of yours to route around. Report it plainly and wait
for the user's one-time approval; once granted, resume the chain (step 8)
from exactly where it stopped rather than re-doing the review.

## 8. Chain to the next task (skip if `--single`)

After step 7 ends in a merge, or in a bail/escalation the user has since
seen and acknowledged: don't stop here. Go back to step 2, auto-pick the
next eligible task (including its "apply the recommended split
automatically" rule), and run steps 2-7 again for it in a fresh
worktree/branch. Reuse the agent+model already resolved in step 1 rather
than re-running the smoke test each time — re-resolve only if a run
itself reports the model/provider is unreachable.

**Take the `Recommended` option automatically wherever this skill would
otherwise call `AskUserQuestion` for a task-selection, rescoping, or
mechanism-design choice** — a chain that stops to ask about every
judgment call isn't unattended, and "this needs a design decision" is not
by itself a reason to stop (see step 2's "Research and decide"). Note
each automatic choice in your eventual report so a person can revisit any
of them later. Exhaust the current task family (all of AD-NNN.MM's
slices) before moving to AD-NNN.(MM+1) or the next AD-(NNN+1), same as
step 2 says.

This does not apply to the short, genuine list below — these really do
need a person, and nothing about "research and decide" is meant to paper
over them:

- **A task cannot be attempted, at any split depth, without relaxing or
  editing the repo's own gating/verification tooling.** This is the one
  content-level stop that survives no matter how much research or
  splitting you do. Report exactly which gate and why the task's real
  requirement conflicts with it.
- **No eligible task remains anywhere in the project** — not just the
  current phase/family; check adjacent phases and the top-level backlog
  too. This should be rare, since "the next slice needs research" is no
  longer a reason to treat a family as exhausted — only genuinely running
  out of backlog, or hitting the gating-tooling wall on every remaining
  item even after real attempts to split around it, counts.
- **An environment-level block**, most notably a merge/push refused by a
  permission classifier (step 7) — that specific approval is outside
  gnhf's control. Report it, wait for the one-time approval, then resume
  the chain from where it stopped.
- **The user interrupts or stops the chain directly.**

Every other fork in this skill (which task's next, whether to split a
vague task, which candidate tick amount or stacking policy a launched
run should pick, etc.) has a stated recommended default specifically so
the chain doesn't stall on it — use that default and keep going.

## Bundled scripts

`scripts/smoke-test.sh` — verifies `pi` or `opencode` can reach its
currently configured model and produce a real response (see step 1).
Review it before first use to verify behavior.

`scripts/rpc-bridge.py` — launches `pi --mode rpc` for an unattended run
and bridges gnhf's file-based monitoring protocol to it, giving the run a
live channel to receive an answer to a `MANUAL_RUN: ASK —` question
(step 6) and auto-answering the plan-mode extension's "Execute the plan"
dialog when launched with `--plan` (see step 5). Also echoes a
human-readable line to its own real stdout for every state transition,
tool call, and completed assistant message — this is what a Herdr pane
shows live when its output isn't redirected away, and what lands in
`<TASK-ID>.readable.log` for the bare-background form (step 5). stdlib-
only Python, no dependencies. Review it before first use to verify
behavior.

`scripts/rpc-bridge-smoke-test.sh` — exercises `rpc-bridge.py` end to end
against a real `pi --mode rpc` subprocess: the ASK/answer loop, the
plan-mode auto-execute loop, a premature-then-real-DONE marker sequence
within one agent run, and the status-file heartbeat during a long-running
tool call. Run it after any change to `rpc-bridge.py` or the vendored
plan-mode extension, before trusting either on a real task.

`scripts/pi-extensions/plan-mode/` — vendored copy of `pi-coding-agent`'s
bundled plan-mode example extension (unmodified). Loaded via `pi
--extension .../index.ts --plan` (step 5) so a `pi` run proposes a
numbered plan read-only before `rpc-bridge.py` auto-approves execution.
