extends "res://tests/testing.gd"
## core/battle/pend.gd (BtPend, R1_PORT_SPEC §1.10): the one pending queue. Page parity from
## fixtures/pend/page_samples.json (tools/record_pend.js: whole attacks stage by stage, nextVictim, dealDamage, gloryHeal,
## the charge need), then hand cases for every applier: hit -> wound -> save, torrent, su, lethal, slay, mortal spill,
## shields, victims, re-roll, gtg, overwatch before its charge and the promotion after it, charge rolls, cmove, grenade,
## heal and revive, rez, shock, adv, padding from fallback:<seq>:<stage>, prune and apply_whole; a pinned digest.

const FIXTURE := "res://tests/unit/fixtures/pend/page_samples.json"
## Digest of the fixed scenario in _digest_scenario; changes only on purpose.
const PINNED_DIGEST := "f42c2a2b8764eaba"
const SHOOT := BattleState.HOW_SHOOT
const FIGHT := BattleState.HOW_FIGHT
const OW := BattleState.HOW_OW

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = _iv(raw) if raw is Dictionary else {}


# ------------------------------------------------------------------ helpers
## JSON numbers come back as floats: every whole number becomes an int (recursively).
func _iv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v)
		TYPE_ARRAY:
			var a: Array = []
			for x: Variant in v:
				a.append(_iv(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _iv(v[k])
			return d
	return v


func _st(round_no: int = 1, turn: int = 0) -> BattleState:
	var st := BattleState.make({"seed": 7, "w": 60, "teams": 2})
	st.round_no = round_no
	st.turn = turn
	return st


func _seats(st: BattleState, cp: int) -> void:
	for i: int in 2:
		var p := st.add_seat(i, "L%d" % i, false, false, "")
		p.cp = cp


func _sq(st: BattleState, id: String, k: String, side: int, pts: Array, hp: int = 0) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, side, int(t.get("n", 1)), 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, hp if hp > 0 else int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


func _line(n: int, x0: int, z: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append([x0 + i * 1700, z])
	return out


## A bare attack entry, queued.
func _atk(st: BattleState, u: String, t: String, shots: int, need: int, wneed: int, sv: int) -> BattleState.Pend:
	var p := BattleState.Pend.new()
	p.kind = BattleState.K_ATK
	p.stage = BattleState.S_HIT
	p.u = u
	p.t = t
	p.att = 0
	p.def = 1
	p.shots = shots
	p.need = need
	p.wneed = wneed
	p.sv = sv
	BtPend.push(st, p)
	return p


func _units(st: BattleState) -> Array:
	var out: Array = []
	for u: BattleState.Unit in st.units:
		out.append([u.id, u.hp])
	return out


func _waiting(st: BattleState) -> Array:
	var out: Array = []
	for b: BattleState.Unit in st.bodies:
		if b.wait:
			out.append(b.id)
	return out


func _keys(st: BattleState) -> Array:
	var out: Array = []
	for l: Dictionary in st.log_lines:
		out.append(l["key"])
	return out


func _deaths(out: Array[Dictionary]) -> Array:
	var r: Array = []
	for e: Dictionary in out:
		if Events.id_of(e) == Events.Id.DEATH:
			r.append(e["uid"])
	return r


func _sixes(n: int) -> Array:
	var a: Array = []
	for i: int in n:
		a.append(6)
	return a


## The fixture's world (squads in order, units in the given order).
func _world(w: Dictionary) -> BattleState:
	var g: Dictionary = w["g"]
	var st := _st(int(g["round"]), int(g["turn"]))
	for q: Dictionary in w["squads"]:
		var s := st.add_squad(str(q["id"]), str(q["k"]), int(q["side"]), int(q["pl"]), int(q["n0"]), int(q["vs"]))
		s.wind_n = int(q["wn"])
	for u: Array in w["units"]:
		st.add_unit(str(u[0]), st.squad(str(u[1])), int(u[4]), int(u[5]), int(u[6]))
	return st


func _snap(p: BattleState.Pend) -> Array:
	return [p.stage, p.hits, p.lethal, p.wounds, p.mortal, p.slay, p.saved, p.sv, 1 if p.rr else 0, 1 if p.gtg else 0, Array(p.hit_r)]


# ------------------------------------------------------------------ page parity
func test_page_attacks() -> void:
	var cases: Array = fx.get("attacks", [])
	assert_true(cases.size() >= 300, "%d whole attacks sampled from the page" % cases.size())
	var bad: Array = []
	var hows := {"shoot": SHOOT, "fight": FIGHT, "ow": OW}
	for ci: int in cases.size():
		var c: Dictionary = cases[ci]
		var inp: Dictionary = c["in"]
		var res: Dictionary = c["out"]
		var st := _world(inp["w"])
		var e: Dictionary = inp["p"]
		var p := _atk(st, str(e["u"]), str(e["t"]), int(e["shots"]), int(e["need"]), int(e["wneed"]), int(e["sv"]))
		p.how = int(hows[str(e["how"])])
		p.melee = p.how == FIGHT
		p.ow = p.how == OW
		p.dmg = int(e["dmg"])
		p.su = int(e["su"])
		p.tr = bool(e["tr"])
		p.lh = bool(e["lh"])
		p.dw = bool(e["dw"])
		p.heel = bool(e["heel"])
		p.mk = bool(e["mk"])
		var dice: Dictionary = res["dice"]
		var out: Array[Dictionary] = []
		var steps: Array = []
		BtPend.apply_hit(st, p, dice["hit"], out)
		steps.append(_snap(p))
		if dice.has("rr"):
			BtPend.apply_reroll(st, p, int(dice["rr"]), out)
			steps.append(_snap(p))
		if dice.has("wound"):
			BtPend.apply_wnd(st, p, dice["wound"], out)
			steps.append(_snap(p))
		if dice.has("save"):
			BtPend.apply_sav(st, p, dice["save"], bool(dice["gtg"]), out)
			steps.append(_snap(p))
		var t := st.squad(p.t)
		var s := st.squad(p.u)
		var end: Dictionary = res["end"]
		var kills: Array = []
		for k: Array in end["kills"]:
			kills.append_array(k)
		var got := {"steps": steps, "units": _units(st), "vs": t.vs, "wn": t.wind_n, "fallen": _waiting(st), "kills": _deaths(out),
			"mk": 1 if t.mk == st.mark_key() else 0, "shot": 1 if s.shot else 0, "fought": 1 if s.fought else 0,
			"pend": st.pend.size(), "short": _keys(st).has("dice_short")}
		var want := {"steps": res["steps"], "units": end["units"], "vs": end["vs"], "wn": end["wn"], "fallen": end["fallen"],
			"kills": kills, "mk": end["mk"], "shot": end["shot"], "fought": end["fought"], "pend": end["pend"], "short": false}
		if got != want:
			bad.append([ci, got, want])
	assert_true(bad.is_empty(), "every attack equals the page stage by stage and in the end (%d cases)" % cases.size(), bad.slice(0, 2))


func test_page_victims() -> void:
	var cases: Array = fx.get("victims", [])
	assert_true(cases.size() >= 200, "%d nextVictim samples" % cases.size())
	var bad: Array = []
	for ci: int in cases.size():
		var c: Dictionary = cases[ci]
		var inp: Dictionary = c["in"]
		var st := _world(inp["w"])
		var from: BattleState.Squad = null if inp["from"] == null else st.squad(str(inp["from"]))
		var m := BtPend.next_victim(st.squad(str(inp["t"])), from)
		var got: Variant = m.id if m != null else null
		if got != c["out"]:
			bad.append([ci, got, c["out"]])
	assert_true(bad.is_empty(), "next_victim equals the page (hurt first, nearest to the centre, from null and from empty)", bad.slice(0, 5))


func test_page_damage() -> void:
	var cases: Array = fx.get("damage", [])
	assert_true(cases.size() >= 150, "%d dealDamage samples" % cases.size())
	var bad: Array = []
	for ci: int in cases.size():
		var c: Dictionary = cases[ci]
		var inp: Dictionary = c["in"]
		var res: Dictionary = c["out"]
		var st := _world(inp["w"])
		var t := st.squad(str(inp["t"]))
		var vs0 := t.vs
		var out: Array[Dictionary] = []
		var k := BtPend.deal_damage(st, t, st.squad(str(inp["from"])), int(inp["n"]), int(inp["dmg"]), int(inp["spill"]) != 0, out)
		var ids: Array = []
		for m: BattleState.Unit in k:
			ids.append(m.id)
		var got := [k.size(), ids, vs0 - t.vs, _units(st), t.vs, _waiting(st), t.wind_n]
		var want := [res["n"], res["killed"], res["sh"], res["units"], res["vs"], res["fallen"], res["wn"]]
		if got != want:
			bad.append([ci, got, want])
	assert_true(bad.is_empty(), "deal_damage equals the page (kill order, units, shields, wind falls)", bad.slice(0, 3))


func test_page_glory() -> void:
	var cases: Array = fx.get("glory", [])
	assert_true(cases.size() >= 50, "%d gloryHeal samples" % cases.size())
	var bad: Array = []
	for ci: int in cases.size():
		var c: Dictionary = cases[ci]
		var inp: Dictionary = c["in"]
		var st := _world(inp["w"])
		var out: Array[Dictionary] = []
		var got := BtAbilities.glory_heal(st, st.squad(str(inp["s"])), int(inp["n"]), out)
		if [got, _units(st)] != [c["out"]["got"], c["out"]["units"]]:
			bad.append([ci, got, _units(st), c["out"]])
	assert_true(bad.is_empty(), "glory_heal equals the page", bad.slice(0, 3))


func test_page_charge_need() -> void:
	var cases: Array = fx.get("charge", [])
	assert_true(cases.size() >= 150, "%d declareCharge samples" % cases.size())
	var bad: Array = []
	for ci: int in cases.size():
		var c: Dictionary = cases[ci]
		var inp: Dictionary = c["in"]
		var st := _world(inp["w"])
		var s := st.squad(str(inp["s"]))
		var t := st.squad(str(inp["t"]))
		var out: Array[Dictionary] = []
		var p := BtPend.declare_charge(st, s, t, out)
		if p.need != int(c["out"]) or BtPend.charge_need(s, t) != p.need or not s.ch_done:
			bad.append([ci, p.need, c["out"]])
	assert_true(bad.is_empty(), "the charge need equals the page exactly (whole-inch edges and one grid step either side)", bad.slice(0, 5))


# ------------------------------------------------------------------ queue
func test_queue_find_push_remove_roller() -> void:
	var st := _st()
	var a := _atk(st, "0:0", "1:0", 1, 4, 4, 4)
	var b := _atk(st, "0:0", "1:1", 1, 4, 4, 4)
	var c := BattleState.Pend.new()
	c.kind = BattleState.K_SHOCK
	c.stage = BattleState.S_SHOCK
	c.u = "0:0"
	c.att = 0
	BtPend.push(st, c)
	assert_eq(BtPend.pend_at(st, "0:0", "", BattleState.K_ATK), a, "pend_at: first match, any target")
	assert_eq(BtPend.pend_at(st, "0:0", "1:1", BattleState.K_ATK), b, "a named target")
	assert_eq(BtPend.pend_at(st, "0:0", "", BattleState.K_SHOCK), c, "by kind")
	assert_eq(BtPend.pend_at(st, "0:0", "", -1), a, "any kind")
	assert_eq(BtPend.pend_at(st, "0:1", "", -1), null, "no entry")
	BtPend.remove(st, a)
	BtPend.remove(st, a)
	assert_eq(st.pend, [b, c] as Array[BattleState.Pend], "remove takes it out once, a second remove is harmless")
	assert_eq([BtPend.roller_of(b), BtPend.roller_of(c)], [0, 0], "hit and shock: the attacker rolls")
	b.stage = BattleState.S_SAVE
	assert_eq(BtPend.roller_of(b), 1, "save: the defender rolls")
	var g := BattleState.Pend.new()
	g.kind = BattleState.K_CHG
	g.stage = BattleState.S_OW
	g.att = 0
	g.def = 1
	assert_eq(BtPend.roller_of(g), 1, "the overwatch decision is the defender's")
	g.stage = BattleState.S_CHARGE
	assert_eq(BtPend.roller_of(g), 0, "the charge roll is the charger's")


func test_pad_and_fallback() -> void:
	var st := _st()
	st.act_seq = 12
	var out: Array[Dictionary] = []
	assert_eq(BtPend.pad(st, [3, 4, 5], 2, "hit", out), PackedInt32Array([3, 4]), "extra dice are cut")
	assert_eq(BtPend.pad(st, [9, 0, "x", -2], 4, "hit", out), PackedInt32Array([6, 1, 1, 1]), "values are clamped to 1..6, non-numbers are 1")
	assert_true(_keys(st).is_empty(), "no log while enough dice came")
	var g := Rng.make("fallback:12:wound", st.seed)
	var want := PackedInt32Array([2])
	for i: int in 3:
		want.append(g.d6())
	assert_eq(BtPend.pad(st, [2], 4, "wound", out), want, "a short array is padded from fallback:<seq>:<stage>")
	assert_eq(st.log_lines[st.log_lines.size() - 1], {"key": "dice_short", "args": ["wound", 1, 4]}, "a short sender is logged")
	assert_eq(BtPend.pad(st, [2], 4, "wound", out), want, "every device pads the same way (a fresh stream per call)")
	var sixty := _sixes(60)
	var n0 := st.log_lines.size()
	var got := BtPend.pad(st, sixty, 64, "hit", out)
	var h := Rng.make("fallback:12:hit", st.seed)
	var tail := PackedInt32Array()
	for i: int in 4:
		tail.append(h.d6())
	assert_eq([got.size(), got.slice(60)], [64, tail], "beyond 60 the fallback stream fills in")
	assert_eq(st.log_lines.size(), n0, "and that is normal: no dice_short")
	BtPend.pad(st, _sixes(59), 64, "hit", out)
	assert_eq(st.log_lines.size(), n0 + 1, "59 of 64 is a sender bug")
	assert_eq(BtPend.pad(st, [], 0, "save", out), PackedInt32Array(), "nothing needed, nothing drawn")


# ------------------------------------------------------------------ attacks
func test_mk_atk() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 10000))
	var p := BtPend.mk_atk(st, s, t, SHOOT)
	var m := BtCombat.atk_math(st, s, t, SHOOT)
	assert_true(p != null and st.pend[st.pend.size() - 1] == p, "mk_atk queues the attack last")
	assert_eq([p.kind, p.stage, p.how, p.u, p.t, p.att, p.def, p.melee, p.ow], [BattleState.K_ATK, BattleState.S_HIT, SHOOT, "0:0", "1:0", 0, 1, false, false], "who and how")
	assert_eq([p.shots, p.need, p.wneed, p.sv, p.dmg, p.su], [m["shots"], m["need"], m["wneed"], m["sv"], m["dmg"], m["su"]], "the numbers of atk_math")
	var o := BtPend.mk_atk(st, t, s, OW)
	assert_true(o.ow and not o.melee and o.need == 6, "overwatch: ow, 6s")
	var hop := _sq(st, "0:1", "hoplite", 0, [[30000, 0]])
	assert_eq(BtPend.mk_atk(st, hop, t, SHOOT), null, "no gun: null")
	var far := _sq(st, "1:1", "heavy", 1, [[0, 80000]])
	assert_eq(BtPend.mk_atk(st, s, far, SHOOT), null, "nobody in range (0 shots): null")
	assert_eq(st.pend.size(), 2, "nothing queued for a null")


func test_hit_wound_save() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var p := _atk(st, s.id, t.id, 6, 4, 4, 5)
	p.how = SHOOT
	BtPend.apply_hit(st, p, [4, 5, 6, 3, 2, 1], out)
	assert_eq([p.hits, p.lethal, p.stage, s.shot, s.fought], [3, 0, BattleState.S_WOUND, true, false], "three hits, the shooter has shot")
	BtPend.apply_hit(st, p, [6, 6, 6, 6, 6, 6], out)
	assert_eq(p.hits, 3, "a second hit act at stage wound is ignored")
	BtPend.apply_wnd(st, p, [4, 1, 6, 6], out)
	assert_eq([Array(p.wound_r), p.wounds, BtPend.save_dice(p), p.stage], [[4, 1, 6], 2, 2, BattleState.S_SAVE], "wound dice cut to the hits, two to save")
	BtPend.apply_sav(st, p, [5, 2], false, out)
	assert_eq([p.saved, p.stage, st.squad_alive(t), st.pend.size()], [1, BattleState.S_DONE, 4, 0], "one saved, one infantry falls, the entry is gone")
	var last: Dictionary = st.log_lines[st.log_lines.size() - 1]
	assert_eq(last, {"key": "atk_done", "args": ["0:0", "1:0", "shoot", 3, 6, 2, 1, 1, 0, 0, 0, 0, 0]}, "the result line")
	# no hits: done at once; no wounds: done; sv 7: no save roll
	var q := _atk(st, s.id, t.id, 2, 4, 4, 5)
	BtPend.apply_hit(st, q, [1, 2], out)
	assert_eq(q.stage, BattleState.S_DONE, "no hits: finished")
	q = _atk(st, s.id, t.id, 2, 4, 4, 5)
	BtPend.apply_hit(st, q, [5, 5], out)
	BtPend.apply_wnd(st, q, [1, 1], out)
	assert_eq(q.stage, BattleState.S_DONE, "no wounds: finished")
	q = _atk(st, s.id, t.id, 2, 4, 4, 7)
	BtPend.apply_hit(st, q, [5, 5], out)
	BtPend.apply_wnd(st, q, [5, 5], out)
	assert_eq([q.stage, st.squad_alive(t)], [BattleState.S_DONE, 2], "save 7: no save roll, both wounds land")
	q = _atk(st, s.id, t.id, 1, 4, 4, 5)
	q.how = FIGHT
	BtPend.apply_hit(st, q, [1], out)
	assert_true(s.fought, "a fight hit act sets fought")
	var o := _atk(st, t.id, s.id, 1, 6, 4, 5)
	o.how = OW
	BtPend.apply_hit(st, o, [1], out)
	assert_false(t.shot or t.fought, "overwatch spends neither")


func test_lethal_skips_wound_roll() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 10000))
	var p := _atk(st, s.id, t.id, 3, 3, 4, 3)
	p.lh = true
	BtPend.apply_hit(st, p, [6, 6, 1], out)
	assert_eq([p.hits, p.lethal, p.stage, Array(p.wound_r), p.wounds], [2, 2, BattleState.S_SAVE, [], 2], "hits all lethal: wounds without a roll, straight to saves")
	var q := _atk(st, s.id, t.id, 3, 3, 4, 3)
	q.lh = true
	q.su = 1
	BtPend.apply_hit(st, q, [6, 1, 1], out)
	assert_eq([q.hits, q.lethal, q.stage], [2, 1, BattleState.S_WOUND], "su with lh: the extra hit still rolls to wound")
	BtPend.apply_wnd(st, q, [], out)
	assert_eq(q.wound_r.size(), 1, "one wound die (padded: none sent)")


