extends GdUnitTestSuite

## Asserts the NeoSnakeWorld GDExtension actually loaded (TASK-027 AC#1). A
## silently-unloaded GDExtension would otherwise make every other test that
## touches SimulationWorld fail with an unrelated "class not found" error, or
## even skip outright -- this test exists so that failure mode fails loudly
## and specifically, right here, instead of hiding behind some other test.


func test_neo_snake_world_class_is_registered() -> void:
	assert_bool(ClassDB.class_exists("NeoSnakeWorld")).is_true()
