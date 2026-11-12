extends "res://tests/testing.gd"
## ArenaState (scenes/arena/arena_state.gd, ARENA_SPEC §7, §13.2): the bot switch with its 1 s cooldown, the hit and
## damage counters, reset (counters to 0, the switch keeps its position) and the stats shape for the board.


func test_toggle_cooldown() -> void:
	var s := ArenaState.new()
	assert_false(s.bot_on, "the bot starts off")
	var toggles := 0
	# a burst of 8 rifle shots in 1 s on the plate (0.125 s apart) toggles once
	for i in 8:
		if s.toggle(10.0 + i * 0.125):
			toggles += 1
	assert_eq(toggles, 1, "a burst of 8 shots in 1 s toggles once")
	assert_true(s.bot_on, "the burst switched the bot on")
	assert_false(s.toggle(10.99), "0.99 s after the toggle is refused")
	assert_true(s.toggle(11.0), "1.0 s after the toggle switches again")
	assert_false(s.bot_on, "the second toggle switched it off")
	assert_within(ArenaState.cooldown(), 1.0, 0.0001, "the cooldown is ArenaData.RANGE.switch_cooldown (1.0 s)")


## Plate hits (rifle, punch, saw sword on the switch) toggle once per burst: hits less than a second apart are one
## burst, which toggles at its first hit past the toggle cooldown and never again, so holding fire on the plate never
## turns the bot on and then off again (ARENA_SPEC §7 "a burst toggles once"; the plain 1 s cooldown counted from the
## last toggle let a burst of 1 s or more toggle twice).
func test_plate_burst_toggles_once() -> void:
	var s := ArenaState.new()
	var toggles := 0
	# 16 rifle hits 0.125 s apart (a 2 s burst at 8 shots/s)
	for i in 16:
		if s.plate_hit(20.0 + i * 0.125):
			toggles += 1
	assert_eq(toggles, 1, "a 2 s burst on the plate toggles once")
	assert_true(s.bot_on, "…and leaves the bot on")
	# a held saw sword on the post: a swing every 0.8 s for 4 s
	var s2 := ArenaState.new()
	var t2 := 0
	for i in 6:
		if s2.plate_hit(5.0 + i * 0.8):
			t2 += 1
	assert_eq(t2, 1, "a saw sword held on the post (a swing every 0.8 s for 4 s) toggles once")
	# a new burst after a quiet second toggles again
	var last := 20.0 + 15 * 0.125
	assert_false(s.plate_hit(last + 0.9), "a hit 0.9 s after the burst's last hit is still part of it")
	assert_true(s.bot_on, "…so the bot stays on")
	assert_true(s.plate_hit(last + 0.9 + 1.0), "a new burst after a quiet second (1.0 s) toggles again")
	assert_false(s.bot_on, "…and switches the bot off")
	# E (toggle) keeps the plain cooldown and still respects a plate toggle that just happened
	var s3 := ArenaState.new()
	assert_true(s3.plate_hit(1.0), "first plate hit toggles")
	assert_false(s3.toggle(1.5), "E 0.5 s after a plate toggle is refused (cooldown)")
	assert_true(s3.toggle(2.0), "E 1.0 s after it toggles")
	assert_false(s3.plate_hit(2.5), "a plate hit 0.5 s after E is refused (cooldown from the last toggle)")
	var t3 := 0
	for i in 12:
		if s3.plate_hit(2.625 + i * 0.125):
			t3 += 1
	assert_eq(t3, 1, "…but the same burst toggles once as soon as the cooldown is over")
	assert_true(s3.bot_on, "…so the bot is on again")


func test_counters_and_reset() -> void:
	var s := ArenaState.new()
	s.record_hit(12)
	s.record_hit(25)
	s.record_hit(0)
	assert_eq(s.hits, 2, "two hits that did damage are counted (a 0 is not)")
	assert_eq(s.damage, 37, "damage sums the applied amounts")
	s.toggle(0.0)
	s.reset()
	assert_eq(s.hits, 0, "reset zeroes the hits")
	assert_eq(s.damage, 0, "reset zeroes the damage")
	assert_true(s.bot_on, "reset keeps the switch's position")


func test_stats_shape() -> void:
	var s := ArenaState.new()
	s.record_hit(12)
	var st := s.stats({"hp": 288, "hp_max": 300, "state": &"chase", "alive": true})
	var keys := st.keys()
	keys.sort()
	assert_eq(keys, ["bot_on", "damage", "dead", "hits", "hp", "hp_max", "state"], "stats has the keys of ArenaWorld.stats_changed")
	assert_eq(st["hp"], 288, "hp passes through")
	assert_eq(st["hp_max"], 300, "hp_max passes through")
	assert_eq(st["state"], &"chase", "the beast state passes through")
	assert_false(bool(st["dead"]), "alive -> not dead")
	assert_true(bool(s.stats({"hp": 0, "hp_max": 300, "state": &"dead", "alive": false})["dead"]), "not alive -> dead")
