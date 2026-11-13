extends "res://tests/testing.gd"
## core/battle/roller.gd (BtRoller, R1_PORT_SPEC §1.15): the tray scheduler without the tray. Page parity of myRoll /
## iRollFor / isHumanHere on 160 sampled queues (fixtures/bot/page_samples.json, tools/record_bot.js), then hand cases:
## who rolls (offline, online, owner, timeout), strict queue order, skipped entries, the act of every kind and stage
## (dice counts, the 60-dice cut, torrent, gtg/brave/rr only with CP and never spent here, ow then the inserted ow
## attack, chr then cmove from charge_spots, chrr re-roll or keep), one act per call, no state change, flush_plan with
## force, roll_whole, stream names, and a pinned digest of a flushed charge-and-fight scenario.

const FIXTURE := "res://tests/unit/fixtures/bot/page_samples.json"
const Apply := preload("res://tests/unit/bot_act_apply.gd")
const PINNED_DIGEST := "bb60316563603aac"

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = raw if raw is Dictionary else {}


func _i(v: Variant) -> int:
	return int(v)


func _world(w: Dictionary) -> BattleState:
	var g: Dictionary = w["g"]
	var st := BattleState.make({"seed": 5, "w": 48, "d": 34, "teams": _i(g["teams"])})
	st.on = true
	st.round_no = _i(g["round"])
	st.turn = _i(g["turn"])
	st.phase = BattleState.PHASES.find(str(g["phase"]))
	for pv: Variant in w.get("seats", []):
		var p: Dictionary = pv
		var q := st.add_seat(_i(p["team"]), str(p["pid"]), _i(p["bot"]) == 1, _i(p["ai"]) == 1, "")
		q.cp = _i(p["cp"])
	for qv: Variant in w["squads"]:
		var q: Dictionary = qv
		st.add_squad(str(q["id"]), str(q["k"]), _i(q["side"]), _i(q["pl"]), _i(q["n0"]), 0)
	for uv: Variant in w["units"]:
		var u: Dictionary = uv
		st.add_unit(str(u["id"]), st.squad(str(u["sq"])), _i(u["hp"]), _i(u["x"]), _i(u["z"]))
	return st


func _st(cp: int = 2) -> BattleState:
	var st := BattleState.make({"seed": 21, "w": 48, "d": 34, "teams": 2})
	st.on = true
	st.phase = BattleState.PH_SHOOT
	for i: int in 2:
		var q := st.add_seat(i, "L%d" % i, false, false, "")
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


func _pend(st: BattleState, kind: int, stage: int, u: String, t: String, att: int, def: int) -> BattleState.Pend:
	var p := BattleState.Pend.new()
	p.kind = kind
	p.stage = stage
	p.u = u
	p.t = t
	p.att = att
	p.def = def
	BtPend.push(st, p)
	return p


const OFF := {"online": false}


# ------------------------------------------------------------------ page parity
func test_next_matches_page() -> void:
	var ins: Array = fx["roll_in"]
	var outs: Array = fx["roll"]
	var bad: Array = []
	var found := 0
	for i: int in ins.size():
		var q: Dictionary = ins[i]
		var st := _world(q["w"])
		for ev: Variant in q["q"]:
			var e: Dictionary = ev
			var p := _pend(st, BattleState.KINDS.find(str(e["kind"])), BattleState.STAGES.find(str(e["stage"])), str(e["u"]),
				str(e["t"]), _i(e["att"]), _i(e["def"]))
			p.ow = _i(e["ow"]) == 1
		var net: Array = q["net"]
		var here := {"online": _i(net[0]) == 1, "owner": _i(net[1]) == 1, "pid": str(net[2]),
			"since_ok": _i(q["age"]) > 25000}
		var p := BtRoller.next(st, here)
		var got := [-1, 0]
		if p != null:
			got = [st.pend.find(p), 1 if BtRoller.human_here(st, BtPend.roller_of(p), here) else 0]
			found += 1
		var want: Array = outs[i]
		if got != [_i(want[0]), _i(want[1])]:
			bad.append([i, q["q"], net, q["age"], want, got])
	assert_true(ins.size() >= 150 and found > 50 and bad.is_empty(),
		"next equals myRoll on %d sampled queues (%d with an entry)" % [ins.size(), found], bad.slice(0, 3))


