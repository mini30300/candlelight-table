extends "res://tests/testing.gd"
## HiveAI (scenes/arena/hive_ai.gd, ARENA_SPEC §8.3, §13.2): the hive beast's state machine with fake time: the bot
## switch, chase, the telegraphed claw (wind-up 0.6 s, the blow at 0.72 s, recover 0.7 s), flinches, death, the walk
## home, the grace after the player is downed and the seeded variants.

const DT := 1.0 / 120.0
const HOME := Vector2(0.0, -29.0)


func _ai(bot_on: bool, seed_v: int = 4404) -> HiveAI:
	var ai := HiveAI.new(seed_v)
	ai.set_home(HOME, 0.0)
	ai.reset(bot_on)
	return ai


## Runs the AI for `seconds` (or until `until` returns true): moves `me` by the AI's answer, records events with times.
## target may be a Callable(t) -> Dictionary so it can move during the run.
func _run(ai: HiveAI, me: Dictionary, target: Variant, seconds: float, until: Callable = Callable()) -> Dictionary:
	var log := []
	var moved := 0.0
	var max_speed := 0.0
	var t := 0.0
	var states := {}
	while t < seconds - 0.0000001:
		var tg: Dictionary = target.call(t) if target is Callable else target
		var r := ai.tick(DT, me, tg)
		var mv: Vector2 = r["move"]
		me["pos"] = (me["pos"] as Vector2) + mv * DT
		me["yaw"] = float(r["face"])
		moved += mv.length() * DT
		max_speed = maxf(max_speed, mv.length())
		t += DT
		states[ai.state] = true
		for e in r["events"]:
			log.append({"e": e, "t": t, "hit": ai.strike_hit, "variant": ai.variant})
		if until.is_valid() and until.call():
			break
	return {"log": log, "moved": moved, "max_speed": max_speed, "t": t, "states": states}


func _events(log: Array, name: StringName) -> Array:
	return log.filter(func(x: Dictionary) -> bool: return x["e"] == name)


func _target(pos: Vector2, alive := true, in_room := true) -> Dictionary:
	return {"pos": pos, "alive": alive, "in_room": in_room, "r": 0.35}


func test_off_stays_dummy() -> void:
	var ai := _ai(false)
	var me := {"pos": HOME, "yaw": 0.0, "hp": 300, "alive": true}
	var r := _run(ai, me, _target(Vector2(0, -27.5)), 10.0)
	assert_eq(r["states"].keys(), [HiveAI.DUMMY], "bot off: the beast stays a dummy for 10 s, the player 1.5 m away")
	assert_eq(r["moved"], 0.0, "bot off: it never moves")
	assert_eq(r["log"], [], "bot off: no wind-up, no strike")
	assert_eq(ai.telegraph(), 0.0, "bot off: no telegraph")


func test_chase_then_claw() -> void:
	var ai := _ai(false)
	var me := {"pos": HOME, "yaw": 0.0, "hp": 300, "alive": true}
	var tgt := _target(Vector2(1.0, -22.0))
	ai.set_bot(true)
	ai.tick(DT, me, tgt)
	assert_eq(ai.state, HiveAI.CHASE, "bot on + the target in the room -> chase")
	var r := _run(ai, me, tgt, 5.0, func() -> bool: return ai.state == HiveAI.WINDUP)
	assert_eq(ai.state, HiveAI.WINDUP, "it reaches the target and winds up (%.2f s)" % r["t"])
	var d := (me["pos"] as Vector2).distance_to(tgt["pos"])
	assert_true(d <= float(ArenaData.BEAST["attack_range"]) + 0.01, "the wind-up starts within attack_range (%.2f m)" % d)
	assert_within(r["max_speed"], float(ArenaData.BEAST["run"]), 0.01, "it chased at run speed 3.7 m/s")
	var ang := absf(angle_difference(float(me["yaw"]), atan2(1.0 - me["pos"].x, -22.0 - me["pos"].y)))
	assert_true(ang <= deg_to_rad(35.0) + 0.001, "the target is within 35° of its facing at the wind-up")