func test_slay_mortal_and_spill() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 10000))
	var p := _atk(st, s.id, t.id, 3, 2, 2, 7)
	p.heel = true
	p.dw = true
	p.dmg = 3
	BtPend.apply_hit(st, p, [6, 6, 6], out)
	BtPend.apply_wnd(st, p, [6, 6, 6], out)
	assert_eq([p.slay, p.mortal, p.wounds], [1, 2, 3], "three sixes: one slay at most, the other two mortal (dw)")
	assert_eq(st.squad_alive(t), 0, "slay kills one, two mortal wounds of 3 damage spill into the 2-wound models")
	# no spill: dmg 3 on 2-wound models kills one per wound
	var st2 := _st()
	var s2 := _sq(st2, "0:0", "infantry", 0, _line(1, 0, 0))
	var t2 := _sq(st2, "1:0", "heavy", 1, _line(3, 0, 10000))
	var k := BtPend.deal_damage(st2, t2, s2, 1, 3, false, out)
	assert_eq([k.size(), st2.squad_alive(t2)], [1, 2], "normal damage does not spill")
	k = BtPend.deal_damage(st2, t2, s2, 1, 3, true, out)
	assert_eq([k.size(), st2.squad_alive(t2), t2.models[0].hp], [1, 1, 1], "a mortal wound of 3 kills one and wounds the next")
	k = BtPend.deal_damage(st2, t2, s2, 3, 1, true, out)
	assert_eq([k.size(), st2.squad_alive(t2)], [1, 0], "damage on an empty squad stops")


