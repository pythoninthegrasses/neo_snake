class_name AppLifecycle
extends Node

## Ports reference/snake.html's window-blur auto-pause (snake.html:620:
## `addEventListener("blur", () => { if (S.status === "playing")
## togglePause(); });`) onto Godot's MainLoop notifications. Which of
## NOTIFICATION_APPLICATION_FOCUS_OUT / NOTIFICATION_WM_WINDOW_FOCUS_OUT
## actually fires is unconfirmed across desktop/mobile/web at design time
## (AC#1), so both -- and their _IN counterparts -- are listened for
## defensively; per backlog/decisions/decision-012, this also covers
## Android backgrounding, which has no blur-equivalent guarantee the way
## desktop browsers do.
##
## Emits focus_lost at most once per genuine focus transition (AC#2),
## even when multiple notification constants fire for the same underlying
## event -- _focused tracks whether a loss has already been reported so a
## caller (a future screens/app-wiring task) that pauses once per
## focus_lost never double-pauses. The _IN notifications exist solely to
## reset that tracking for the next transition; mirroring the oracle
## exactly, there is no focus-regained signal, since snake.html has no
## resume-on-focus behavior to port.

signal focus_lost

var _focused := true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _focused:
			_focused = false
			focus_lost.emit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true
