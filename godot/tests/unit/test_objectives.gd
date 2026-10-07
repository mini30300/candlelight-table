extends "res://tests/testing.gd"
## core/battle/objectives.gd (BtObjectives, R1_PORT_SPEC §1.6) against the page and by hand.
## Page samples: fixtures/objectives/page_samples.json (tools/record_army_objectives.js runs the page's own
## placeObjectives / objOC / objCtl / scoreObjectives in Chromium): placement to the free-spot grid rounding (fragile
## samples counted, R1_PORT_SPEC §7 #2); OC per team, owners, VP and held objectives exact, except where a model
## stands within 1e-9 inch of the reach, where the page's double may fall either side (the integer rule is pinned
## by hand below).
## Hand cases: placement order and the free-spot shift, OC with shaken squads and per-type oc, the reach boundary,
## the tie rules, the VP cap and the log line, and a pinned digest.

const FIX := "res://tests/unit/fixtures/objectives/page_samples.json"
## Digest of the fixed scenario in _digest_scenario; changes only on purpose.
const PINNED_DIGEST := "d6299b52606cc990:ebec7a6ab30f8f69"
var F: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		F = _iv(p)


# ---------------------------------------------------------------- helpers
## JSON numbers arrive as floats: whole ones become ints (deep)
func _iv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if f == floorf(f) and absf(f) < 1.0e18 else f
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_iv(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _iv(v[k])
			return d
	return v


## a recorded field with models [type key, x, z] standing on it (one squad per type, team 0)
func _field(fname: String, units: Array) -> BattleState:
	var f: Dictionary = F["fields"][fname]
	var st := BattleState.make({"seed": f["seed"], "w": f["w"], "d": f["d"]})
	var items: Array[Dictionary] = []
	for r: Variant in f["props"]:
		items.append(BtBlocking.prep_one(str(r[0]), r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
	st.set_props(items, true)
	for r: Variant in units:
		var k := str(r[0])
		var sq := st.squad("s:" + k)
		if sq == null:
			sq = st.add_squad("s:" + k, k, 0, 0, 1, 0)
		st.add_unit("u%d" % st.units.size(), sq, 1, int(r[1]), int(r[2]))
	return st


## an open table with squads [id, type key, team, shaken] and models [id, squad id, x, z]
func _world(teams: int, squads: Array, units: Array) -> BattleState:
	var st := BattleState.make({"seed": 1, "w": 72, "teams": teams})
	for sv: Variant in squads:
		var s := st.add_squad(str(sv[0]), str(sv[1]), int(sv[2]), int(sv[2]), 1, 0)
		s.shaken = int(sv[3]) != 0
	for uv: Variant in units:
		st.add_unit(str(uv[0]), st.squad(str(uv[1])), 1, int(uv[2]), int(uv[3]))
	return st


func _objs(st: BattleState, rows: Array) -> void:
	for r: Variant in rows:
		st.add_obj(int(r[0]), int(r[1]), int(r[2]))


## a type key with this oc (and, when r > 0, this base radius in MI)
func _type_with(oc: int, r: int = 0) -> String:
	for t: Dictionary in GameData.types():
		var k := str(t["k"])
		if int(t.get("oc", -1)) == oc and not GameData.is_hidden(k) and (r == 0 or BtSquads.radius_of(GameData.index_of(k)) == r):
			return k
	return ""


# ---------------------------------------------------------------- page samples
func test_fixture_loaded() -> void:
	for k: String in ["fields", "place", "worlds"]:
		assert_true(F.has(k), "fixture has " + k)


func test_place_matches_page() -> void:
	var bad: Array = []
	var n := 0
	var fragile := 0
	for cv: Variant in F["place"]:
		var c: Dictionary = cv
		var st := _field(str(c["field"]), c["units"])
		BtObjectives.place(st)
		var want: Array = c["obj"]
		if st.objs.size() != want.size():
			bad.append([c["field"], st.objs.size()])
			continue
		for i: int in want.size():
			var o := st.objs[i]
			var q: Array = want[i]
			if o.n != int(q[0]) or Fx.imod(o.x, 10) != 0 or Fx.imod(o.z, 10) != 0:
				bad.append([c["field"], "n or grid", o.n, o.x, o.z])
			if int(q[4]) == 0:
				fragile += 1
				continue
			n += 1
			# the same candidate: the near rings' offsets differ by their rounding (5 MI), the wide rings' by 15 MI
			var tol := 5.0 if int(q[3]) <= 1 + BtOffsets.FREESPOT_NEAR.size() else 15.0
			if absf(float(o.x) - float(q[1])) > tol + 0.000001 or absf(float(o.z) - float(q[2])) > tol + 0.000001:
				bad.append([c["field"], o.n, [o.x, o.z], q])
	assert_true(n >= 30, "%d robust objective placements (%d fragile counted)" % [n, fragile])
	assert_true(bad.is_empty(), "place equals the page's placeObjectives (order, numbers, points to the grid rounding)", bad.slice(0, 4))


func test_oc_ctl_score_match_page() -> void:
	var bad: Array = []
	var cells := 0
	var near := 0
	var scored := 0
	for wv: Variant in F["worlds"]:
		var w: Dictionary = wv
		var teams: int = w["teams"]
		var st := _world(teams, w["squads"], w["units"])
		_objs(st, w["obj"])
		var any_near := false
		for i: int in st.objs.size():
			var row: Array = w["oc"][i]
			var row_near := false
			for t: int in teams:
				var e: Array = row[t]
				if int(e[1]) == 1:
					near += 1
					row_near = true
					continue
				cells += 1
				if BtObjectives.oc(st, st.objs[i], t) != int(e[0]):
					bad.append(["oc", i, t, BtObjectives.oc(st, st.objs[i], t), e[0]])
			any_near = any_near or row_near
			if not row_near and BtObjectives.ctl(st, st.objs[i]) != int(w["ctl"][i]):
				bad.append(["ctl", i, BtObjectives.ctl(st, st.objs[i]), w["ctl"][i]])
		if any_near:
			continue
		# score every team in turn: VP and the objectives each one holds
		var ev: Array[Dictionary] = []
		for t: int in teams:
			BtObjectives.score(st, t, ev)
			scored += 1
			var args: Array = ev.back()["args"]
			if st.vp[t] != int(w["vp"][t][t]) or args.slice(4) != w["held"][t]:
				bad.append(["score", t, st.vp[t], w["vp"][t], args, w["held"][t]])
	assert_true(cells >= 450, "%d OC samples (%d within 1e-9 inch of the reach, counted)" % [cells, near])
	assert_true(scored >= 80, "%d scored turns" % scored)
	assert_true(bad.is_empty(), "oc, ctl and score equal the page's objOC, objCtl and scoreObjectives", bad.slice(0, 5))


# ---------------------------------------------------------------- hand cases
func test_place_hand() -> void:
	var st := BattleState.make({"seed": 2, "w": 48})
	BtObjectives.place(st)
	var got: Array = []
	for o: BattleState.Obj in st.objs:
		got.append([o.n, o.x, o.z])
	assert_eq(got, [[1, 0, 0], [2, -12960, -9180], [3, 12960, -9180], [4, -12960, 9180], [5, 12960, 9180]],
		"an open 48 x 34 table: the centre, then the four diagonals at 27/100 of width and depth, numbered 1..5")
	BtObjectives.place(st)
	assert_eq(st.objs.size(), 5, "placing again replaces the five (the page's OBJ = [])")
	# a model on the centre: objective 1 moves to the first near-ring point 2 inches clear (bases 800 + 1200)
	var sq := st.add_squad("0:0", "infantry", 0, 0, 1, 0)
	st.add_unit("0:0.0", sq, 1, 0, 0)
	var want := PackedInt64Array()
	for o: Array in BtOffsets.FREESPOT_NEAR:
		if int(o[0]) * int(o[0]) + int(o[1]) * int(o[1]) >= 2000 * 2000:
			want = PackedInt64Array([int(o[0]), int(o[1])])
			break
	BtObjectives.place(st)
	assert_eq(PackedInt64Array([st.objs[0].x, st.objs[0].z]), want, "a model on the spot pushes the objective to the first free near-ring point")
	assert_eq([st.objs[1].x, st.objs[1].z], [-12960, -9180], "the other four stay")
	# a building over a diagonal spot pushes that objective out of it
	var items: Array[Dictionary] = [BtBlocking.prep_one("building", 12960, 9180, 0, 10000, 0, 6000, 6000)]
	st.set_props(items, true)
	BtObjectives.place(st)
	var o5 := st.objs[4]
	assert_true(not BtBlocking.block_at(st, o5.x, o5.z) and [o5.x, o5.z] != [12960, 9180], "objective 5 leaves the building")
	assert_true(Fx.imod(o5.x, 10) == 0 and Fx.imod(o5.z, 10) == 0, "and stays on the 10 MI grid")
	# an odd width: 27/100 of 47 inches is 12690 MI, exact
	var odd := BattleState.make({"seed": 2, "w": 47, "d": 33})
	BtObjectives.place(odd)
	assert_eq([odd.objs[4].x, odd.objs[4].z], [12690, 8910], "odd sizes stay exact (w x 270 MI)")


func test_oc_hand() -> void:
	var k2 := _type_with(2, 800)
	var k3 := _type_with(3)
	var k0 := _type_with(0)
	assert_true(k2 != "" and k3 != "" and k0 != "", "the data has types with oc 2 (base 800), oc 3 and oc 0")
	var r3 := BtSquads.radius_of(GameData.index_of(k3))
	var reach2 := 3000 + 800 + 1
	var reach3 := 3000 + r3 + 1
	var st := _world(3, [["0:0", k2, 0, 0], ["0:1", k3, 0, 0], ["1:0", k2, 1, 0], ["2:0", k0, 2, 0]],
		[["a", "0:0", reach2, 0], ["b", "0:0", 0, -reach2 - 1], ["c", "0:1", 0, reach3], ["d", "0:1", -reach3, 0],
		["e", "1:0", 1000, 1000], ["f", "2:0", 0, 0]])
	_objs(st, [[1, 0, 0]])
	var o := st.objs[0]
	assert_eq(BtObjectives.oc(st, o, 0), 2 + 3 + 3, "team 0: the base edge exactly 3 inches + 1 MI away counts, 1 MI more does not; oc per type")
	assert_eq(BtObjectives.oc(st, o, 1), 2, "team 1 counts only its own")
	assert_eq(BtObjectives.oc(st, o, 2), 0, "a type with oc 0 adds nothing")
	assert_eq(BtObjectives.oc(st, o, 3), 0, "a team with no models: 0")
	st.squad("0:1").shaken = true
	assert_eq(BtObjectives.oc(st, o, 0), 2, "a shaken squad does not count")
	st.squad("0:1").shaken = false
	st.remove_unit(st.unit("c"))
	assert_eq(BtObjectives.oc(st, o, 0), 2 + 3, "a dead model does not count")
	var body := st.unit("d")
	st.remove_unit(body)
	st.add_body(body)
	assert_eq(BtObjectives.oc(st, o, 0), 2, "nor does a body waiting for the wind")
	assert_eq(BtObjectives.oc(st, null, 0), 0, "no objective: 0")
	# a diagonal on the reach: (x, z) with x^2 + z^2 just inside and just outside (3801)^2
	var dg := _world(2, [["0:0", k2, 0, 0]], [["p", "0:0", 2280, 3040], ["q", "0:0", -2281, 3041]])
	_objs(dg, [[1, 0, 0]])
	assert_eq(BtObjectives.oc(dg, dg.objs[0], 0), 2, "on a diagonal the exact square decides (3800 MI in, 3801.4 MI out)")


func test_ctl_ties() -> void:
	var k1 := _type_with(1, 800)
	var k2 := _type_with(2, 800)
	var k0 := _type_with(0)
	var case_ := func(counts: Array) -> int:
		var squads: Array = []
		var units: Array = []
		for t: int in counts.size():
			var c: Array = counts[t]
			squads.append(["%d:0" % t, c[0], t, 0])
			for j: int in int(c[1]):
				units.append(["%d.%d" % [t, j], "%d:0" % t, 100 * j, 100 * t])
		var st := _world(counts.size(), squads, units)
		_objs(st, [[1, 0, 0]])
		return BtObjectives.ctl(st, st.objs[0])
	assert_eq(case_.call([[k1, 0], [k2, 1]]), 1, "the only team with OC holds it")
	assert_eq(case_.call([[k1, 2], [k2, 1], [k1, 1]]), -1, "a tie at the top (2, 2, 1) holds nothing")
	assert_eq(case_.call([[k1, 2], [k2, 1], [k1, 3]]), 2, "a later team above the tie clears it (2, 2, 3)")
	assert_eq(case_.call([[k1, 3], [k2, 1], [k1, 1]]), 0, "a later lower team does not tie (3, 2, 1)")
	assert_eq(case_.call([[k1, 0], [k1, 0]]), -1, "nobody near: -1")
	assert_eq(case_.call([[k0, 4], [k0, 2]]), -1, "models with oc 0 hold nothing, even many of them")
	assert_eq(case_.call([[k0, 4], [k1, 1]]), 1, "and do not tie a team with oc")


func test_score_cap_and_log() -> void:
	var k := _type_with(2, 800)
	var st := _world(3, [["0:0", k, 0, 0], ["1:0", k, 1, 0]], [])
	# team 0 stands on all five, team 1 on the last one too (a tie there)
	var spots := [[0, 0], [-20000, -10000], [20000, -10000], [-20000, 10000], [20000, 10000]]
	for i: int in 5:
		st.add_unit("a%d" % i, st.squad("0:0"), 1, int(spots[i][0]), int(spots[i][1]))
		st.add_obj(i + 1, int(spots[i][0]), int(spots[i][1]))
	st.add_unit("b", st.squad("1:0"), 1, 20000, 10000)
	var ev: Array[Dictionary] = []
	BtObjectives.score(st, 0, ev)
	assert_eq(Array(st.vp), [15, 0, 0], "four held at 5 each is 20: capped at 15")
	assert_eq([Events.name_of(Events.id_of(ev[0])), ev[0]["key"], ev[0]["args"]], ["LOG_LINE", "obj_score", [0, 4, 15, 15, 1, 2, 3, 4]],
		"LOG_LINE obj_score [team, held, got, total, numbers held]")
	assert_eq(st.log_lines.back(), {"key": "obj_score", "args": [0, 4, 15, 15, 1, 2, 3, 4]}, "the same line in the log")
	BtObjectives.score(st, 1, ev)
	assert_eq(Array(st.vp), [15, 0, 0], "team 1 only ties: nothing")
	assert_eq(ev[1]["args"], [1, 0, 0, 0], "and its line says so")
	st.remove_unit(st.unit("b"))
	st.remove_unit(st.unit("a0"))
	st.remove_unit(st.unit("a1"))
	st.remove_unit(st.unit("a2"))
	BtObjectives.score(st, 0, ev)
	assert_eq(Array(st.vp), [25, 0, 0], "two held: 10 more")
	BtObjectives.score(st, 7, ev)
	assert_eq(Array(st.vp), [25, 0, 0], "a team outside the VP table changes nothing")
	assert_eq(ev.back()["args"], [7, 0, 0, 0], "and still logs its line")


# ---------------------------------------------------------------- pinned digest
func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the scenario digest is stable within a run")
	assert_true(_last_vp > 0, "somebody scored in the scenario (VP %d)" % _last_vp)
	assert_digest(a, PINNED_DIGEST, "BtObjectives scenario digest is pinned")


var _last_vp := 0


## a 2 x 2 team game on a ruin field: armies, deployment, objectives, then every team scores twice; the owners and
## OC per team fold into the digest with the BattleState digest
func _digest_scenario() -> String:
	var g := BattleState.make({"seed": 31, "w": 48, "teams": 2, "perTeam": 2, "mode": "team", "budget": 1000})
	var fp := FieldProps.generate(FieldTerrain.make(48, FieldTerrain.depth_for(48), "ruin", "hills", 31), true, 1000)
	g.set_props(BtBlocking.prep_field(fp), false)
	BtArmy.mk_players(g)
	for p: BattleState.Seat in g.seats:
		BtArmy.auto_list(g, p.id, null)
	var ev: Array[Dictionary] = []
	BtArmy.deploy(g, ev)
	BtObjectives.place(g)
	# march team 1's first squad onto objective 1 so somebody holds something
	var s := g.squad("2:0")
	for m: BattleState.Unit in s.models:
		m.x = g.objs[0].x
		m.z = g.objs[0].z
	var v := PackedInt64Array()
	for round: int in 2:
		for t: int in g.teams:
			BtObjectives.score(g, t, ev)
	for o: BattleState.Obj in g.objs:
		v.append(BtObjectives.ctl(g, o))
		for t: int in g.teams:
			v.append(BtObjectives.oc(g, o, t))
	_last_vp = g.vp[0] + g.vp[1]
	return Hash.digest_hex(v) + ":" + g.digest()