func test_shields_and_hd() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 10000))
	t.vs = 2
	var k := BtPend.deal_damage(st, t, s, 3, 999, false, out)
	assert_eq([t.vs, k.size()], [0, 1], "two layers stop two whole hits, even slays")
	var p := _atk(st, s.id, t.id, 1, 2, 2, 7)
	t.vs = 1
	p.mortal = 1
	p.wounds = 1
	p.dmg = 2
	BtPend.finish_atk(st, p, out)
	var last: Dictionary = st.log_lines[st.log_lines.size() - 1]
	assert_eq([t.vs, last["args"][10], st.squad_alive(t)], [0, 1, 2], "finish_atk logs the absorbed hit")


func test_victim_order() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [2000, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[5000, 9000], [1000, 9000], [-3000, 9000]])
	assert_eq(BtPend.next_victim(t, s).id, "1:0.1", "nearest to the attacker's centre (1000, 0)")
	t.models[2].hp = 1
	assert_eq(BtPend.next_victim(t, s).id, "1:0.2", "a hurt model first")
	t.models[2].hp = 2
	assert_eq(BtPend.next_victim(t, null).id, "1:0.0", "no attacker: the first")
	st.remove_unit(s.models[0])
	st.remove_unit(s.models[0])
	assert_eq(BtPend.next_victim(t, s).id, "1:0.1", "an attacker with nobody left: nearest to (0, 0), not the first")
	var tie := _sq(st, "1:1", "heavy", 1, [[-4000, 0], [4000, 0]])
	assert_eq(BtPend.next_victim(tie, s).id, "1:1.0", "a tie: the first wins")
	st.remove_unit(tie.models[0])
	st.remove_unit(tie.models[0])
	assert_eq(BtPend.next_victim(tie, s), null, "an empty target: null")


