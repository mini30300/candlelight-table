extends "res://tests/testing.gd"
## Speeds and hidden stamina (0.14 item 1b, the model half): the ArenaData.PLAYER / MOVE_CLASS / MOVE_KITS / BREATH /
## STEPS numbers and the pure ArenaStamina model, a critical-speed (CS) / reserve (D') balance: above CS the reserve
## drains at (v - CS)·dt, below it recovers with Skiba's differential model (time constant D' / (CS - v)), and the top
## speed falls smoothly from the fresh sprint toward CS once the reserve is under the knee. The expected numbers are the
## design simulation's (scratchpad sim stamina_sim.py, fixed step 1/60, the player's accel lerp included), human
## (5.6 / 3.2 / 30 m) and armoured (6.5 / 4.2 / 40 m). Machines never tire. The player half (inputs, gaits, sync, sounds)
## drives a real ArenaPlayer.

const DT := 1.0 / 60.0
const SRC := "res://ui/arena/arena_stamina.gd"
## the design simulation, sampled once a second for 25 s of an all-out sprint from rest: speed, reserve, distance
const SIM_SECS: PackedInt32Array = [1, 3, 5, 7, 8, 9, 10, 12, 15, 20, 25]
const SIM := {
	"human": {"v": [5.50, 5.60, 5.60, 5.59, 5.38, 5.01, 4.64, 4.09, 3.66, 3.40, 3.31],
		"r": [0.96, 0.80, 0.64, 0.48, 0.40, 0.33, 0.28, 0.20, 0.14, 0.09, 0.06],
		"d": [4, 15, 27, 38, 43, 49, 53, 62, 74, 91, 108], "half": 10.8,
		"rest": [6.5, 21.6], "walk": [12.2, 40.6], "jog": [41.6, 138.2], "dodge": 2.84},
	"armoured": {"v": [6.38, 6.50, 6.50, 6.50, 6.50, 6.50, 6.46, 6.03, 5.31, 4.69, 4.46],
		"r": [0.97, 0.86, 0.74, 0.63, 0.57, 0.51, 0.45, 0.35, 0.24, 0.15, 0.10],
		"d": [5, 18, 31, 44, 50, 57, 63, 76, 93, 118, 140], "half": 14.8,
		"rest": [6.6, 21.9], "walk": [10.7, 35.4], "jog": [27.7, 92.1], "dodge": 2.54},
}
const FIELDS: PackedStringArray = ["walk", "jog", "back", "run", "cs", "dprime", "knee"]
const PLAYER_SCENE := "res://scenes/arena/arena_player.tscn"
const EGG := "res://scenes/arena/egg_gunner.gd"
const SOLDIER := "res://scenes/arena/soldier_figure.gd"


func _cls(name: String) -> Dictionary:
	return ArenaData.PLAYER.merged(ArenaData.MOVE_CLASS[name], true)


## an all-out sprint from rest, as the player drives it: want = top(), the accel lerp, then tick on the new speed
func _all_out(st: ArenaStamina, secs: int) -> Dictionary:
	var v := 0.0
	var d := 0.0
	var half := -1.0
	var low := INF
	var mid := (st.vmax + st.cs) * 0.5
	var out := {"v": {}, "r": {}, "d": {}, "e20": -1.0}
	for i in range(secs * 60):
		var want := st.top()
		v += (want - v) * (1.0 - exp(-st.accel_to(want, v) * DT))
		st.tick(v, DT)
		d += v * DT
		var t := (i + 1) * DT
		if half < 0.0 and t > 1.0 and v < mid:
			half = t
		if t > 1.0:
			low = minf(low, v)
		if out["e20"] < 0.0 and st.effort() >= float(ArenaData.BREATH["on"]):
			out["e20"] = t
		if (i + 1) % 60 == 0:
			var s := int((i + 1) / 60.0)
			out["v"][s] = v
			out["r"][s] = st.reserve()
			out["d"][s] = d
	out["half"] = half
	out["low"] = low
	return out


## seconds held at speed v from an empty reserve until the reserve reaches each of the levels
func _recover(cls: String, v: float, levels: Array) -> Array:
	var st := ArenaStamina.new(cls)
	st.bal = 0.0
	var out := []
	var n := 0
	for lv in levels:
		while st.reserve() < float(lv) and n < 60 * 400:
			st.tick(v, DT)
			n += 1
		out.append(n * DT)
	return out