func test_strike_timing_and_reach() -> void:
	var cases := [
		["stays at 2.0 m", Vector2(0, 2.0), Vector2(0, 2.0), true],
		["steps back to 2.7 m during the wind-up", Vector2(0, 2.0), Vector2(0, 2.7), false],
		["steps behind it after the wind-up", Vector2(0, 2.0), Vector2(0, -1.5), false],
		["stands 60° to the side at 2.4 m", Vector2(0, 2.0), Vector2(sin(deg_to_rad(60)), cos(deg_to_rad(60))) * 2.4, true],
		["stands 80° to the side at 2.0 m", Vector2(0, 2.0), Vector2(sin(deg_to_rad(80)), cos(deg_to_rad(80))) * 2.0, false],
	]
	for c in cases:
		var ai := _ai(true)
		var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
		var t0 := [-1.0]
		# the target stands at c[1] until the wind-up is 0.65 s old (the beast no longer turns), then at c[2]
		var tgt := func(t: float) -> Dictionary:
			if t0[0] < 0.0 and ai.state == HiveAI.WINDUP:
				t0[0] = t
			var late: bool = t0[0] >= 0.0 and t - t0[0] >= 0.65
			return _target(c[2] if late else c[1])
		var r := _run(ai, me, tgt, 3.0)
		var wind := _events(r["log"], &"windup")
		var strikes := _events(r["log"], &"strike")
		var rec := _events(r["log"], &"recovered")
		assert_true(wind.size() >= 1 and strikes.size() >= 1 and rec.size() >= 1, "%s: windup, strike and recovered happen" % c[0])
		if wind.is_empty() or strikes.is_empty() or rec.is_empty():
			continue
		var tw: float = wind[0]["t"]
		var ts: float = strikes[0]["t"]
		assert_within(ts - tw, 0.72, DT + 0.001, "%s: the blow lands 0.72 s after the wind-up began" % c[0])
		var before_rec := strikes.filter(func(x: Dictionary) -> bool: return x["t"] <= rec[0]["t"])
		assert_eq(before_rec.size(), 1, "%s: exactly one strike per wind-up" % c[0])
		assert_eq(bool(strikes[0]["hit"]), c[3], "%s: the claw %s" % [c[0], "hits" if c[3] else "misses"])
		assert_within(rec[0]["t"] - ts, float(ArenaData.BEAST["recover"]), DT + 0.001, "%s: recover lasts 0.7 s" % c[0])


func test_recover_back_to_chase() -> void:
	var ai := _ai(true)
	var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	var tgt := _target(Vector2(0, 2.0))
	_run(ai, me, tgt, 3.0, func() -> bool: return ai.state == HiveAI.RECOVER)
	assert_eq(ai.state, HiveAI.RECOVER, "after the blow it recovers")
	assert_eq(ai.telegraph(), 0.0, "no telegraph while recovering")
	_run(ai, me, tgt, 1.0, func() -> bool: return ai.state != HiveAI.RECOVER)
	assert_eq(ai.state, HiveAI.CHASE, "after recover, chase again (bot on, target in the room)")


func test_telegraph_rises() -> void:
	var ai := _ai(true)
	var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	var tgt := _target(Vector2(0, 2.0))
	_run(ai, me, tgt, 3.0, func() -> bool: return ai.state == HiveAI.WINDUP)
	var a0 := ai.telegraph()
	_run(ai, me, tgt, 0.3)
	var a1 := ai.telegraph()
	assert_true(a0 < 0.05 and absf(a1 - 0.5) < 0.03, "the telegraph rises 0 -> 0.5 over the first 0.3 s (%.2f, %.2f)" % [a0, a1])
	_run(ai, me, tgt, 0.35)
	assert_eq(ai.state, HiveAI.STRIKE, "after 0.65 s it is in strike")
	assert_eq(ai.telegraph(), 1.0, "the telegraph stays at 1 in strike")


func test_stagger_cancels_strike() -> void:
	var ai := _ai(true)
	var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	var tgt := _target(Vector2(0, 2.0))
	_run(ai, me, tgt, 3.0, func() -> bool: return ai.state == HiveAI.WINDUP)
	_run(ai, me, tgt, 0.3)
	var react := ai.on_damage(25, true, false)
	assert_eq(react, &"flinch", "a punch during the wind-up flinches it")
	assert_eq(ai.state, HiveAI.HIT, "-> hit")
	var r := _run(ai, me, tgt, 0.9)
	assert_eq(_events(r["log"], &"strike"), [], "the cancelled strike never lands (no blow within 0.9 s)")
	# a sword swing staggers longer
	var ai2 := _ai(true)
	var me2 := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai2, me2, tgt, 3.0, func() -> bool: return ai2.state == HiveAI.WINDUP)
	assert_eq(ai2.on_damage(45, true, false), &"flinch_heavy", "a saw sword swing staggers it heavily")
	var r2 := _run(ai2, me2, tgt, 1.0, func() -> bool: return ai2.state != HiveAI.HIT)
	assert_within(r2["t"], float(ArenaData.BEAST["flinch_heavy"]), DT + 0.001, "the heavy stagger lasts 0.8 s")
	var ai3 := _ai(true)
	var me3 := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai3, me3, tgt, 3.0, func() -> bool: return ai3.state == HiveAI.CHASE)
	ai3.on_damage(25, true, false)
	var r3 := _run(ai3, me3, tgt, 1.0, func() -> bool: return ai3.state != HiveAI.HIT)
	assert_within(r3["t"], float(ArenaData.BEAST["flinch"]), DT + 0.001, "a flinch lasts 0.35 s")


