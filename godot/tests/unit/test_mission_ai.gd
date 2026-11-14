extends "res://tests/testing.gd"
## MissionAI (CAMPAIGN_SPEC §5.4, §7 track C) with fake time like test_hive_ai: a rusher wakes, chases, winds up for
## stats.windup (scaled by windup_pct: catastrophe strikes 30 % sooner) and strikes; a brute's telegraph fills 0 -> 1; a
## gunner keeps its range (backs off when close, closes in when far or without line of sight), aims then fires and cools
## down; flinches (light roles on some gun hits and every melee hit, heavy roles on melee only, poise); seeded target
## choice between the player, the base and hostages; guards wait for the player; flankers swing wide; strike geometry;
## the same seed and inputs give the same tick results.

const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")
const DT := 0.05


func _stats(role: String, diff := "normal", extra := {}) -> Dictionary:
	var s := MissionRoster.stats(Specs.make("purge", {"difficulty": diff, "modifier": "ambush"}), role)
	s.merge(extra, true)
	return s


## Run until an event appears or time runs out: [time, event, last tick, pos]. The AI walks by its own move output.
func _run_until(ai: MissionAI, pos: Vector2, targets: Array, want: StringName, limit := 10.0) -> Array:
	var t := 0.0
	var r := {}
	while t < limit:
		r = ai.tick(DT, {"pos": pos, "yaw": 0.0, "alive": true, "los": true}, targets)
		pos += (r["move"] as Vector2) * DT
		t += DT
		if r["event"] == want:
			return [t, r["event"], r, pos]
	return [t, &"", r, pos]


func _player(p: Vector2) -> Dictionary:
	return {"pos": p, "alive": true, "r": 0.35, "kind": "player", "w": 6.0}


func test_rusher_chase_and_strike() -> void:
	var ai := MissionAI.new(11, "rusher", _stats("rusher"))
	var tp := Vector2(0.0, 8.0)
	var a := _run_until(ai, Vector2.ZERO, [_player(tp)], &"windup")
	assert_eq(a[1], &"windup", "the rusher winds up once in reach")
	var pos: Vector2 = a[3]
	assert_true(pos.distance_to(tp) <= float(_stats("rusher")["reach"]) + 0.4, "it ran to the player (%.2f m away)" % pos.distance_to(tp))
	assert_true(float(a[0]) > 1.5, "it took time to run 8 m (%.2f s)" % float(a[0]))
	var b := _run_until(ai, pos, [_player(tp)], &"strike")
	assert_within(float(b[0]), float(_stats("rusher")["windup"]), DT * 1.5, "normal windup %.2f s before the strike" % float(_stats("rusher")["windup"]))
	assert_eq(ai.state, MissionAI.RECOVER, "recovers after the strike")
	assert_eq(ai.strikes, 1, "one strike counted")
	var c := MissionAI.new(11, "rusher", _stats("rusher", "catastrophe"))
	var a2 := _run_until(c, Vector2.ZERO, [_player(tp)], &"windup")
	var b2 := _run_until(c, a2[3], [_player(tp)], &"strike")
	assert_within(float(b2[0]), float(_stats("rusher")["windup"]) * 0.7, DT * 1.5, "catastrophe windup is 70 %")
	assert_true(float(a2[0]) < float(a[0]), "catastrophe rushers arrive sooner (speed 130 %)")


func test_brute_telegraph() -> void:
	var ai := MissionAI.new(5, "brute", _stats("brute"))
	var a := _run_until(ai, Vector2.ZERO, [_player(Vector2(0.0, 6.0))], &"windup")
	assert_eq(ai.state, MissionAI.WINDUP, "the brute winds up")
	var t0 := ai.telegraph()
	var r: Dictionary = {}
	var mid := -1.0
	for i in 40:
		r = ai.tick(DT, {"pos": a[3], "yaw": float(a[2]["face"]), "alive": true}, [_player(Vector2(0.0, 6.0))])
		if mid < 0.0 and ai.state == MissionAI.WINDUP and i == 5:
			mid = ai.telegraph()
		if r["event"] == &"strike":
			break
	assert_true(t0 < 0.15 and mid > t0 and mid < 1.0, "the telegraph fills while winding up (%.2f -> %.2f)" % [t0, mid])
	assert_eq(r["event"], &"strike", "then strikes")
	assert_eq(ai.telegraph(), 0.0, "no telegraph after the strike")