func test_numbers() -> void:
	var p := ArenaData.PLAYER
	for k in ["hp", "accel", "radius", "invuln", "down_time", "holster", "draw"]:
		assert_true(p.has(k), "PLAYER keeps %s" % k, p.keys())
	for k in FIELDS + PackedStringArray(["sprint_accel"]):
		assert_true(p.has(k) and float(p[k]) > 0.0, "PLAYER.%s is a positive number" % k, p.get(k))
	assert_eq(ArenaData.MOVE_CLASS.keys(), ["human", "armoured", "machine"], "three move classes")
	assert_within(float(p["walk"]), 1.5, 1e-9, "a true walk 1.5 m/s (Ctrl)")
	assert_within(float(p["jog"]), 2.7, 1e-9, "W is a 2.7 m/s jog, slower than the old 3.0")
	assert_within(float(p["back"]), 1.8, 1e-9, "backwards is capped at 1.8 m/s")
	assert_within(float(p["run"]), 5.6, 1e-9, "a fresh sprint 5.6 m/s")
	assert_within(float(p["cs"]), 3.2, 1e-9, "critical speed 3.2 m/s")
	assert_within(float(p["dprime"]), 30.0, 1e-9, "a 30 m reserve above it")
	assert_within(float(p["sprint_accel"]), 4.0, 1e-9, "the sprint ramps up at 4 /s")
	for name in ["human", "armoured"]:
		var c := _cls(name)
		assert_true(float(c["walk"]) < float(c["jog"]) and float(c["jog"]) < float(c["cs"]) and
			float(c["cs"]) < float(c["run"]), "%s: walk < jog < CS < sprint" % name, c)
		assert_true(float(c["back"]) >= float(c["walk"]) and float(c["back"]) < float(c["jog"]),
			"%s: walk <= back < jog" % name, c)
		assert_true(float(c["knee"]) > 0.0 and float(c["knee"]) < 1.0, "%s: the knee is inside the reserve" % name, c)
	var hu := _cls("human")
	var ar := _cls("armoured")
	for k in FIELDS:
		assert_true(float(ar[k]) >= float(hu[k]), "armoured >= human in %s" % k, [ar[k], hu[k]])
	assert_within(float(ar["run"]), 6.5, 1e-9, "the armoured sprint 6.5 m/s")
	assert_within(float(ar["cs"]), 4.2, 1e-9, "armoured critical speed 4.2 m/s")
	assert_within(float(ar["dprime"]), 40.0, 1e-9, "the armoured reserve 40 m")
	var mc := _cls("machine")
	assert_eq(float(mc["cs"]), 0.0, "machines never tire (cs 0)")
	assert_true(float(mc["walk"]) < float(mc["jog"]) and float(mc["jog"]) < float(mc["run"]) and
		float(mc["back"]) >= float(mc["walk"]), "machine gaits are ordered", mc)
	var beast := float(ArenaData.BEAST["run"])
	assert_true(beast > float(hu["cs"]) and beast < float(hu["run"]),
		"the beast's chase lies between CS and the sprint: a fresh sprint escapes, a tired runner is caught", beast)
	for kit in ["knight", "kblade", "kcapt", "cxw"]:
		assert_eq(ArenaData.MOVE_KITS.get(kit, ""), "armoured", "kit %s is armoured" % kit)
	assert_eq(ArenaData.MOVE_KITS.get("rwar", ""), "machine", "the robot kit is a machine")
	for kit in ArenaData.MOVE_KITS:
		assert_true(ArenaData.MOVE_CLASS.has(ArenaData.MOVE_KITS[kit]), "kit %s maps to a known class" % kit)
	# the model copies its class
	var st := ArenaStamina.new("armoured")
	assert_true(st.cls == "armoured" and st.vmax == 6.5 and st.cs == 4.2 and st.bal == 40.0 and st.jog == 3.2,
		"ArenaStamina.new(armoured) takes the armoured numbers, full", [st.vmax, st.cs, st.bal])
	st = ArenaStamina.new("no such class")
	assert_true(st.cls == "human" and st.vmax == 5.6 and st.walk == 1.5 and st.back == 1.8 and st.bal == 30.0,
		"an unknown class falls back to human", [st.cls, st.vmax])
	assert_true(ArenaStamina.new().cls == "human", "the default class is human")


func test_top_speed_law() -> void:
	for name in ["human", "armoured"]:
		var st := ArenaStamina.new(name)
		assert_within(st.top(), st.vmax, 1e-9, "%s: full reserve -> the fresh sprint" % name)
		st.bal = 0.0
		assert_within(st.top(), st.cs, 1e-9, "%s: empty -> critical speed" % name)
		var prev := st.cs
		var worst := 0.0
		var mono := true
		var flat := true
		for i in range(1001):
			var r := i / 1000.0
			st.bal = r * st.dprime
			var v := st.top()
			worst = maxf(worst, absf(v - prev))
			mono = mono and v >= prev - 1e-12
			if r >= st.knee:
				flat = flat and absf(v - st.vmax) < 1e-12
			prev = v
		assert_true(mono, "%s: top speed never falls as the reserve grows" % name)
		assert_true(worst < 0.02, "%s: continuous (step < 0.02 m/s over 1000 samples)" % name, worst)
		assert_true(flat, "%s: flat at the sprint while the reserve >= the knee" % name)
	var m := ArenaStamina.new("machine")
	m.bal = 0.0
	assert_eq(m.top(), 4.5, "a machine always sprints at 4.5")
	assert_eq(m.reserve(), 1.0, "a machine's reserve reads full")


func test_drain_exact() -> void:
	for v in [3.5, 4.0, 5.6]:
		var s1 := ArenaStamina.new()
		var spent := 0.0
		for i in range(600):
			s1.tick(v, DT)
			spent += (v - s1.cs) * DT
		assert_within(s1.bal, s1.dprime - spent, 1e-9, "600 ticks at %.1f m/s drain exactly sum (v - CS)·dt" % v)
	var st := ArenaStamina.new()
	for i in range(600):
		st.tick(8.0, DT)
	assert_eq(st.bal, 0.0, "a long fast run stops at an empty reserve, never below")
	st.refill()
	for i in range(600):
		st.tick(1.0, DT)
	assert_eq(st.bal, st.dprime, "a full reserve stays full below CS, never above")
	# a fixed (not random) mix of speeds keeps it inside [0, D']
	var inside := true
	var moved := false
	for i in range(3000):
		st.tick(4.5 + 4.5 * sin(i * 0.37) + 1.5 * sin(i * 0.011), DT)
		inside = inside and st.bal >= 0.0 and st.bal <= st.dprime
		moved = moved or st.bal < st.dprime * 0.5
	assert_true(inside and moved, "the reserve stays within [0, D'] under a varied run", st.bal)
	var m := ArenaStamina.new("machine")
	m.tick(9.0, 10.0)
	assert_true(m.reserve() == 1.0 and m.effort() == 0.0, "a machine never spends its reserve")


