extends "res://tests/testing.gd"
## core/battle/bot.gd (BtBot, R1_PORT_SPEC §1.16). Page parity from fixtures/bot/page_samples.json
## (tools/record_bot.js): expDmg for every ordered pair and how of 16 worlds (exact rationals vs the page's doubles),
## botChoice for 160 entries, and 114 whole bot phases (botStep until false: the act sequence, the dice counts and the
## planMove targets). Then hand boards for each decision (fall back when outmatched, hold an objective, go for the
## closest objective, shoot the best target, grenade fallback with CP >= 2, charge only when worth it, heal), the
## legality of every bot act, purity (no state change), the end-of-phase condition, and a pinned digest.

const FIXTURE := "res://tests/unit/fixtures/bot/page_samples.json"
const Apply := preload("res://tests/unit/bot_act_apply.gd")
## Digest of _digest_scenario; changes only on purpose.
const PINNED_DIGEST := "f1e14e21b206c550"
## planMove targets: the port's integer target vs the page's double (centres are js_round means, lengths isqrt).
const TARGET_TOL := 5

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = raw if raw is Dictionary else {}


# ------------------------------------------------------------------ helpers
func _i(v: Variant) -> int:
	return int(v)


## A fixture world (record_bot.js format) as a BattleState in play.
func _world(w: Dictionary) -> BattleState:
	var g: Dictionary = w["g"]
	var st := BattleState.make({"seed": 5, "w": 48, "d": 34, "teams": _i(g["teams"]), "freeFire": _i(g["ff"])})
	st.on = true
	st.round_no = _i(g["round"])
	st.turn = _i(g["turn"])
	st.phase = BattleState.PHASES.find(str(g["phase"]))
	for pv: Variant in w.get("seats", []):
		var p: Dictionary = pv
		var q := st.add_seat(_i(p["team"]), str(p["pid"]), _i(p["bot"]) == 1, _i(p["ai"]) == 1, "")
		q.cp = _i(p["cp"])
		q.done = _i(p["done"]) == 1
	for qv: Variant in w["squads"]:
		var q: Dictionary = qv
		var s := st.add_squad(str(q["id"]), str(q["k"]), _i(q["side"]), _i(q["pl"]), _i(q["n0"]), 0)
		var f: Array = q["f"]
		s.moved = _i(f[0]) == 1
		s.adv = _i(f[1]) == 1
		s.fell = _i(f[2]) == 1
		s.still = _i(f[3]) == 1
		s.shot = _i(f[4]) == 1
		s.charged = _i(f[5]) == 1
		s.ch_done = _i(f[6]) == 1
		s.shaken = f.size() > 7 and _i(f[7]) == 1
		if str(q.get("mk", "")) == "cur":
			s.mk = st.mark_key()
	for uv: Variant in w["units"]:
		var u: Dictionary = uv
		st.add_unit(str(u["id"]), st.squad(str(u["sq"])), _i(u["hp"]), _i(u["x"]), _i(u["z"]))
	for ov: Variant in w.get("objs", []):
		var o: Array = ov
		st.add_obj(_i(o[0]), _i(o[1]), _i(o[2]))
	for uv: Variant in w.get("used", []):
		var u: Array = uv
		st.used[BtStrats.key(st, str(u[0]), _i(u[1]))] = true
	return st


func _st2(cp: int = 2) -> BattleState:
	var st := BattleState.make({"seed": 9, "w": 48, "d": 34, "teams": 2})
	st.on = true
	st.phase = BattleState.PH_MOVE
	for i: int in 2:
		var q := st.add_seat(i, "L%d" % i, i == 0, false, "")
		q.cp = cp
	return st


func _sq(st: BattleState, id: String, k: String, side: int, pts: Array) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, side, int(t.get("n", 1)), 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


