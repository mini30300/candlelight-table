extends "res://tests/testing.gd"
## core/battle/squads.gd (BtSquads, R1_PORT_SPEC §1.4): radius, can_target, center, dist2_min/dist_min, edge,
## edge_within, foes_of, real_foes, engaged_with, is_engaged, half, formation.
## Two kinds of checks: page samples (fixtures/squads/page_samples.json, written by tools/record_squads_strats.js from
## the page's own functions run in Chromium) compared exactly or within the rounding the spec states, and hand cases
## at the exact boundaries (where the page's doubles may land either side, the spec's integer rule is pinned).

const FIXTURE := "res://tests/unit/fixtures/squads/page_samples.json"
## Digest of a fixed scenario through every BtSquads function (see _digest_scenario); changes only on purpose.
const PINNED_DIGEST := "c0217484df79a039"

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = raw if raw is Dictionary else {}


# ------------------------------------------------------------------ helpers
func _st(free_fire: bool = false) -> BattleState:
	return BattleState.make({"seed": 3, "w": 48, "teams": 3, "freeFire": 1 if free_fire else 0})


## A squad of type k on side `side` with models at the given [x, z] points (MI) and hp (0 = the type's w).
func _sq(st: BattleState, id: String, k: String, side: int, pts: Array, hp: int = 0) -> BattleState.Squad:
	var t := GameData.ty(k)
	var n0: int = int(t.get("n", 1))
	var s := st.add_squad(id, k, side, side, n0, 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, hp if hp > 0 else int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


func _ids(list: Array[BattleState.Squad]) -> Array:
	var out: Array = []
	for q: BattleState.Squad in list:
		out.append(q.id)
	return out


func _pts(slots: Array[PackedInt64Array]) -> Array:
	var out: Array = []
	for p: PackedInt64Array in slots:
		out.append([p[0], p[1]])
	return out


## A JSON number (always a double in Godot's parser) as an int.
func _i(v: Variant) -> int:
	return int(v)


## Builds the BattleState of one fixture world (squads in order, units in the recorded global order).
func _world(w: Dictionary, free_fire: bool) -> BattleState:
	var st := BattleState.make({"seed": 1, "w": 48, "teams": 3, "freeFire": 1 if free_fire else 0})
	for sv: Variant in w["squads"]:
		var s: Dictionary = sv
		st.add_squad(str(s["id"]), str(s["k"]), _i(s["side"]), _i(s["pl"]), _i(s["n0"]), 0)
	for uv: Variant in w["units"]:
		var u: Dictionary = uv
		st.add_unit(str(u["id"]), st.squad(str(u["sq"])), _i(u["hp"]), _i(u["x"]), _i(u["z"]))
	return st


## The page's mean (inches, a double) against the port's js_round centre in MI: equal to the nearest MI, or either
## neighbour when the page value sits on a half (the exact mean is then a half and js_round goes up).
func _center_ok(port: int, page_in: float) -> bool:
	var v := page_in * 1000.0
	var fl := floorf(v)
	if absf(v - fl - 0.5) < 0.000001:
		return port == int(fl) or port == int(fl) + 1
	return port == int(roundf(v))


# ------------------------------------------------------------------ page samples
func test_fixture_loaded() -> void:
	assert_true(fx.has("worlds") and fx.has("formation") and fx.has("radius_mi"), "fixture has worlds, formation and radii")
	var live: Array = fx.get("live_check", [])
	var all_same := live.size() >= 4
	for c: Variant in live:
		all_same = all_same and bool((c as Dictionary)["same"])
	assert_true(all_same, "recorder's live cross-check: the cut formation equals BT.place on a started match", live)


func test_radius_matches_page() -> void:
	var rows: Array = fx["radius_mi"]
	assert_eq(rows.size(), GameData.count(), "one sampled radius per datasheet")
	var bad: Array = []
	for rv: Variant in rows:
		var r: Array = rv
		var ti := GameData.index_of(str(r[0]))
		if ti < 0 or BtSquads.radius_of(ti) != _i(r[1]):
			bad.append([r[0], r[1], BtSquads.radius_of(ti)])
	assert_true(bad.is_empty(), "radius_of equals the page's radOfType for every datasheet (%d)" % rows.size(), bad)
	assert_eq(BtSquads.radius_of(-1), _i(fx["radius_unknown_mi"]), "an unknown type gets the page's default 800")
	assert_eq(BtSquads.radius_of(GameData.count()), 800, "an index past the table gets 800")
	assert_eq(BtSquads.radius(null), 800, "radius of no squad is 800")
	assert_eq(BtSquads.ENGAGE_LIM, GameData.const_int("ENGAGE", -1) * 1000 + 1, "ENGAGE_LIM is the data's ENGAGE (inches) plus the page's 0.001 inch")
	var st := _st()
	assert_eq(BtSquads.radius(_sq(st, "0:0", "cavalry", 0, [[0, 0]])), 1100, "a cavalry squad's radius")
	assert_eq(BtSquads.radius(_sq(st, "0:1", "infantry", 0, [[0, 0]])), 800, "a type without r uses 800")
	var ghost := st.add_squad("0:2", "no-such-unit", 0, 0, 1, 0)
	assert_eq(ghost.ti, -1, "an unknown key has no type index")
	assert_eq(BtSquads.radius(ghost), 800, "and its radius is 800")


func test_worlds_match_page() -> void:
	var ins: Array = fx["worlds_in"]
	var outs: Array = fx["worlds"]
	assert_eq(ins.size(), outs.size(), "one result per sampled world")
	var counts := {"squads": 0, "pairs": 0, "near": 0}
	var bad := {"center": [], "half": [], "real": [], "engaged": [], "is_engaged": [], "foes": [], "foes_ff": [],
		"dist": [], "dist_min": [], "edge": [], "target": [], "target_ff": [], "within1": [], "within12": [],
		"within24": [], "aura6": [], "empty": []}
	for wi: int in ins.size():
		var win: Dictionary = ins[wi]
		var wout: Dictionary = outs[wi]
		var st := _world(win, false)
		var sf := _world(win, true)
		var rows: Array = wout["squads"]
		for i: int in rows.size():
			var row: Dictionary = rows[i]
			var s := st.squads[i]
			var c := BtSquads.center(s)
			counts["squads"] += 1
			if not (_center_ok(c[0], float(row["cx"])) and _center_ok(c[1], float(row["cz"]))):
				bad["center"].append([wi, s.id, c, row["cx"], row["cz"]])
			if BtSquads.half(s) != bool(row["half"]):
				bad["half"].append([wi, s.id])
			if _ids(BtSquads.real_foes(st, s)) != row["real"]:
				bad["real"].append([wi, s.id])
			if _ids(BtSquads.engaged_with(st, s)) != row["engaged"]:
				bad["engaged"].append([wi, s.id, _ids(BtSquads.engaged_with(st, s)), row["engaged"]])
			if BtSquads.is_engaged(st, s) != bool(row["is_engaged"]):
				bad["is_engaged"].append([wi, s.id])
			if _ids(BtSquads.foes_of(st, s)) != row["foes"]:
				bad["foes"].append([wi, s.id])
			if _ids(BtSquads.foes_of(sf, sf.squads[i])) != row["foes_ff"]:
				bad["foes_ff"].append([wi, s.id])
			# free fire never changes who is a real foe or who is engaged
			if _ids(BtSquads.engaged_with(sf, sf.squads[i])) != row["engaged"] or _ids(BtSquads.real_foes(sf, sf.squads[i])) != row["real"]:
				bad["engaged"].append([wi, s.id, "free fire"])
		for pv: Variant in wout["pairs"]:
			var p: Array = pv
			var a := st.squads[_i(p[0])]
			var b := st.squads[_i(p[1])]
			var dist_in: float = p[2]
			var edge_in: float = p[3]
			var bits := _i(p[4])
			counts["pairs"] += 1
			var d2 := BtSquads.dist2_min(a, b)
			if a.models.is_empty() or b.models.is_empty():
				# the page's 1e9 sentinel for both distance and edge
				if dist_in != 1000000000.0 or edge_in != 1000000000.0 or d2 != BattleState.FAR2 \
						or BtSquads.dist_min(a, b) != BattleState.FAR2 or BtSquads.edge(a, b) != BattleState.FAR2 \
						or BtSquads.edge_within(a, b, 1001) or BtSquads.edge_within(a, b, 1000000):
					bad["empty"].append([wi, a.id, b.id])
			else:
				var exact := sqrt(float(d2))
				if absf(exact - dist_in * 1000.0) > 0.000001:
					bad["dist"].append([wi, a.id, b.id, d2, dist_in])
				if BtSquads.dist_min(a, b) != int(floorf(exact + 0.0000001)):
					bad["dist_min"].append([wi, a.id, b.id])
				var e := BtSquads.edge(a, b)
				var pe := edge_in * 1000.0
				if float(e) > pe + 0.000001 or float(e) <= pe - 1.000001:
					bad["edge"].append([wi, a.id, b.id, e, edge_in])
			if BtSquads.can_target(st, a, b) != ((bits & 1) != 0):
				bad["target"].append([wi, a.id, b.id])
			if BtSquads.can_target(sf, sf.squads[a.idx], sf.squads[b.idx]) != ((bits & 2) != 0):
				bad["target_ff"].append([wi, a.id, b.id])
			if (bits & 64) != 0:
				counts["near"] += 1
				continue
			if BtSquads.edge_within(a, b, 1001) != ((bits & 4) != 0):
				bad["within1"].append([wi, a.id, b.id, edge_in])
			if BtSquads.edge_within(a, b, 12001) != ((bits & 8) != 0):
				bad["within12"].append([wi, a.id, b.id, edge_in])
			if BtSquads.edge_within(a, b, 24001) != ((bits & 16) != 0):
				bad["within24"].append([wi, a.id, b.id, edge_in])
			if (d2 <= 6001 * 6001) != ((bits & 32) != 0):
				bad["aura6"].append([wi, a.id, b.id, dist_in])
	assert_true(counts["squads"] >= 100 and counts["pairs"] >= 500, "sampled %d squads and %d ordered pairs (%d near a threshold, skipped)" % [counts["squads"], counts["pairs"], counts["near"]])
	for k: String in bad:
		var list: Array = bad[k]
		assert_true(list.is_empty(), "page samples agree: " + k, list.slice(0, 5))


func test_formation_matches_page() -> void:
	var cases: Array = fx["formation"]
	var bad: Array = []
	var ties := 0
	var axes := 0
	for cv: Variant in cases:
		var c: Dictionary = cv
		var f: Array = c["f"]
		var got := BtSquads.formation(_i(c["n"]), _i(c["cx"]), _i(c["cz"]), _i(f[0]), _i(f[1]), _i(c["r"]))
		var want: Array = c["slots"]
		if got.size() != want.size():
			bad.append([c["n"], "size", got.size(), want.size()])
			continue
		for i: int in want.size():
			var ws: Array = want[i]
			for ax: int in 2:
				var e: Array = ws[ax]
				axes += 1
				var v: int = got[i][ax]
				if _i(e[1]) == 1:
					ties += 1
					if v != _i(e[2]) and v != _i(e[2]) + 10:
						bad.append([c["n"], c["f"], c["r"], i, ax, v, e])
				elif v != _i(e[0]):
					bad.append([c["n"], c["f"], c["r"], i, ax, v, e])
	assert_true(cases.size() >= 90, "%d formation cases from the page (n 0..12 and 20, seven facings, six radii)" % cases.size())
	assert_true(bad.is_empty(), "every slot equals the page's slot on the 10 MI grid (%d axes, %d on a half step)" % [axes, ties], bad.slice(0, 5))


# ------------------------------------------------------------------ hand cases
func test_can_target() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var b := _sq(st, "0:1", "infantry", 0, [[3000, 0]])
	var c := _sq(st, "1:0", "infantry", 1, [[6000, 0]])
	assert_false(BtSquads.can_target(st, a, a), "never yourself")
	assert_false(BtSquads.can_target(st, a, b), "not a team-mate")
	assert_true(BtSquads.can_target(st, a, c), "another side")
	assert_false(BtSquads.can_target(st, a, null) or BtSquads.can_target(st, null, a), "null is never a target")
	st.free_fire = true
	assert_true(BtSquads.can_target(st, a, b), "free fire: a team-mate")
	assert_false(BtSquads.can_target(st, a, a), "free fire: still never yourself")


func test_center_rounding() -> void:
	var st := _st()
	assert_eq(BtSquads.center(_sq(st, "0:0", "infantry", 0, [[-1, -2], [-2, -3]])), PackedInt64Array([-1, -2]), "mean -1.5 and -2.5 round up to -1 and -2 (js_round)")
	assert_eq(BtSquads.center(_sq(st, "0:1", "infantry", 0, [[1, 2], [2, 3]])), PackedInt64Array([2, 3]), "mean 1.5 and 2.5 round up to 2 and 3")
	assert_eq(BtSquads.center(_sq(st, "0:2", "infantry", 0, [[-1, 0], [-2, 0], [-2, 0]])), PackedInt64Array([-2, 0]), "mean -5/3 rounds to -2")
	assert_eq(BtSquads.center(_sq(st, "0:3", "infantry", 0, [[-90000, 90000], [-90000, 89990], [-89990, 90000]])), PackedInt64Array([-89997, 89997]), "corner of a 180 table")
	assert_eq(BtSquads.center(_sq(st, "0:4", "infantry", 0, [])), PackedInt64Array([0, 0]), "an empty squad's centre is the table centre, as the page")
	assert_eq(BtSquads.center(null), PackedInt64Array([0, 0]), "no squad: [0, 0]")
	var s := _sq(st, "0:5", "infantry", 0, [[1000, 0], [2000, 0], [3000, 0]])
	st.remove_unit(s.models[2])
	assert_eq(BtSquads.center(s), PackedInt64Array([1500, 0]), "the dead are not counted")


func test_dist_and_edge() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[0, 0], [-5000, 0]])
	var b := _sq(st, "1:0", "cavalry", 1, [[3000, 4000], [9000, 9000]])
	assert_eq(BtSquads.dist2_min(a, b), 25000000, "nearest pair 3-4-5: d2 = 5000 squared")
	assert_eq(BtSquads.dist2_min(b, a), 25000000, "symmetric")
	assert_eq(BtSquads.dist_min(a, b), 5000, "5 inches")
	assert_eq(BtSquads.edge(a, b), 5000 - 800 - 1100, "edge = 5 inches minus both radii")
	var c := _sq(st, "1:1", "infantry", 1, [[1001, 1001]])
	assert_eq(BtSquads.dist_min(a, c), 1415, "isqrt floors (1415.6)")
	assert_eq(BtSquads.edge(a, c), 1415 - 1600, "overlapping bases give a negative edge")
	var e := _sq(st, "1:2", "infantry", 1, [])
	assert_eq(BtSquads.dist2_min(a, e), BattleState.FAR2, "an empty side gives FAR2")
	assert_eq(BtSquads.dist_min(e, a), BattleState.FAR2, "dist_min of an empty side is FAR2")
	assert_eq(BtSquads.edge(a, e), BattleState.FAR2, "edge of an empty side is FAR2 (the page's 1e9)")
	assert_eq(BtSquads.dist2_min(a, null), BattleState.FAR2, "no squad gives FAR2")
	assert_eq(BtSquads.dist2_min(a, a), 0, "a squad to itself is 0")