## Poise (ARENA_SPEC §17): with the bot on, during a flinch and for BEAST.poise (1.2 s) after it ends further hits do
## not flinch it again, so punch or saw-sword spam can no longer keep it flinching for ever: it still lands claws. Hits
## keep doing damage (ArenaCombat.apply in HiveBeast), only the flinch is skipped. A dummy (bot off) still flinches on
## every punch.
func test_poise_lets_a_claw_through_melee_spam() -> void:
	for spam in [["punch", 25, true, 0.67], ["sword", 45, true, 0.8]]:
		var ai := _ai(true)
		var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
		var tgt := _target(Vector2(0, 1.9))
		_run(ai, me, tgt, 3.0, func() -> bool: return ai.state == HiveAI.WINDUP)
		var strikes := 0
		var landed := 0
		var flinches := 0
		var t := 0.0
		var next := 0.0
		while t < 6.0:
			if t >= next:
				next += float(spam[3])
				if ai.on_damage(int(spam[1]), bool(spam[2]), false) != &"none":
					flinches += 1
			var r := ai.tick(DT, me, tgt)
			me["yaw"] = float(r["face"])
			for e in r["events"]:
				if e == &"strike":
					strikes += 1
					if ai.strike_hit:
						landed += 1
			t += DT
		assert_true(landed >= 2, "%s spam every %.2f s for 6 s: the beast still lands claws (%d strikes, %d landed)" % [spam[0], spam[3], strikes, landed])
		assert_true(flinches >= 2, "%s spam still flinches it now and then (%d flinches)" % [spam[0], flinches])
	# the poise window itself
	var ai2 := _ai(true)
	var me2 := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	var far := _target(Vector2(0, 8.0))
	_run(ai2, me2, far, 0.2)
	assert_eq(ai2.on_damage(25, true, false), &"flinch", "a punch flinches it")
	assert_eq(ai2.on_damage(45, true, false), &"none", "a second hit during the flinch does not flinch it again")
	_run(ai2, me2, far, 0.4)
	assert_true(ai2.state != HiveAI.HIT and absf(ai2.poise_left() - float(ArenaData.BEAST["poise"]) + 0.05) <= 0.02,
		"after the 0.35 s flinch it has %.2f s of poise left (1.2 - 0.05)" % ai2.poise_left())
	assert_eq(ai2.on_damage(25, true, false), &"none", "a punch inside the poise window does not flinch it")
	assert_eq(ai2.on_damage(45, true, false), &"none", "nor does a saw sword swing")
	assert_eq(ai2.on_damage(300, true, true), HiveAI.DEAD, "a killing hit still kills it inside the poise window")
	var ai3 := _ai(true)
	var me3 := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai3, me3, far, 0.2)
	ai3.on_damage(25, true, false)
	_run(ai3, me3, far, 0.35 + 1.25)
	assert_eq(ai3.on_damage(25, true, false), &"flinch", "after the poise window a punch flinches it again")
	# a dummy flinches on every punch
	var ai4 := _ai(false)
	var me4 := {"pos": HOME, "yaw": 0.0, "hp": 300, "alive": true}
	assert_eq(ai4.on_damage(25, true, false), &"flinch", "a dummy flinches on a punch")
	_run(ai4, me4, far, 0.4)
	assert_eq(ai4.on_damage(25, true, false), &"flinch", "…and on the next punch right after (no poise with the bot off)")
	ai4.reset(true)
	assert_eq(ai4.poise_left(), 0.0, "reset clears the poise")