func _line(n: int, x0: int, z: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append([x0 + i * 1800, z])
	return out


## The flags the page's stubs set for an act (record_bot.js): what the next botStep sees.
func _mark(st: BattleState, a: Dictionary) -> void:
	var s := st.squad(str(a.get("u", "")))
	if s == null:
		return
	match str(a["a"]):
		"stay", "smove":
			s.moved = true
		"skip":
			var ph := str(a["ph"])
			if ph == "shoot":
				s.shot = true
			elif ph == "charge":
				s.ch_done = true
			else:
				s.moved = true
		"atk", "heal":
			s.shot = true
		"gren":
			BtStrats.use(st, "gren", s.pl, [] as Array[Dictionary])
			s.shot = true
		"chg":
			s.ch_done = true


# ------------------------------------------------------------------ page parity
func test_exp_dmg_matches_page() -> void:
	var ins: Array = fx["exp_in"]
	var outs: Array = fx["exp"]
	var bad: Array = []
	var n := 0
	var nonzero := 0
	for wi: int in ins.size():
		var st := _world(ins[wi])
		for rv: Variant in outs[wi]:
			var r: Array = rv
			var a := st.squads[_i(r[0])]
			var b := st.squads[_i(r[1])]
			for h: int in 3:
				var want: float = r[2 + h]
				var got := BtBot.exp_dmg(st, a, b, h)
				var v := float(got[0]) / float(got[1])
				n += 1
				if want != 0.0:
					nonzero += 1
				if got[1] <= 0 or absf(v - want) > 1e-9 * maxf(1.0, absf(want)):
					bad.append([wi, a.id, b.id, h, want, v])
	assert_true(n > 1000 and nonzero > 300 and bad.is_empty(),
		"exp_dmg equals the page's expDmg on %d pairs x hows (%d non-zero)" % [n, nonzero], bad.slice(0, 5))


func test_choice_matches_page() -> void:
	var ins: Array = fx["choice_in"]
	var outs: Array = fx["choice"]
	var bad: Array = []
	var hits := [0, 0, 0]
	for i: int in ins.size():
		var q: Dictionary = ins[i]
		var st := _world(q["w"])
		var e: Dictionary = q["p"]
		var p := BattleState.Pend.new()
		p.kind = BattleState.KINDS.find(str(e["kind"]))
		p.stage = BattleState.STAGES.find(str(e["stage"]))
		p.u = str(e["u"])
		p.t = str(e["t"])
		p.att = _i(e["att"])
		p.def = _i(e["def"])
		p.melee = _i(e["melee"]) == 1
		p.wounds = _i(e["wounds"])
		p.sv = _i(e["sv"])
		var c := BtBot.choice(st, p)
		var got := [1 if c["yes"] else 0, 1 if c["gtg"] else 0, 1 if c["brave"] else 0]
		var want: Array = outs[i]
		for k: int in 3:
			if _i(want[k]) == 1:
				hits[k] += 1
		if got != [_i(want[0]), _i(want[1]), _i(want[2])]:
			bad.append([i, e, want, got])
	assert_true(ins.size() >= 150 and hits[0] > 0 and hits[1] > 0 and hits[2] > 0 and bad.is_empty(),
		"choice equals botChoice on %d entries (yes %d, gtg %d, brave %d)" % [ins.size(), hits[0], hits[1], hits[2]],
		bad.slice(0, 5))


func test_phases_match_page() -> void:
	var ins: Array = fx["steps_in"]
	var outs: Array = fx["steps"]
	var bad: Array = []
	var codes := {}
	var worst := 0
	var acts_n := 0
	for wi: int in ins.size():
		var st := _world(ins[wi])
		var dice := Rng.make("bot:%d" % st.turn, 3)
		var got: Array = []
		var targets: Array = []
		for guard: int in 200:
			var a := BtBot.next_act(st, dice)
			if a.is_empty():
				break
			var o := {"a": a["a"], "u": a["u"]}
			for k: String in ["t", "how", "ph"]:
				if a.has(k):
					o[k] = a[k]
			if a.has("hit"):
				o["n"] = (a["hit"] as Array).size()
			if a.has("roll"):
				o["n"] = (a["roll"] as Array).size() if a["roll"] is Array else 1
			if str(a["a"]) == "smove":
				var d := BtBot.move_decision(st, st.squad(str(a["u"])))
				targets.append([d["x"], d["z"]])
				assert_true(str(d["how"]) == str(a["how"]), "decision and act agree on how")
			got.append(o)
			_mark(st, a)
		var want: Array = outs[wi]["acts"]
		var ok := want.size() == got.size()
		var ti := 0
		for k: int in mini(want.size(), got.size()):
			var wa: Dictionary = want[k]
			var ga: Dictionary = got[k]
			codes[str(wa["a"])] = int(codes.get(str(wa["a"]), 0)) + 1
			acts_n += 1
			for key: String in ["a", "u", "t", "how", "ph", "n"]:
				if wa.has(key) != ga.has(key) or (wa.has(key) and str(wa[key]) != str(ga[key]) and _num_ne(wa[key], ga[key])):
					ok = false
			if str(wa["a"]) == "smove" and str(ga["a"]) == "smove":
				var t: Array = targets[ti]
				ti += 1
				var dx: int = absi(int(t[0]) - roundi(float(wa["x"]) * 1000.0))
				var dz: int = absi(int(t[1]) - roundi(float(wa["z"]) * 1000.0))
				worst = maxi(worst, maxi(dx, dz))
				if dx > TARGET_TOL or dz > TARGET_TOL:
					ok = false
		if not ok:
			bad.append([wi, want, got])
	assert_true(ins.size() >= 100 and bad.is_empty(),
		"next_act replays botStep on %d phases (%d acts %s, target error <= %d MI)" % [ins.size(), acts_n, str(codes), worst],
		bad.slice(0, 2))
	for c: String in ["stay", "skip", "smove", "atk", "chg", "gren", "heal"]:
		assert_true(int(codes.get(c, 0)) > 0, "the sampled phases include a bot '%s'" % c)


func _num_ne(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
		return int(a) != int(b)
	return true


# ------------------------------------------------------------------ small functions
func test_melee_and_squads() -> void:
	var st := _st2()
	var a := _sq(st, "0:0", "cavalry", 0, _line(1, 0, 0))
	var b := _sq(st, "0:1", "boy", 0, _line(1, 0, 4000))
	var c := _sq(st, "0:2", "infantry", 0, _line(1, 0, 8000))
	var d := _sq(st, "1:0", "infantry", 1, _line(1, 0, -9000))
	var e := _sq(st, "0:3", "infantry", 0, [])
	assert_true(BtBot.melee(a), "no gun is melee")
	assert_true(BtBot.melee(b), "a 12-inch gun is melee")
	assert_false(BtBot.melee(c), "a 24-inch gun is not melee")
	var ids: Array = []
	for s: BattleState.Squad in BtBot.squads(st):
		ids.append(s.id)
	assert_eq(ids, ["0:0", "0:1", "0:2"], "squads: alive squads of the bot seat in turn, creation order (dead 0:3 and side 1 out)")
	st.seats[0].bot = false
	assert_eq(BtBot.squads(st).size(), 0, "a human seat has no bot squads")
	st.seats[0].bot = true
	st.turn = 1
	assert_eq(BtBot.squads(st).size(), 0, "side 1 is human: none")
	assert_true(d != null and e != null, "built")


func test_exp_dmg_exact() -> void:
	var st := _st2()
	var a := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var b := _sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var c := _sq(st, "1:1", "cavalry", 1, _line(3, 0, 60000))
	# 5 shots (rf at 10" half range 12": +1 each = 10), bs 4 (3/6), S3 vs T3 4+ (3/6), sv 5 (4/6 not saved), d 1
	# e = 10 * 1/2 * 1/2 * 2/3 = 5/3; times (1 + 45/(100*5)) = 545/500 -> 109/60
	var v := BtBot.exp_dmg(st, a, b, BattleState.HOW_SHOOT)
	assert_eq(v[0] * 60, v[1] * 109, "infantry on infantry at 10 inches: exactly 109/60")
	assert_eq(BtBot.exp_dmg(st, c, a, BattleState.HOW_SHOOT), PackedInt64Array([0, 1]), "no gun: [0, 1]")
	assert_eq(BtBot.exp_dmg(st, a, c, BattleState.HOW_SHOOT), PackedInt64Array([0, 1]), "nobody in range: [0, 1]")
	assert_true(BtBot.gt(PackedInt64Array([2, 3]), PackedInt64Array([3, 5])), "2/3 > 3/5")
	assert_false(BtBot.gt(PackedInt64Array([2, 4]), PackedInt64Array([1, 2])), "equal is not greater")


# ------------------------------------------------------------------ move phase
func test_move_fall_back_when_outmatched() -> void:
	var st := _st2()
	var me := _sq(st, "0:0", "infantry", 0, _line(5, -3600, 0))
	var foe := _sq(st, "1:0", "templar", 1, _line(3, -1800, 2500))
	assert_true(BtSquads.is_engaged(st, me), "engaged")
	var a := BtBot.next_act(st, Rng.make("bot:0", 1))
	assert_eq(str(a.get("a", "")), "smove", "outmatched gun squad falls back")
	assert_eq(str(a.get("how", "")), "fb", "how fb")
	var d := BtBot.move_decision(st, me)
	var c := BtSquads.center(me)
	var f := BtSquads.center(foe)
	assert_true(Fx.dist2(int(d["x"]), int(d["z"]), f[0], f[1]) > Fx.dist2(c[0], c[1], f[0], f[1]), "the target is further from the foe")
	assert_eq(Fx.isqrt(Fx.dist2(int(d["x"]), int(d["z"]), c[0], c[1])), 6000, "by the full 6-inch move")
	var st2 := _st2()
	_sq(st2, "0:0", "templar", 0, _line(3, -1800, 0))
	_sq(st2, "1:0", "infantry", 1, _line(5, -3600, 2500))
	assert_eq(BtBot.next_act(st2, null), {"a": "stay", "u": "0:0"}, "a melee squad in combat stays")
	var st3 := _st2()
	_sq(st3, "0:0", "infantry", 0, _line(5, -3600, 0))
	_sq(st3, "1:0", "infantry", 1, _line(5, -3600, 2500))
	assert_eq(BtBot.next_act(st3, null), {"a": "stay", "u": "0:0"}, "an even fight stays (not strictly outmatched)")


func test_move_hold_and_go_for_objectives() -> void:
	var st := _st2()
	st.add_obj(1, 0, 0)
	st.add_obj(2, -12960, -9180)
	st.add_obj(3, 12960, 9180)
	var me := _sq(st, "0:0", "infantry", 0, [[1000, 0], [-1000, 0]])
	_sq(st, "1:0", "infantry", 1, _line(5, -4000, 22000))
	assert_eq(BtBot.next_act(st, null), {"a": "stay", "u": "0:0"}, "standing on an objective holds it")
	BtMoves.go_to(st, me.models[0], 9000, 5000)
	BtMoves.go_to(st, me.models[1], 10000, 6000)
	var d := BtBot.move_decision(st, me)
	assert_eq(str(d["a"]), "smove", "off the objective: move")
	var c := BtSquads.center(me)
	assert_true(Fx.dist2(int(d["x"]), int(d["z"]), 12960, 9180) < Fx.dist2(c[0], c[1], 12960, 9180),
		"towards the closest objective it does not hold")
	var gd := Fx.isqrt(Fx.dist2(c[0], c[1], 12960, 9180))
	assert_eq(Fx.isqrt(Fx.dist2(int(d["x"]), int(d["z"]), c[0], c[1])), gd - 1200, "stops 1.2 inches short of it (within one move)")
	var a := BtBot.next_act(st, null)
	assert_eq(str(a["how"]), "move", "act how move")
	assert_eq((a["to"] as Array).size(), 2, "one point per model from plan_move")
	# no foes at all: skip
	var st2 := _st2()
	_sq(st2, "0:0", "infantry", 0, _line(5, 0, 0))
	assert_eq(BtBot.next_act(st2, null), {"a": "skip", "u": "0:0", "ph": "move"}, "no foes: skip")


func test_move_gunline_stays() -> void:
	var st := _st2()
	_sq(st, "0:0", "archer", 0, _line(5, -3600, 0))
	_sq(st, "1:0", "infantry", 1, _line(5, -3600, 20000))
	assert_eq(BtBot.next_act(st, null), {"a": "stay", "u": "0:0"}, "hv gun with the foe inside 17/20 range stays")
	var st2 := _st2()
	_sq(st2, "0:0", "infantry", 0, _line(5, -3600, 0))
	_sq(st2, "1:0", "infantry", 1, _line(5, -3600, 20000))
	assert_eq(str(BtBot.next_act(st2, null)["a"]), "smove", "no hv and the foe beyond 3/5 range: advance")
	var st3 := _st2()
	_sq(st3, "0:0", "infantry", 0, _line(5, -3600, 0))
	_sq(st3, "1:0", "infantry", 1, _line(5, -3600, 14400))
	assert_eq(BtBot.next_act(st3, null), {"a": "stay", "u": "0:0"}, "exactly 3/5 of the range: stays (inclusive)")
	var st4 := _st2()
	_sq(st4, "0:0", "infantry", 0, _line(5, -3600, 0))
	_sq(st4, "1:0", "infantry", 1, _line(5, -3600, 14410))
	assert_eq(str(BtBot.next_act(st4, null)["a"]), "smove", "one grid step beyond 3/5 of the range: moves")


# ------------------------------------------------------------------ shoot phase
func test_shoot_best_target_and_grenade() -> void:
	var st := _st2()
	st.phase = BattleState.PH_SHOOT
	var me := _sq(st, "0:0", "infantry", 0, _line(5, -3600, 0))
	var far := _sq(st, "1:0", "infantry", 1, _line(5, -3600, 20000))
	var near := _sq(st, "1:1", "infantry", 1, _line(5, 10000, 8000))
	var va := BtBot.exp_dmg(st, me, far, BattleState.HOW_SHOOT)
	var vb := BtBot.exp_dmg(st, me, near, BattleState.HOW_SHOOT)
	assert_true(BtBot.gt(vb, va), "rapid fire makes the nearer squad the better target")
	var a := BtBot.next_act(st, Rng.make("bot:0", 1))
	assert_eq(str(a["a"]), "atk", "shoots")
	assert_eq(str(a["t"]), near.id, "at the best target by exact expected damage")
	assert_eq((a["hit"] as Array).size(), int(BtCombat.atk_math(st, me, near, BattleState.HOW_SHOOT)["shots"]), "one die per shot")
	assert_eq(str(BtCombat.shot_why_not(st, me, near)["key"]), "", "the shot is legal")
	# grenade: the only foe is in combat with a squad of ours (no shot), cp 2
	var st2 := _st2(2)
	st2.phase = BattleState.PH_SHOOT
	var g := _sq(st2, "0:0", "infantry", 0, _line(2, 0, -5000))
	var foe := _sq(st2, "1:0", "infantry", 1, _line(1, 0, 0))
	_sq(st2, "0:1", "templar", 0, _line(1, 0, 2500))
	assert_eq(str(BtCombat.shot_why_not(st2, g, foe)["key"]), "target_engaged", "the foe cannot be shot")
	var a2 := BtBot.next_act(st2, Rng.make("bot:0", 1))
	assert_eq(str(a2.get("a", "")), "gren", "grenade with CP 2")
	assert_eq((a2["roll"] as Array).size(), 6, "six dice")
	assert_eq(st2.seats[0].cp, 2, "the bot does not spend the CP (the act handler does)")
	st2.seats[0].cp = 1
	assert_eq(BtBot.next_act(st2, null), {"a": "skip", "u": "0:0", "ph": "shoot"}, "CP 1: no grenade, skip")
	# no gun: skip; healer heals
	var st3 := _st2()
	st3.phase = BattleState.PH_SHOOT
	_sq(st3, "0:0", "templar", 0, _line(1, 0, 0))
	var hurt := _sq(st3, "0:1", "infantry", 0, _line(3, 0, 4000))
	var med := _sq(st3, "0:2", "medic", 0, _line(1, 0, 6000))
	_sq(st3, "1:0", "infantry", 1, _line(5, -3600, 24000))
	assert_eq(BtBot.next_act(st3, null), {"a": "skip", "u": "0:0", "ph": "shoot"}, "no gun: skip")
	st3.squad("0:0").shot = true
	var a3 := BtBot.next_act(st3, Rng.make("bot:0", 1))
	assert_eq(str(a3["a"]), "atk", "infantry in range shoots")
	hurt.shot = true
	var a4 := BtBot.next_act(st3, Rng.make("bot:0", 1))
	assert_eq([a4["a"], a4["u"], a4["t"]], ["heal", med.id, hurt.id], "the medic heals the first squad it can (lost models)")
	assert_true(BtCombat.can_heal(st3, med, hurt), "the heal is legal")
	var r: int = a4["roll"]
	assert_true(r >= 1 and r <= 6, "one die")


# ------------------------------------------------------------------ charge phase
func test_charge_only_when_worth_it() -> void:
	var st := _st2()
	st.phase = BattleState.PH_CHARGE
	var me := _sq(st, "0:0", "templar", 0, _line(1, 0, 0))
	var foe := _sq(st, "1:0", "infantry", 1, _line(5, -3600, 11000))
	var a := BtBot.next_act(st, null)
	assert_eq(a, {"a": "chg", "u": me.id, "t": foe.id}, "melee squad within 11 inches of edge charges")
	assert_eq(str(BtCombat.charge_why_not(st, me, foe)["key"]), "", "the charge is legal")
	me.ch_done = true
	assert_eq(BtBot.next_act(st, null), {}, "charged squads are passed over without an act")
	var st2 := _st2()
	st2.phase = BattleState.PH_CHARGE
	_sq(st2, "0:0", "infantry", 0, _line(5, -3600, 0))
	_sq(st2, "1:0", "infantry", 1, _line(5, -3600, 5000))
	assert_eq(BtBot.next_act(st2, null), {"a": "skip", "u": "0:0", "ph": "charge"}, "a gun squad that fights worse than it shoots skips")
	var st3 := _st2()
	st3.phase = BattleState.PH_CHARGE
	var adv := _sq(st3, "0:0", "templar", 0, _line(1, 0, 0))
	_sq(st3, "1:0", "infantry", 1, _line(5, -3600, 30000))
	adv.adv = true
	assert_eq(BtBot.next_act(st3, null), {}, "advanced squads do not charge")
	adv.adv = false
	assert_eq(BtBot.next_act(st3, null), {"a": "skip", "u": "0:0", "ph": "charge"}, "nothing in charge range: skip")


# ------------------------------------------------------------------ purity, legality, end of phase
func test_next_act_is_pure_and_legal() -> void:
	var ins: Array = fx["steps_in"]
	var bad: Array = []
	var checked := 0
	for wi: int in ins.size():
		var st := _world(ins[wi])
		for guard: int in 200:
			var before := st.digest()
			var cp := []
			for q: BattleState.Seat in st.seats:
				cp.append(q.cp)
			var a := BtBot.next_act(st, Rng.make("bot:0", wi))
			var after := []
			for q: BattleState.Seat in st.seats:
				after.append(q.cp)
			if st.digest() != before or cp != after:
				bad.append([wi, "mutated", a])
			if a.is_empty():
				break
			var s := st.squad(str(a["u"]))
			var t := st.squad(str(a.get("t", "")))
			var why := ""
			match str(a["a"]):
				"atk":
					why = str(BtCombat.shot_why_not(st, s, t)["key"])
				"chg":
					why = str(BtCombat.charge_why_not(st, s, t)["key"])
				"gren":
					why = str(BtCombat.gren_why_not(st, s, t)["key"])
					if not BtStrats.can(st, "gren", s.pl):
						why = "no_cp"
				"heal":
					why = "" if BtCombat.can_heal(st, s, t) else "cannot_heal"
			if s == null or s.side != st.turn or why != "":
				bad.append([wi, a, why])
			checked += 1
			_mark(st, a)
	assert_true(checked > 200 and bad.is_empty(), "%d bot acts: state untouched by next_act and every act legal" % checked, bad.slice(0, 5))


func test_finished_act() -> void:
	var st := BattleState.make({"seed": 9, "teams": 2, "perTeam": 2})
	st.on = true
	st.phase = BattleState.PH_MOVE
	var h := st.add_seat(0, "L0", false, false, "")
	var b := st.add_seat(0, "", true, false, "")
	st.add_seat(1, "L2", false, false, "")
	var bs := st.add_squad("1:0", "infantry", 0, 1, 5, 0)
	st.add_unit("1:0.0", bs, 1, 0, 0)
	_sq(st, "2:0", "infantry", 1, _line(1, 0, 20000))
	st.squads[1].pl = 2
	assert_eq(BtBot.finished_act(st), {}, "the bot squad still has to move")
	st.squads[0].moved = true
	assert_eq(BtBot.finished_act(st), {}, "the human team-mate has not pressed done")
	h.done = true
	assert_eq(BtBot.finished_act(st), {"a": "endph", "ph": "move"}, "bot done and every human done: endph")
	assert_false(b.done, "the bot seat's done is never set (§7 #17)")
	var p := BattleState.Pend.new()
	p.kind = BattleState.K_SHOCK
	p.stage = BattleState.S_SHOCK
	BtPend.push(st, p)
	assert_eq(BtBot.finished_act(st), {}, "a pending roll waits")
	st.pend.clear()
	st.phase = BattleState.PH_FIGHT
	assert_eq(BtBot.finished_act(st), {}, "fight is not the bot's phase")
	st.phase = BattleState.PH_CMD
	assert_eq(BtBot.finished_act(st), {}, "nor command")
	st.phase = BattleState.PH_SHOOT
	assert_eq(BtBot.finished_act(st), {}, "shoot: the bot squad has a target in range")
	bs.shot = true
	assert_eq(BtBot.finished_act(st), {"a": "endph", "ph": "shoot"}, "shoot: once it has shot, endph")
	st.turn = 1
	assert_eq(BtBot.finished_act(st), {}, "a team with no bot seat is not the bot's business")
	st.turn = 0
	st.over = true
	assert_eq(BtBot.finished_act(st), {}, "over: nothing")
	# a team of bots only is always done
	var st2 := _st2()
	_sq(st2, "0:0", "infantry", 0, _line(1, 0, 0))
	_sq(st2, "1:0", "infantry", 1, _line(1, 0, 20000))
	assert_eq(BtBot.finished_act(st2), {}, "bots-only team with work left")
	st2.squads[0].moved = true
	assert_eq(BtBot.finished_act(st2), {"a": "endph", "ph": "move"}, "bots-only team: endph once its squads acted")


# ------------------------------------------------------------------ pinned scenario
func _digest_scenario() -> BattleState:
	var st := BattleState.make({"seed": 4242, "w": 48, "d": 34, "teams": 2})
	st.on = true
	for i: int in 2:
		var q := st.add_seat(i, "", true, false, "")
		q.cp = 3
	_sq(st, "0:0", "infantry", 0, _line(5, -4000, -12000))
	_sq(st, "0:1", "templar", 0, _line(3, 6000, -9000))
	_sq(st, "0:2", "archer", 0, _line(5, -14000, -14000))
	_sq(st, "0:3", "medic", 0, _line(1, 0, -14000))
	_sq(st, "1:0", "boy", 1, _line(10, -9000, 9000))
	_sq(st, "1:1", "cavalry", 1, _line(3, 8000, 8000))
	_sq(st, "1:2", "hmg", 1, _line(2, -2000, 14000))
	st.squads[3].fx = 0
	st.squads[3].fz = 1000
	for s: BattleState.Squad in st.squads:
		if s.side == 1:
			s.fz = -1000
	BtObjectives.place(st)
	var here := {"online": false, "force": true}
	for turn: int in 4:
		st.turn = turn % 2
		st.round_no = 1 + turn / 2
		for s: BattleState.Squad in st.squads:
			if s.side == st.turn:
				s.reset_turn()
		for ph: int in [BattleState.PH_MOVE, BattleState.PH_SHOOT, BattleState.PH_CHARGE]:
			st.phase = ph
			Apply.bot_phase(st, here)
			assert_eq(BtBot.finished_act(st), {"a": "endph", "ph": st.phase_name()}, "turn %d %s ends with endph" % [turn, st.phase_name()])
	return st


func test_pinned_digest() -> void:
	var a := _digest_scenario()
	var b := _digest_scenario()
	assert_eq(a.digest(), b.digest(), "the scenario is deterministic")
	var moved := 0
	for u: BattleState.Unit in a.units:
		if u.z != -12000 and u.z != -9000 and u.z != -14000 and u.z != 9000 and u.z != 8000 and u.z != 14000:
			moved += 1
	assert_true(moved > 5, "bots moved models (%d off their start row)" % moved)
	assert_true(a.units.size() < 29, "bots killed models (%d of 29 left)" % a.units.size())
	if PINNED_DIGEST == "":
		print("      pinned digest to record: " + a.digest())
	assert_digest(a.digest(), PINNED_DIGEST, "pinned digest of the four-turn bot scenario")
