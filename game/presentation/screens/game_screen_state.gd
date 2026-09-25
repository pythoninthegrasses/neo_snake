class_name GameScreenState
extends RefCounted

## Pure port of reference/snake.html's status-driven overlay content --
## the menu overlay's static markup (snake.html:227-241), die()'s and
## win()'s showOverlay() calls (snake.html:402, 407), and togglePause()'s
## showOverlay() call (snake.html:562) -- with no Node/Control/
## SimulationWorld dependency, so every screen transition is directly
## gdUnit4-testable without a live scene (TASK-036 AC#3). Text is plain
## (no <br>/<b> markup): the task explicitly calls for real Control nodes
## instead of showOverlay()'s innerHTML string-building, and a Label needs
## no markup to break a line or emphasize a number.

## The keyboard split local 2-player uses (backlog/decisions/decision-035):
## player 0 owns the arrow keys, player 1 owns WASD. Shown on the menu so a
## second player doesn't have to be told which half of the keyboard is
## theirs. Player 2's line stays up for a 1-player game too -- it is how a
## player learns a 2-player game exists.
const CONTROLS_LEGEND := "Player 1: Arrow Keys\nPlayer 2: WASD"

const SCREEN_MENU := "menu"
const SCREEN_PLAYING := "playing"
const SCREEN_PAUSED := "paused"
const SCREEN_DEAD := "dead"

## sim_status is a SimulationWorld/BoardGeometry status value. The live
## ABI only ever reports menu/playing/dead (see backlog/decisions/ --
## ns_toggle_pause has no export, so a real world's status never becomes
## BoardGeometry.STATUS_PAUSED); app_paused is the orchestrator's own
## app-level pause flag, layered on top since TickDriver gates ticks on it
## directly instead of the sim status ever leaving .playing.
static func screen_for(sim_status: int, app_paused: bool) -> String:
	if sim_status == BoardGeometry.STATUS_PLAYING:
		return SCREEN_PAUSED if app_paused else SCREEN_PLAYING
	if sim_status == BoardGeometry.STATUS_DEAD:
		return SCREEN_DEAD
	return SCREEN_MENU

## screen must be SCREEN_MENU, SCREEN_PAUSED, or SCREEN_DEAD --
## SCREEN_PLAYING has no overlay and is never passed here. is_win
## distinguishes die() from win() (both leave sim status .dead; the
## caller tells them apart via the drained NS_EVENT_WIN/NS_EVENT_DIE kind,
## not a derived full-board check).
static func overlay_content(screen: String, score: int, best: int, snake_len: int, is_win: bool) -> Dictionary:
	match screen:
		SCREEN_MENU:
			return {
				"title": "Ready?",
				"sub": "Eat the red squares. Don't hit the walls or yourself.\nSpace to pause.",
				"button_label": "",
				"show_mode_select": true,
				"show_player_select": true,
				"show_return_to_title": false,
				"show_quit": true,
				"controls": CONTROLS_LEGEND,
			}
		SCREEN_PAUSED:
			return {
				"title": "Paused",
				"sub": "Score %d · Length %d\nSpace to resume." % [score, snake_len],
				"button_label": "Resume",
				"show_mode_select": false,
				"show_player_select": false,
				"show_return_to_title": false,
				"show_quit": false,
				"controls": "",
			}
		SCREEN_DEAD:
			if is_win:
				return {
					"title": "You Win",
					"sub": "Perfect board — Score %d. Insane." % score,
					"button_label": "Play Again",
					"show_mode_select": false,
					"show_player_select": false,
					"show_return_to_title": true,
					"show_quit": false,
					"controls": "",
				}
			return {
				"title": "Game Over",
				"sub": "Score %d · Best %d\nPress R to run it back." % [score, best],
				"button_label": "Play Again",
				"show_mode_select": false,
				"show_player_select": false,
				"show_return_to_title": true,
				"show_quit": false,
				"controls": "",
			}
		_:
			return {}