func test_bullets_never_flinch() -> void:
	var ai := _ai(true)
	var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	var tgt := _target(Vector2(0, 2.0))
	_run(ai, me, tgt, 3.0, func() -> bool: return ai.state == HiveAI.WINDUP)
	for i in 4:
		assert_eq(ai.on_damage(int(ArenaData.WEAPONS["gun"]["damage"]), bool(ArenaData.WEAPONS["gun"]["stagger"]), false), &"none",
			"rifle hit %d during the wind-up: no reaction" % (i + 1))
	assert_eq(ai.state, HiveAI.WINDUP, "still winding up")
	var r := _run(ai, me, tgt, 0.8)
	assert_eq(_events(r["log"], &"strike").size(), 1, "the strike still lands")
	var ai2 := _ai(false)
	assert_eq(ai2.on_damage(12, false, false), &"none", "a bullet does not flinch a dummy either")
	assert_eq(ai2.state, HiveAI.DUMMY, "it stays a dummy")
	assert_eq(ai2.on_damage(25, true, false), &"flinch", "a punch flinches a dummy")
	var me2 := {"pos": HOME, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai2, me2, tgt, 0.5)
	assert_eq(ai2.state, HiveAI.DUMMY, "after the flinch a dummy is a dummy again")


func test_death_from_every_state() -> void:
	var near := _target(Vector2(0, 2.0))
	var far := _target(Vector2(0, 8.0))
	var setups := {
		HiveAI.DUMMY: func(ai: HiveAI, me: Dictionary) -> void: ai.reset(false),
		HiveAI.IDLE: func(ai: HiveAI, me: Dictionary) -> void:
			me["pos"] = Vector2(3, -20)
			_run(ai, me, _target(Vector2(0, -5), true, false), 0.2),
		HiveAI.CHASE: func(ai: HiveAI, me: Dictionary) -> void: _run(ai, me, far, 0.2),
		HiveAI.WINDUP: func(ai: HiveAI, me: Dictionary) -> void: _run(ai, me, near, 3.0, func() -> bool: return ai.state == HiveAI.WINDUP),
		HiveAI.STRIKE: func(ai: HiveAI, me: Dictionary) -> void: _run(ai, me, near, 3.0, func() -> bool: return ai.state == HiveAI.STRIKE),
		HiveAI.RECOVER: func(ai: HiveAI, me: Dictionary) -> void: _run(ai, me, near, 3.0, func() -> bool: return ai.state == HiveAI.RECOVER),
		HiveAI.HIT: func(ai: HiveAI, me: Dictionary) -> void:
			_run(ai, me, far, 0.2)
			ai.on_damage(25, true, false),
	}
	for st in setups:
		var ai := _ai(true)
		var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
		(setups[st] as Callable).call(ai, me)
		assert_eq(ai.state, st, "reached %s" % st)
		assert_eq(ai.on_damage(12, false, true), HiveAI.DEAD, "HP 0 in %s -> dead" % st)
		assert_eq(ai.state, HiveAI.DEAD, "%s -> dead" % st)
	# dead ignores everything but reset
	var ai := _ai(true)
	var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 0, "alive": false}
	ai.on_damage(300, true, true)
	var r := _run(ai, me, near, 0.1)
	assert_eq(_events(r["log"], &"died").size(), 1, "the death is reported once")
	ai.set_bot(false)
	assert_eq(ai.state, HiveAI.DEAD, "the switch does not wake the dead (off)")
	assert_false(ai.bot, "but the flag changed")
	ai.set_bot(true)
	assert_eq(ai.state, HiveAI.DEAD, "nor on")
	assert_eq(ai.on_damage(45, true, false), &"none", "a dead beast does not react")
	r = _run(ai, me, near, 3.0)
	assert_eq(r["moved"], 0.0, "a dead beast never moves")
	assert_eq(r["log"], [], "nor attacks")
	ai.reset(true)
	assert_eq(ai.state, HiveAI.IDLE, "reset with the bot on -> idle")
	ai.on_damage(300, true, true)
	ai.reset(false)
	assert_eq(ai.state, HiveAI.DUMMY, "reset with the bot off -> dummy")


func test_off_during_chase() -> void:
	var ai := _ai(true)
	var me := {"pos": HOME, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai, me, _target(Vector2(0, -15)), 0.5)
	assert_eq(ai.state, HiveAI.CHASE, "chasing")
	ai.set_bot(false)
	assert_eq(ai.state, HiveAI.DUMMY, "off during chase -> dummy at once")
	var p: Vector2 = me["pos"]
	var r := _run(ai, me, _target(Vector2(0, -15)), 2.0)
	assert_eq(r["moved"], 0.0, "and it stops dead")
	assert_eq((me["pos"] as Vector2), p, "where it was")
	var ai2 := _ai(true)
	var me2 := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai2, me2, _target(Vector2(0, 2.0)), 3.0, func() -> bool: return ai2.state == HiveAI.WINDUP)
	ai2.set_bot(false)
	assert_eq(ai2.state, HiveAI.DUMMY, "off during the wind-up -> dummy")
	var r2 := _run(ai2, me2, _target(Vector2(0, 2.0)), 1.0)
	assert_eq(_events(r2["log"], &"strike"), [], "and the strike never lands")


