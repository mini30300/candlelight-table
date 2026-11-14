extends "res://tests/testing.gd"
## MissionObjectives (CAMPAIGN_SPEC §2.4, §5.5, §7 track C): the objective state machines and the stats behind the report.
## purge (kill all), defend (180 s timer, base HP 1000, base falls = fail), rescue (free / follow / save / die, at least one
## saved, the 600 s limit), destroy_camp (pylon HP x hp_pct, extract at the pickup), the secondaries in spec order (75 %
## kills, the 30 s beacon, the caged hostage, the outside pylon), revives and the last down, quit, nothing changes after
## the end, and the result dictionary with exactly the §5.5 keys.

const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")
const KEYS: PackedStringArray = ["v", "outcome", "time_s", "kills", "shots", "hits", "damage_taken", "downs", "secondary_done"]


func _keys(r: Dictionary) -> PackedStringArray:
	var k := PackedStringArray(r.keys())
	k.sort()
	return k


func _want(extra: Array) -> PackedStringArray:
	var k := PackedStringArray(KEYS)
	k.append_array(extra)
	k.sort()
	return k


func test_purge() -> void:
	var o := MissionObjectives.new(Specs.make("purge", {"secondary": ["purge"]}), 8)
	for i in 5:
		o.kill("rusher")
	assert_eq(o.secondary_done(), [false], "5 / 8 kills: the 75 % secondary is not done")
	o.kill("gunner")
	assert_eq(o.secondary_done(), [true], "6 / 8 = 75 %: done")
	assert_eq(o.outcome(), "", "not won yet")
	o.kill("brute")
	o.kill("boss")
	assert_eq(o.outcome(), "win", "every enemy killed: win")
	o.kill("rusher")
	assert_eq(int(o.kills["rusher"]), 5, "nothing counts after the end")
	var r := o.result()
	assert_eq(_keys(r), _want([]), "purge result: exactly the §5.5 keys")
	assert_eq(r["kills"], {"rusher": 5, "gunner": 1, "brute": 1, "boss": 1, "structure": 0}, "kills by role")


func test_defend() -> void:
	var o := MissionObjectives.new(Specs.make("defend", {"secondary": ["defend"]}), 30)
	assert_eq([o.base_hp, o.base_pct(), o.timer_s()], [1000, 100, 180.0], "base 1000 HP, 180 s on the clock")
	assert_eq(o.base_damage(250), 250, "the base takes damage")
	assert_eq(o.base_pct(), 75, "75 %")
	o.beacon_tick(5.0, true)
	assert_eq(o.beacon_s, 0.0, "the beacon counts only after E")
	assert_true(o.beacon_start() and o.beacon_on, "E switches the beacon on")
	assert_false(o.beacon_start(), "once")
	o.beacon_tick(20.0, true)
	o.beacon_tick(5.0, false)
	assert_eq(o.secondary_done(), [false], "20 s in the ring: not yet (outside does not count)")
	o.beacon_tick(12.0, true)
	assert_eq(o.secondary_done(), [true], "30 s held: done")
	for i in 179:
		o.tick(1.0)
	assert_eq(o.outcome(), "", "179 s: still holding")
	o.tick(1.0)
	assert_eq(o.outcome(), "win", "the timer ran out with the base standing: win")
	var r := o.result()
	assert_eq(_keys(r), _want(["base_hp_pct"]), "defend result has base_hp_pct")
	assert_eq([int(r["base_hp_pct"]), float(r["time_s"])], [75, 180.0], "75 % base left, 180 s")
	var f := MissionObjectives.new(Specs.make("defend"), 30)
	f.base_damage(5000)
	assert_eq([f.outcome(), f.base_hp], ["fail", 0], "the base falls: fail")


