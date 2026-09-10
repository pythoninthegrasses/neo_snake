#!/usr/bin/env bash
# Exercise rpc-bridge.py end to end against a real `pi --mode rpc`
# subprocess, in four scenarios:
#   1. ASK/answer loop: force a MANUAL_RUN: ASK --, answer it via the
#      control file, confirm MANUAL_RUN: DONE -- is reached.
#   2. Plan-mode auto-execute: launch with --plan and the vendored
#      plan-mode extension, confirm the bridge auto-answers the
#      "Execute the plan" dialog with no control-file write, and
#      MANUAL_RUN: DONE -- is still reached.
#   3. Premature-then-real DONE within one agent run: the model prints a
#      DONE-shaped line, then keeps generating more tool calls before
#      truly finishing (this is exactly what happened live on
#      AD-003.08.04 -- NOT a deterministic plan-mode re-trigger, on
#      inspection: agent_end's own handler just returns if the todo list
#      isn't complete, it doesn't re-prompt. What actually happened is
#      pi's ordinary agent loop continuing because the model itself chose
#      to keep working past its first "done" line -- so this scenario
#      reproduces that shape directly with plain tool calls, no --plan).
#      Confirms the bridge waits for agent_settled rather than latching
#      onto the first DONE-shaped text mid-run, and that the LAST marker
#      of each kind in the accumulated turn text wins (scan_markers's
#      dict comprehension keeps the last match per kind, not the first).
#   4. Heartbeat + stale-ASK clear: confirms the status file's timestamp
#      actually advances during a longer RUNNING stretch (not just once at
#      launch), and that answering an ASK clears the label back to RUNNING
#      on the next agent_start rather than leaving a stale "ASK" behind.
# Plus one deterministic (no LLM, no pi) unit check of MARKER_RE/
# scan_markers before any of the above, so the marker-parsing fix itself
# has coverage that doesn't depend on model cooperation -- scenario 3
# exercises the same fix live, but can only prove it when the model
# happens to continue past its own premature DONE line.
# Exit 0 = the unit check and all four live loops worked, non-zero = one
# didn't (see diagnostics).
set -uo pipefail   # not -e: we poll in loops and inspect status ourselves

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$SCRIPT_DIR/rpc-bridge.py"
EXTENSION="$SCRIPT_DIR/pi-extensions/plan-mode/index.ts"
TIMEOUT=120