func test_walks_home_when_target_leaves() -> void:
	var ai := _ai(true)
	var me := {"pos": Vector2(3.0, -20.0), "yaw": 1.0, "hp": 300, "alive": true}
	_run(ai, me, _target(Vector2(0, -15)), 0.3)
	assert_eq(ai.state, HiveAI.CHASE, "chasing the target in the room")
	var gone := _target(Vector2(0, -5), true, false)
	var r0 := _run(ai, me, gone, 1.0, func() -> bool: return ai.state != HiveAI.CHASE)
	assert_eq(ai.state, HiveAI.IDLE, "the target in the corridor -> idle")
	assert_true(r0["t"] <= 0.1 + DT, "at the next think (10 Hz): %.3f s" % r0["t"])
	var r := _run(ai, me, gone, 12.0)
	assert_eq(r["states"].keys(), [HiveAI.IDLE], "idle all the way home")
	assert_true(r["max_speed"] <= float(ArenaData.BEAST["home_speed"]) + 0.001, "it walks home at home_speed (max %.2f m/s)" % r["max_speed"])
	var d := (me["pos"] as Vector2).distance_to(HOME)
	assert_true(d <= HiveAI.HOME_R + 0.05, "it is back on the pad (%.2f m off)" % d)
	assert_within(wrapf(float(me["yaw"]), -PI, PI), 0.0, 0.01, "facing +z, the entry")


func test_grace_after_downed() -> void:
	var ai := _ai(true)
	var me := {"pos": HOME, "yaw": 0.0, "hp": 300, "alive": true}
	_run(ai, me, _target(Vector2(0, -15)), 0.3)
	assert_eq(ai.state, HiveAI.CHASE, "chasing")
	# downed for 2 s, then up again in the room
	var tgt := func(t: float) -> Dictionary: return _target(Vector2(0, -12.5), t >= 2.0, true)
	var r0 := _run(ai, me, tgt, 1.0, func() -> bool: return ai.state != HiveAI.CHASE)
	assert_eq(ai.state, HiveAI.IDLE, "the player downed -> idle (after %.3f s)" % r0["t"])
	var tgt2 := func(t: float) -> Dictionary: return tgt.call(t + r0["t"])
	var r := _run(ai, me, tgt2, 5.0, func() -> bool: return ai.state == HiveAI.CHASE)
	var t: float = r0["t"] + r["t"]
	assert_true(t >= float(ArenaData.BEAST["grace"]) - 0.001 and t <= float(ArenaData.BEAST["grace"]) + 0.12,
		"it chases again only after the 3 s grace, though the player was up at 2 s (at %.2f s)" % t)


func test_seeded_variants() -> void:
	var seqs := []
	for k in 3:
		var ai := _ai(true, 4404)
		if k == 2:
			ai.reset(true)    # a reset re-seeds
		var me := {"pos": Vector2.ZERO, "yaw": 0.0, "hp": 300, "alive": true}
		var r := _run(ai, me, _target(Vector2(0, 2.0)), 10.0)
		var seq := _events(r["log"], &"windup").map(func(x: Dictionary) -> int: return int(x["variant"]))
		ai.on_damage(12, false, true)
		seq.append(ai.variant)
		seqs.append(seq)
	assert_true((seqs[0] as Array).size() >= 6, "about 6 claws in 10 s (%d)" % ((seqs[0] as Array).size() - 1))
	assert_eq(seqs[1], seqs[0], "the same seed gives the same attack and death variants")
	assert_eq(seqs[2], seqs[0], "a reset re-seeds: the same variants again")
	var all_ok := true
	for v in seqs[0]:
		all_ok = all_ok and int(v) >= 0 and int(v) < HiveAI.VARIANTS
	assert_true(all_ok, "variants are 0..2: %s" % str(seqs[0]))
	var mixed := {}
	for v in seqs[0]:
		mixed[v] = true
	assert_true(mixed.size() >= 2, "the variants change between claws: %s" % str(seqs[0]))
