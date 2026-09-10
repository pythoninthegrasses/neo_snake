#!/usr/bin/env python3
# Bridges gnhf's file-based monitoring protocol to a `pi --mode rpc`
# subprocess, so an unattended pi run has a live channel to receive an
# answer to a MANUAL_RUN: ASK -- question instead of running deaf like a
# plain `pi -p` launch. Also auto-answers the plan-mode extension's
# "Execute the plan" dialog (see scripts/pi-extensions/plan-mode/), so a
# --plan run doesn't stall waiting for a human that isn't there.
#
# Status-file vocabulary (first line of --status-file, atomically written):
#   RUNNING        pi subprocess started, no terminal outcome yet
#   ASK            model printed MANUAL_RUN: ASK -- ; waiting on --control-file
#   DONE           model printed MANUAL_RUN: DONE --
#   BAILED         model printed MANUAL_RUN: BAILED --
#   PROCESS_EXITED pi exited before ever printing a terminal marker
#   BRIDGE_ERROR   this script hit an unhandled exception
#   KILLED         this script received SIGTERM (TTL expiry or external kill)
import argparse
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

# The detail group stops at the next MANUAL_RUN marker (or end of string),
# not just at end of string -- a plain greedy `(.*)` with DOTALL and no
# lookahead swallows every subsequent marker into the first one's detail,
# so a genuine premature-then-corrected DONE (see rpc-bridge-smoke-test.sh
# scenario 3) would report the premature marker's text instead of the real
# final one. Still DOTALL/non-greedy internally so a legitimately
# multi-line detail (e.g. an ASK's "what I already tried" paragraph) is
# still captured whole when it's the last/only marker in the text.
MARKER_RE = re.compile(
    r"MANUAL_RUN:\s*(DONE|BAILED|ASK)\s*—\s*(.*?)(?=\n*MANUAL_RUN:\s*(?:DONE|BAILED|ASK)\s*—|\Z)",
    re.DOTALL,
)

# Control-file command types passed straight through to pi's stdin verbatim,
# beyond the bridge's own synthesized "answer" -> steer/prompt translation.
PASSTHROUGH_TYPES = {
    "prompt", "steer", "follow_up", "get_state", "abort", "abort_bash",
    "abort_retry", "clear_queue", "set_steering_mode", "set_follow_up_mode",
    "set_auto_retry", "set_auto_compaction", "bash",
}

# Minimum seconds between RUNNING heartbeat rewrites. The status file's
# timestamp line is what a monitor compares against wall clock to tell
# "still working" from "stalled" (see SKILL.md step 6) -- too frequent and
# it's needless atomic-replace churn on every text_delta event, too sparse
# and a monitor's stall check loses resolution.
HEARTBEAT_INTERVAL_S = 10.0


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--session-id", required=True)
    p.add_argument("--prompt-file", required=True)
    p.add_argument("--control-file", required=True)
    p.add_argument("--events-log", required=True)
    p.add_argument("--status-file", required=True)
    p.add_argument("--cwd", required=True)
    p.add_argument("--provider")
    p.add_argument("--model")
    p.add_argument("--pi-bin", default="pi")
    p.add_argument("--extension", action="append", default=[], help="path to load via pi's --extension (repeatable)")
    p.add_argument("--plan", action="store_true", help="start pi in plan mode (passes --plan through)")
    p.add_argument("--poll-interval", type=float, default=1.0)
    return p.parse_args()