func test_gunner_range_and_fire() -> void:
	var st := _stats("gunner")
	var ai := MissionAI.new(3, "gunner", st)
	var a := _run_until(ai, Vector2(0.0, -10.0), [_player(Vector2.ZERO)], &"aim")
	assert_eq(a[1], &"aim", "a gunner at 10 m with line of sight aims")
	var b := _run_until(ai, a[3], [_player(Vector2.ZERO)], &"fire")
	assert_within(float(b[0]), float(st["windup"]), DT * 1.5, "fires after its windup")
	assert_eq(ai.state, MissionAI.COOL, "cools down after a shot")
	var c := _run_until(ai, b[3], [_player(Vector2.ZERO)], &"fire")
	assert_true(float(c[0]) >= 1.0 + float(st["windup"]) - DT, "the next shot waits for the cooldown (%.2f s)" % float(c[0]))
	# close: back off
	var near := MissionAI.new(4, "gunner", st)
	var p := Vector2(0.0, -2.5)
	var away := 0.0
	for i in 30:
		var r := near.tick(DT, {"pos": p, "yaw": 0.0, "alive": true, "los": true}, [_player(Vector2.ZERO)])
		away += (r["move"] as Vector2).dot(p.normalized()) * DT
		p += (r["move"] as Vector2) * DT
	assert_true(away > 0.3, "a gunner backs away from a close player (%.2f m)" % away)
	# far or no line of sight: close in, no aim
	var far := MissionAI.new(6, "gunner", st)
	p = Vector2(0.0, -30.0)
	var aimed := false
	for i in 40:
		var r := far.tick(DT, {"pos": p, "yaw": 0.0, "alive": true, "los": false}, [_player(Vector2.ZERO)])
		aimed = aimed or r["event"] == &"aim"
		p += (r["move"] as Vector2) * DT
	assert_true(not aimed and p.y > -29.0, "far / no line of sight: it walks closer and holds fire (z %.1f)" % p.y)
	# a cover post in range of the target is used
	var cov := MissionAI.new(8, "gunner", st)
	p = Vector2(0.0, -20.0)
	for i in 60:
		var r := cov.tick(DT, {"pos": p, "yaw": 0.0, "alive": true, "los": false, "post": Vector2(4.0, -9.0)}, [_player(Vector2.ZERO)])
		p += (r["move"] as Vector2) * DT
	assert_true(p.distance_to(Vector2(4.0, -9.0)) < p.distance_to(Vector2(0.0, -9.0)) + 0.01 and p.x > 0.5, "it heads for its cover post (%s)" % str(p))


func test_flinch_and_poise() -> void:
	var ai := MissionAI.new(21, "rusher", _stats("rusher"))
	ai.state = MissionAI.WINDUP
	assert_eq(ai.on_damage(25, true, false), &"flinch", "a melee hit always flinches a rusher (even mid-windup)")
	assert_eq(ai.state, MissionAI.HIT, "state hit")
	assert_eq(ai.on_damage(25, true, false), &"none", "poise: no flinch again at once")
	var n := 0
	for s in 40:
		var x := MissionAI.new(100 + s, "rusher", _stats("rusher"))
		if x.on_damage(12, false, false) == &"flinch":
			n += 1
	assert_true(n > 8 and n < 32, "rifle hits flinch light enemies about half the time (%d / 40)" % n)
	var br := MissionAI.new(9, "brute", _stats("brute"))
	assert_eq(br.on_damage(12, false, false), &"none", "rifle hits never flinch a brute")
	assert_eq(br.on_damage(45, true, false), &"flinch", "a saw-sword hit flinches a brute")
	var bo := MissionAI.new(9, "boss", _stats("boss"))
	assert_eq(bo.on_damage(900, false, true), &"die", "killed -> die")
	assert_eq(bo.state, MissionAI.DEAD, "dead")
	var r := bo.tick(DT, {"pos": Vector2.ZERO, "alive": true}, [_player(Vector2(0, 1))])
	assert_eq([r["move"], r["event"]], [Vector2.ZERO, &""], "the dead do nothing")


