extends "res://tests/testing.gd"
## The Clock autoload: the one tick source for view timers; frozen + step(ms) make it deterministic in tests.

const ClockScript := preload("res://app/clock.gd")


func test_autoload_is_live() -> void:
	assert_true(Clock != null and Clock.is_inside_tree(), "the Clock autoload is in the tree under the runner")
	assert_false(Clock.frozen, "the live clock runs by default")
	assert_true(Clock.now_ms() >= 0, "now_ms() counts from app start: " + str(Clock.now_ms()))


func test_freeze_and_step() -> void:
	var c: Node = ClockScript.new()
	c.frozen = true
	var t0: int = c.now_ms()
	assert_eq(c.now_ms(), t0, "a frozen clock does not move")
	c.step(1500)
	assert_eq(c.now_ms(), t0 + 1500, "step(1500) advances a frozen clock by exactly 1500 ms")
	c.step(0)
	assert_eq(c.now_ms(), t0 + 1500, "step(0) is a no-op")
	c.step(250)
	c.step(250)
	assert_eq(c.now_ms(), t0 + 2000, "steps add up")
	c.frozen = true
	assert_eq(c.now_ms(), t0 + 2000, "freezing twice changes nothing")
	c.free()


func test_unfreeze_continues_from_the_held_time() -> void:
	var c: Node = ClockScript.new()
	c.frozen = true
	c.step(5000)
	var held: int = c.now_ms()
	c.frozen = false
	var running: int = c.now_ms()
	assert_true(running >= held and running < held + 1000, "unfreezing continues from the held value: %d → %d" % [held, running])
	c.step(3000)
	assert_true(c.now_ms() >= running + 3000, "step() also advances a running clock")
	c.frozen = true
	var a: int = c.now_ms()
	var b: int = c.now_ms()
	assert_eq(a, b, "frozen again: two reads agree")
	c.free()