# ------------------------------------------------------------------ who rolls
func test_rolls_here() -> void:
	var st := BattleState.make({"seed": 1, "teams": 2})
	st.add_seat(0, "pa", false, false, "")
	st.add_seat(1, "pb", true, false, "")
	st.add_seat(1, "pc", false, true, "")
	var on := {"online": true, "owner": false, "pid": "pa"}
	var own := {"online": true, "owner": true, "pid": "pz"}
	var own_late := {"online": true, "owner": true, "pid": "pz", "since_ok": true}
	var other_late := {"online": true, "owner": false, "pid": "pz", "since_ok": true}
	assert_true(BtRoller.rolls_here(st, 0, OFF) and BtRoller.rolls_here(st, 1, OFF) and BtRoller.rolls_here(st, 2, OFF),
		"offline: this device rolls for everyone")
	assert_true(BtRoller.rolls_here(st, 0, on), "online: my own seat")
	assert_false(BtRoller.rolls_here(st, 1, on), "online, not owner: not the bot's")
	assert_true(BtRoller.rolls_here(st, 1, own) and BtRoller.rolls_here(st, 2, own), "the owner rolls for bot and Claude seats")
	assert_false(BtRoller.rolls_here(st, 0, own), "the owner does not roll for a human who is still in time")
	assert_true(BtRoller.rolls_here(st, 0, own_late), "the owner takes over after OWNER_WAIT")
	assert_false(BtRoller.rolls_here(st, 0, other_late), "a non-owner never takes over")
	assert_true(BtRoller.rolls_here(st, 9, OFF), "a missing seat is rolled like a bot (offline)")
	assert_false(BtRoller.rolls_here(st, 9, on), "a missing seat online: owner only")
	assert_true(BtRoller.human_here(st, 0, on) and not BtRoller.human_here(st, 1, OFF) and not BtRoller.human_here(st, 2, OFF),
		"human_here: a human seat on this device only")
	var p := _pend(st, BattleState.K_ATK, BattleState.S_SAVE, "x", "y", 1, 0)
	assert_eq(BtRoller.stream_name(st, p, on), "dice:0", "a human's own save rolls on dice:<seat>")
	p.stage = BattleState.S_HIT
	assert_eq(BtRoller.stream_name(st, p, own), "bot:1", "a bot's hit rolls on bot:<seat>")
	p.att = 0
	assert_eq(BtRoller.stream_name(st, p, own_late), "bot:0", "the owner rolling for a silent human uses bot:<seat>")


func test_queue_order_and_skips() -> void:
	var st := _st()
	st.seats[1].pid = "L1"
	_sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	_sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var dead := st.add_squad("1:9", "infantry", 1, 1, 5, 0)
	var here := {"online": true, "owner": false, "pid": "L0"}
	var theirs := _pend(st, BattleState.K_ATK, BattleState.S_HIT, "1:0", "0:0", 1, 0)
	var mine := _pend(st, BattleState.K_ATK, BattleState.S_HIT, "0:0", "1:0", 0, 1)
	assert_true(BtRoller.next(st, here) == null, "the first entry is someone else's: wait, even with mine behind it")
	theirs.stage = BattleState.S_SAVE
	assert_true(BtRoller.next(st, here) == theirs, "their attack at save is mine to roll (the defender)")
	theirs.t = dead.id
	assert_true(BtRoller.next(st, here) == mine, "an attack on a wiped squad is skipped")
	theirs.t = "0:0"
	theirs.u = dead.id
	assert_true(BtRoller.next(st, here) == theirs, "a dead attacker past the hit stage still gets its save rolled")
	theirs.stage = BattleState.S_HIT
	assert_true(BtRoller.next(st, here) == mine, "a dead attacker at hit is skipped")
	st.pend.clear()
	var c := _pend(st, BattleState.K_CHG, BattleState.S_OWATK, "0:0", "1:0", 0, 1)
	var ow := _pend(st, BattleState.K_ATK, BattleState.S_HIT, "1:0", "0:0", 1, 0)
	ow.ow = true
	st.pend.remove_at(1)
	st.pend.insert(0, ow)
	assert_true(BtRoller.next(st, OFF) == ow, "the overwatch attack sits before its charge and is rolled first")
	st.pend.remove_at(0)
	st.pend.append(ow)
	assert_true(BtRoller.next(st, OFF) == ow, "a charge waiting on overwatch is passed over")
	st.pend.remove_at(1)
	assert_true(BtRoller.next(st, OFF) == c, "with no overwatch left the waiting charge is rolled as a charge")
	assert_eq(str(BtRoller.roll(st, c, {}, Rng.make("dice:0", 1))[0]["a"]), "chr", "and it rolls 2d6")
	c.t = dead.id
	assert_true(BtRoller.next(st, OFF) == null, "a charge on a wiped squad is skipped")
	st.pend.clear()
	assert_true(BtRoller.next(st, OFF) == null, "empty queue: null")


