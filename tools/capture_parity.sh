#!/usr/bin/env bash
# TASK-037 golden-image parity capture.
#
# Renders reference/snake.html (a real Firefox window) and the Godot build
# (via game_screen.gd's --capture-state= debug hook, see game_screen.gd's
# _maybe_drive_capture_state()) under a headless sway compositor, injecting
# input with wtype and grabbing frames with grim -- the same
# sway+wtype+grim stack proven in ~/git/zelda3's task-005. Substitutes for
# this task's AC#2 literal "xvfb-run" wording; see
# backlog/decisions/decision-025 for why, and docs/build-layout.md for the
# full mechanism writeup. Linux + Wayland-tooling only -- not part of
# `task check` (see taskfiles/parity.yml).
#
# Output is a set of PNGs for a human to eyeball side by side -- this suite
# is judgment-matched, not an automated pixel-diff gate (see task-037's own
# Description and docs/build-layout.md).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/artifacts/parity}"
STATES=(menu playing paused dead)

for bin in sway wtype grim firefox godot; do
	command -v "$bin" >/dev/null 2>&1 || {
		echo "capture_parity: missing required binary: $bin" >&2
		exit 1
	}
done

mkdir -p "$OUT_DIR"
WORKDIR="$(mktemp -d)"

SWAY_PID=""
WTYPE_PID=""

cleanup() {
	[ -n "$WTYPE_PID" ] && kill -9 "$WTYPE_PID" >/dev/null 2>&1 || true
	[ -n "$SWAY_PID" ] && kill -9 "$SWAY_PID" >/dev/null 2>&1 || true
	rm -rf "$WORKDIR"
}
trap cleanup EXIT

SWAY_CONF="$WORKDIR/sway.conf"
cat >"$SWAY_CONF" <<EOF
output HEADLESS-1 resolution 520x600
EOF

env WLR_BACKENDS=headless WLR_RENDERER=pixman sway -c "$SWAY_CONF" >"$WORKDIR/sway.log" 2>&1 &
SWAY_PID=$!
sleep 2

SOCK="$(ls "${XDG_RUNTIME_DIR}"/wayland-[0-9]* 2>/dev/null | head -1)"
if [ -z "$SOCK" ]; then
	echo "capture_parity: sway produced no wayland socket -- see $WORKDIR/sway.log" >&2
	exit 1
fi
export WAYLAND_DISPLAY
WAYLAND_DISPLAY="$(basename "$SOCK")"

# One long-lived virtual keyboard avoids the create/bind-race a lone
# per-invocation `wtype` can lose (see decision-025).
wtype -s 600000 >/dev/null 2>&1 &
WTYPE_PID=$!
sleep 1

echo "capturing Godot build states..."
for state in "${STATES[@]}"; do
	env SDL_VIDEODRIVER=wayland godot --path "$ROOT_DIR/game" \
		--rendering-driver opengl3 --rendering-method gl_compatibility \
		-- "--capture-state=$state" >"$WORKDIR/godot-$state.log" 2>&1 &
	pid=$!
	sleep 4
	grim "$OUT_DIR/godot-$state.png"
	kill -9 "$pid" >/dev/null 2>&1 || true
	wait "$pid" 2>/dev/null || true
	sleep 1
done

echo "capturing reference/snake.html oracle states..."
for state in "${STATES[@]}"; do
	mkdir -p "$WORKDIR/ff-profile-$state"
	firefox --new-instance --profile "$WORKDIR/ff-profile-$state" --no-remote \
		"file://$ROOT_DIR/reference/snake.html" >"$WORKDIR/firefox-$state.log" 2>&1 &
	pid=$!
	sleep 4
	case "$state" in
	menu) ;;
	playing)
		wtype -k Up
		sleep 1
		;;
	paused)
		wtype -k Up
		sleep 1
		wtype -k space
		sleep 1
		;;
	dead)
		# Menu/dead auto-start always clobbers the pressed direction to
		# right (decision-015) -- wait out however long "Walls (classic)"
		# takes the snake to run into the right wall from its spawn point.
		wtype -k Up
		sleep 10
		;;
	esac
	grim "$OUT_DIR/oracle-$state.png"
	kill -9 "$pid" >/dev/null 2>&1 || true
	wait "$pid" 2>/dev/null || true
	sleep 1
done

echo "done -- screenshots in $OUT_DIR"