func test_edge_within_boundaries() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	# two 800 MI bases: edge exactly 1 inch at 2600, 1 inch + 1 MI at 2601, + 2 MI at 2602
	var b := _sq(st, "1:0", "infantry", 1, [[2600, 0]])
	var c := _sq(st, "1:1", "infantry", 1, [[2601, 0]])
	var d := _sq(st, "1:2", "infantry", 1, [[0, -2602]])
	var e := _sq(st, "1:3", "infantry", 1, [[1560, 2080]])
	var f := _sq(st, "1:4", "infantry", 1, [[1561, 2080]])
	assert_true(BtSquads.edge_within(a, b, 1001), "edge exactly 1 inch is engaged")
	assert_true(BtSquads.edge_within(a, c, 1001), "edge 1 inch + 1 MI is engaged (the page's + 0.001)")
	assert_false(BtSquads.edge_within(a, d, 1001), "edge 1 inch + 2 MI is not")
	assert_true(BtSquads.edge_within(a, e, 1001), "a diagonal at exactly 2600 (1560, 2080) is engaged")
	assert_false(BtSquads.edge_within(a, f, 1000), "2600.6 is beyond edge 1 inch exactly")
	assert_true(BtSquads.edge_within(a, f, 1001), "2600.6 is inside 1 inch + 1 MI")
	assert_true(BtSquads.edge_within(a, b, 1000), "lim 1000 admits exactly 1 inch (<=)")
	assert_false(BtSquads.edge_within(a, c, 1000), "lim 1000 refuses 1 inch + 1 MI")
	# negative and zero sums
	var g := _sq(st, "1:5", "infantry", 1, [[0, 0]])
	assert_true(BtSquads.edge_within(a, g, -1600), "sum 0: only a zero distance passes")
	assert_false(BtSquads.edge_within(a, b, -1600), "sum 0 refuses any distance")
	assert_false(BtSquads.edge_within(a, g, -1601), "a negative sum refuses even stacked bases")
	# empty sides and huge limits
	var h := _sq(st, "1:6", "infantry", 1, [])
	assert_false(BtSquads.edge_within(a, h, 1000000000), "an empty side is never within")
	assert_false(BtSquads.edge_within(null, a, 1001), "no squad is never within")
	var far := _sq(st, "1:7", "infantry", 1, [[-9999000, 9999000]])
	assert_true(BtSquads.edge_within(a, far, 4000000000), "a limit whose square would overflow is simply true")
	assert_false(BtSquads.edge_within(a, far, 12001), "and a real limit is false out there")