func test_all_out_timeline() -> void:
	var tol := {"v": 0.006, "r": 0.006, "d": 0.6}
	for name in ["human", "armoured"]:
		var st := ArenaStamina.new(name)
		var got := _all_out(st, 25)
		var exp_: Dictionary = SIM[name]
		for key in ["v", "r", "d"]:
			var bad := []
			for j in SIM_SECS.size():
				var s := SIM_SECS[j]
				if absf(float(got[key][s]) - float(exp_[key][j])) > float(tol[key]):
					bad.append([s, snappedf(float(got[key][s]), 0.001), exp_[key][j]])
			assert_true(bad.is_empty(), "%s: %s matches the design simulation second by second" % [name, key], bad)
		assert_within(float(got["half"]), float(exp_["half"]), 0.06, "%s: half the extra speed gone at the simulated time" % name)
		assert_true(float(got["low"]) >= st.cs - 1e-9, "%s: never below CS" % name, got["low"])
	# the design's headline numbers for the human
	var h := _all_out(ArenaStamina.new(), 20)
	assert_within(float(h["v"][5]), 5.60, 0.02, "full sprint 5.6 at 5 s")
	assert_within(float(h["half"]), 10.8, 0.3, "4.4 m/s (half the extra speed) at 10.8 s")
	assert_within(float(h["v"][20]), 3.40, 0.05, "3.4 m/s after 20 s")
	assert_within(float(h["d"][20]), 91.0, 2.0, "91 m in 20 s")
	assert_true(float(h["v"][12]) < 5.0, "any run longer than about 12 s is slower than the old 5.0", h["v"][12])


func test_recovery() -> void:
	var st := ArenaStamina.new()
	st.bal = 0.0
	st.rest(st.dprime / st.cs)
	assert_within(st.reserve(), 1.0 - exp(-1.0), 0.005, "standing for D'/CS = 9.375 s refills 1 - 1/e")
	st.bal = 0.0
	for i in range(562):
		st.tick(0.0, DT)
	assert_within(st.reserve(), 1.0 - exp(-1.0), 0.005, "the same by 562 ticks (9.37 s)")
	for name in ["human", "armoured"]:
		var exp_: Dictionary = SIM[name]
		var c := ArenaStamina.new(name)
		var t_rest := _recover(name, 0.0, [0.5, 0.9])
		var t_walk := _recover(name, c.walk, [0.5, 0.9])
		var t_jog := _recover(name, c.jog, [0.5, 0.9])
		for pair in [["rest", t_rest], ["walk", t_walk], ["jog", t_jog]]:
			var want: Array = exp_[pair[0]]
			assert_within(float(pair[1][0]), float(want[0]), 0.07, "%s: %s from empty to half as simulated" % [name, pair[0]])
			assert_within(float(pair[1][1]), float(want[1]), 0.07, "%s: %s from empty to 0.9 as simulated" % [name, pair[0]])
		assert_true(t_rest[0] < t_walk[0] and t_walk[0] < t_jog[0], "%s: rest recovers faster than walk, walk than jog" % name,
			[t_rest, t_walk, t_jog])
		c.bal = c.dprime * 0.3
		for i in range(600):
			c.tick(c.cs, DT)
		assert_within(c.bal, c.dprime * 0.3, 1e-9, "%s: at exactly CS nothing changes" % name)


## A full reserve below CS skips the exp() (Codex, PR #31): it stays exactly full, and a reserve just under full still
## refills by the same formula, bit for bit.
func test_full_skips_exp() -> void:
	var st := ArenaStamina.new()
	for v in [0.0, st.walk, st.jog, st.cs * 0.999]:
		st.bal = st.dprime
		for i in range(120):
			st.tick(v, DT)
		assert_true(st.bal == st.dprime, "full at %.2f m/s, below CS: stays exactly full" % v, st.bal)
	var b := st.dprime * 0.999
	st.bal = b
	st.tick(st.walk, DT)
	var want := st.dprime - (st.dprime - b) * exp(-(st.cs - st.walk) * DT / st.dprime)
	assert_true(st.bal == want, "just under full: the same refill formula, bit for bit", [st.bal, want])


func test_lazy_equals_ticks() -> void:
	var a := ArenaStamina.new()
	var b := ArenaStamina.new()
	a.bal = 7.0
	b.bal = 7.0
	a.rest(10.0)
	for i in range(600):
		b.tick(0.0, DT)
	assert_within(a.bal, b.bal, 1e-9, "rest(10) equals 600 standing ticks")
	a.bal = 2.0
	b.bal = 2.0
	a.rest(3.25)
	a.rest(4.75)
	b.rest(8.0)
	assert_within(a.bal, b.bal, 1e-9, "rest(3.25) then rest(4.75) equals rest(8)")
	var before := a.bal
	a.rest(0.0)
	a.rest(-5.0)
	assert_eq(a.bal, before, "resting no time (or negative time) changes nothing")


func test_dodge_cost() -> void:
	var d := ArenaData.DODGE
	var n := roundi(float(d["time"]) / DT)
	for name in ["human", "armoured"]:
		var st := ArenaStamina.new(name)
		# the player moves by dodge_travel differences, i.e. the speed at the middle of each tick
		for i in range(n):
			st.tick(ArenaCombat.dodge_speed((i + 0.5) * DT), DT)
		var cost := st.dprime - st.bal
		assert_within(cost, float(SIM[name]["dodge"]), 0.1, "%s: one dodge costs its burst above CS" % name)
		assert_within(cost, float(d["distance"]) - st.cs * float(d["time"]), 1e-6,
			"%s: the cost is the dash distance minus CS x its time" % name)