func test_rescue() -> void:
	var o := MissionObjectives.new(Specs.make("rescue", {"secondary": ["rescue"]}), 18)
	assert_eq(o.hostages.size(), 4, "three hostages + one caged (secondary)")
	assert_false(o.save_hostage(0), "a captive cannot be saved before it is freed")
	assert_true(o.free_hostage(0), "free")
	assert_false(o.free_hostage(0), "free once")
	assert_eq(o.hostage_state(0), MissionObjectives.FOLLOW, "following")
	assert_true(o.save_hostage(0), "saved at the pickup")
	assert_true(o.free_hostage(1) and o.hostage_died(1), "hostage 1 freed then killed")
	assert_eq(o.outcome(), "", "one captive left: not over")
	assert_true(o.hostage_died(2), "a captive can die too")
	assert_eq(o.outcome(), "win", "every living primary hostage saved (one): win")
	var st := o.state()
	assert_eq([st["hostages"]["saved"], st["hostages"]["alive"], st["hostages"]["total"]], [1, 2, 4], "hostage counts")
	var r := o.result()
	assert_eq(_keys(r), _want(["hostages_saved", "hostages_total"]), "rescue result has the hostage keys")
	assert_eq([int(r["hostages_saved"]), int(r["hostages_total"]), r["secondary_done"]], [1, 4, [false]], "1 of 4 saved, the cage not done")
	var all_dead := MissionObjectives.new(Specs.make("rescue"), 18)
	for i in 3:
		all_dead.hostage_died(i)
	assert_eq(all_dead.outcome(), "fail", "every hostage dead: fail")
	var late := MissionObjectives.new(Specs.make("rescue"), 18)
	late.tick(599.0)
	assert_eq(late.outcome(), "", "599 s: still time")
	late.tick(1.0)
	assert_eq(late.outcome(), "fail", "600 s: the rescue failed")
	var sec := MissionObjectives.new(Specs.make("purge", {"secondary": ["rescue"]}), 5)
	sec.free_hostage(0)
	sec.save_hostage(0)
	assert_eq(sec.secondary_done(), [true], "a caged hostage brought home completes the rescue secondary")


func test_destroy_camp() -> void:
	var o := MissionObjectives.new(Specs.make("destroy_camp", {"secondary": ["destroy_camp"], "difficulty": "hard"}), 26)
	assert_eq(o.pylons.size(), 4, "three camp pylons + one outside")
	assert_eq(int(o.pylons[0]["max"]), 400 * 130 / 100, "pylon HP 400 x hard 130 %")
	var r1 := o.damage_pylon(0, 100)
	assert_eq([int(r1["applied"]), bool(r1["killed"])], [100, false], "a pylon takes damage")
	o.damage_pylon(0, 9999)
	o.damage_pylon(1, 9999)
	assert_false(o.extract_ready(), "two down: not ready to extract")
	o.set_at_pickup(true)
	o.damage_pylon(2, 9999)
	assert_true(o.extract_ready(), "three down: extract")
	assert_eq(o.outcome(), "win", "standing at the pickup when the last falls: win")
	assert_eq(int(o.kills["structure"]), 3, "pylons count as structure kills")
	var o2 := MissionObjectives.new(Specs.make("destroy_camp", {"secondary": ["destroy_camp"]}), 26)
	for i in 3:
		o2.damage_pylon(i, 9999)
	assert_eq(o2.outcome(), "", "away from the pickup: not yet")
	o2.damage_pylon(3, 9999)
	assert_eq(o2.secondary_done(), [true], "the outside pylon: secondary done")
	o2.set_at_pickup(true)
	assert_eq(o2.outcome(), "win", "walking into the pickup: win")
	assert_eq(o2.damage_pylon(0, 5), {"applied": 0, "hp": 0, "killed": false}, "a broken pylon takes nothing")


func test_revives_and_quit() -> void:
	var o := MissionObjectives.new(Specs.make("purge"), 10)
	assert_eq(o.player_down(), "revive", "normal: first down revives")
	assert_eq(o.player_down(), "revive", "second down revives")
	assert_eq(o.revives_left, 0, "no revives left")
	assert_eq(o.player_down(), "fail", "the third down fails")
	assert_eq([o.outcome(), o.downs], ["fail", 3], "fail with 3 downs")
	var h := MissionObjectives.new(Specs.make("purge", {"difficulty": "hard"}), 10)
	h.player_down()
	assert_eq(h.player_down(), "fail", "hard: one revive")
	var c := MissionObjectives.new(Specs.make("purge", {"difficulty": "catastrophe"}), 10)
	assert_eq(c.player_down(), "fail", "catastrophe: the first down fails")
	var q := MissionObjectives.new(Specs.make("defend"), 10)
	q.tick(12.5)
	q.shot()
	q.shot()
	q.hit()
	q.hit()
	q.hit()
	q.hurt(17)
	q.quit()
	q.tick(5.0)
	var r := q.result()
	assert_eq([r["outcome"], float(r["time_s"]), int(r["shots"]), int(r["hits"]), int(r["damage_taken"])], ["quit", 12.5, 2, 2, 17],
		"quit: outcome quit, the clock stopped, hits never above shots")
	var s := q.state()
	assert_true(s.has_all(["primary", "secondary", "timer_s", "base_pct", "hostages", "revives"]), "state() has the HUD keys")