func test_foes_and_engagement() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [1700, 0]])
	# foes created in an order where the nearest comes last
	var far := _sq(st, "1:0", "infantry", 1, [[1700, 2601]])
	var mid := _sq(st, "2:0", "infantry", 2, [[-2400, 0]])
	var near := _sq(st, "1:1", "infantry", 1, [[1700, 2000]])
	var mate := _sq(st, "0:1", "infantry", 0, [[0, -2000]])
	var away := _sq(st, "1:2", "infantry", 1, [[30000, 0]])
	var dead := _sq(st, "2:1", "infantry", 2, [])
	assert_eq(_ids(BtSquads.real_foes(st, s)), ["1:0", "2:0", "1:1", "1:2"], "real foes: alive, other sides, squads order")
	assert_eq(_ids(BtSquads.foes_of(st, s)), ["1:0", "2:0", "1:1", "1:2"], "foes without free fire = real foes")
	assert_eq(_ids(BtSquads.engaged_with(st, s)), ["1:0", "2:0", "1:1"], "engaged in squads order, not by distance; the team-mate is not")
	assert_true(BtSquads.is_engaged(st, s), "is engaged")
	assert_false(BtSquads.is_engaged(st, away), "a lone squad far away is not")
	assert_eq(_ids(BtSquads.engaged_with(st, mate)), [], "a team-mate touching only its own side is not engaged")
	assert_true(BtSquads.edge_within(s, mate, 1001), "although it stands within 1 inch of s")
	st.free_fire = true
	assert_eq(_ids(BtSquads.foes_of(st, s)), ["1:0", "2:0", "1:1", "0:1", "1:2"], "free fire adds the team-mate to foes_of in squads order (never itself)")
	assert_eq(_ids(BtSquads.real_foes(st, s)), ["1:0", "2:0", "1:1", "1:2"], "free fire leaves real foes alone")
	assert_eq(_ids(BtSquads.engaged_with(st, s)), ["1:0", "2:0", "1:1"], "and engagement alone")
	assert_false(_ids(BtSquads.foes_of(st, s)).has(dead.id), "a dead squad is nobody's foe")
	assert_eq(_ids(BtSquads.foes_of(st, dead)), _ids(st.alive_squads()), "free fire: a dead squad's foes are all alive squads")
	assert_eq(BtSquads.foes_of(st, null).size() + BtSquads.real_foes(st, null).size() + BtSquads.engaged_with(st, null).size(), 0, "no squad has no foes")
	assert_false(BtSquads.is_engaged(st, null), "and is not engaged")
	# a death can end an engagement
	st.free_fire = false
	for m: BattleState.Unit in near.models.duplicate():
		st.remove_unit(m)
	st.remove_unit(far.models[0])
	st.remove_unit(mid.models[0])
	assert_eq(_ids(BtSquads.engaged_with(st, s)), [], "wiped foes no longer engage")
	assert_false(BtSquads.is_engaged(st, s), "so the squad is free")