func test_breath_map() -> void:
	var b := ArenaData.BREATH
	assert_false(ArenaStamina.breath_on(0.19, false), "silent below e 0.2")
	assert_true(ArenaStamina.breath_on(0.2, false), "panting starts at e 0.2")
	assert_true(ArenaStamina.breath_on(0.16, true), "once on, it stays on above 0.15")
	assert_false(ArenaStamina.breath_on(0.149, true), "it stops below 0.15")
	for e in [0.2, 0.5, 1.0]:
		assert_within(ArenaStamina.breath_rate(e), 16.0 + 40.0 * e, 1e-9, "rate 16 + 40e per minute at e %.1f" % e)
	assert_within(ArenaStamina.breath_gain(0.2), float(b["gain0"]), 1e-9, "quiet at the threshold")
	assert_within(ArenaStamina.breath_gain(0.9), float(b["gain1"]), 1e-9, "full loudness at e 0.9")
	assert_within(ArenaStamina.breath_gain(1.0), float(b["gain1"]), 1e-9, "no louder past it")
	var rises := true
	var prev := ArenaStamina.breath_gain(0.0)
	for i in range(101):
		var g := ArenaStamina.breath_gain(i / 100.0)
		rises = rises and g >= prev - 1e-12
		prev = g
	assert_true(rises, "loudness rises with effort")
	assert_false(ArenaStamina.breath_hard(0.54, false), "soft below 0.55")
	assert_true(ArenaStamina.breath_hard(0.55, false), "hard from 0.55")
	assert_true(ArenaStamina.breath_hard(0.51, true), "hard stays down to 0.5")
	assert_false(ArenaStamina.breath_hard(0.49, true), "soft again below 0.5")
	var hu := ArenaStamina.new()
	var ar := ArenaStamina.new("armoured")
	hu.bal = hu.dprime * 0.4
	ar.bal = ar.dprime * 0.4
	assert_true(hu.breathing(false) and ar.breathing(false), "both pant at e 0.6")
	assert_within(hu.breath_volume(), ArenaStamina.breath_gain(0.6), 1e-9, "the human pants at the mapped loudness")
	assert_within(ar.breath_volume(), 0.6 * ArenaStamina.breath_gain(0.6), 1e-9, "the armoured helmet x 0.6")
	assert_true(hu.breath_pitch() == 1.0 and ar.breath_pitch() == 0.94, "the helmet lowers the pitch to 0.94")
	var m := ArenaStamina.new("machine")
	m.bal = 0.0
	assert_true(not m.breathing(false) and not m.breathing(true) and m.breath_volume() == 0.0, "machines are silent")
	# from the simulation: audible after 3.0 s of a fresh sprint; after a 20 s sprint, 14.2 s standing until e < 0.2
	var st := ArenaStamina.new()
	assert_within(float(_all_out(st, 20)["e20"]), 3.0, 0.06, "panting is audible after 3 s of a fresh sprint")
	assert_within(st.effort(), 0.91, 0.006, "e 0.91 after a 20 s sprint")
	var n := 0
	while st.effort() >= float(b["on"]) and n < 6000:
		st.tick(0.0, DT)
		n += 1
	assert_within(n * DT, 14.2, 0.1, "and 14.2 s of standing until it drops below 0.2")


func test_cadence() -> void:
	for p in ArenaData.STEPS["cadence"]:
		assert_within(ArenaStamina.cadence(p.x), p.y, 1e-9, "the stride wheel passes (%.2f, %.0f)" % [p.x, p.y])
	var prev := ArenaStamina.cadence(0.0)
	var rises := true
	for i in range(1, 66):
		var c := ArenaStamina.cadence(i * 0.1)
		rises = rises and c > prev
		prev = c
	assert_true(rises, "steps per minute rise with speed up to 6.5 m/s", prev)
	assert_within(ArenaStamina.cadence(9.0), 195.0, 1e-9, "flat past the last point")
	# จุดเป็น Vector2 (float32) จึงเทียบหยาบกว่า
	assert_within(ArenaStamina.cadence(2.7), lerpf(103.0, 164.0, (2.7 - 1.45) / 1.55), 1e-4, "linear between points")


func test_purity() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	assert_true(src.length() > 500, "read the model's source", src.length())
	for word in ["randf", "randi", "Time.", "OS.", "Engine.", "Node", "get_tree"]:
		assert_false(src.contains(word), "the model never uses %s (fixed step, no random, no clock)" % word)


# ---- the player half: a real ArenaPlayer driven tick by tick (as in test_arena_dodge.gd) ----

func _player(fig: Node3D, level := "mid") -> Node3D:
	var p: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.call("setup", null, {"figure": fig, "level": level})
	p.call("place", Vector3(0, 0, 40), 0.0, PI)      # far from everything, facing +z
	return p


func _free(p: Node3D) -> void:
	p.get_parent().remove_child(p)
	p.free()


func _ticks(p: Node3D, n: int) -> void:
	for i in n:
		p.call("_physics_process", DT)


## hold the actions down for n ticks, then let go
func _hold(p: Node3D, actions: Array, n: int) -> void:
	for a: StringName in actions:
		Input.action_press(a)
	_ticks(p, n)
	for a: StringName in actions:
		Input.action_release(a)