func test_flush_plan_force() -> void:
	var st := _st()
	st.seats[1].pid = "L1"
	_sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	_sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var p := _pend(st, BattleState.K_ATK, BattleState.S_HIT, "1:0", "0:0", 1, 0)
	var here := {"online": true, "owner": false, "pid": "L0"}
	assert_true(BtRoller.flush_plan(st, here) == null, "not forced: nothing of mine")
	here["force"] = true
	assert_true(BtRoller.flush_plan(st, here) == p, "forced: the first entry is rolled here")


# ------------------------------------------------------------------ the acts
func test_attack_acts() -> void:
	var st := _st(2)
	var a := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var b := _sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var dice := Rng.make("dice:0", 7)
	var p := BtPend.mk_atk(st, a, b, BattleState.HOW_SHOOT)
	var before := st.digest()
	var acts := BtRoller.roll(st, p, {}, dice)
	assert_eq(acts.size(), 1, "one act per call")
	assert_eq(st.digest(), before, "roll does not change the state")
	var hit: Dictionary = acts[0]
	assert_eq([hit["a"], hit["u"], hit["t"], hit["how"], (hit["hit"] as Array).size()], ["atk", "0:0", "1:0", "shoot", p.shots],
		"hit: atk with one die per shot")
	p.shots = 75
	assert_eq((BtRoller.roll(st, p, {}, dice)[0]["hit"] as Array).size(), 60, "never more than 60 dice (the rest pad on every device)")
	p.shots = 10
	p.tr = true
	assert_eq(BtRoller.roll(st, p, {}, dice)[0]["hit"], [], "torrent: no hit dice")
	p.tr = false
	Apply.apply(st, {"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 6, 6, 6, 6, 6, 6, 6]})
	assert_eq(p.stage, BattleState.S_WOUND, "applied: stage wound")
	var w := BtRoller.roll(st, p, {}, dice)[0]
	assert_eq([w["a"], (w["wound"] as Array).size()], ["wnd", BtPend.wound_dice(p)], "wound: wnd with wound_dice dice")
	Apply.apply(st, {"a": "wnd", "u": "0:0", "t": "1:0", "wound": [6, 6, 6, 6, 6, 6, 6, 6, 6, 6]})
	assert_eq(p.stage, BattleState.S_SAVE, "stage save")
	assert_eq(BtPend.roller_of(p), 1, "the defender rolls the save")
	var s := BtRoller.roll(st, p, BtBot.choice(st, p), dice)[0]
	assert_eq([s["a"], (s["save"] as Array).size()], ["sav", BtPend.save_dice(p)], "save: sav with save_dice dice")
	assert_eq(s["gtg"], 0, "a human seat's auto choice never takes gtg")
	st.seats[1].bot = true
	var c := BtBot.choice(st, p)
	assert_true(bool(c["gtg"]), "a bot takes gtg with cp 2, 10 wounds, sv 5, infantry")
	assert_eq(BtRoller.roll(st, p, c, dice)[0]["gtg"], 1, "gtg 1 when the team can use it")
	assert_eq(st.seats[1].cp, 2, "the roller never spends CP")
	st.used[BtStrats.key(st, "gtg", 1)] = true
	assert_eq(BtRoller.roll(st, p, {"gtg": true}, dice)[0]["gtg"], 0, "gtg 0 when the team already used it this phase")
	p.stage = BattleState.S_DONE
	assert_eq(BtRoller.roll(st, p, {}, dice), [] as Array[Dictionary], "a finished entry: no act")
	assert_eq(BtRoller.roll(st, null, {}, dice), [] as Array[Dictionary], "null: no act")


func test_shock_and_rez_acts() -> void:
	var st := _st(2)
	_sq(st, "0:0", "infantry", 0, _line(2, 0, 0))
	var dice := Rng.make("dice:0", 3)
	var p := _pend(st, BattleState.K_SHOCK, BattleState.S_SHOCK, "0:0", "", 0, -1)
	p.need = 6
	var a := BtRoller.roll(st, p, {}, dice)[0]
	assert_eq([a["a"], a["u"], (a["roll"] as Array).size(), a["brave"]], ["shock", "0:0", 2, 0], "shock: two dice")
	var b := BtRoller.roll(st, p, {"brave": true}, dice)[0]
	assert_eq([b["roll"], b["brave"]], [[], 1], "brave: no dice")
	st.seats[0].cp = 0
	var c := BtRoller.roll(st, p, {"brave": true}, dice)[0]
	assert_eq([(c["roll"] as Array).size(), c["brave"]], [2, 0], "brave without CP: rolls instead")
	var r := _pend(st, BattleState.K_REZ, BattleState.S_REZ, "0:0", "", 0, -1)
	r.n = 3
	var z := BtRoller.roll(st, r, {}, dice)[0]
	assert_eq([z["a"], (z["roll"] as Array).size()], ["rez", 3], "rez: n dice")
	r.n = 14
	assert_eq((BtRoller.roll(st, r, {}, dice)[0]["roll"] as Array).size(), 10, "rez: at most 10")


func test_charge_chain_one_act_per_call() -> void:
	var st := _st(3)
	st.phase = BattleState.PH_CHARGE
	st.seats[1].bot = true
	var a := _sq(st, "0:0", "templar", 0, _line(3, 0, 0))
	var b := _sq(st, "1:0", "infantry", 1, _line(5, -3600, 6000))
	Apply.apply(st, {"a": "chg", "u": "0:0", "t": "1:0"})
	var p := BtPend.pend_at(st, "0:0", "1:0", BattleState.K_CHG)
	assert_eq(p.stage, BattleState.S_OW, "the infantry can overwatch")
	assert_true(BtRoller.next(st, OFF) == p, "the charge waits on the defender's decision")
	assert_eq(BtPend.roller_of(p), 1, "the defender decides")
	var c := BtBot.choice(st, p)
	assert_true(bool(c["yes"]), "a bot with CP 3 overwatches")
	var acts := BtRoller.roll(st, p, c, st.rng("bot:1"))
	assert_eq(acts.size(), 1, "ow: one act")
	assert_eq([acts[0]["a"], acts[0]["use"]], ["ow", 1], "ow use 1")
	Apply.apply(st, acts[0])
	var o := BtRoller.next(st, OFF)
	assert_true(o != null and o.kind == BattleState.K_ATK and o.ow and o.t == "0:0", "next: the inserted overwatch attack")
	assert_eq(BtPend.roller_of(o), 1, "rolled by the same seat")
	assert_eq(st.pend.find(o), st.pend.find(p) - 1, "before its charge")
	var oa := BtRoller.roll(st, o, BtBot.choice(st, o), st.rng("bot:1"))[0]
	assert_eq([oa["a"], oa["how"]], ["atk", "ow"], "atk how ow")
	Apply.apply(st, oa)
	Apply.flush(st, {"online": false, "force": false, "pid": ""})
	# the overwatch resolved, the charge was promoted and rolled; whatever happened, the chain went one act at a time
	assert_true(BtPend.pend_at(st, "0:0", "1:0", BattleState.K_CHG) == null, "the flush finished the charge")
	assert_eq(st.seats[1].cp, 2, "overwatch cost the defender 1 CP (spent by the act handler)")
	assert_true(a.ch_done, "the charger is done")
	assert_true(b != null, "built")


func test_chr_cmove_and_chrr() -> void:
	var st := _st(1)
	st.phase = BattleState.PH_CHARGE
	var a := _sq(st, "0:0", "templar", 0, _line(3, 0, 0))
	var b := _sq(st, "1:0", "cavalry", 1, _line(3, -1800, 8000))
	var dice := Rng.make("dice:0", 11)
	var p := BtPend.declare_charge(st, a, b, [] as Array[Dictionary])
	assert_eq(p.stage, BattleState.S_CHARGE, "cavalry has no gun: no overwatch")
	var r := BtRoller.roll(st, p, {}, dice)[0]
	assert_eq([r["a"], (r["roll"] as Array).size(), r["rr"], r["keep"]], ["chr", 2, 0, 0], "charge: chr with two dice")
	Apply.apply(st, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [6, 6], "rr": 0, "keep": 0})
	assert_eq(p.stage, BattleState.S_MOVE, "12 is enough: stage move")
	var m := BtRoller.roll(st, p, {}, dice)
	assert_eq(m.size(), 1, "move: one act")
	var spots := BtMoves.pts(BtMoves.charge_spots(st, a, b, 12000))
	assert_eq([m[0]["a"], m[0]["to"]], ["cmove", spots], "cmove to charge_spots for the roll's sum")
	Apply.apply(st, m[0])
	assert_true(a.charged and BtSquads.is_engaged(st, a), "the charger is in combat")
	# a failed charge with CP: chrr; yes and CP -> re-roll, no -> keep the old roll
	var st2 := _st(1)
	st2.phase = BattleState.PH_CHARGE
	var a2 := _sq(st2, "0:0", "templar", 0, _line(3, 0, 0))
	var b2 := _sq(st2, "1:0", "cavalry", 1, _line(3, -1800, 8000))
	var p2 := BtPend.declare_charge(st2, a2, b2, [] as Array[Dictionary])
	Apply.apply(st2, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [1, 1], "rr": 0, "keep": 0})
	assert_eq(p2.stage, BattleState.S_CHRR, "missed with CP left: chrr")
	var y := BtRoller.roll(st2, p2, {"yes": true}, dice)[0]
	assert_eq([y["a"], y["rr"], y["keep"], (y["roll"] as Array).size()], ["chr", 1, 0, 2], "yes: re-roll two new dice")
	assert_eq(st2.seats[0].cp, 1, "not spent by the roller")
	var k := BtRoller.roll(st2, p2, {"yes": false}, dice)[0]
	assert_eq([k["rr"], k["keep"], k["roll"]], [0, 1, [1, 1]], "no: keep with the old roll")
	st2.used[BtStrats.key(st2, "rr", 0)] = true
	assert_eq(BtRoller.roll(st2, p2, {"yes": true}, dice)[0]["keep"], 1, "yes but the team used its re-roll: keep")
	st2.used.clear()
	Apply.apply(st2, y)
	assert_eq(st2.seats[0].cp, 0, "the act handler spent the CP")
	assert_true(p2.stage == BattleState.S_MOVE or p2.stage == BattleState.S_DONE, "the re-roll resolved the charge")