func test_half() -> void:
	var st := _st()
	var five := _sq(st, "0:0", "infantry", 0, [[0, 0], [1, 0], [2, 0]])
	assert_false(BtSquads.half(five), "3 of 5 left is not below half")
	st.remove_unit(five.models[2])
	assert_true(BtSquads.half(five), "2 of 5 is below half")
	var one := _sq(st, "0:1", "mech", 0, [[0, 0]], 6)
	assert_false(BtSquads.half(one), "a 1-model squad at hp 6 of 12 is not below half")
	one.models[0].hp = 5
	assert_true(BtSquads.half(one), "hp 5 of 12 is")
	one.models[0].hp = 12
	assert_false(BtSquads.half(one), "full hp is not")
	st.remove_unit(one.models[0])
	assert_true(BtSquads.half(one), "a dead 1-model squad counts as below half (0 x 2 < 1)")
	var three := _sq(st, "0:2", "heavy", 0, [[0, 0], [1, 0]], 1)
	assert_false(BtSquads.half(three), "2 of 3 at hp 1 is not below half (hp counts only for single models)")
	# an unknown key reads the first datasheet, as the page's TY() does
	var first := GameData.types()[0]
	var w0: int = int(first["w"])
	var ghost := st.add_squad("0:3", "no-such-unit", 0, 0, 1, 0)
	var gm := st.add_unit("0:3.0", ghost, w0, 0, 0)
	assert_false(BtSquads.half(ghost), "unknown key at the first datasheet's full w is not below half")
	gm.hp = (w0 - 1) / 2
	assert_true(BtSquads.half(ghost), "and below half of that w is")
	assert_false(BtSquads.half(null), "no squad is not below half")