func test_reroll() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 10000))
	var p := _atk(st, s.id, t.id, 5, 4, 4, 3)
	BtPend.apply_reroll(st, p, 6, out)
	assert_false(p.rr, "not at stage hit")
	BtPend.apply_hit(st, p, [3, 2, 5, 2, 4], out)
	BtPend.apply_reroll(st, p, 6, out)
	assert_eq([Array(p.hit_r), p.hits, p.rr], [[3, 6, 5, 2, 4], 3, true], "the lowest failed die, the first of two 2s")
	BtPend.apply_reroll(st, p, 6, out)
	assert_eq(Array(p.hit_r), [3, 6, 5, 2, 4], "once only")
	var q := _atk(st, s.id, t.id, 2, 4, 4, 3)
	BtPend.apply_hit(st, q, [5, 6], out)
	BtPend.apply_reroll(st, q, 1, out)
	assert_eq([Array(q.hit_r), q.rr], [[5, 6], false], "no failed die: nothing changes (the act already spent the CP)")
	var r := _atk(st, s.id, t.id, 2, 4, 4, 3)
	BtPend.apply_hit(st, r, [1, 5], out)
	st.act_seq = 3
	BtPend.apply_reroll(st, r, 0, out)
	assert_eq(r.hit_r[0], Rng.make("fallback:3:rr", st.seed).d6(), "v 0: one die from fallback:<seq>:rr")
	var m := _atk(st, s.id, t.id, 2, 4, 4, 3)
	m.mk = true
	BtPend.apply_hit(st, m, [1, 1], out)
	assert_eq(t.mk, -1, "no hits: not marked")
	BtPend.apply_reroll(st, m, 5, out)
	assert_eq([m.stage, t.mk], [BattleState.S_DONE, -1], "no hits: the attack is over, nothing to re-roll")
	var m2 := _atk(st, s.id, t.id, 2, 4, 4, 3)
	m2.mk = true
	BtPend.apply_hit(st, m2, [1, 5], out)
	assert_eq(t.mk, st.mark_key(), "one hit marks")