func _soldier(body := "") -> Node3D:
	var f: Node3D = (load(SOLDIER) as GDScript).new()
	f.call("set_manual", true)
	f.set("body_id", body)
	return f


func _make(name: String) -> Node3D:
	return _soldier() if name == "soldier" else (load(EGG) as GDScript).new()


func test_player_speeds() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	var h := _cls("human")
	for name in ["egg", "soldier"]:
		var p := _player(_make(name))
		var fig: Node3D = p.call("figure")
		var st: ArenaStamina = p.get("_st")
		assert_true(InputMap.has_action(&"walk"), "%s: the player adds the Ctrl walk action" % name)
		assert_eq(st.cls, "human", "%s: a human mover" % name)
		_hold(p, [&"move_forward"], 180)
		assert_within(float(p.call("speed")), float(h["jog"]), 0.02, "%s: W for 3 s jogs at 2.7 m/s" % name)
		assert_eq(st.reserve(), 1.0, "%s: ...under CS, so the reserve stays full" % name)
		_hold(p, [&"move_forward", &"walk"], 120)
		assert_within(float(p.call("speed")), float(h["walk"]), 0.02, "%s: Ctrl + W walks at 1.5" % name)
		_hold(p, [&"move_back"], 120)
		assert_within(float(p.call("speed")), float(h["back"]), 0.02, "%s: S backs off at 1.8" % name)
		_hold(p, [&"move_back", &"run"], 120)
		assert_within(float(p.call("speed")), float(h["back"]), 0.02, "%s: Shift + S still backs off at 1.8 (no sprinting backwards)" % name)
		if name == "egg":
			assert_false(bool(fig.get("_running")), "egg: ...and gets no run flag (no slow-motion run clip)")
		if bool(p.call("strafes")):
			_hold(p, [&"move_left", &"run"], 120)
			assert_within(float(p.call("speed")), float(h["jog"]), 0.02, "%s: Shift + A strafes at the jog (sprint is forward only)" % name)
			if name == "egg":
				assert_false(bool(fig.get("_running")), "egg: ...also without the run flag")
		_hold(p, [&"move_forward", &"run", &"walk"], 120)
		assert_within(float(p.call("speed")), float(h["walk"]), 0.02, "%s: Ctrl + Shift + W walks at 1.5" % name)
		if name == "egg":
			assert_false(bool(fig.get("_running")), "egg: ...without the run flag")
		p.call("place", Vector3(0, 0, 40), 0.0, PI)
		_hold(p, [&"move_forward", &"run"], 90)
		assert_within(float(p.call("speed")), float(h["run"]), 0.02, "%s: Shift + W sprints at 5.6 within 1.5 s" % name)
		if name == "egg":
			assert_true(bool(fig.get("_running")), "egg: the sprint itself raises the run flag")
		_hold(p, [&"move_forward", &"run"], 20 * 60 - 90)
		assert_within(float(p.call("speed")), 3.40, 0.06, "%s: after 20 s of Shift the tired sprint is down to 3.4" % name)
		assert_true(st.reserve() < 0.1, "%s: ...with under a tenth of the reserve left (%.3f)" % [name, st.reserve()])
		if name == "soldier":
			assert_eq(fig.get("_loop"), &"jog", "soldier: the tired sprint plays the jog clip")
		# touch stick: a light push walks, the ring edge sprints
		p.call("place", Vector3(0, 0, 40), 0.0, PI)
		p.call("set_stick", Vector2(0, 0.4))
		_ticks(p, 120)
		assert_within(float(p.call("speed")), float(h["jog"]) * 0.4 / ArenaPlayer.RUN_STICK, 0.02, "%s: stick 0.4 moves at 1.27" % name)
		p.call("set_stick", Vector2(0, 0.95))
		_ticks(p, 90)
		assert_within(float(p.call("speed")), float(h["run"]), 0.02, "%s: stick 0.95 (the ring edge) sprints" % name)
		p.call("set_stick", Vector2.ZERO)
		_ticks(p, 120)
		# a dodge pays its burst above CS out of the reserve; placing and getting up fill it again
		p.call("place", Vector3(0, 0, 40), 0.0, PI)
		assert_true(bool(p.call("dodge")), "%s: dodges" % name)
		_ticks(p, 60)
		assert_within(st.dprime - st.bal, float(SIM["human"]["dodge"]), 0.15, "%s: one dodge costs about 2.84 m of the reserve" % name)
		p.call("place", Vector3(0, 0, 40), 0.0, PI)
		assert_eq(st.reserve(), 1.0, "%s: place() fills the reserve" % name)
		_hold(p, [&"move_forward", &"run"], 600)
		p.call("_go_down")
		_ticks(p, 60)
		assert_true(st.reserve() < 0.6, "%s: down after a 10 s sprint, still tired (%.3f)" % [name, st.reserve()])
		_ticks(p, 90)
		assert_eq(st.reserve(), 1.0, "%s: getting up (revive) fills the reserve" % name)
		_free(p)