func test_formation_hand_values() -> void:
	var up := [0, 1000]
	assert_eq(BtSquads.formation(0, 0, 0, 0, 1000, 800).size(), 0, "n 0 gives no slots")
	assert_eq(BtSquads.formation(-3, 0, 0, 0, 1000, 800).size(), 0, "negative n gives no slots")
	assert_eq(_pts(BtSquads.formation(1, 1230, -450, 0, 1000, 800)), [[1230, -450]], "one model stands on the centre")
	# gap 1950 for r 800: side offsets of +-975 are exact halves, js_round sends both up (-970 and 980)
	assert_eq(_pts(BtSquads.formation(2, 0, 0, up[0], up[1], 800)), [[-970, 0], [980, 0]], "two abreast, facing +z")
	assert_eq(_pts(BtSquads.formation(3, 0, 0, 0, 1000, 800)), [[-1950, 0], [0, 0], [1950, 0]], "three abreast")
	assert_eq(_pts(BtSquads.formation(4, 0, 0, 0, 1000, 800)), [[-970, 880], [980, 880], [-970, -880], [980, -880]], "four as two rows of two, row 0 in front (+z)")
	assert_eq(_pts(BtSquads.formation(2, 0, 0, 1000, 0, 800)), [[0, 980], [0, -970]], "facing +x the side vector is (0, -1)")
	assert_eq(_pts(BtSquads.formation(3, 0, 0, 0, 1000, 1700)), [[-3750, 0], [0, 0], [3750, 0]], "gap 2r + 350 for big bases")
	assert_eq(_pts(BtSquads.formation(3, 0, 0, 0, 1000, 600)), [[-1700, 0], [0, 0], [1700, 0]], "gap never below 1700")