func test_gtg() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	for c: Array in [[5, false, true, 4], [4, false, true, 3], [3, false, true, 3], [5, true, true, 5], [5, false, false, 5]]:
		var p := _atk(st, s.id, t.id, 1, 2, 2, int(c[0]))
		p.melee = bool(c[1])
		BtPend.apply_hit(st, p, [6], out)
		BtPend.apply_wnd(st, p, [6], out)
		BtPend.apply_sav(st, p, [6], bool(c[2]), out)
		assert_eq([p.sv, p.gtg], [int(c[3]), int(c[3]) != int(c[0])], "gtg on sv %d melee %s used %s -> %d" % c)


# ------------------------------------------------------------------ charge and overwatch
func test_overwatch_and_promotion() -> void:
	var st := _st()
	_seats(st, 3)
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(5, 0, 9000))
	assert_true(BtPend.ow_ok(st, t, s), "the target can overwatch (gun, CP, edge in range)")
	var p := BtPend.declare_charge(st, s, t, out)
	assert_eq([p.kind, p.stage, p.need, s.ch_done, p.att, p.def], [BattleState.K_CHG, BattleState.S_OW, 7, true, 0, 1], "declared: wait for the overwatch decision, need ceil(edge - 1)")
	var other := _atk(st, "0:0", "1:0", 1, 4, 4, 4)
	BtPend.apply_ow(st, p, true, out)
	assert_eq([p.stage, t.ow_used, st.seats[1].cp], [BattleState.S_OWATK, true, 2], "used: one CP, the charge waits")
	var a := st.pend[0]
	assert_true(a.kind == BattleState.K_ATK and a.ow and a.u == "1:0" and a.t == "0:0" and st.pend[1] == p and st.pend[2] == other, "the overwatch attack is inserted right before its charge")
	BtPend.prune(st, out)
	assert_eq(p.stage, BattleState.S_OWATK, "prune: no promotion while the overwatch is pending")
	BtPend.apply_hit(st, a, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], out)
	assert_eq(p.stage, BattleState.S_OWATK, "the attack resolved, the charge is promoted by prune, not by the applier")
	BtPend.prune(st, out)
	assert_eq(p.stage, BattleState.S_CHARGE, "prune promotes owatk -> charge after the overwatch")
	assert_false(BtPend.ow_ok(st, t, s), "used this turn: no second overwatch")
	# declined: owatk, promoted at once by prune (no attack)
	var st2 := _st()
	_seats(st2, 3)
	var s2 := _sq(st2, "0:0", "infantry", 0, _line(5, 0, 0))
	var t2 := _sq(st2, "1:0", "infantry", 1, _line(5, 0, 9000))
	var p2 := BtPend.declare_charge(st2, s2, t2, out)
	BtPend.apply_ow(st2, p2, false, out)
	assert_eq([p2.stage, st2.pend.size(), st2.seats[1].cp], [BattleState.S_OWATK, 1, 3], "declined: no CP, no attack")
	BtPend.prune(st2, out)
	assert_eq(p2.stage, BattleState.S_CHARGE, "and prune lets the charge roll")
	# a target without a gun, or out of range: straight to the charge roll
	var st3 := _st()
	_seats(st3, 3)
	var s3 := _sq(st3, "0:0", "infantry", 0, _line(1, 0, 0))
	var h := _sq(st3, "1:0", "hoplite", 1, _line(1, 0, 5000))
	assert_eq(BtPend.declare_charge(st3, s3, h, out).stage, BattleState.S_CHARGE, "no gun: no overwatch")
	assert_eq(BtPend.declare_charge(st3, s3, h, out).need, 3, "need max(2, ceil(5 - 1.6 - 1)) = 3")
	var close := _sq(st3, "1:1", "infantry", 1, _line(1, 30000, 2000))
	assert_eq(BtPend.declare_charge(st3, _sq(st3, "0:1", "infantry", 0, [[30000, 0]]), close, out).need, 2, "never below 2")
	st3.seats[1].cp = 0
	var s4 := _sq(st3, "0:2", "infantry", 0, [[-30000, 0]])
	assert_eq(BtPend.declare_charge(st3, s4, _sq(st3, "1:2", "infantry", 1, [[-30000, 9000]]), out).stage, BattleState.S_CHARGE, "no CP: no overwatch")