func test_target_choice() -> void:
	var base := {"pos": Vector2(0.0, 5.0), "alive": true, "r": 2.2, "kind": "base", "w": 4.0}
	var hostage := {"pos": Vector2(3.0, 3.0), "alive": true, "r": 0.35, "kind": "hostage", "w": 2.5}
	var counts := [0, 0, 0]
	for s in 300:
		var ai := MissionAI.new(1000 + s, "rusher", _stats("rusher"))
		ai.tick(MissionAI.THINK, {"pos": Vector2(0.0, -10.0), "alive": true}, [_player(Vector2.ZERO), base, hostage])
		counts[ai.target] += 1
	var f := [float(counts[0]) / 300.0, float(counts[1]) / 300.0, float(counts[2]) / 300.0]
	assert_true(absf(f[0] - 6.0 / 12.5) < 0.1 and absf(f[1] - 4.0 / 12.5) < 0.1 and absf(f[2] - 2.5 / 12.5) < 0.1,
		"weighted choice player / base / hostage ≈ 48 / 32 / 20 %% (%s)" % str(counts))
	var a := MissionAI.new(77, "rusher", _stats("rusher"))
	var b := MissionAI.new(77, "rusher", _stats("rusher"))
	var ra: Array = []
	var rb: Array = []
	for i in 80:
		ra.append(a.tick(DT, {"pos": Vector2(0.0, -10.0 + i * 0.05), "alive": true}, [_player(Vector2.ZERO), base, hostage]))
		rb.append(b.tick(DT, {"pos": Vector2(0.0, -10.0 + i * 0.05), "alive": true}, [_player(Vector2.ZERO), base, hostage]))
	assert_eq(var_to_str(ra), var_to_str(rb), "the same seed and inputs give the same ticks")
	# a dead target is dropped at the next think
	var c := MissionAI.new(5, "rusher", _stats("rusher"))
	c.tick(MissionAI.THINK, {"pos": Vector2.ZERO, "alive": true}, [_player(Vector2(0, 5)), base])
	var dead := _player(Vector2(0, 5))
	dead["alive"] = false
	c.tick(MissionAI.THINK, {"pos": Vector2.ZERO, "alive": true}, [dead, base])
	assert_eq(c.target, 1, "a dead target is dropped for the living one")


func test_guard_and_flank() -> void:
	var g := MissionAI.new(2, "rusher", _stats("rusher", "normal", {"aggro": 10.0}))
	var p := Vector2(0.0, -20.0)
	for i in 60:
		var r := g.tick(DT, {"pos": p, "alive": true}, [_player(Vector2.ZERO)])
		p += (r["move"] as Vector2) * DT
	assert_eq(g.state, MissionAI.IDLE, "a guard waits while the player is 20 m away")
	assert_eq(p, Vector2(0.0, -20.0), "and stands still")
	for i in 20:
		g.tick(DT, {"pos": p, "alive": true}, [_player(Vector2(0.0, -12.0))])
	assert_true(g.alerted and g.state == MissionAI.CHASE, "the player within 10 m wakes it")
	var g2 := MissionAI.new(2, "rusher", _stats("rusher", "normal", {"aggro": 10.0}))
	g2.on_damage(12, false, false)
	assert_true(g2.alerted, "a hit wakes a guard too")
	var fl := MissionAI.new(3, "rusher", _stats("rusher", "normal", {"flank_pct": 100}))
	assert_true(fl.flank, "flank_pct 100: a flanker")
	fl.tick(MissionAI.THINK, {"pos": Vector2(0.0, -20.0), "alive": true}, [_player(Vector2.ZERO)])
	assert_true(absf(fl.goal.x) > 3.0, "a far flanker aims beside the player (goal %s)" % str(fl.goal))
	var nf := MissionAI.new(3, "rusher", _stats("rusher", "normal", {"flank_pct": 0}))
	assert_false(nf.flank, "flank_pct 0: no flanker")
	var n := 0
	for s in 200:
		if MissionAI.new(s, "rusher", _stats("rusher", "normal", {"flank_pct": MissionTypes.flank_pct("veryhard")})).flank:
			n += 1
	assert_true(n > 55 and n < 105, "very hard: about 40 %% flank (%d / 200)" % n)


func test_strike_geometry() -> void:
	var ai := MissionAI.new(1, "rusher", _stats("rusher"))
	assert_true(ai.strike_hits(Vector2.ZERO, 0.0, Vector2(0.0, 1.5), 0.35), "in front within reach: hit")
	assert_false(ai.strike_hits(Vector2.ZERO, 0.0, Vector2(0.0, 3.0), 0.35), "beyond reach: miss (a dodge)")
	assert_false(ai.strike_hits(Vector2.ZERO, 0.0, Vector2(0.0, -1.0), 0.35), "behind: miss")