func test_formation_shape() -> void:
	var faces := [[0, 1000], [1000, 0], [0, -1000], [-1000, 0], [707, 707], [-600, 800]]
	var bad: Array = []
	for n: int in range(1, 11):
		for fv: Variant in faces:
			var f: Array = fv
			var fx_: int = f[0]
			var fz_: int = f[1]
			var r := 800 if n % 2 == 0 else 1300
			var gap := maxi(1700, 2 * r + 350)
			var cx := -12340 if n % 3 == 0 else 4560
			var cz := 7890
			var sl := BtSquads.formation(n, cx, cz, fx_, fz_, r)
			if sl.size() != n:
				bad.append([n, f, "size"])
				continue
			var per := n if n <= 3 else (2 if n == 4 else 3)
			var rows := (n + per - 1) / per
			# forward projection (times 1000) of each row; side offsets pair up around the centre
			var fwd: Array = []
			for row: int in rows:
				var first := row * per
				var in_row := mini(per, n - first)
				var sum_side := 0
				var proj := 0
				for c: int in in_row:
					var p := sl[first + c]
					var dx := p[0] - cx
					var dz := p[1] - cz
					if Fx.imod(p[0], 10) != 0 or Fx.imod(p[1], 10) != 0:
						bad.append([n, f, "grid", p])
					sum_side += dx * fz_ - dz * fx_
					proj = dx * fx_ + dz * fz_
					if c > 0:
						# neighbours in a row stand one gap apart (within the 10 MI rounding of each)
						var q := sl[first + c - 1]
						var gd := Fx.isqrt(Fx.dist2(p[0], p[1], q[0], q[1]))
						if absi(gd - gap) > 15:
							bad.append([n, f, "gap", gd, gap])
				# mirror symmetry of a row about the facing axis: the side offsets cancel to within the rounding
				if absi(sum_side) > in_row * 10 * 1000:
					bad.append([n, f, "symmetry", row, sum_side])
				fwd.append(proj)
			for row: int in range(1, rows):
				if int(fwd[row]) >= int(fwd[row - 1]):
					bad.append([n, f, "row order", fwd])
			if rows > 1 and absi(int(fwd[0]) + int(fwd[rows - 1])) > 10 * 1000 * 2:
				bad.append([n, f, "rows centred", fwd])
	assert_true(bad.is_empty(), "n 1..10 x six facings: on the 10 MI grid, gaps kept, rows symmetric, row 0 in front, rows centred", bad.slice(0, 5))


