extends GdUnitTestSuite

## Exercises AppLifecycle (TASK-035) directly against Godot's own
## NOTIFICATION_* constants by calling _notification() as a plain method --
## the same values the engine itself would deliver to a live node, so this
## verifies the class's real dedup logic on desktop (AC#3) without needing
## an actual window-manager focus change. Android/web coverage is not
## automatable (no test harness can simulate OS-level backgrounding) and is
## documented instead, per backlog/decisions/decision-012's own note that
## correctness there relies on manual/platform testing.

var _lifecycle: AppLifecycle
var _lost_count := 0


func before_test() -> void:
	_lifecycle = AppLifecycle.new()
	_lost_count = 0
	_lifecycle.focus_lost.connect(func() -> void: _lost_count += 1)
	add_child(_lifecycle)


func after_test() -> void:
	_lifecycle.queue_free()


func test_application_focus_out_emits_focus_lost() -> void:
	_lifecycle._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_int(_lost_count).is_equal(1)


func test_wm_window_focus_out_emits_focus_lost() -> void:
	_lifecycle._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_int(_lost_count).is_equal(1)


func test_both_focus_out_notifications_firing_for_the_same_transition_emits_once() -> void:
	_lifecycle._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_lifecycle._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_int(_lost_count).is_equal(1)


func test_focus_in_resets_tracking_so_a_later_focus_out_fires_again() -> void:
	_lifecycle._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_lifecycle._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_lifecycle._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_int(_lost_count).is_equal(2)


func test_focus_in_without_a_prior_focus_out_does_not_emit() -> void:
	_lifecycle._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_lifecycle._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	assert_int(_lost_count).is_equal(0)


func test_unrelated_notifications_are_ignored() -> void:
	_lifecycle._notification(NOTIFICATION_READY)
	assert_int(_lost_count).is_equal(0)