## The page's flushPend(true) forces a waiting charge (owatk) to roll when myRoll() finds nothing to roll. Offline every
## seat rolls on this device, so myRoll() returns the first entry that is not a waiting charge; and a waiting charge
## always has its overwatch attack in front of it (apply_ow inserts it before the charge) or nothing at all (then prune
## promotes it). So whenever the queue is non-empty after prune, its first entry is something to roll, and the forced
## promotion cannot happen offline. v10 drops it and promotes only in prune.
func test_forced_promotion_cannot_happen_offline() -> void:
	var st := _st()
	_seats(st, 9)
	var out: Array[Dictionary] = []
	var chargers: Array = []
	for i: int in 3:
		var s := _sq(st, "0:%d" % i, "infantry", 0, _line(5, i * 20000 - 20000, 0))
		var t := _sq(st, "1:%d" % i, "infantry", 1, _line(5, i * 20000 - 20000, 9000))
		chargers.append(BtPend.declare_charge(st, s, t, out))
		st.used.clear()
	var firsts: Array = []
	for i: int in 3:
		BtPend.apply_ow(st, chargers[i], i != 1, out)
		st.used.clear()
		BtPend.prune(st, out)
		firsts.append(_first_rollable(st))
	assert_eq(firsts, [true, true, true], "after every decision and prune the first entry is rollable")
	var guard := 0
	while not st.pend.is_empty() and guard < 50:
		guard += 1
		var p := st.pend[0]
		assert_true(_first_rollable(st), "entry %d at the head is rollable (%s %s)" % [guard, BattleState.KINDS[p.kind], BattleState.STAGES[p.stage]])
		if p.kind == BattleState.K_ATK:
			if p.stage == BattleState.S_HIT:
				BtPend.apply_hit(st, p, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], out)
		elif p.kind == BattleState.K_CHG:
			BtPend.apply_charge(st, p, [1, 1], false, out)
			if p.stage == BattleState.S_CHRR:
				BtPend.keep_charge(st, p, out)
		BtPend.prune(st, out)
	assert_true(st.pend.is_empty(), "the queue drains with no forced promotion (%d steps)" % guard)


func _first_rollable(st: BattleState) -> bool:
	if st.pend.is_empty():
		return true
	var p := st.pend[0]
	return not (p.kind == BattleState.K_CHG and p.stage == BattleState.S_OWATK)