class Bridge:
    def __init__(self, args):
        self.a = args
        self.proc = None
        self.is_streaming = False
        self.turn_text = []
        self.control_offset = 0
        self.log_lock = threading.Lock()
        self.status_lock = threading.Lock()
        self.stop_event = threading.Event()
        self.terminal_state = None  # "DONE" | "BAILED" once reached
        self.current_status_state = None  # mirrors the last state written to --status-file
        self.bridge_log_path = self._bridge_log_path()

    def _bridge_log_path(self) -> str:
        base, _ = os.path.splitext(self.a.events_log)
        return base + ".bridge.log"

    # ---------- lifecycle ----------
    def start(self):
        cmd = [self.a.pi_bin, "--mode", "rpc", "--session-id", self.a.session_id]
        if self.a.provider:
            cmd += ["--provider", self.a.provider]
        if self.a.model:
            cmd += ["--model", self.a.model]
        for ext in self.a.extension:
            cmd += ["--extension", ext]
        if self.a.plan:
            cmd += ["--plan"]
        self.append_bridge_log(f"Spawning: {' '.join(cmd)} (cwd={self.a.cwd})")
        self.echo(f"[bridge] launching: {' '.join(cmd)}")
        self.proc = subprocess.Popen(
            cmd, cwd=self.a.cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1,
        )
        self.write_status("RUNNING", "")
        prompt_text = open(self.a.prompt_file, encoding="utf-8").read()
        self.send_command({"type": "prompt", "message": prompt_text})

    def run(self):
        threading.Thread(target=self.control_loop, daemon=True).start()
        threading.Thread(target=self.stderr_pump, daemon=True).start()
        threading.Thread(target=self.heartbeat_loop, daemon=True).start()
        self.event_loop()

    # ---------- outbound (bridge -> pi stdin) ----------
    def send_command(self, cmd: dict):
        line = json.dumps(cmd)
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()
        self.append_log(json.dumps({"bridge_sent": cmd}))

    # ---------- events (pi stdout -> bridge) ----------
    def event_loop(self):
        for raw in self.proc.stdout:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            self.append_log(raw)
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                continue
            self.handle_event(event)
            if self.terminal_state:
                self.shutdown_pi()
                break
        self.finish()

    def handle_event(self, event):
        etype = event.get("type")
        if etype == "extension_ui_request":
            self.handle_extension_ui_request(event)
        elif etype == "agent_start":
            self.is_streaming = True
            self.turn_text = []
            if not self.terminal_state and self.current_status_state != "RUNNING":
                # Clears a stale ASK (or SETTLED_NO_MARKER-adjacent) label once
                # the model resumes -- otherwise a monitor that already
                # answered the question keeps seeing "ASK" with a frozen
                # timestamp from before the answer, indistinguishable from a
                # genuinely stalled/unanswered one.
                self.write_status("RUNNING", "")
        elif etype == "message_end":
            msg = event.get("message") or {}
            if msg.get("role") == "assistant":
                for block in msg.get("content") or []:
                    if block.get("type") == "text":
                        self.turn_text.append(block.get("text", ""))
                        text = block.get("text", "").strip()
                        if text:
                            self.echo(text)
        elif etype == "tool_execution_start":
            self.echo(f"[tool] {self._describe_tool_call(event)}")
        elif etype == "agent_settled":
            self.is_streaming = False
            text = "".join(self.turn_text)
            state, detail = self.scan_markers(text)
            if state != "SETTLED_NO_MARKER":
                self.write_status(state, detail)
                if state in ("DONE", "BAILED"):
                    self.terminal_state = state
            else:
                # Ordinary mid-run settle (e.g. one plan-execution step) --
                # not an anomaly by itself. Only a settle with no marker
                # that pi then never follows up from (process exits with
                # no terminal_state) is worth flagging; see finish().
                self.append_bridge_log("settled with no MANUAL_RUN marker (not terminal, continuing)")
        elif etype == "response" and event.get("success") is False:
            self.append_bridge_log(f"WARN command failed: {json.dumps(event)}")

    def handle_extension_ui_request(self, event):
        method = event.get("method")
        req_id = event.get("id")
        if method == "select":
            options = event.get("options") or []
            execute_opt = next((o for o in options if o.startswith("Execute the plan")), None)
            if execute_opt is not None:
                self.append_bridge_log(f"auto-answering plan-mode select -> {execute_opt!r}")
                self.echo(f"[bridge] auto-approving plan: {execute_opt}")
                self.send_command({"type": "extension_ui_response", "id": req_id, "value": execute_opt})
                return
            self.append_bridge_log(f"WARN unrecognized select dialog, cancelling: {json.dumps(event)}")
            self.send_command({"type": "extension_ui_response", "id": req_id, "cancelled": True})
        elif method in ("confirm", "input", "editor"):
            self.append_bridge_log(f"WARN unhandled {method} dialog, cancelling: {json.dumps(event)}")
            self.send_command({"type": "extension_ui_response", "id": req_id, "cancelled": True})
        else:
            # fire-and-forget (notify/setStatus/setWidget/setTitle/set_editor_text): no response needed
            self.append_bridge_log(f"extension_ui_request (fire-and-forget): {json.dumps(event)}")

    @staticmethod
    def scan_markers(text: str):
        found = {m.group(1): m.group(2).strip() for m in MARKER_RE.finditer(text)}
        for kind in ("BAILED", "DONE", "ASK"):
            if kind in found:
                return kind, found[kind]
        return "SETTLED_NO_MARKER", ""

    def heartbeat_loop(self):
        # A genuine wall-clock timer, NOT triggered by incoming pi events --
        # `pi` emits nothing at all on stdout while a tool call is silently
        # running (confirmed: a plain `sleep 12` produces zero events for
        # the full 12s), so an event-triggered heartbeat never fires during
        # exactly the gap it exists to cover. This periodic write is
        # therefore only a liveness signal ("the bridge's own loop is still
        # alive and pi hasn't exited"), not a "pi made real progress"
        # signal -- a long, legitimately silent tool call looks identical
        # to a stuck one from here. That distinction still needs the
        # SKILL.md step 6 approach (scan tool-call content, watch for a
        # repeated identical failure), this just replaces "the timestamp is
        # frozen at launch time forever" with something that actually moves.
        while not self.stop_event.wait(HEARTBEAT_INTERVAL_S):
            if self.terminal_state:
                return
            if self.current_status_state == "RUNNING":
                self.write_status("RUNNING", "")

    # ---------- control file (monitor -> bridge) ----------
    def control_loop(self):
        while not self.stop_event.is_set():
            self.poll_control_file()
            time.sleep(self.a.poll_interval)
        self.poll_control_file()

    def poll_control_file(self):
        path = self.a.control_file
        if not os.path.exists(path):
            return
        with open(path, "r", encoding="utf-8") as f:
            f.seek(self.control_offset)
            chunk = f.read()
        if not chunk:
            return
        idx = chunk.rfind("\n")
        complete = chunk[: idx + 1] if idx != -1 else ""
        if not complete:
            return
        self.control_offset += len(complete.encode("utf-8"))
        for line in complete.splitlines():
            line = line.strip()
            if line:
                self.handle_control_line(line)

    def handle_control_line(self, line: str):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            self.append_bridge_log(f"WARN malformed control line, skipped: {line!r}")
            return
        ctype = parsed.get("type")
        if ctype == "answer":
            message = parsed.get("message", "")
            cmd = {"type": "steer", "message": message} if self.is_streaming else {"type": "prompt", "message": message}
            self.send_command(cmd)
        elif ctype in PASSTHROUGH_TYPES:
            self.send_command(parsed)
        else:
            self.append_bridge_log(f"WARN unknown control command type: {ctype!r}")

    # ---------- status file (bridge -> monitor), atomic ----------
    def write_status(self, state: str, detail: str):
        # Called from the main event-loop thread (agent_start/agent_settled/
        # finish) and now also from heartbeat_loop's own thread -- the tmp
        # filename is only unique per-process (os.getpid()), not per-thread,
        # so two concurrent callers would race on the same tmp path without
        # this lock.
        changed = state != self.current_status_state
        with self.status_lock:
            tmp = f"{self.a.status_file}.tmp.{os.getpid()}"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(f"{state}\n{utcnow()}\n{detail}\n")
            os.replace(tmp, self.a.status_file)
            self.current_status_state = state
        if changed:
            # Only on a real transition -- not the heartbeat's own periodic
            # re-write of the same RUNNING state, which would otherwise spam
            # an identical line every ~10s.
            self.echo(f"[bridge] status -> {state}" + (f" ({detail})" if detail else ""))

    # ---------- human-readable live echo (bridge's own real stdout) ----------
    def echo(self, line: str):
        # A bare-background launch redirects this to the task's own log
        # file (`> logs/<TASK-ID>.log`), giving a readable companion next
        # to the raw JSONL --events-log. A Herdr-pane launch that does NOT
        # redirect this away shows it live in the pane -- this is the
        # whole point: rpc-bridge.py previously produced zero real stdout
        # output (everything went to files), which is both invisible to a
        # human watching the pane and, empirically, unreliable for Herdr's
        # own pane-output-based agent detection.
        for text_line in line.splitlines() or [""]:
            print(text_line, flush=True)

    @staticmethod
    def _describe_tool_call(event: dict) -> str:
        name = event.get("toolName", "?")
        args = event.get("args") or {}
        if name == "bash":
            return f"bash: {args.get('command', '')}"
        if name in ("edit", "write"):
            return f"{name}: {args.get('path', '')}"
        if name == "read":
            path = args.get("path", "")
            offset, limit = args.get("offset"), args.get("limit")
            span = f" [{offset}:{offset + limit}]" if offset is not None and limit is not None else ""
            return f"read: {path}{span}"
        # Fallback: name + a short, single-line rendering of whatever args exist.
        return f"{name}: {json.dumps(args)[:200]}"

    # ---------- shutdown ----------
    def shutdown_pi(self):
        # Empirically confirmed: pi --mode rpc exits ~0.2s after stdin
        # closes once settled. Kept SIGTERM/SIGKILL as a fallback in case
        # a future pi version or an unusual run doesn't behave the same.
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=10)
            return
        except subprocess.TimeoutExpired:
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()

    def finish(self):
        self.stop_event.set()
        rc = self.proc.wait()
        if not self.terminal_state:
            self.write_status("PROCESS_EXITED", f"pi exited (code {rc}) before a terminal MANUAL_RUN marker")
        sys.exit(0)

    def stderr_pump(self):
        for line in self.proc.stderr:
            self.append_bridge_log("[pi stderr] " + line.rstrip("\n"))

    def append_log(self, line: str):
        with self.log_lock:
            with open(self.a.events_log, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    def append_bridge_log(self, line: str):
        with open(self.bridge_log_path, "a", encoding="utf-8") as f:
            f.write(f"{utcnow()} {line}\n")


def main():
    args = parse_args()
    bridge = Bridge(args)

    def on_sigterm(signum, frame):
        try:
            bridge.write_status("KILLED", "bridge received SIGTERM (TTL expiry or external kill)")
        except Exception:
            pass
        sys.exit(143)

    signal.signal(signal.SIGTERM, on_sigterm)

    try:
        bridge.start()
        bridge.run()
    except Exception as exc:
        try:
            bridge.write_status("BRIDGE_ERROR", repr(exc))
        except Exception:
            pass
        raise


if __name__ == "__main__":
    main()