func test_roll_whole() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var b := _sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var c := _sq(st, "1:1", "cavalry", 1, _line(3, 0, 60000))
	var n: int = int(BtCombat.atk_math(st, a, b, BattleState.HOW_SHOOT)["shots"])
	var r := BtRoller.roll_whole(st, a, b, BattleState.HOW_SHOOT, Rng.make("dice:0", 1))
	assert_eq([(r["hit"] as Array).size(), (r["wound"] as Array).size(), (r["save"] as Array).size()], [n, 2 * n, 2 * n],
		"rollFor: n hit, 2n wound, 2n save dice")
	var z := BtRoller.roll_whole(st, c, a, BattleState.HOW_SHOOT, Rng.make("dice:0", 1))
	assert_eq([z["hit"], z["wound"], z["save"]], [[], [], []], "no weapon: empty")
	var f := _sq(st, "0:1", "flamer", 0, _line(5, 0, 3000))
	var t := BtRoller.roll_whole(st, f, b, BattleState.HOW_SHOOT, Rng.make("dice:0", 1))
	assert_eq(t["hit"], [], "torrent: no hit dice")
	assert_true((t["wound"] as Array).size() > 0, "but wound dice")


# ------------------------------------------------------------------ pinned scenario
func _scenario() -> BattleState:
	var st := BattleState.make({"seed": 777, "w": 48, "d": 34, "teams": 2})
	st.on = true
	st.add_seat(0, "", true, false, "").cp = 3
	st.add_seat(1, "", true, false, "").cp = 3
	_sq(st, "0:0", "templar", 0, _line(3, -2000, -3000))
	_sq(st, "0:1", "cavalry", 0, _line(3, 6000, -4000))
	_sq(st, "0:2", "hmg", 0, _line(2, -9000, -12000))
	_sq(st, "1:0", "infantry", 1, _line(5, -5000, 6000))
	_sq(st, "1:1", "heavy", 1, _line(3, 5000, 7000))
	var here := {"online": false, "force": true}
	for ph: int in [BattleState.PH_SHOOT, BattleState.PH_CHARGE]:
		st.phase = ph
		Apply.bot_phase(st, here)
	# the fight: every engaged squad of side 0 fights once, rolled through the roller
	st.phase = BattleState.PH_FIGHT
	for s: BattleState.Squad in st.alive_squads():
		if s.side != 0:
			continue
		var e := BtSquads.engaged_with(st, s)
		if e.is_empty():
			continue
		var p := BtPend.mk_atk(st, s, e[0], BattleState.HOW_FIGHT)
		if p != null:
			Apply.flush(st, here)
	return st


func test_pinned_digest() -> void:
	var a := _scenario()
	var b := _scenario()
	assert_eq(a.digest(), b.digest(), "the flushed scenario is deterministic")
	assert_true(a.pend.is_empty(), "the flush left nothing pending")
	var charged := 0
	for s: BattleState.Squad in a.squads:
		if s.charged:
			charged += 1
	assert_true(charged > 0, "at least one charge reached (%d)" % charged)
	if PINNED_DIGEST == "":
		print("      pinned digest to record: " + a.digest())
	assert_digest(a.digest(), PINNED_DIGEST, "pinned digest of the charge-and-fight scenario")