func test_digest_pinned() -> void:
	var a := _digest_scenario()
	var b := _digest_scenario()
	assert_eq(a, b, "the scenario digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtSquads scenario digest is pinned")


## Every BtSquads function over a fixed hand-made field (three sides, a dead squad, a stacked pair, a 1-model squad
## hurt, free fire both ways) and formations of 0..12 models for four facings, folded into one FNV-1a 64 digest.
func _digest_scenario() -> String:
	var v := PackedInt64Array()
	for ff: bool in [false, true]:
		var st := _st(ff)
		_sq(st, "0:0", "infantry", 0, [[0, 0], [1700, 0], [-1700, 10]])
		_sq(st, "0:1", "mech", 0, [[-6000, 3000]], 5)
		_sq(st, "1:0", "cavalry", 1, [[1700, 2900], [3400, 2900], [5100, 2905]])
		_sq(st, "1:1", "heavy", 1, [[-7300, 6100], [-9000, 6100]])
		_sq(st, "2:0", "hoplite", 2, [[20000, -14000], [21700, -14000], [23400, -14000], [25100, -14000], [26800, -14000]])
		_sq(st, "2:1", "archer", 2, [])
		_sq(st, "2:2", "troy", 2, [[-1, -1]], 3)
		for s: BattleState.Squad in st.squads:
			v.append(BtSquads.radius(s))
			v.append_array(BtSquads.center(s))
			v.append(1 if BtSquads.half(s) else 0)
			v.append(1 if BtSquads.is_engaged(st, s) else 0)
			for lst: Array[BattleState.Squad] in [BtSquads.foes_of(st, s), BtSquads.real_foes(st, s), BtSquads.engaged_with(st, s)]:
				v.append(lst.size())
				for q: BattleState.Squad in lst:
					v.append(q.idx)
			for t: BattleState.Squad in st.squads:
				v.append_array(PackedInt64Array([BtSquads.dist2_min(s, t), BtSquads.dist_min(s, t), BtSquads.edge(s, t),
					1 if BtSquads.edge_within(s, t, 1001) else 0, 1 if BtSquads.edge_within(s, t, 12001) else 0,
					1 if BtSquads.can_target(st, s, t) else 0]))
	for n: int in 13:
		for f: Array in [[0, 1000], [1000, 0], [-600, -800], [707, -707]]:
			for p: PackedInt64Array in BtSquads.formation(n, 10 * n - 60, -30 * n, int(f[0]), int(f[1]), 800 + 100 * n):
				v.append_array(p)
	return Hash.digest_hex(v)