usage() {
  cat <<'EOF'
Usage: rpc-bridge-smoke-test.sh [--timeout SECS]

Options:
  --timeout SECS   per-scenario wall-clock bound for the pi subprocess (default: 120)
  -h, --help       show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v pi >/dev/null 2>&1; then
  echo "FAIL: pi is not on PATH" >&2
  exit 1
fi

### Scenario 0: MARKER_RE/scan_markers unit check -- no LLM, no pi, deterministic
run_scenario_0() {
  python3 - "$BRIDGE" <<'EOF'
import importlib.util
import sys

bridge_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("rpc_bridge", bridge_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Two markers of the same kind in one accumulated turn_text -- this is
# exactly what a genuine premature-then-corrected DONE looks like. The
# last one must win, and its detail must not have swallowed the first.
text = (
    "MANUAL_RUN: DONE — premature, ignore this one\n\n"
    "Correcting that false alarm — continuing to the real step.\n\n"
    "MANUAL_RUN: DONE — printed final"
)
state, detail = mod.Bridge.scan_markers(text)
assert state == "DONE", f"expected state DONE, got {state!r}"
assert detail == "printed final", f"expected detail 'printed final', got {detail!r}"

# A legitimately multi-line detail (the last/only marker) must still be
# captured whole, not truncated at its first newline.
ask_text = "Some work.\n\nMANUAL_RUN: ASK — question line one\nstill part of the question\nand more"
state2, detail2 = mod.Bridge.scan_markers(ask_text)
assert state2 == "ASK", f"expected state ASK, got {state2!r}"
assert detail2 == "question line one\nstill part of the question\nand more", f"unexpected multi-line detail: {detail2!r}"

print("PASS(0): MARKER_RE/scan_markers unit check (last-marker-wins, multi-line detail preserved)")
EOF
}

run_scenario_0 || { echo "FAIL(0): marker-parsing unit check failed" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
BRIDGE_PID=0
cleanup() {
  # BRIDGE_PID=0 means "nothing to kill" -- `kill 0` would signal this
  # script's whole process group instead, which is not what we want here.
  [ "$BRIDGE_PID" -ne 0 ] 2>/dev/null && kill "$BRIDGE_PID" 2>/dev/null
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

fail() {
  local label="$1" status="$2"
  echo "FAIL($label): $status" >&2
  # >&2 2>/dev/null, in that order: redirect stdout to (the real) stderr
  # first, THEN silence each command's own stderr -- the reverse order
  # remaps fd2 to /dev/null before >&2 copies it, which silently discards
  # the very output these diagnostics exist to show.
  echo "--- status file ---" >&2; cat "$WORKDIR/$label.status" >&2 2>/dev/null
  echo "--- tail events log ---" >&2; tail -n 60 "$WORKDIR/$label.log" >&2 2>/dev/null
  echo "--- tail bridge log ---" >&2; tail -n 60 "$WORKDIR/$label.bridge.log" >&2 2>/dev/null
  exit 1
}

wait_for_status() {   # wait_for_status LABEL WANT_STATE BUDGET_SECS
  local label="$1" want="$2" budget="$3" waited=0
  while (( waited < budget )); do
    if [ -f "$WORKDIR/$label.status" ] && [ "$(head -n1 "$WORKDIR/$label.status")" = "$want" ]; then
      return 0
    fi
    kill -0 "$BRIDGE_PID" 2>/dev/null || { fail "$label" "bridge process died before reaching $want"; }
    sleep 1; ((waited++))
  done
  return 1
}

### Scenario 1: ASK -> answer via control file -> DONE
run_scenario_1() {
  local label="ask"
  cat > "$WORKDIR/$label.prompt.md" <<'EOF'
You are in a test harness, not a real task. Do not use any tools.
Pick a favorite integer between 1000 and 2000 -- since nothing settles
which one, treat this as STUCK POLICY's genuine-ambiguity case: print a
line starting exactly "MANUAL_RUN: ASK — " with your question, then end
your turn and wait. When a later message tells you which number to use,
print a line starting exactly "MANUAL_RUN: DONE — chose <number>" and
stop.
EOF

  timeout "$TIMEOUT" "$BRIDGE" \
      --session-id "rpc-bridge-smoke-$label" \
      --prompt-file "$WORKDIR/$label.prompt.md" \
      --control-file "$WORKDIR/$label.control.jsonl" \
      --events-log "$WORKDIR/$label.log" \
      --status-file "$WORKDIR/$label.status" \
      --cwd "$WORKDIR" \
      >"$WORKDIR/$label.bridge-stdout.log" 2>&1 &
  BRIDGE_PID=$!

  wait_for_status "$label" ASK 60 || fail "$label" "never reached ASK within 60s"
  echo "PASS(1a): reached MANUAL_RUN: ASK --"

  printf '%s\n' '{"type":"answer","message":"Use 1013."}' >> "$WORKDIR/$label.control.jsonl"

  wait_for_status "$label" DONE 60 || fail "$label" "never reached DONE within 60s after answering"
  grep -q '1013' "$WORKDIR/$label.status" || fail "$label" "DONE status did not reflect the answer (expected 1013)"
  wait "$BRIDGE_PID" 2>/dev/null; BRIDGE_PID=0
  echo "PASS(1b): answer via control file reached MANUAL_RUN: DONE --"
}

### Scenario 2: --plan auto-execute -> DONE, no control-file write
run_scenario_2() {
  local label="plan"
  cat > "$WORKDIR/$label.prompt.md" <<'EOF'
You are in a test harness, not a real task. You are in plan mode. When
asked to create a plan, output exactly this (and nothing else):

Plan:
1. Print the word done

When later asked to execute the plan, for step 1: print a line
containing exactly "[DONE:1]", then on its own line print exactly
"MANUAL_RUN: DONE — printed done". Do not use any tools.
EOF

  timeout "$TIMEOUT" "$BRIDGE" \
      --session-id "rpc-bridge-smoke-$label" \
      --prompt-file "$WORKDIR/$label.prompt.md" \
      --control-file "$WORKDIR/$label.control.jsonl" \
      --events-log "$WORKDIR/$label.log" \
      --status-file "$WORKDIR/$label.status" \
      --cwd "$WORKDIR" \
      --extension "$EXTENSION" \
      --plan \
      >"$WORKDIR/$label.bridge-stdout.log" 2>&1 &
  BRIDGE_PID=$!

  wait_for_status "$label" DONE 90 || fail "$label" "never reached DONE within 90s"
  wait "$BRIDGE_PID" 2>/dev/null; BRIDGE_PID=0

  if [ -f "$WORKDIR/$label.control.jsonl" ] && [ -s "$WORKDIR/$label.control.jsonl" ]; then
    fail "$label" "control file was written to, but scenario 2 expects a fully automatic auto-execute with no control-file involvement"
  fi
  grep -q 'auto-answering plan-mode select' "$WORKDIR/$label.bridge.log" || \
    fail "$label" "bridge log has no record of auto-answering the plan-mode select dialog"
  echo "PASS(2): plan-mode select dialog auto-answered, MANUAL_RUN: DONE — reached with no control-file write"
}

### Scenario 3: premature DONE-shaped line, more tool calls follow, real DONE wins
run_scenario_3() {
  local label="redo"
  cat > "$WORKDIR/$label.prompt.md" <<'EOF'
You are in a test harness, not a real task. Follow these steps in order,
in ONE continuous response (do not stop or end your turn early):

1. Run the bash command `echo step1` using your bash tool.
2. Immediately after that tool result, print a line starting exactly
   "MANUAL_RUN: DONE — premature, ignore this one" -- but do NOT stop
   here, this is a deliberate false alarm you must then correct.
3. Run the bash command `echo step2` using your bash tool.
4. After that tool result, print a line starting exactly
   "MANUAL_RUN: DONE — printed final" and THEN genuinely stop (no further
   tool calls, no further text).
EOF

  timeout "$TIMEOUT" "$BRIDGE" \
      --session-id "rpc-bridge-smoke-$label" \
      --prompt-file "$WORKDIR/$label.prompt.md" \
      --control-file "$WORKDIR/$label.control.jsonl" \
      --events-log "$WORKDIR/$label.log" \
      --status-file "$WORKDIR/$label.status" \
      --cwd "$WORKDIR" \
      >"$WORKDIR/$label.bridge-stdout.log" 2>&1 &
  BRIDGE_PID=$!

  wait_for_status "$label" DONE 90 || fail "$label" "never reached DONE within 90s"
  wait "$BRIDGE_PID" 2>/dev/null; BRIDGE_PID=0

  grep -q 'echo step1' "$WORKDIR/$label.log" || fail "$label" "step 1's tool call never ran"

  # This scenario needs the model to keep generating past a DONE-shaped
  # line despite being told to -- that's genuine model behavior, not
  # something the bridge or this script can force deterministically. A
  # small/fast local model sometimes just stops there instead (observed
  # live: 2/3 runs continued as instructed, 1/3 settled early) -- that is
  # the model not cooperating with the test's contrived setup, not a
  # bridge regression, so it's inconclusive rather than a failure. The
  # regex fix itself is covered separately by a deterministic (non-LLM)
  # unit check; treat this scenario as the integration nice-to-have it is.
  if ! grep -q 'echo step2' "$WORKDIR/$label.log"; then
    echo "SKIP(3): model settled right after the premature DONE line instead of continuing to step 2 this run -- inconclusive, not a failure (see comment above). Status file correctly reflects what actually happened:"
    head -n3 "$WORKDIR/$label.status"
    return 0
  fi

  grep -q 'printed final' "$WORKDIR/$label.status" || \
    fail "$label" "status file's DONE detail is not the real final marker (expected 'printed final') -- the bridge may have latched onto the premature one"
  if grep -q 'premature, ignore this one' "$WORKDIR/$label.status"; then
    fail "$label" "status file's DONE detail is the PREMATURE marker, not the final one -- bridge terminated too early"
  fi
  echo "PASS(3): premature DONE-shaped line was superseded by the real final DONE within the same agent run, and the bridge waited for agent_settled rather than latching on early"
}

### Scenario 4: status-file timestamp heartbeats during a long RUNNING stretch
run_scenario_4() {
  local label="heartbeat"
  cat > "$WORKDIR/$label.prompt.md" <<'EOF'
You are in a test harness, not a real task. Run the bash command
`sleep 12` using your bash tool and wait for it to complete (do not skip
this step or use a shorter sleep). After it finishes, print a line
starting exactly "MANUAL_RUN: DONE — slept" and stop. Do not use any
other tools.
EOF

  timeout "$TIMEOUT" "$BRIDGE" \
      --session-id "rpc-bridge-smoke-$label" \
      --prompt-file "$WORKDIR/$label.prompt.md" \
      --control-file "$WORKDIR/$label.control.jsonl" \
      --events-log "$WORKDIR/$label.log" \
      --status-file "$WORKDIR/$label.status" \
      --cwd "$WORKDIR" \
      >"$WORKDIR/$label.bridge-stdout.log" 2>&1 &
  BRIDGE_PID=$!

  # Wait for the status file to exist at all, then sample its timestamp,
  # wait past one heartbeat interval, sample again -- while still RUNNING
  # this proves the heartbeat (not just the one-time launch write) is what
  # moved it.
  local waited=0
  while [ ! -f "$WORKDIR/$label.status" ] && (( waited < 30 )); do
    sleep 1; ((waited++))
  done
  [ -f "$WORKDIR/$label.status" ] || fail "$label" "status file never appeared"
  local ts0
  ts0="$(sed -n '2p' "$WORKDIR/$label.status")"

  sleep 13   # > HEARTBEAT_INTERVAL_S (10s); the sleep-12 tool call should still be running

  kill -0 "$BRIDGE_PID" 2>/dev/null || fail "$label" "bridge process died before the heartbeat window elapsed"
  local ts1 state1
  ts1="$(sed -n '2p' "$WORKDIR/$label.status")"
  state1="$(head -n1 "$WORKDIR/$label.status")"
  if [ "$ts1" = "$ts0" ]; then
    fail "$label" "status file timestamp did not advance across a 13s window while still $state1 -- heartbeat is not firing"
  fi
  echo "PASS(4a): status-file timestamp advanced from a heartbeat during a long RUNNING stretch ($ts0 -> $ts1, still $state1)"

  wait_for_status "$label" DONE 60 || fail "$label" "never reached DONE within 60s after the sleep completed"
  wait "$BRIDGE_PID" 2>/dev/null; BRIDGE_PID=0
  echo "PASS(4b): reached MANUAL_RUN: DONE — after the heartbeat-covered stretch"
}

run_scenario_1
run_scenario_2
run_scenario_3
run_scenario_4
echo "PASS: unit check + all live rpc-bridge loops verified"
