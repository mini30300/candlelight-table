extends "res://tests/testing.gd"
## The Log autoload: a ring buffer of the last 500 lines with info/warn/error levels and dump().

const LogScript := preload("res://app/log.gd")


func test_autoload_is_live() -> void:
	assert_true(Log != null and Log.is_inside_tree(), "the Log autoload is in the tree under the runner")
	var before := Log.size()
	Log.echo = false
	Log.info("runner says hello")
	Log.echo = true
	assert_eq(Log.size(), before + 1, "info() adds one line to the live log")
	assert_true(Log.lines()[Log.size() - 1].ends_with("runner says hello"), "the newest line is last")


func test_ring_buffer_keeps_the_last_500_lines() -> void:
	var l: Node = LogScript.new()
	l.echo = false
	assert_eq([l.size(), l.dump()], [0, ""], "empty at start")
	for i in 620:
		l.info("L%04d" % i)
	assert_eq(l.size(), LogScript.CAPACITY, "capped at %d lines" % LogScript.CAPACITY)
	var lines: PackedStringArray = l.lines()
	assert_eq(lines.size(), LogScript.CAPACITY, "lines() returns the whole buffer")
	assert_true(lines[0].ends_with("L0120"), "the oldest kept line is the 121st written: " + lines[0])
	assert_true(lines[lines.size() - 1].ends_with("L0619"), "the newest line is last: " + lines[lines.size() - 1])
	var dump: String = l.dump()
	assert_true(dump.contains("L0619") and dump.contains("L0120") and not dump.contains("L0119"), "dump() holds exactly the kept lines")
	assert_eq(dump.split("\n").size(), LogScript.CAPACITY, "dump() is one line per entry")
	l.free()


func test_levels_and_clear() -> void:
	var l: Node = LogScript.new()
	l.echo = false   # no push_warning/push_error noise in the test output
	l.info("plain")
	l.warn("careful")
	l.error("broken")
	var lines: PackedStringArray = l.lines()
	assert_eq(lines.size(), 3, "three lines")
	assert_true(lines[0].begins_with("I ") and lines[1].begins_with("W ") and lines[2].begins_with("E "), "each line starts with its level", lines)
	assert_true(lines[1].ends_with("careful") and lines[2].ends_with("broken"), "the message is kept verbatim")
	l.clear()
	assert_eq([l.size(), l.lines().size(), l.dump()], [0, 0, ""], "clear() empties the buffer")
	l.info("after clear")
	assert_eq(l.size(), 1, "logging continues after clear()")
	l.free()