func test_player_sync() -> void:
	var p := _player(_make("egg"))
	var st: ArenaStamina = p.get("_st")
	_hold(p, [&"move_forward", &"run"], 600)
	_ticks(p, 120)
	assert_false(p.is_physics_processing(), "after a sprint, standing still puts the tick to sleep (no stamina work per frame)")
	assert_true(st.reserve() < 0.5, "...still tired (%.3f)" % st.reserve())
	# the frames the tick slept through are credited as standing rest in one closed-form call, once
	var ref := ArenaStamina.new()
	ref.bal = st.bal
	for i in 90:
		ref.tick(0.0, DT)
	p.set("_st_frame", int(p.get("_st_frame")) - 90)
	p.call("_stamina_sync")
	assert_within(st.bal, ref.bal, 1e-9, "the catch-up of 90 sleeping frames equals 90 standing ticks")
	var once := st.bal
	p.call("_stamina_sync")
	assert_eq(st.bal, once, "...credited once")
	# pause banks the rest before it, and the paused frames are not rest
	p.set("_st_frame", int(p.get("_st_frame")) - 30)
	p.call("set_paused", true)
	ref.bal = once
	ref.rest(30 * DT)
	assert_within(st.bal, ref.bal, 1e-9, "pausing banks the 30 frames slept before it")
	var banked := st.bal
	_ticks(p, 5)
	p.set("_st_frame", int(p.get("_st_frame")) - 600)
	p.call("set_paused", false)
	p.call("_stamina_sync")
	assert_eq(st.bal, banked, "the 10 s spent paused are not counted as rest")
	_free(p)


func test_levels_same_gameplay() -> void:
	var out := {}
	for level in ["hi", "min"]:
		var p := _player(_soldier(), level)
		_hold(p, [&"move_forward"], 60)
		_hold(p, [&"move_forward", &"run"], 600)
		_hold(p, [&"move_back"], 60)
		_hold(p, [&"move_forward", &"walk"], 60)
		p.call("dodge")
		_ticks(p, 60)
		out[level] = [p.global_position, (p.get("_st") as ArenaStamina).bal]
		_free(p)
	assert_eq(out["hi"][0], out["min"][0], "hi and min: the same inputs end on the same spot, bit for bit")
	assert_eq(out["hi"][1], out["min"][1], "...with the same reserve")


func test_move_profiles() -> void:
	var egg: Node3D = (load(EGG) as GDScript).new()
	assert_eq(egg.call("move_profile"), {"class": "human", "voice": "low", "pitch": 1.2, "feet": "none"},
		"the egg: human, the low voice a little higher, no feet")
	egg.free()
	for c in [["", "low"], ["f1", "high"], ["f2", "high"], ["m2", "low"]]:
		var p := _player(_soldier(c[0]))
		assert_eq((p.call("figure") as Node3D).call("move_profile"), {"class": "human", "voice": c[1], "feet": "boot"},
			"soldier body '%s': human, %s voice, boots" % c)
		assert_eq(p.get("_profile"), (p.call("figure") as Node3D).call("move_profile"), "...read by the player once at setup")
		_free(p)
	for c in [["kblade", "armoured", "low", "metal"], ["cxw", "armoured", "low", "metal"], ["rwar", "machine", "none", "metal"],
			["warrior", "human", "none", "boot"], ["infantry", "human", "low", "boot"]]:
		var k := KitFighter.new()
		k.walk_kit = c[0]
		var mp: Dictionary = k.move_profile()
		assert_eq([mp["class"], mp["voice"], mp["feet"]], [c[1], c[2], c[3]], "kit %s: %s, voice %s, %s feet" % c)
		k.free()
	# the class reaches the player's speeds: an armoured kit jogs at its own 3.2
	var kf := KitFighter.new()
	kf.walk_kit = "kblade"
	var p := _player(kf)
	var st: ArenaStamina = p.get("_st")
	assert_eq(st.cls, "armoured", "an armoured kit makes the player an armoured mover")
	_hold(p, [&"move_forward"], 180)
	assert_within(float(p.call("speed")), float(_cls("armoured")["jog"]), 0.02, "...that jogs at 3.2 with W")
	_free(p)


func test_step_phase() -> void:
	var p := _player(_soldier())
	var fig: Node3D = p.call("figure")
	assert_true(bool(p.get("_fig_phase")), "the player finds the soldier's step_phase hook (H13)")
	assert_eq(float(fig.call("step_phase")), -1.0, "standing: no gait loop, phase -1")
	_hold(p, [&"move_forward"], 30)
	var ap: AnimationPlayer = fig.call("animation_player")
	assert_eq(fig.get("_loop"), &"jog", "W: the jog loop plays")
	ap.seek(ap.current_animation_length * 0.25, true)
	assert_within(float(fig.call("step_phase")), 0.25, 0.001, "...and step_phase is its position over its length")
	_ticks(p, 120)
	assert_eq(float(fig.call("step_phase")), -1.0, "stopped: phase -1 again")
	_free(p)


const PRIM := "res://tests/fixtures/figure_pack/prim_figure.gd"


## hold the actions for n ticks; a manual soldier's clips advance one tick each time (in play its AnimationPlayer runs
## on idle frames), and feet gets the foot (0 right, 1 left) of every new step
func _walk(p: Node3D, actions: Array, n: int, feet: Array = []) -> void:
	var fig: Node3D = p.call("figure")
	for a: StringName in actions:
		Input.action_press(a)
	for i in n:
		var was := int(p.get("_steps"))
		p.call("_physics_process", DT)
		if fig is SoldierFigure:
			fig.call("step", DT)
		if int(p.get("_steps")) > was:
			feet.append(int(p.get("_foot")))
	for a: StringName in actions:
		Input.action_release(a)


## what the arena asked of Sfx (Dummy driver: asks are counted before the per-kind gap), summed over kinds with this
## prefix; -1 without the Sfx autoload
func _asks(prefix: String) -> int:
	var s := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"Sfx")
	if s == null:
		return -1
	var n := 0
	var ask: Dictionary = (s.get("stats") as Dictionary)["ask"]
	for k: String in ask:
		if k.begins_with(prefix):
			n += int(ask[k])
	return n


