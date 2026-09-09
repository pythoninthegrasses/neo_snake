extends GdUnitTestSuite

## Proves the headless gdUnit4 pipeline (TASK-005 AC#1) actually runs a
## real assertion, not just that the runner starts and exits cleanly.


func test_pipeline_runs_a_real_assertion() -> void:
	assert_that(1 + 1).is_equal(2)