func test_charge_roll_reroll_keep() -> void:
	var st := _st()
	_seats(st, 1)
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var t := _sq(st, "1:0", "hoplite", 1, _line(5, 0, 9000))
	var p := BtPend.declare_charge(st, s, t, out)
	assert_eq([p.stage, p.need], [BattleState.S_CHARGE, 7], "need 7")
	BtPend.apply_charge(st, p, [1, 2], false, out)
	assert_eq([p.stage, Array(p.roll), st.pend.size()], [BattleState.S_CHRR, [1, 2], 1], "missed with CP for a re-roll: wait")
	BtPend.apply_charge(st, p, [3, 4], true, out)
	assert_eq([p.stage, p.ok, st.pend.size()], [BattleState.S_MOVE, true, 1], "re-rolled 7: made it, waiting to move")
	var to: Array = []
	for m: BattleState.Unit in s.models:
		to.append([m.x, m.z + 6000])
	to.append([99, 99])
	BtPend.apply_cmove(st, p, to, out)
	assert_eq([s.charged, s.ch_tgt, s.moved, s.still, st.pend.size(), p.stage], [true, "1:0", true, false, 0, BattleState.S_DONE], "cmove: charged at the target, moved, entry done")
	assert_eq([s.models[0].z, s.models[4].x, s.fx, s.fz], [6000, 4 * 1700, 0, 1000], "zipped onto the models in order, facing the target")
	# keep: the first miss stands
	s.ch_done = false
	var q := BtPend.declare_charge(st, _sq(st, "0:1", "infantry", 0, _line(1, 30000, 0)), _sq(st, "1:1", "hoplite", 1, _line(1, 30000, 9000)), out)
	BtPend.apply_charge(st, q, [1, 1], false, out)
	BtPend.keep_charge(st, q, out)
	assert_eq([q.stage, st.pend.size()], [BattleState.S_DONE, 0], "keep: the charge fails")
	# no CP: a miss ends at once; a re-roll miss ends too
	st.seats[0].cp = 0
	var r := BtPend.declare_charge(st, _sq(st, "0:2", "infantry", 0, _line(1, -30000, 0)), _sq(st, "1:2", "hoplite", 1, _line(1, -30000, 9000)), out)
	BtPend.apply_charge(st, r, [1, 1], false, out)
	assert_eq([r.stage, r.ok, st.pend.size()], [BattleState.S_DONE, false, 0], "no CP: missed and gone")
	# a dead charger: the entry is dropped by the applier
	var d := BtPend.declare_charge(st, _sq(st, "0:3", "infantry", 0, _line(1, -30000, 20000)), _sq(st, "1:3", "hoplite", 1, _line(1, -30000, 25000)), out)
	st.remove_unit(st.unit("0:3.0"))
	BtPend.apply_charge(st, d, [6, 6], false, out)
	assert_eq([d.stage, st.pend.size()], [BattleState.S_DONE, 0], "charger gone: dropped")
	# cmove clamps to the table edge and ignores wrong stages
	var e := BtPend.declare_charge(st, _sq(st, "0:4", "infantry", 0, _line(1, 0, -20000)), _sq(st, "1:4", "hoplite", 1, _line(1, 0, -16000)), out)
	BtPend.apply_cmove(st, e, [[999999, -999999]], out)
	assert_eq(e.stage, BattleState.S_CHARGE, "cmove before the roll: ignored")
	BtPend.apply_charge(st, e, [6, 6], false, out)
	BtPend.apply_cmove(st, e, [[999999, -999999]], out)
	assert_eq([st.unit("0:4.0").x, st.unit("0:4.0").z], [st.w * 500, -st.d * 500], "clamped to the table")


# ------------------------------------------------------------------ the other kinds
func test_shock_and_adv() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(2, 0, 0))
	var p := BattleState.Pend.new()
	p.kind = BattleState.K_SHOCK
	p.stage = BattleState.S_SHOCK
	p.u = s.id
	p.need = 7
	BtPend.push(st, p)
	BtPend.apply_shock(st, p, [3, 3], false, out)
	assert_eq([s.shaken, st.pend.size(), p.stage], [true, 0, BattleState.S_DONE], "6 < 7: shaken")
	p.stage = BattleState.S_SHOCK
	BtPend.apply_shock(st, p, [3, 4], false, out)
	assert_false(s.shaken, "7: passes")
	s.shaken = true
	p.stage = BattleState.S_SHOCK
	BtPend.apply_shock(st, p, [], true, out)
	assert_true(s.shaken, "brave: passes without a roll and changes nothing (page parity)")
	BtPend.apply_adv(st, s, 4, out)
	assert_eq([s.adv, s.adv_r], [true, 4], "advance roll kept")
	BtPend.apply_adv(st, s, 0, out)
	assert_eq(s.adv_r, 1, "a missing roll is 1, never a draw")