func _alternates(feet: Array) -> bool:
	for i in range(1, feet.size()):
		if feet[i] == feet[i - 1]:
			return false
	return feet.size() > 1


func test_footsteps() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	# loudness: walk 0.35 → jog 0.55 → sprint 0.8, tired feet land 20 % heavier
	var st := ArenaStamina.new()
	for c in [[st.walk, 0.35, "walk"], [st.jog, 0.55, "jog"], [st.vmax, 0.8, "sprint"], [0.5, 0.35, "slower than walk"], [9.0, 0.8, "past the sprint"]]:
		assert_within(st.step_gain(c[0]), c[1], 1e-9, "step gain, %s" % c[2])
	st.bal = 0.0
	assert_within(st.step_gain(st.jog), 0.55 * 1.2, 1e-6, "...x 1.2 with the reserve spent")
	# the soldier steps on its own clips' foot strikes (H13): right at phase 0, left at 0.5
	var p := _player(_soldier())
	var fig: Node3D = p.call("figure")
	var ap: AnimationPlayer = fig.call("animation_player")
	_walk(p, [&"move_forward"], 120)
	assert_eq(fig.get("_loop"), &"jog", "W: the soldier jogs")
	var per_s := 2.0 * absf(ap.get_playing_speed()) / ap.current_animation_length
	var n0 := int(p.get("_steps"))
	var a0 := _asks("step_boot")
	var feet := []
	_walk(p, [&"move_forward"], 600, feet)
	var n := int(p.get("_steps")) - n0
	assert_within(float(n), per_s * 10.0, 1.0, "a 10 s jog steps on each strike of the jog clip (%d steps, %.0f /min)" % [n, per_s * 60.0])
	assert_true(_alternates(feet), "...right and left in turn")
	if a0 >= 0:
		assert_eq(_asks("step_boot") - a0, n, "...each one a boot step asked of Sfx")
	# backwards the walk clip plays in reverse: the strikes are crossed the other way and still count
	_walk(p, [&"move_back"], 60)
	assert_true(bool(fig.call("moving_back")), "S: the soldier's walk clip plays in reverse")
	per_s = 2.0 * absf(ap.get_playing_speed()) / ap.current_animation_length
	n0 = int(p.get("_steps"))
	feet = []
	_walk(p, [&"move_back"], 360, feet)
	n = int(p.get("_steps")) - n0
	assert_within(float(n), per_s * 6.0, 1.0, "a 6 s backwards walk steps too (%d steps)" % n)
	assert_true(_alternates(feet), "...in turn")
	_walk(p, [], 120)
	n0 = int(p.get("_steps"))
	_ticks(p, 60)
	assert_eq(int(p.get("_steps")), n0, "standing: no steps")
	_free(p)
	# the egg floats: no feet, no steps
	p = _player(_make("egg"))
	a0 = _asks("step_")
	_walk(p, [&"move_forward"], 300)
	assert_eq(int(p.get("_steps")), 0, "the egg makes no steps")
	if a0 >= 0:
		assert_eq(_asks("step_"), a0, "...and asks Sfx for none")
	_free(p)
	# a pack figure without H13 (the fixture's primitive) steps on the stride wheel: cadence(v) steps a minute
	p = _player((load(PRIM) as GDScript).new())
	_walk(p, [&"move_forward"], 120)
	n0 = int(p.get("_steps"))
	feet = []
	_walk(p, [&"move_forward"], 600, feet)
	n = int(p.get("_steps")) - n0
	assert_within(float(n), ArenaStamina.cadence(2.7) / 6.0, 1.0, "the stride wheel: a 10 s jog takes cadence(2.7) / 6 steps (%d)" % n)
	assert_true(_alternates(feet), "...in turn")
	_free(p)
	# armoured feet ring metal
	var kf := KitFighter.new()
	kf.walk_kit = "kblade"
	p = _player(kf)
	a0 = _asks("step_metal")
	_walk(p, [&"move_forward"], 180)
	n = int(p.get("_steps"))
	assert_true(n > 3, "an armoured kit steps on the wheel (%d)" % n)
	if a0 >= 0:
		assert_eq(_asks("step_metal") - a0, n, "...with metal steps")
	_free(p)


func test_sleeps_while_panting() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	for level in ["hi", "min"]:
		var p := _player(_soldier(), level)
		var st: ArenaStamina = p.get("_st")
		var timer := p.get_node_or_null(^"Breath") as Timer
		assert_true(timer != null and timer.is_stopped() and timer.one_shot, "%s: a one-shot Breath timer waits, stopped" % level)
		if timer == null:
			_free(p)
			continue
		var pant0 := _asks("pant_")
		var hard0 := _asks("pant_in_hard_") + _asks("pant_out_hard_")
		var step0 := _asks("step_boot")
		_walk(p, [&"move_forward"], 30)
		assert_true(timer.is_stopped(), "%s: jogging under CS: no panting" % level)
		_walk(p, [&"move_forward", &"run"], 10 * 60)
		assert_true(bool(p.get("_breath_on")) and not timer.is_stopped(), "%s: after 10 s of Shift the player pants (e %.2f)" % [level, st.effort()])
		if pant0 >= 0:
			assert_true(_asks("pant_") > pant0 and _asks("step_boot") > step0, "%s: ...through Sfx, with footsteps" % level)
		var k := 0
		while float(p.call("speed")) > 0.0 and k < 120:
			_walk(p, [], 1)
			k += 1
		_walk(p, [], 2)
		assert_false(p.is_physics_processing(), "%s: two ticks after stopping, the player's tick sleeps..." % level)
		assert_true(bool(p.get("_breath_on")) and not timer.is_stopped(), "%s: ...while the Breath timer pants on" % level)
		# the timer's breaths: in and out in turn; the sleeping frames are only peeked at, the reserve is the tick's
		var ins := _asks("pant_in_")
		var outs := _asks("pant_out_")
		var bal := st.bal
		p.set("_st_frame", int(p.get("_st_frame")) - 60)
		for i in 4:
			p.call("_on_breath")
		if ins >= 0:
			assert_eq([_asks("pant_in_") - ins, _asks("pant_out_") - outs], [2, 2], "%s: four breaths: two in, two out" % level)
			assert_eq(_asks("pant_in_hard_") + _asks("pant_out_hard_") - hard0, 4, "%s: ...from the hard set, tired past e 0.55" % level)
		assert_eq(st.bal, bal, "%s: breathing never changes the reserve (sound only)" % level)
		p.call("set_paused", true)
		assert_true(timer.paused, "%s: pause holds the Breath timer" % level)
		p.call("set_paused", false)
		assert_false(timer.paused, "%s: ...and resume lets it go" % level)
		# breaths lock to strides: an inhale due within 0.25 s moves onto the foot strike, a later one waits
		p.set("_breath_in", false)
		p.call("_on_breath")
		timer.start(0.5)
		var in1 := _asks("pant_in_")
		p.call("_step", 0)
		assert_true(_asks("pant_in_") == in1 and timer.time_left == 0.5, "%s: an inhale 0.5 s away waits for its time" % level)
		timer.start(0.2)
		p.call("_step", 1)
		if in1 >= 0:
			assert_eq(_asks("pant_in_") - in1, 1, "%s: one 0.2 s away is taken on the foot strike" % level)
		assert_true(not bool(p.get("_breath_in")) and timer.time_left > 0.25, "%s: ...and the exhale is timed from there" % level)
		# 30 s of standing rest: the next breath finds the player rested and stops the timer
		var pant1 := _asks("pant_")
		p.set("_st_frame", int(p.get("_st_frame")) - 30 * 60)
		p.call("_on_breath")
		assert_true(timer.is_stopped() and not bool(p.get("_breath_on")), "%s: rested: the panting stops" % level)
		assert_eq(_asks("pant_"), pant1, "%s: ...without another breath" % level)
		p.call("_stamina_sync")
		assert_true(st.reserve() > 0.95, "%s: the tick's sync credits the rest (%.3f)" % [level, st.reserve()])
		_free(p)


## turning while sprinting: the direction follows at accel 12 (sprint_accel only holds back the speed's growth)
func test_turning_sprint() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	var p := _player(_soldier())
	assert_false(bool(p.call("strafes")), "soldier: A/D turn the body")
	_walk(p, [&"move_forward", &"run"], 120)
	var f0 := float(p.get("face"))
	var low := 99.0
	var off := 0.0
	for a: StringName in [&"move_forward", &"run", &"move_left"]:
		Input.action_press(a)
	for i in 60:
		p.call("_physics_process", DT)
		var d: Vector2 = ArenaPlayer.local_dir(p.get("_vel"), float(p.get("face")))
		low = minf(low, float(p.call("speed")))
		off = maxf(off, rad_to_deg(absf(atan2(d.x, d.y))))
	for a: StringName in [&"move_forward", &"run", &"move_left"]:
		Input.action_release(a)
	var turned := rad_to_deg(absf(angle_difference(f0, float(p.get("face")))))
	assert_true(turned > 60.0, "soldier: Shift + W + A for 1 s turns the body (%.0f deg)" % turned)
	assert_true(low >= 5.3, "...still sprinting through the turn, never under 5.3 m/s (%.2f)" % low)
	assert_true(off <= 15.0, "...with the velocity within 15 deg of the facing (%.1f)" % off)
	var was := float(p.get("_step_prev"))
	p.call("place", Vector3(0, 0, 40), 0.0, PI)
	assert_true(was >= 0.0 and float(p.get("_step_prev")) == -1.0, "place() forgets the step phase (was %.2f): no phantom step on the next stride" % was)
	_free(p)


## the panting stops when the player goes down, is hidden or leaves the tree; heal_full() also fills the reserve
func test_breath_stops() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	var p := _player(_soldier())
	var st: ArenaStamina = p.get("_st")
	var timer := p.get_node_or_null(^"Breath") as Timer
	_walk(p, [&"move_forward", &"run"], 10 * 60)
	assert_true(timer != null and not timer.is_stopped(), "after 10 s of Shift the player pants")
	if timer == null:
		_free(p)
		return
	var pant0 := _asks("pant_")
	p.call("_go_down")
	p.call("_on_breath")
	assert_true(timer.is_stopped() and not bool(p.get("_breath_on")), "down: the next breath stops the panting")
	assert_eq(_asks("pant_"), pant0, "...without another breath")
	p.call("heal_full")
	assert_true(not bool(p.call("is_downed")) and st.reserve() == 1.0, "heal_full() stands the player up with a full reserve")
	st.bal = 0.0
	p.call("_on_breath")
	assert_false(timer.is_stopped(), "worn out again: panting")
	p.hide()
	var pant1 := _asks("pant_")
	p.call("_on_breath")
	assert_true(timer.is_stopped() and _asks("pant_") == pant1, "hidden: the next breath stops the panting, silently")
	p.show()
	p.call("_on_breath")
	assert_false(timer.is_stopped(), "shown again: panting")
	p.get_parent().remove_child(p)
	assert_true(timer.is_stopped() and not bool(p.get("_breath_on")), "leaving the tree stops the Breath timer")
	p.free()