func test_grenade_and_heal() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 6000))
	BtPend.apply_gren(st, s, t, [4, 4, 4, 1, 2, 3], out)
	assert_eq([s.shot, st.squad_alive(t), t.models[0].hp], [true, 2, 1], "three 4+ are three mortal wounds that spill")
	var med := _sq(st, "1:1", "medic", 1, _line(1, 10000, 6000))
	BtPend.apply_heal(st, med, t, 2, out)
	assert_eq([med.shot, t.models[0].hp], [true, 1], "a 2 fails")
	BtPend.apply_heal(st, med, t, 3, out)
	assert_eq(t.models[0].hp, 2, "a 3: the first hurt model +1")
	BtPend.apply_heal(st, med, t, 6, out)
	assert_eq([st.squad_alive(t), st.units[st.units.size() - 1].id, st.units[st.units.size() - 1].hp], [3, "1:0.0", 1], "nobody hurt: the first missing model comes back with 1 wound, appended")
	var f := BtSquads.formation(1, 0, 0, 0, 1000, 800)
	assert_true(f.size() == 1 and st.unit("1:0.0").x % 10 == 0, "revived on the 10 MI grid")
	BtPend.apply_heal(st, med, t, 6, out)
	assert_eq(st.squad_alive(t), 3, "everybody back and whole: nothing to do")
	# a revived index that was lying as a wind body leaves the body list (the page drops it from FALLEN)
	var dead := t.models[1]
	st.remove_unit(dead)
	BtAbilities.wind_fall(st, dead)
	assert_eq([t.wind_n, st.bodies.size()], [1, 1], "wind_fall: counted and lying")
	var back := BtAbilities.revive_one(st, t, out)
	assert_eq([back.id, back.hp, st.bodies.size(), st.body_of(t.id)], [dead.id, 1, 0, null], "revive_one takes that index and the body is gone")
	var none := _sq(st, "1:2", "heavy", 1, [])
	assert_eq(BtAbilities.revive_one(st, none, out), null, "nobody standing: no revive")


func test_prune() -> void:
	var st := _st()
	_seats(st, 0)
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(1, 0, 10000))
	var u := _sq(st, "1:1", "infantry", 1, _line(1, 20000, 10000))
	var a := _atk(st, s.id, t.id, 1, 4, 4, 4)
	var b := _atk(st, u.id, s.id, 1, 4, 4, 4)
	var c := _atk(st, u.id, s.id, 1, 4, 4, 4)
	c.stage = BattleState.S_WOUND
	c.hits = 1
	var g := BtPend.declare_charge(st, u, t, out)
	st.remove_unit(t.models[0])
	st.remove_unit(u.models[0])
	BtPend.prune(st, out)
	assert_eq([a.stage, b.stage, st.pend.size(), st.pend[0] == c, g.stage], [BattleState.S_DONE, BattleState.S_HIT, 1, true, BattleState.S_CHARGE], "target gone: finished; attacker gone before rolling: dropped; mid-roll stays; charge with a dead side: dropped")


func test_apply_whole() -> void:
	var st := _st()
	var out: Array[Dictionary] = []
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(5, 0, 10000))
	var p := BtPend.apply_whole(st, s, t, [6, 6, 6, 6, 6, 6, 6, 6, 6, 6], [6, 6, 6, 6, 6, 6, 6, 6, 6, 6], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], SHOOT, out)
	assert_eq([p.stage, st.squad_alive(t), st.pend.size()], [BattleState.S_DONE, 0, 0], "a whole shot in one act")
	assert_eq(BtPend.apply_whole(st, _sq(st, "0:1", "hoplite", 0, [[30000, 0]]), s, [], [], [], SHOOT, out), null, "no gun: null")


func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtPend scenario digest is pinned")


## Two squads trade fire, overwatch, a charge, a fight, a grenade and a heal with fixed dice and some short arrays.
func _digest_scenario() -> String:
	var st := _st(2, 0)
	_seats(st, 4)
	st.act_seq = 40
	var out: Array[Dictionary] = []
	var a := _sq(st, "0:0", "heavy", 0, _line(3, -2000, 0))
	var b := _sq(st, "1:0", "infantry", 1, _line(5, -4000, 11000))
	var m := _sq(st, "1:1", "medic", 1, _line(1, 6000, 13000))
	var w := _sq(st, "0:1", _wind_key(), 0, _line(1, 9000, 1000))
	BtPend.apply_whole(st, a, b, [3, 4, 5, 6, 2, 6], [2, 5, 6], [], SHOOT, out)
	var g := BtPend.declare_charge(st, a, b, out)
	BtPend.apply_ow(st, g, true, out)
	BtPend.apply_hit(st, st.pend[0], [6, 6], out)
	BtPend.prune(st, out)
	BtPend.apply_wnd(st, st.pend[0], [5], out)
	BtPend.prune(st, out)
	BtPend.apply_charge(st, g, [2, 3], false, out)
	BtPend.apply_charge(st, g, [6], true, out)
	if g.stage == BattleState.S_MOVE:
		BtPend.apply_cmove(st, g, [[-2000, 8000], [0, 8000], [2000, 8000]], out)
	var f := BtPend.mk_atk(st, a, b, FIGHT)
	BtPend.apply_hit(st, f, [4, 4, 1, 6, 6, 2], out)
	BtPend.apply_reroll(st, f, 5, out)
	BtPend.apply_wnd(st, f, [6, 1, 3], out)
	if f.stage == BattleState.S_SAVE:
		BtPend.apply_sav(st, f, [5], true, out)
	BtPend.apply_gren(st, b, w, [4, 5], out)
	BtPend.apply_heal(st, m, b, 4, out)
	BtPend.deal_damage(st, w, b, 1, 999, false, out)
	BtPend.prune(st, out)
	var v := st.state_ints()
	v.append(out.size())
	for e: Dictionary in out:
		v.append(Events.id_of(e))
	return Hash.digest_hex(v)


func _wind_key() -> String:
	for t: Dictionary in GameData.types():
		if t.has("wind") and not GameData.is_hidden(str(t["k"])):
			return str(t["k"])
	return "infantry"
