extends "res://tests/testing.gd"
## core/battle/moves.gd (BtMoves, R1_PORT_SPEC §1.11): move_range, near_foe, spot_free, plan_move, go_to, apply_smove,
## try_move, can_group / group_all / group_plan / group_act, charge_spots.
## - fixtures/moves/page.json (tools/record_moves.js runs the page's own functions in Chromium over worlds on the v10
##   integer grids; its live cross-check proves the cut code is the running page): the integer tests (moveRange,
##   nearFoe, spotFree, applySMove, canGroup / groupAll) must match exactly; the searches (planMove, tryMoveSq,
##   groupMove, chargeSpots) must take the page's decision path, with points within TOL, for every decision the
##   recorder marks robust (no step could flip within the 50 MI the v10 candidates differ from the page's doubles);
##   fragile ones are only counted (the borderline flips R1_PORT_SPEC §7 #2-#4 allow);
## - plain references of plan_move and charge_spots written from the spec on the public spot_free / block_at / crowded:
##   the port must equal them on every page sample and on random worlds (plan_move's per-model filter never changes a
##   result), and they give the port's decision path for the comparison above;
## - hand cases at every edge (near-foe margin, apply_smove 49/50/51 MI, try_move keys in page order, sidestep round a
##   house, boxed in, group order and sequencing, charge angles and fallback), the 10 MI grid invariant, a time budget
##   and a pinned digest.

const FIX := "res://tests/unit/fixtures/moves/page.json"
## The page's point is toFixed(2) of a candidate at most EPS (50 MI) from the port's: 50 + 5 per axis.
const TOL := 55
## chargeSpots points are the page's raw doubles (rounded to 1 MI in the fixture): 50 + 1.
const TOL_CHARGE := 51
## Time budget (ARCHITECTURE §4, R1_PORT_SPEC §1.11 tests): plan_move for a 20-model squad among 480 props and 500 models
## under 150 ms headless x86 (best of three runs, so one scheduler hiccup does not fail it).
const BUDGET_MS := 150
## Digest of the fixed scenario in _digest_scenario (changes only on purpose).
const PINNED_DIGEST := "13f82b365d751298"

var F: Dictionary = {}
var _worlds: Array[BattleState] = []


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		F = p
	for wi: int in (F.get("worlds", []) as Array).size():
		_worlds.append(_world(wi))


# ---------------------------------------------------------------- helpers
func _i(v: Variant) -> int:
	return int(v)


## the fixture world wi as a BattleState (props through prep_one, squads with their flags and facing, units in order)
func _world(wi: int) -> BattleState:
	var w: Dictionary = F["worlds"][wi]
	var st := BattleState.make({"seed": _i(w["seed"]), "w": _i(w["w"]), "d": _i(w["d"]), "teams": 3})
	var items: Array[Dictionary] = []
	for rv: Variant in w["props"]:
		var r: Array = rv
		items.append(BtBlocking.prep_one(str(r[0]), _i(r[1]), _i(r[2]), _i(r[3]), _i(r[4]), _i(r[5]), _i(r[6]), _i(r[7])))
	st.set_props(items, true)
	for rv: Variant in w["squads"]:
		var r: Array = rv
		var s := st.add_squad(str(r[0]), str(r[1]), _i(r[2]), _i(r[3]), _i(r[4]), 0)
		s.adv = _i(r[5]) == 1
		s.adv_r = _i(r[6])
		s.moved = _i(r[7]) == 1
		s.fx = _i(r[8])
		s.fz = _i(r[9])
	for rv: Variant in w["units"]:
		var r: Array = rv
		st.add_unit(str(r[0]), st.squad(str(r[1])), _i(r[2]), _i(r[3]), _i(r[4]))
	st.turn = _i(w["turn"])
	return st


func _st(w: int = 48) -> BattleState:
	return BattleState.make({"seed": 5, "w": w, "teams": 3})


## a squad of type k on `side` with models at the [x, z] points (MI), facing (fx, fz)
func _sq(st: BattleState, id: String, k: String, side: int, pts: Array, fx: int = 0, fz: int = 1000) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, side, maxi(int(t.get("n", 1)), pts.size()), 0)
	s.fx = fx
	s.fz = fz
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


## a plain prop at (x, z): building (bw x bd as drawn, MI) or a disc kind, no turn, scale 1
func _prop(kind: String, x: int, z: int, bw: int = 0, bd: int = 0) -> Dictionary:
	return BtBlocking.prep_one(kind, x, z, 0, 10000, 0, bw, bd)


func _props(st: BattleState, items: Array) -> void:
	var list: Array[Dictionary] = []
	for o: Variant in items:
		list.append(o)
	st.set_props(list, true)


func _arr(pts: Array[PackedInt64Array]) -> Array:
	var out: Array = []
	for p: PackedInt64Array in pts:
		out.append([p[0], p[1]])
	return out


func _ints(a: Array) -> Array:
	var out: Array = []
	for v: Variant in a:
		out.append(_ints(v) if typeof(v) == TYPE_ARRAY else int(v))
	return out


## a decision padded to n entries
func _pad(p: Array, n: int) -> Array:
	var out := _ints(p)
	while out.size() < n:
		out.append(0)
	return out


func _near(a: Array, b: Array, tol: int) -> bool:
	return absi(int(a[0]) - int(b[0])) <= tol and absi(int(a[1]) - int(b[1])) <= tol


## the page's tryMoveSq message as the port's key
func _key_of(pop: String) -> String:
	if pop == "":
		return ""
	var keys := [["หน่วยนี้เดินไปแล้ว", "already_moved"], ["ติดประชิดอยู่", "engaged_need_fb"], ["ไกลเกินไป", "too_far"],
		["ตรงนั้นมีสิ่งกีดขวาง", "blocked"], ["ถอยออกไปทางนั้นไม่ได้", "cant_fall_back"], ["ไปตรงนั้นไม่ได้", "near_foe"],
		["ตรงนั้นไม่มีที่ว่างพอ", "no_room"], ["ต้องถอยให้พ้นระยะประชิด", "fb_not_clear"]]
	for kv: Variant in keys:
		if pop.begins_with(str(kv[0])):
			return str(kv[1])
	return "?" + pop


## the spec's plan_move written plainly on BtMoves.spot_free; also the decision per model [slot, kind, a, b]:
## kind 0 ring (a = PLAN_RING index), 1 straight back (a = k), 2 sidestep (a, b = k), 3 stays
func _ref_plan(st: BattleState, s: BattleState.Squad, x0: int, z0: int) -> Dictionary:
	var pts: Array = []
	var path: Array = []
	if s == null or s.models.is_empty():
		return {"pts": pts, "path": path}
	var x := 10 * Fx.js_round(x0, 10)
	var z := 10 * Fx.js_round(z0, 10)
	var r := BtSquads.radius(s)
	var rng := BtMoves.move_range(s)
	var c := BtSquads.center(s)
	var f := PackedInt64Array([s.fx, s.fz])
	if Fx.dist2(c[0], c[1], x, z) > 300 * 300:
		f = Fx.norm1000(x - c[0], z - c[1])
	elif s.fx == 0 and s.fz == 0:
		f = PackedInt64Array([0, 1000])
	var slots := BtSquads.formation(s.models.size(), x, z, f[0], f[1], r)
	var used := {}
	var chosen: Array[PackedInt64Array] = []
	for m: BattleState.Unit in s.models:
		var best := -1
		var bd := 0
		for j: int in slots.size():
			if used.has(j):
				continue
			var d2 := Fx.dist2(slots[j][0], slots[j][1], m.x, m.z)
			if best < 0 or d2 < bd:
				best = j
				bd = d2
		used[best] = true
		var sx: int = slots[best][0]
		var sz: int = slots[best][1]
		var spot: Array = []
		var step: Array = []
		for i: int in BtOffsets.PLAN_RING.size():
			var px: int = sx + int(BtOffsets.PLAN_RING[i][0])
			var pz: int = sz + int(BtOffsets.PLAN_RING[i][1])
			if rng + 1 < 0 or Fx.dist2(px, pz, m.x, m.z) > (rng + 1) * (rng + 1):
				continue
			if absi(px) > st.w * 500 - 1200 or absi(pz) > st.d * 500 - 1200:
				continue
			if BtMoves.spot_free(st, s, px, pz, r, chosen):
				spot = [px, pz]
				step = [best, 0, i, 0]
				break
		var dx := sx - m.x
		var dz := sz - m.z
		var le := Fx.isqrt(dx * dx + dz * dz)
		if le == 0:
			le = 1000
		if spot.is_empty():
			var ff := mini(rng, le)
			for k: int in range(10, 0, -1):
				var qx := m.x + 10 * Fx.js_round(dx * ff * k, le * 100)
				var qz := m.z + 10 * Fx.js_round(dz * ff * k, le * 100)
				if BtMoves.spot_free(st, s, qx, qz, r, chosen):
					spot = [qx, qz]
					step = [best, 1, k, 0]
					break
		if spot.is_empty() and le - 300 > 0:
			var lim := (le - 300) * (le - 300)
			var u := Fx.norm1000(dx, dz)
			if u[0] == 0 and u[1] == 0:
				u = PackedInt64Array([0, 1000])
			for a: int in range(1, 9):
				var rot: Array = BtOffsets.SIDESTEP_ROT[(a + 1) / 2 - 1]
				var cc: int = rot[0]
				var sn: int = rot[1]
				var sg := 1 if a % 2 == 1 else -1
				var vx := Fx.js_round(u[0] * cc + sg * u[1] * sn, 65536)
				var vz := Fx.js_round(u[1] * cc - sg * u[0] * sn, 65536)
				for k: int in range(5, 0, -1):
					var qx := m.x + 10 * Fx.js_round(vx * rng * k, 50000)
					var qz := m.z + 10 * Fx.js_round(vz * rng * k, 50000)
					var dd := Fx.dist2(sx, sz, qx, qz)
					if dd < lim and BtMoves.spot_free(st, s, qx, qz, r, chosen):
						lim = dd
						spot = [qx, qz]
						step = [best, 2, a, k]
		if spot.is_empty():
			spot = [m.x, m.z]
			step = [best, 3, 0, 0]
		chosen.append(PackedInt64Array(spot))
		pts.append(spot)
		path.append(step)
	return {"pts": pts, "path": path}


## the spec's charge_spots written plainly; decision per model [target model index, kind, try]:
## kind 0 a try round the target, 1 free_spot, 2 own spot after free_spot found none, 3 no target model
func _ref_charge(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, dist: int) -> Dictionary:
	var pts: Array = []
	var path: Array = []
	var taken: Array = []
	var ts: Array = t.models if t != null else []
	for m: BattleState.Unit in s.models:
		var best := -1
		var bd := 0
		for j: int in ts.size():
			var q: BattleState.Unit = ts[j]
			var d2 := Fx.dist2(m.x, m.z, q.x, q.z)
			if best < 0 or d2 < bd:
				best = j
				bd = d2
		if best < 0:
			pts.append([m.x, m.z])
			path.append([-1, 3, 0])
			continue
		var b: BattleState.Unit = ts[best]
		var rm := BtSquads.radius_of(m.ti)
		var rr := rm + BtSquads.radius_of(b.ti) + 300
		var u := Fx.norm1000(m.x - b.x, m.z - b.z)
		if u[0] == 0 and u[1] == 0:
			u = PackedInt64Array([0, 1000])
		var spot: Array = []
		var step: Array = []
		for tries: int in 9:
			var vx: int = u[0]
			var vz: int = u[1]
			if tries > 0:
				var rot: Array = BtOffsets.CHARGE_ROT[(tries + 1) / 2 - 1]
				var cc: int = rot[0]
				var sn: int = rot[1]
				var sg := 1 if tries % 2 == 1 else -1
				vx = Fx.js_round(u[0] * cc + sg * u[1] * sn, 65536)
				vz = Fx.js_round(u[1] * cc - sg * u[0] * sn, 65536)
			var qx := b.x + 10 * Fx.js_round(vx * rr, 10000)
			var qz := b.z + 10 * Fx.js_round(vz * rr, 10000)
			if dist + 1 < 0 or Fx.dist2(qx, qz, m.x, m.z) > (dist + 1) * (dist + 1):
				continue
			if BtBlocking.block_at(st, qx, qz):
				continue
			var hit := false
			for p: Variant in taken:
				if Fx.dist2(int(p[0]), int(p[1]), qx, qz) < 4 * rm * rm:
					hit = true
			if hit or BtBlocking.crowded(st, qx, qz, m, -1):
				continue
			spot = [qx, qz]
			step = [best, 0, tries]
			break
		if spot.is_empty():
			var dx := b.x - m.x
			var dz := b.z - m.z
			var le := Fx.isqrt(dx * dx + dz * dz)
			if le == 0:
				le = 1000
			var go := maxi(0, mini(dist, le - rr))
			var fs := BtBlocking.free_spot(st, m.x + 10 * Fx.js_round(dx * go, le * 10), m.z + 10 * Fx.js_round(dz * go, le * 10),
				m, PackedInt64Array([m.x, m.z]), dist, rm)
			if fs.is_empty():
				spot = [m.x, m.z]
				step = [best, 2, 0]
			else:
				spot = [fs[0], fs[1]]
				step = [best, 1, 0]
		taken.append(spot)
		pts.append(spot)
		path.append(step)
	return {"pts": pts, "path": path}


## the caller's loop of a group move (UI / Battle.group_move): plan, then act and apply squad by squad
func _group_run(st: BattleState, ids: PackedStringArray, x: int, z: int) -> Dictionary:
	var steps: Array = []
	var acts: Array = []
	var out: Array[Dictionary] = []
	for step: Dictionary in BtMoves.group_plan(st, ids, x, z):
		var act := BtMoves.group_act(st, step)
		steps.append([str(step["u"]), 0 if act.is_empty() else 1])
		if act.is_empty():
			continue
		acts.append(act)
		BtMoves.apply_smove(st, st.squad(str(act["u"])), act["to"], str(act["how"]), out)
	return {"steps": steps, "acts": acts}


func _ids(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	for x: Variant in v:
		out.append(str(x))
	return out


# ---------------------------------------------------------------- the page
func test_fixture_loaded() -> void:
	assert_true(F.has("worlds") and F.has("plan") and F.has("try") and F.has("group") and F.has("charge") and F.has("smove"),
		"page fixture loaded from " + FIX)
	var meta: Dictionary = F.get("meta", {})
	assert_eq(str(meta.get("app_ver", "")), "9.4", "recorded from page APP_VER 9.4")
	assert_eq(_i(meta.get("eps_mi", 0)), 50, "robust = no decision flips within 50 MI")
	var live: Array = meta.get("live_check", [])
	var same := live.size() >= 4
	for c: Variant in live:
		same = same and bool(c["same"]) and _i(c["n"]) > 0
	assert_true(same, "the recorder's live check: the cut tryMoveSq / groupMove send the running page's acts", live)
	assert_eq(_worlds.size(), 6, "six sampled worlds")


func test_move_range_matches_page() -> void:
	var bad: Array = []
	var st := _st()
	var n := 0
	for rv: Variant in F["move_range"]:
		var r: Array = rv
		var s := st.add_squad("mr%d" % n, str(r[0]), 0, 0, 1, 0)
		n += 1
		for a: int in 7:
			s.adv = a > 0
			s.adv_r = a
			if BtMoves.move_range(s) != _i(r[a + 1]):
				bad.append([r[0], a, BtMoves.move_range(s), r[a + 1]])
	assert_true(n > 100, "%d open datasheets sampled" % n)
	assert_true(bad.is_empty(), "move_range equals the page's moveRange walking and after advances of 1..6", bad.slice(0, 5))


func test_near_foe_and_spot_free_match_page() -> void:
	var bad_nf: Array = []
	var bad_sf: Array = []
	var nf_n := 0
	var sf_n := 0
	var sf_frag := 0
	for rv: Variant in F["near_foe"]:
		var r: Array = rv
		var st := _worlds[_i(r[0])]
		if _i(r[6]) != 1:
			continue
		nf_n += 1
		if BtMoves.near_foe(st, st.squad(str(r[1])), _i(r[2]), _i(r[3]), _i(r[4])) != (_i(r[5]) == 1):
			bad_nf.append(r)
	for rv: Variant in F["spot_free"]:
		var r: Array = rv
		var st := _worlds[_i(r[0])]
		var chosen: Array[PackedInt64Array] = []
		for p: Variant in r[5]:
			chosen.append(PackedInt64Array([_i(p[0]), _i(p[1])]))
		var got := BtMoves.spot_free(st, st.squad(str(r[1])), _i(r[2]), _i(r[3]), _i(r[4]), chosen)
		if _i(r[7]) != 1:
			sf_frag += 1
			continue
		sf_n += 1
		if got != (_i(r[6]) == 1):
			bad_sf.append(r)
	assert_true(nf_n >= 300 and sf_n >= 300, "%d nearFoe and %d spotFree samples (%d spotFree within 12 MI of an edge, skipped)" % [nf_n, sf_n, sf_frag])
	assert_true(bad_nf.is_empty(), "near_foe equals the page's nearFoe", bad_nf.slice(0, 5))
	assert_true(bad_sf.is_empty(), "spot_free equals the page's spotFree", bad_sf.slice(0, 5))


func test_plan_move_matches_page() -> void:
	var bad_ref: Array = []
	var bad_path: Array = []
	var bad_pts: Array = []
	var models := 0
	var lead := 0
	var whole := 0
	var frag_same := 0
	var frag := 0
	var worst := 0
	for sv: Variant in F["plan"]:
		var smp: Dictionary = sv
		var st := _worlds[_i(smp["w"])]
		var s := st.squad(str(smp["u"]))
		var x := _i(smp["x"])
		var z := _i(smp["z"])
		var got := _arr(BtMoves.plan_move(st, s, x, z))
		var ref := _ref_plan(st, s, x, z)
		if got != ref["pts"]:
			bad_ref.append([smp["w"], smp["u"], x, z])
		var want := _ints(smp["to"])
		var path: Array = smp["path"]
		var ok_n := _i(smp["ok_n"])
		models += path.size()
		lead += ok_n
		var rng_in := BtMoves.move_range(s) / 1000
		for i: int in ok_n:
			if _pad(path[i], 4) != ref["path"][i]:
				bad_path.append([smp["w"], smp["u"], x, z, i, path[i], ref["path"][i]])
				break
			var tol := TOL + (2 * rng_in if _i(path[i][1]) == 2 else 0)
			worst = maxi(worst, maxi(absi(int(got[i][0]) - int(want[i][0])), absi(int(got[i][1]) - int(want[i][1]))))
			if not _near(got[i], want[i], tol):
				bad_pts.append([smp["w"], smp["u"], x, z, i, got[i], want[i]])
				break
		if _i(smp["robust"]) == 1:
			whole += 1
		else:
			frag += 1
			var same := got.size() == want.size()
			for i: int in mini(got.size(), want.size()):
				same = same and _near(got[i], want[i], TOL)
			if same:
				frag_same += 1
	assert_true(bad_ref.is_empty(), "plan_move equals the plain reference on all %d page samples" % F["plan"].size(), bad_ref.slice(0, 5))
	assert_true(lead >= 250, "%d of %d model decisions come before any fragile step (%d whole samples robust)" % [lead, models, whole])
	assert_true(bad_path.is_empty(), "every robust decision takes the page's path (slot, ring index / step)", bad_path.slice(0, 5))
	assert_true(bad_pts.is_empty(), "and lands within %d MI per axis of the page's point (worst %d)" % [TOL, worst], bad_pts.slice(0, 5))
	assert_true(frag_same * 2 >= frag, "fragile samples mostly agree anyway: %d of %d (only counted)" % [frag_same, frag])


func test_try_move_matches_page() -> void:
	var bad: Array = []
	var n := 0
	var keys := {}
	var frag := 0
	var frag_same := 0
	var re := RegEx.create_from_string("<b>([0-9.]+)\"</b> / เดินได้ ([0-9]+)\"")
	for sv: Variant in F["try"]:
		var smp: Dictionary = sv
		var st := _worlds[_i(smp["w"])]
		var s := st.squad(str(smp["u"]))
		var res := BtMoves.try_move(st, s, _i(smp["x"]), _i(smp["z"]), _i(smp["fb"]) == 1)
		var want := _key_of(str(smp["pop"]))
		var same := str(res["key"]) == want
		if same and want == "too_far":
			var m := re.search(str(smp["pop"]))
			var args: Array = res["args"]
			same = m != null and _i(args[1]) == int(m.get_string(2)) and absi(_i(args[0]) - roundi(float(m.get_string(1)) * 1000.0)) <= 52
		if same and want == "":
			var act: Dictionary = res["act"]
			var pa: Dictionary = smp["act"]
			var to: Array = act.get("to", [])
			var pto := _ints(pa["to"])
			same = str(act.get("a", "")) == "smove" and str(act["u"]) == str(pa["u"]) and str(act["how"]) == str(pa["how"]) and to.size() == pto.size()
			for i: int in mini(to.size(), pto.size()):
				same = same and _near(to[i], pto[i], TOL + 2 * BtMoves.move_range(s) / 1000)
		# an act comes with the empty key and only then
		var act0: Dictionary = res["act"]
		same = same and (str(res["key"]) == "") == (not act0.is_empty())
		if _i(smp["robust"]) == 1:
			n += 1
			keys[want] = int(keys.get(want, 0)) + 1
			if not same:
				bad.append([smp["w"], smp["u"], smp["x"], smp["z"], smp["fb"], want, res["key"], res["args"]])
		else:
			frag += 1
			if same:
				frag_same += 1
	assert_true(n >= 150, "%d robust tryMoveSq samples: %s" % [n, str(keys)])
	assert_true(bad.is_empty(), "try_move gives the page's answer (key, too_far numbers, the smove act within %d MI)" % TOL, bad.slice(0, 5))
	assert_true(frag_same * 2 >= frag, "fragile samples mostly agree anyway: %d of %d (only counted)" % [frag_same, frag])


func test_group_move_matches_page() -> void:
	var bad: Array = []
	var n := 0
	var steps_n := 0
	for sv: Variant in F["group"]:
		var smp: Dictionary = sv
		var st := _world(_i(smp["w"]))
		var run := _group_run(st, _ids(smp["ids"]), _i(smp["x"]), _i(smp["z"]))
		var psteps: Array = smp["steps"]
		var pacts: Array = smp["acts"]
		var ok_n := _i(smp["ok_n"])
		var gsteps: Array = run["steps"]
		var gacts: Array = run["acts"]
		var ai := 0
		for i: int in ok_n:
			steps_n += 1
			if i >= gsteps.size() or str(gsteps[i][0]) != str(psteps[i][0]) or _i(gsteps[i][1]) != _i(psteps[i][1]):
				bad.append([smp["w"], smp["ids"], "step", i, gsteps.slice(0, ok_n), psteps.slice(0, ok_n)])
				break
			if _i(psteps[i][1]) == 0:
				continue
			var ga: Dictionary = gacts[ai]
			var pa: Dictionary = pacts[ai]
			ai += 1
			var to: Array = ga["to"]
			var pto := _ints(pa["to"])
			var q := st.squad(str(ga["u"]))
			var same := str(ga["how"]) == str(pa["how"]) and to.size() == pto.size()
			for j: int in mini(to.size(), pto.size()):
				same = same and _near(to[j], pto[j], TOL + 2 * BtMoves.move_range(q) / 1000)
			if not same:
				bad.append([smp["w"], smp["ids"], "act", i, to, pto])
				break
		if _i(smp["robust"]) == 1:
			n += 1
			if gsteps.size() != psteps.size():
				bad.append([smp["w"], smp["ids"], "count", gsteps, psteps])
	assert_true(n >= 25 and steps_n >= 15, "%d robust groupMove samples, %d squads ahead of any fragile step" % [n, steps_n])
	assert_true(bad.is_empty(), "group_plan + group_act + apply_smove send the page's acts in the page's order", bad.slice(0, 3))


func test_charge_spots_match_page() -> void:
	var bad_ref: Array = []
	var bad: Array = []
	var lead := 0
	var models := 0
	var worst := 0
	for sv: Variant in F["charge"]:
		var smp: Dictionary = sv
		var st := _worlds[_i(smp["w"])]
		var s := st.squad(str(smp["u"]))
		var t := st.squad(str(smp["t"]))
		var dist := _i(smp["dist"]) * 1000
		var got := _arr(BtMoves.charge_spots(st, s, t, dist))
		var ref := _ref_charge(st, s, t, dist)
		if got != ref["pts"]:
			bad_ref.append([smp["w"], smp["u"], smp["t"], smp["dist"]])
		var want := _ints(smp["to"])
		var path: Array = smp["path"]
		var ok_n := _i(smp["ok_n"])
		models += path.size()
		lead += ok_n
		for i: int in ok_n:
			if _pad(path[i], 3) != ref["path"][i]:
				bad.append([smp["w"], smp["u"], smp["t"], smp["dist"], i, path[i], ref["path"][i]])
				break
			worst = maxi(worst, maxi(absi(int(got[i][0]) - int(want[i][0])), absi(int(got[i][1]) - int(want[i][1]))))
			if not _near(got[i], want[i], TOL_CHARGE):
				bad.append([smp["w"], smp["u"], smp["t"], smp["dist"], i, got[i], want[i]])
				break
	assert_true(bad_ref.is_empty(), "charge_spots equals the plain reference on all %d page samples" % F["charge"].size(), bad_ref.slice(0, 5))
	assert_true(lead >= 150, "%d of %d model decisions come before any fragile step" % [lead, models])
	assert_true(bad.is_empty(), "every robust decision takes the page's path and lands within %d MI (worst %d)" % [TOL_CHARGE, worst], bad.slice(0, 5))


func test_apply_smove_matches_page() -> void:
	var bad: Array = []
	for sv: Variant in F["smove"]:
		var smp: Dictionary = sv
		var st := _world(_i(smp["w"]))
		var s := st.squad(str(smp["u"]))
		var out: Array[Dictionary] = []
		BtMoves.apply_smove(st, s, _ints(smp["to"]), str(smp["how"]), out)
		var after: Array = []
		for m: BattleState.Unit in s.models:
			after.append([m.x, m.z])
		var log: String = str(smp["log"])
		var key := ""
		if log != "":
			key = "smove_fb" if log.contains("ถอย") else ("smove_adv" if log.contains("วิ่ง") else "smove_move")
		var got_key := "" if st.log_lines.is_empty() else str(st.log_lines.back()["key"])
		var same := after == _ints(smp["after"]) and s.moved == (_i(smp["moved"]) == 1) and s.still == (_i(smp["still"]) == 1) \
			and s.fell == (_i(smp["fell"]) == 1) and got_key == key
		if same and key != "":
			# the page logs far.toFixed(1) inches; the port logs isqrt of the largest d2 (MI)
			var far_in := float(log.get_slice(" ", log.get_slice_count(" ") - 1).trim_suffix("\""))
			same = absi(_i(st.log_lines.back()["args"][1]) - roundi(far_in * 1000.0)) <= 51
		if not same:
			bad.append([smp["w"], smp["u"], smp["how"], after, smp["after"], s.moved, s.still, s.fell, got_key, log])
	assert_eq((F["smove"] as Array).size(), 60, "60 applySMove samples")
	assert_true(bad.is_empty(), "apply_smove: positions (with the table clamp), moved / still / fell and the log equal the page", bad.slice(0, 3))


func test_group_all_matches_page() -> void:
	var bad: Array = []
	for sv: Variant in F["group_all"]:
		var smp: Dictionary = sv
		var st := _worlds[_i(smp["w"])]
		var turn0 := st.turn
		st.turn = _i(smp["turn"])
		var can: Array = []
		for s: BattleState.Squad in st.squads:
			can.append(1 if BtMoves.can_group(st, s) else 0)
		if Array(BtMoves.group_all(st)) != smp["all"] or can != _ints(smp["can"]):
			bad.append([smp["w"], smp["turn"], BtMoves.group_all(st), smp["all"], can, smp["can"]])
		st.turn = turn0
	assert_true(bad.is_empty(), "can_group and group_all equal the page's canGroup (canAct aside) and groupAll", bad.slice(0, 3))



# ---------------------------------------------------------------- hand cases
func test_move_range_hand() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	assert_eq(BtMoves.move_range(s), 6000, "infantry walks 6 inches")
	s.adv_r = 4
	assert_eq(BtMoves.move_range(s), 6000, "an advance roll counts only once the squad advanced")
	s.adv = true
	assert_eq(BtMoves.move_range(s), 10000, "advanced: 6 + 4 inches")
	assert_eq(BtMoves.move_range(_sq(st, "0:1", "cavalry", 0, [[5000, 0]])), 12000, "cavalry 12 inches")
	assert_eq(BtMoves.move_range(null), 0, "no squad has no range")
	var ghost := st.add_squad("0:2", "no-such-unit", 0, 0, 1, 0)
	assert_eq(BtMoves.move_range(ghost), int(GameData.types()[0]["mv"]) * 1000, "an unknown key reads the first datasheet (the page's TY)")
	assert_eq(BtMoves.NEAR_PAD, GameData.const_int("ENGAGE", -1) * 1000 + 50, "NEAR_PAD is ENGAGE plus the page's 0.05 inch")


func test_near_foe_margin() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[-20000, 0]])
	_sq(st, "1:0", "infantry", 1, [[0, 0]])
	# two 800 MI bases: edge 1049 / 1050 / 1051 MI at centre distance 2649 / 2650 / 2651
	assert_true(BtMoves.near_foe(st, a, 2649, 0, 800), "edge 1049 MI is near")
	assert_true(BtMoves.near_foe(st, a, 2650, 0, 800), "edge 1050 MI is near (ENGAGE + 0.05 inch, inclusive)")
	assert_false(BtMoves.near_foe(st, a, 2651, 0, 800), "edge 1051 MI is not")
	assert_true(BtMoves.near_foe(st, a, -1590, -2120, 800), "a diagonal at exactly 2650 (3-4-5) is near")
	assert_false(BtMoves.near_foe(st, a, -1591, -2120, 800), "one MI further out is not")
	assert_true(BtMoves.near_foe(st, a, 3100, 0, 1250), "the base radius r counts: 1250 + 800 + 1050")
	assert_false(BtMoves.near_foe(st, a, 3101, 0, 1250), "and one MI past it is free")
	var c := _sq(st, "2:0", "cavalry", 2, [[0, 10000]])
	assert_true(BtMoves.near_foe(st, a, 0, 10000 - 2950, 800), "a foe's own base radius counts (cavalry 1100)")
	assert_false(BtMoves.near_foe(st, a, 0, 10000 - 2951, 800), "and one MI past it is free")
	var mate := _sq(st, "0:1", "infantry", 0, [[0, -8000]])
	assert_false(BtMoves.near_foe(st, a, 0, -8000, 800), "a team-mate is never a foe")
	st.free_fire = true
	assert_false(BtMoves.near_foe(st, a, 0, -8000, 800), "not even with free fire (the page counts sides)")
	st.remove_unit(c.models[0])
	assert_false(BtMoves.near_foe(st, a, 0, 10000 - 2000, 800), "a dead foe is gone")
	assert_false(BtMoves.near_foe(st, null, 0, 0, 800), "no squad: false")
	assert_eq(mate.models.size(), 1, "the team-mate still stands")


func test_spot_free_hand() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[0, 0], [2000, 0]])
	_sq(st, "0:1", "infantry", 0, [[5000, 0]])
	_sq(st, "1:0", "infantry", 1, [[0, 12000]])
	_props(st, [_prop("building", -9000, -9000, 4000, 4000)])
	var none: Array[PackedInt64Array] = []
	assert_true(BtMoves.spot_free(st, a, 3400, 0, 800, none), "exactly r + r_q from another squad's model is free (strict overlap)")
	assert_false(BtMoves.spot_free(st, a, 3401, 0, 800, none), "one MI closer overlaps")
	assert_true(BtMoves.spot_free(st, a, 0, 0, 800, none), "the squad's own models do not count (they are moving)")
	assert_true(BtMoves.spot_free(st, a, 2000, 0, 800, none), "nor does any other model of the same squad")
	var chosen: Array[PackedInt64Array] = [PackedInt64Array([0, 3000])]
	assert_true(BtMoves.spot_free(st, a, 0, 4600, 800, chosen), "exactly 2r from a chosen spot is free")
	assert_false(BtMoves.spot_free(st, a, 0, 4599, 800, chosen), "one MI closer is taken")
	assert_false(BtMoves.spot_free(st, a, 0, 12000 - 2650, 800, none), "near a foe is not free")
	assert_true(BtMoves.spot_free(st, a, 0, 12000 - 2651, 800, none), "just outside the near-foe margin is")
	assert_false(BtMoves.spot_free(st, a, -9000, -9000, 800, none), "inside a building is not free")
	assert_true(BtMoves.spot_free(st, a, 23200, 0, 800, none), "the table edge margin is 800 MI (block_at)")
	assert_false(BtMoves.spot_free(st, a, 23201, 0, 800, none), "one MI past it is blocked")
	assert_false(BtMoves.spot_free(st, null, 0, 0, 800, none), "no squad: false")


func _sorted(pts: Variant) -> Array:
	var out: Array = []
	for p: Variant in pts:
		out.append([int(p[0]), int(p[1])])
	out.sort()
	return out


func test_plan_open_table_keeps_formation() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[-1950, 0], [0, 0], [1950, 0]])
	var got := BtMoves.plan_move(st, s, 0, 4000)
	assert_eq(_arr(got), [[-1950, 4000], [0, 4000], [1950, 4000]], "a row of three, 4 inches ahead: each model takes its own slot")
	var far := 0
	for i: int in got.size():
		far = maxi(far, Fx.dist2(got[i][0], got[i][1], s.models[i].x, s.models[i].z))
	assert_eq(far, 16000000, "everyone moved exactly 4 inches")
	var col := _sq(st, "0:1", "infantry", 0, [[-9000, -1950], [-9000, 0], [-9000, 1950]])
	assert_eq(_arr(BtMoves.plan_move(st, col, -6000, 0)), [[-6000, -1950], [-6000, 0], [-6000, 1950]],
		"a target to +x: the formation turns to face +x (a row across x)")
	# two rows of three: the slot pick is greedy by distance (strict, first index wins), so the front row, nearer the
	# new back row, takes it and the back row walks on to the new front row (5756 MI, inside the 6 inch range)
	var six := BtSquads.formation(6, 0, -12000, 0, 1000, 800)
	var pts: Array = []
	for p: PackedInt64Array in six:
		pts.append([p[0], p[1]])
	var two := _sq(st, "0:2", "infantry", 0, pts)
	var want := BtSquads.formation(6, 0, -8000, 0, 1000, 800)
	assert_eq(_arr(BtMoves.plan_move(st, two, 0, -8000)), [_p(want[3]), _p(want[4]), _p(want[5]), _p(want[0]), _p(want[1]), _p(want[2])],
		"two rows, 4 inches ahead: the rows swap (the page's greedy nearest slot)")


func _p(p: PackedInt64Array) -> Array:
	return [p[0], p[1]]


func test_plan_short_move_uses_squad_facing() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, -2000], [0, 0], [0, 2000]], 1000, 0)
	# the centre is (0, 0): a target 200 MI away keeps the squad's own facing (+x), not the 200 MI vector (+z)
	assert_eq(_sorted(BtMoves.plan_move(st, s, 0, 200)), _sorted(BtSquads.formation(3, 0, 200, 1000, 0, 800)),
		"a nudge within 300 MI keeps the squad facing")
	assert_eq(_sorted(BtMoves.plan_move(st, s, 0, 300)), _sorted(BtSquads.formation(3, 0, 300, 1000, 0, 800)),
		"exactly 300 MI is still a nudge (strict >)")
	assert_eq(_sorted(BtMoves.plan_move(st, s, 0, 310)), _sorted(BtSquads.formation(3, 0, 310, 0, 1000, 800)),
		"past 300 MI the formation faces the target")
	s.fx = 0
	s.fz = 0
	assert_eq(_sorted(BtMoves.plan_move(st, s, 0, 200)), _sorted(BtSquads.formation(3, 0, 200, 0, 1000, 800)),
		"no facing at all reads as +z (the page's face 0)")


func test_plan_far_target_stops_at_range() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[-1950, 0], [0, 0], [1950, 0]])
	var got := BtMoves.plan_move(st, s, 0, 15000)
	var rng := BtMoves.move_range(s)
	var ok := got.size() == 3
	for i: int in got.size():
		var d2 := Fx.dist2(got[i][0], got[i][1], s.models[i].x, s.models[i].z)
		ok = ok and d2 <= (rng + 1) * (rng + 1) and d2 > (rng - 1000) * (rng - 1000)
		ok = ok and Fx.imod(got[i][0], 10) == 0 and Fx.imod(got[i][1], 10) == 0
	assert_true(ok, "a target 15 inches off: everyone moves nearly the full 6 inches and no further, on the grid", _arr(got))
	assert_eq(_arr(got), _ref_plan(st, s, 0, 15000)["pts"], "and the reference agrees")


func test_plan_straight_back_and_sidestep() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	# a wide house in front (z 1300..7200): the far slot is out of range, the straight line is blocked past 1200 MI
	_props(st, [_prop("building", 0, 4250, 14000, 4500)])
	assert_eq(_arr(BtMoves.plan_move(st, s, 0, 20000)), [[0, 1200]], "straight back: the last free step of ten on the line (k = 2)")
	assert_eq(_ref_plan(st, s, 0, 20000)["path"], [[0, 1, 2, 0]], "decision: straight back, k = 2")
	# a narrow tall house (x -1700..1700, z 300..7200): every straight step is blocked, the sidestep goes round it
	_props(st, [_prop("building", 0, 3750, 2000, 5500)])
	assert_eq(_arr(BtMoves.plan_move(st, s, 0, 20000)), [[2330, 5530]], "sidestep: +0.4 rad at the full 6 inches, the free point nearest the slot")
	assert_eq(_ref_plan(st, s, 0, 20000)["path"], [[0, 2, 1, 5]], "decision: sidestep a = 1, k = 5 (its mirror point ties and loses)")
	var m := _sq(st, "0:1", "infantry", 0, [[0, 15000]])
	assert_eq(_arr(BtMoves.plan_move(st, m, 0, -5000)), _ref_plan(st, m, 0, -5000)["pts"], "approaching from the other side agrees with the reference")
	# a wall along the path (a quarter turn: blocks |x| < 1500, z -900..7500): the same sidestep round its side
	var w := _st()
	var lone := _sq(w, "0:0", "infantry", 0, [[0, 0]])
	_props(w, [BtBlocking.prep_one("wall", 0, 3300, FieldProps.TWO_PI / 4, 10000, 0, 0, 0)])
	assert_true(BtBlocking.block_at(w, 0, 600) and BtBlocking.block_at(w, 0, 6000) and not BtBlocking.block_at(w, 1600, 3000),
		"the wall covers the straight line and nothing beside it")
	assert_eq(_arr(BtMoves.plan_move(w, lone, 0, 20000)), [[2330, 5530]], "a wall in the way: sidestep round it")


func test_turn_tables() -> void:
	var r0: Array = BtOffsets.SIDESTEP_ROT[0]
	var c0: Array = BtOffsets.CHARGE_ROT[0]
	assert_eq(BtMoves.turn(0, 1000, int(r0[0]), int(r0[1]), true), PackedInt64Array([389, 921]), "+0.4 rad from +z: (sin, cos) of 0.4 at length 1000")
	assert_eq(BtMoves.turn(0, 1000, int(r0[0]), int(r0[1]), false), PackedInt64Array([-389, 921]), "-0.4 rad mirrors x")
	assert_eq(BtMoves.turn(1000, 0, int(c0[0]), int(c0[1]), true), PackedInt64Array([853, -523]), "+0.55 rad from +x turns towards -z (the atan2(x, z) convention)")
	assert_eq(BtMoves.turn(-600, -800, 65536, 0, true), PackedInt64Array([-600, -800]), "a zero turn keeps the vector")
	assert_eq(BtMoves.snap(-8505), -8500, "snap rounds half up (js_round): -8505 to -8500")
	assert_eq(BtMoves.snap(8505), 8510, "and +8505 to +8510")


func test_plan_boxed_in_stays() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [1950, 0], [-1950, 0]])
	_props(st, [_prop("building", 0, 0, 30000, 30000)])
	assert_eq(_arr(BtMoves.plan_move(st, s, 0, 5000)), [[0, 0], [1950, 0], [-1950, 0]], "inside a house that fills the reach: everyone stays")
	var kinds: Array = []
	for p: Variant in _ref_plan(st, s, 0, 5000)["path"]:
		kinds.append(int(p[1]))
	assert_eq(kinds, [3, 3, 3], "decision: stays, for every model")
	var t := _st()
	var lone := _sq(t, "0:0", "infantry", 0, [[1500, 1500]])
	for i: int in range(-3, 4):
		for j: int in range(-3, 4):
			_sq(t, "1:%d_%d" % [i + 3, j + 3], "infantry", 1, [[i * 3000, j * 3000]])
	assert_eq(_arr(BtMoves.plan_move(t, lone, 1500, 2500)), [[1500, 1500]], "foes everywhere within reach: the model stays")


func test_plan_chosen_spacing_and_snap() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [0, 100]])
	var got := BtMoves.plan_move(st, s, 0, 3000)
	assert_true(Fx.dist2(got[0][0], got[0][1], got[1][0], got[1][1]) >= 1600 * 1600, "two models never end within 2r of each other", _arr(got))
	assert_eq(_arr(BtMoves.plan_move(st, s, 1234, 2995)), _arr(BtMoves.plan_move(st, s, 1230, 3000)), "an off-grid target is snapped to the 10 MI grid first (half up)")
	assert_eq(BtMoves.plan_move(st, null, 0, 0).size(), 0, "no squad: no plan")
	var e := _sq(st, "0:1", "infantry", 0, [[20000, 0]])
	var edge := BtMoves.plan_move(st, e, 23500, 0)
	assert_true(absi(edge[0][0]) <= 24000 - 1200, "a target past the table margin: the ring point found stays inside it", _arr(edge))
	st.remove_unit(s.models[1])
	st.remove_unit(s.models[0])
	assert_eq(BtMoves.plan_move(st, s, 0, 0).size(), 0, "a wiped squad: no plan")


func _events(out: Array[Dictionary]) -> Array:
	var names: Array = []
	for e: Dictionary in out:
		names.append(Events.name_of(Events.id_of(e)))
	return names


func _arr_units(s: BattleState.Squad) -> Array:
	var out: Array = []
	for m: BattleState.Unit in s.models:
		out.append([m.x, m.z])
	return out


func test_apply_smove_thresholds() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [2000, 0], [4000, 0]])
	var out: Array[Dictionary] = []
	BtMoves.apply_smove(st, s, [[49, 0], [2000, 0], [4000, 0]], "move", out)
	assert_true(s.moved and s.still and s.models[0].x == 0, "49 MI: marked moved, nobody walks, still stays", [s.moved, s.still, s.models[0].x])
	assert_eq(_events(out), ["LOG_LINE"], "no MOVE_STEP, one log line")
	assert_eq(st.log_lines.back(), {"key": "smove_move", "args": ["0:0", 49]}, "log smove_move [squad, farthest MI]")
	for v: Array in [[[50, 0], 0, true], [[30, 40], 0, true], [[51, 0], 51, false], [[36, 36], 36, false]]:
		s.moved = false
		s.still = true
		s.models[0].x = 0
		s.models[0].z = 0
		out.clear()
		BtMoves.apply_smove(st, s, [v[0]], "move", out)
		assert_true(s.models[0].x == int(v[1]) and s.still == bool(v[2]),
			"%s: %s" % [str(v[0]), "stays (the page's d > 0.05 inch is d2 > 2500)" if bool(v[2]) else "walks"], [s.models[0].x, s.still])
	assert_eq(_events(out), ["MOVE_STEP", "LOG_LINE"], "a real step sends MOVE_STEP then the log line")
	assert_eq(out[0], Events.make(Events.Id.MOVE_STEP, {"uid": "0:0.0", "gx": 36, "gz": 36}), "MOVE_STEP carries the new rules position")
	s.moved = false
	s.models[0].x = 0
	s.models[0].z = 0
	BtMoves.apply_smove(st, s, [[0, -3000], [2000, -3000], [4000, -3000]], "fb", out)
	assert_true(s.fell and s.moved and not s.still, "fb sets fell (and moved, not still)")
	assert_eq([s.fx, s.fz], [0, -1000], "the centre moved 3 inches to -z: the squad faces -z")
	assert_eq(str(st.log_lines.back()["key"]), "smove_fb", "log smove_fb")
	var before := _arr_units(s)
	BtMoves.apply_smove(st, s, [[9000, 9000]], "move", out)
	assert_eq(_arr_units(s), before, "a squad that moved already ignores another smove")
	var t := _sq(st, "0:1", "infantry", 0, [[0, 6000], [2000, 6000]])
	BtMoves.apply_smove(st, t, [], "move", out)
	assert_false(t.moved, "an empty list changes nothing (moved stays false, as the page's netAct)")
	BtMoves.apply_smove(st, t, [[99999, 6000]], "adv", out)
	assert_eq(_arr_units(t), [[24000, 6000], [2000, 6000]], "only zipped models move, clamped to the table edge (24000)")
	assert_eq([t.fx, t.fz], [1000, 0], "centre shift 12 inches to +x: facing +x")
	assert_eq(str(st.log_lines.back()["key"]), "smove_move", "not advanced: smove_move (the page's text follows s.adv, not how)")
	var u := _sq(st, "0:2", "infantry", 0, [[-6000, -6000], [-4000, -6000], [-2000, -6000]], 0, 1000)
	u.adv = true
	BtMoves.apply_smove(st, u, [[-6000, -5400], [-4000, -6000], [-2000, -6000], [5, 5]], "adv", out)
	assert_eq([u.fx, u.fz], [0, 1000], "a centre shift of 200 MI keeps the facing; extra points are ignored")
	assert_eq(st.log_lines.back(), {"key": "smove_adv", "args": ["0:2", 600]}, "advanced squads log smove_adv")
	assert_eq(BtMoves.point("bad"), PackedInt64Array([0, 0]), "a malformed point reads as [0, 0] (the server's rule)")
	assert_eq(BtMoves.point(PackedInt64Array([7, 8])), PackedInt64Array([7, 8]), "a packed point reads as is")


func test_go_to_clamps() -> void:
	var st := _st(47)
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	BtMoves.go_to(st, s.models[0], 30000, -30000)
	assert_eq([s.models[0].x, s.models[0].z], [23500, -st.d * 500], "clamped to +-w/2, +-d/2 (odd width 47: 23500)")
	BtMoves.go_to(st, s.models[0], -100, 70)
	assert_eq([s.models[0].x, s.models[0].z], [-100, 70], "inside the table: exactly where told")
	BtMoves.go_to(st, null, 0, 0)
	assert_true(true, "a missing model is ignored")


func test_try_move_keys_in_page_order() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[-10000, 0]])
	var foe := _sq(st, "1:0", "infantry", 1, [[-10000, 2200]])
	_props(st, [_prop("building", 10000, 10000, 4000, 4000)])
	a.moved = true
	assert_eq(BtMoves.try_move(st, a, 99999, 0, false)["key"], "already_moved", "moved beats everything")
	a.moved = false
	assert_eq(BtMoves.try_move(st, a, 99999, 0, false)["key"], "engaged_need_fb", "engaged without fall back beats too far")
	var r := BtMoves.try_move(st, a, -10000, -8510, true)
	assert_eq([r["key"], r["args"]], ["too_far", [8510, 6]], "fall back pressed, 8.51 inches: too_far [MI, inches]")
	st.remove_unit(foe.models[0])
	assert_eq(BtMoves.try_move(st, a, -10000, -8500, false)["key"], "", "exactly 6 + 2.5 inches is not too far")
	assert_eq(BtMoves.try_move(st, a, -10000, -8505, false)["key"], "", "-8505 snaps to -8500 (half up, towards +inf): allowed")
	assert_eq(BtMoves.try_move(st, a, -10000, -8506, false)["key"], "too_far", "-8506 snaps to -8510: too far")
	assert_eq(BtMoves.try_move(st, a, -10000, 8505, false)["key"], "too_far", "+8505 snaps to +8510: too far")
	var b := _sq(st, "0:1", "infantry", 0, [[10000, 4000]])
	assert_eq(BtMoves.try_move(st, b, 10000, 10000, false)["key"], "blocked", "a target inside a house")
	assert_eq(BtMoves.try_move(st, b, 10000, 99999, false)["key"], "too_far", "too far is checked before blocked")
	var ok := BtMoves.try_move(st, a, -10000, 3000, false)
	var act: Dictionary = ok["act"]
	assert_eq([ok["key"], act["a"], act["u"], act["how"]], ["", "smove", "0:0", "move"], "a free order: the smove act to send")
	assert_eq(act["to"], _arr(BtMoves.plan_move(st, a, -10000, 3000)), "carrying plan_move's points as [x, z] rows")
	assert_eq(a.models[0].x, -10000, "try_move applies nothing")
	a.adv = true
	a.adv_r = 3
	var r2 := BtMoves.try_move(st, a, -10000, 3000, false)
	assert_eq(str(r2["act"]["how"]), "adv", "an advanced squad sends how adv")
	assert_eq(BtMoves.try_move(st, null, 0, 0, false)["key"], "no_squad", "no squad")


func test_try_move_no_room_and_near_foe() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	# a wide house fills z 300..6700 in front: every candidate within reach is blocked or too far from the slot
	_props(st, [_prop("building", 0, 3500, 14000, 5000)])
	assert_eq(BtMoves.try_move(st, a, 0, 8000, false)["key"], "no_room", "nobody can move 300 MI: no_room")
	_sq(st, "1:0", "infantry", 1, [[0, 8000]])
	assert_false(BtSquads.is_engaged(st, a), "the foe 8 inches off does not engage")
	assert_eq(BtMoves.try_move(st, a, 0, 8000, false)["key"], "near_foe", "and with a foe at the target: near_foe")


func test_try_move_fall_back() -> void:
	var st := _st()
	# model 1 sits in a house that fills its reach, engaged with a foe; model 0 can step out to -x
	var a := _sq(st, "0:0", "infantry", 0, [[-2000, 0], [2000, 0]])
	_sq(st, "1:0", "infantry", 1, [[2000, 2200]])
	_props(st, [_prop("building", 2000, 0, 10800, 10800)])
	assert_true(BtSquads.is_engaged(st, a), "engaged")
	assert_eq(BtMoves.try_move(st, a, -5000, 0, false)["key"], "engaged_need_fb", "needs the fall back button")
	assert_eq(BtMoves.try_move(st, a, -5000, 0, true)["key"], "fb_not_clear", "one model cannot get clear: fb_not_clear")
	var t := _st()
	var lone := _sq(t, "0:0", "infantry", 0, [[1500, 1500]])
	for i: int in range(-3, 4):
		for j: int in range(-3, 4):
			_sq(t, "1:%d_%d" % [i + 3, j + 3], "infantry", 1, [[i * 3000, j * 3000]])
	assert_eq(BtMoves.try_move(t, lone, 1500, 2500, true)["key"], "cant_fall_back", "engaged and boxed in by foes: cant_fall_back")
	var u := _st()
	var c := _sq(u, "0:0", "infantry", 0, [[0, 0], [1950, 0]])
	_sq(u, "1:0", "infantry", 1, [[900, 2200]])
	var r := BtMoves.try_move(u, c, 900, -6000, true)
	var act: Dictionary = r["act"]
	assert_eq([r["key"], act.get("how", "")], ["", "fb"], "a clear fall back sends how fb")
	var safe := true
	for p: Variant in act["to"]:
		safe = safe and not BtMoves.near_foe(u, c, int(p[0]), int(p[1]), 800)
	assert_true(safe, "and every planned point is out of the near-foe margin")


func _plan_rows(plan: Array[Dictionary], keys: Array) -> Array:
	var out: Array = []
	for p: Dictionary in plan:
		var row: Array = []
		for k: Variant in keys:
			row.append(p[k])
		out.append(row)
	return out


func test_group_plan() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "infantry", 0, [[-6000, 0]])
	var b := _sq(st, "0:1", "infantry", 0, [[0, 0]])
	_sq(st, "0:2", "infantry", 0, [[6000, 0]])
	var foe := _sq(st, "1:0", "infantry", 1, [[0, 14000]])
	var ids := PackedStringArray(["0:0", "0:1", "0:2"])
	assert_eq(Array(BtMoves.group_all(st)), ["0:0", "0:1", "0:2"], "group_all: the side in turn, creation order")
	st.turn = 1
	assert_eq(Array(BtMoves.group_all(st)), ["1:0"], "the other side's turn")
	st.turn = 0
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 10000, 0), ["u", "x", "z", "how"]),
		[["0:2", 12000, 0, "move"], ["0:1", 6000, 0, "move"], ["0:0", 0, 0, "move"]],
		"10 inches east of the middle: front squad first, each 6 inches (its range) east")
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 0, 4000), ["u", "x", "z"]),
		[["0:0", -6000, 4000], ["0:1", 0, 4000], ["0:2", 6000, 4000]], "4 inches north: all tie on the projection, ids order kept")
	assert_eq(BtMoves.group_plan(st, ids, 290, 0).size(), 0, "a target under 300 MI from the middle: nothing")
	assert_eq(BtMoves.group_plan(st, ids, 300, 0).size(), 3, "exactly 300 MI moves")
	assert_eq(BtMoves.group_plan(st, PackedStringArray(), 5000, 0).size(), 0, "no squads: nothing")
	assert_eq(BtMoves.group_plan(st, PackedStringArray(["0:9", "1:0x"]), 5000, 0).size(), 0, "unknown ids are dropped")
	b.moved = true
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 0, 4000), ["u"]), [["0:0"], ["0:2"]], "a moved squad is left out")
	b.moved = false
	foe.models[0].z = 2200
	assert_false(BtMoves.can_group(st, b), "an engaged squad cannot group")
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 0, 4000), ["u"]), [["0:0"], ["0:2"]], "and is left out")
	assert_false(BtMoves.can_group(st, null), "no squad cannot group")
	foe.models[0].z = 14000
	a.adv = true
	a.adv_r = 6
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 0, 40000), ["u", "z", "how"]),
		[["0:0", 12000, "adv"], ["0:1", 6000, "move"], ["0:2", 6000, "move"]], "each squad goes its own range (advanced 12 inches)")
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 0, -90000), ["z"]), [[-12000], [-6000], [-6000]], "south, full range each")
	_sq(st, "0:3", "cavalry", 0, [[0, -14000]])
	var plan := BtMoves.group_plan(st, PackedStringArray(["0:3"]), 0, -40000)
	assert_eq([plan[0]["x"], plan[0]["z"]], [0, -(17000 - 1200)], "clamped 1200 MI inside the table edge")


func test_group_sequencing() -> void:
	var st := _st()
	_sq(st, "0:0", "infantry", 0, [[0, 0]])
	var back := _sq(st, "0:1", "infantry", 0, [[0, -3000]])
	var ids := PackedStringArray(["0:1", "0:0"])
	assert_eq(_plan_rows(BtMoves.group_plan(st, ids, 0, 1500), ["u", "z"]), [["0:0", 3000], ["0:1", 0]], "the front squad goes first")
	var early := BtMoves.plan_move(st, back, 0, 0)
	assert_ne(_arr(early), [[0, 0]], "planned too early, the follower would avoid the leader's old spot")
	var run := _group_run(st, ids, 0, 1500)
	assert_eq(run["steps"], [["0:0", 1], ["0:1", 1]], "both send an smove")
	assert_eq(_arr_units(back), [[0, 0]], "applied in order, the follower takes the spot the leader left")
	var t := _st()
	_sq(t, "0:0", "infantry", 0, [[0, 0]])
	_props(t, [_prop("building", 0, 0, 30000, 30000)])
	var step := BtMoves.group_plan(t, PackedStringArray(["0:0"]), 0, 5000)
	assert_eq(step.size(), 1, "planned")
	assert_eq(BtMoves.group_act(t, step[0]), {}, "but nobody moves 300 MI: no act")
	assert_eq(BtMoves.group_act(t, {"u": "nobody", "x": 0, "z": 0}), {}, "an unknown squad: no act")


func test_charge_spots_hand() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[0, 6000]])
	assert_eq(_arr(BtMoves.charge_spots(st, s, t, 6000)), [[0, 4100]], "straight at the nearest target model, base to base + 300 MI")
	assert_eq(_arr(BtMoves.charge_spots(st, s, t, 4100)), [[0, 4100]], "exactly the roll's reach")
	assert_eq(_arr(BtMoves.charge_spots(st, s, t, 2000)), [[0, 2000]], "out of reach: as far as the roll allows along the line (free_spot from the model)")
	var s2 := _sq(st, "0:1", "infantry", 0, [[-100, -3000], [100, -3000]])
	var two := BtMoves.charge_spots(st, s2, t, 12000)
	assert_true(Fx.dist2(two[0][0], two[0][1], two[1][0], two[1][1]) >= 1600 * 1600, "the second charger does not take a spot within 2r of the first", _arr(two))
	var tries: Array = []
	for p: Variant in _ref_charge(st, s2, t, 12000)["path"]:
		tries.append(int(p[2]))
	# at rr = 1900 MI the +-0.55 rad tries land about 1030 MI from the first spot, inside 2r: the +1.1 rad try is next
	assert_eq(tries, [0, 3], "first try straight in; the second charger skips +-0.55 rad and takes +1.1 rad")
	var dead := _sq(st, "1:1", "infantry", 1, [])
	assert_eq(_arr(BtMoves.charge_spots(st, s2, dead, 12000)), [[-100, -3000], [100, -3000]], "no target model: everyone stays")
	assert_eq(_arr(BtMoves.charge_spots(st, s2, null, 12000)), [[-100, -3000], [100, -3000]], "no target squad: everyone stays")
	assert_eq(BtMoves.charge_spots(st, null, t, 12000).size(), 0, "no charger: nothing")
	_props(st, [_prop("building", 0, 9000, 6000, 4000)])
	var u := _sq(st, "0:2", "infantry", 0, [[0, 15000]])
	var round_ := BtMoves.charge_spots(st, u, t, 12000)
	assert_false(BtBlocking.block_at(st, round_[0][0], round_[0][1]), "a house behind the target: the spot is never inside it", _arr(round_))
	assert_eq(_arr(round_), _ref_charge(st, u, t, 12000)["pts"], "and agrees with the reference")


func test_charge_spots_legal_on_page_worlds() -> void:
	var bad: Array = []
	var n := 0
	for wi: int in _worlds.size():
		var st := _worlds[wi]
		for s: BattleState.Squad in st.alive_squads():
			for t: BattleState.Squad in BtSquads.real_foes(st, s):
				for dist: int in [2000, 7000, 12000]:
					var got := BtMoves.charge_spots(st, s, t, dist)
					var ref := _ref_charge(st, s, t, dist)
					n += 1
					if _arr(got) != ref["pts"]:
						bad.append([wi, s.id, t.id, dist, "ref"])
						continue
					for i: int in got.size():
						var m := s.models[i]
						var kind := int(ref["path"][i][1])
						var p := got[i]
						if Fx.dist2(p[0], p[1], m.x, m.z) > (dist + 1) * (dist + 1) or Fx.imod(p[0], 10) != 0 or Fx.imod(p[1], 10) != 0:
							bad.append([wi, s.id, t.id, dist, i, "reach/grid"])
						elif kind == 0 and (BtBlocking.block_at(st, p[0], p[1]) or BtBlocking.crowded(st, p[0], p[1], m, -1)):
							bad.append([wi, s.id, t.id, dist, i, "a try spot blocked or crowded"])
	assert_true(n > 300, "%d charges between every pair of foe squads of the six worlds" % n)
	assert_true(bad.is_empty(), "every spot is within the roll (+1 MI) of its model, on the grid, and try spots are free", bad.slice(0, 5))


func test_plan_equals_reference_on_random_orders() -> void:
	var rng := Rng.make("test:moves", 7)
	var bad: Array = []
	var off_grid := 0
	var n := 0
	for wi: int in _worlds.size():
		var st := _worlds[wi]
		var alive := st.alive_squads()
		for k: int in 60:
			var s := alive[rng.bounded(alive.size())]
			var c := BtSquads.center(s)
			# targets anywhere: near, far, off the grid, off the table
			var span: int = [400, 3000, 9000, 40000][k % 4]
			var x := c[0] + rng.bounded(2 * span + 1) - span
			var z := c[1] + rng.bounded(2 * span + 1) - span
			var got := BtMoves.plan_move(st, s, x, z)
			n += 1
			if _arr(got) != _ref_plan(st, s, x, z)["pts"]:
				bad.append([wi, s.id, x, z])
			for p: PackedInt64Array in got:
				if Fx.imod(p[0], 10) != 0 or Fx.imod(p[1], 10) != 0:
					off_grid += 1
	assert_eq(n, 360, "360 random orders over the six page worlds")
	assert_true(bad.is_empty(), "plan_move equals the plain reference (the per-model filter never changes a result)", bad.slice(0, 5))
	assert_eq(off_grid, 0, "every planned point is on the 10 MI grid (models on the grid, any target)")


func test_plan_with_off_grid_models_and_odd_states() -> void:
	var st := _world(3)
	var s := st.alive_squads()[0]
	s.models[0].x += 3
	s.models[0].z -= 7
	var x := BtSquads.center(s)[0] + 2500
	var z := BtSquads.center(s)[1] - 1000
	assert_eq(_arr(BtMoves.plan_move(st, s, x, z)), _ref_plan(st, s, x, z)["pts"], "a model off the grid still agrees with the reference")
	s.adv = true
	s.adv_r = -9
	assert_eq(_arr(BtMoves.plan_move(st, s, x, z)), _ref_plan(st, s, x, z)["pts"], "a negative range (corrupt state) agrees too")


func test_group_targets_on_grid() -> void:
	var rng := Rng.make("test:group", 3)
	var bad: Array = []
	var n := 0
	for wi: int in _worlds.size():
		var st := _worlds[wi]
		for side: int in 3:
			var ids := PackedStringArray()
			for s: BattleState.Squad in st.alive_squads():
				if s.side == side:
					ids.append(s.id)
			for k: int in 6:
				var x := rng.bounded(st.w * 1000) - st.w * 500 + 3
				var z := rng.bounded(st.d * 1000) - st.d * 500 - 7
				for step: Dictionary in BtMoves.group_plan(st, ids, x, z):
					var tx: int = step["x"]
					var tz: int = step["z"]
					var q := st.squad(str(step["u"]))
					var c := BtSquads.center(q)
					var rng_ := BtMoves.move_range(q)
					n += 1
					var inside := absi(tx) <= st.w * 500 - 1200 and absi(tz) <= st.d * 500 - 1200
					var clamped := absi(tx) == st.w * 500 - 1200 or absi(tz) == st.d * 500 - 1200
					if Fx.imod(tx, 10) != 0 or Fx.imod(tz, 10) != 0 or not inside \
							or (not clamped and Fx.dist2(c[0], c[1], tx, tz) > (rng_ + 10) * (rng_ + 10)):
						bad.append([wi, step, c, rng_])
	assert_true(n > 100, "%d group targets" % n)
	assert_true(bad.is_empty(), "group targets: on the grid, inside the 1200 MI margin, never past the squad's range (+ the grid step)", bad.slice(0, 5))


# ---------------------------------------------------------------- time budget
## a 100 x 72 table with 480 props and 510 models: 49 squads of 10 on open ground plus one 20-model squad
func _big_field() -> Dictionary:
	var st := BattleState.make({"seed": 11, "w": 100, "teams": 2})
	var rng := Rng.make("test:perf", 11)
	var kinds := ["building", "wall", "tower", "rubble", "barricade", "pillars", "boulder", "tree", "crater", "pipe"]
	var items: Array[Dictionary] = []
	while items.size() < 480:
		var kind: String = kinds[rng.bounded(kinds.size())]
		var bw := 4000 + rng.bounded(4000) if kind == "building" else 0
		var bd := 3500 + rng.bounded(4000) if kind == "building" else 0
		var px := rng.bounded(96000) - 48000
		var pz := rng.bounded(68000) - 34000
		# the middle (where the big squad stands) keeps some open ground, as deployment does
		if absi(px) < 7000 and absi(pz) < 7000:
			continue
		items.append(BtBlocking.prep_one(kind, px, pz, rng.bounded(411774), 7000 + rng.bounded(4000), rng.bounded(65536), bw, bd))
	st.set_props(items, true)
	var big := st.add_squad("0:big", "infantry", 0, 0, 20, 0)
	var start := BtSquads.formation(20, 0, 0, 0, 1000, 800)
	var spots: Array = []
	for z: int in range(-32300, 32301, 1700):
		for x: int in range(-47600, 47601, 1700):
			if absi(x) < 9000 and absi(z) < 9000:
				continue
			if not BtBlocking.block_at(st, x, z):
				spots.append([x, z])
	var n := 0
	var sq: BattleState.Squad = null
	for p: Variant in spots:
		if n >= 490:
			break
		if n % 10 == 0:
			sq = st.add_squad("%d:%d" % [(n / 10) % 2, n / 10], "infantry", (n / 10) % 2, (n / 10) % 2, 10, 0)
		st.add_unit("%s.%d" % [sq.id, n % 10], sq, 1, int(p[0]), int(p[1]))
		n += 1
	for j: int in 20:
		st.add_unit("0:big.%d" % j, big, 1, start[j][0], start[j][1])
	return {"st": st, "big": big, "props": items.size(), "models": st.units.size()}


func _best_ms(f: Callable) -> int:
	var best := 1 << 40
	for k: int in 3:
		var t0 := Time.get_ticks_usec()
		f.call()
		best = mini(best, Time.get_ticks_usec() - t0)
	return best / 1000


func test_time_budget() -> void:
	var w := _big_field()
	var st: BattleState = w["st"]
	var big: BattleState.Squad = w["big"]
	assert_eq([w["props"], w["models"]], [480, 510], "480 props, 490 models in 49 squads of 10 plus the 20-model squad")
	var foe := st.squad("1:1")
	var tgt := BtSquads.center(big)
	assert_eq(str(BtMoves.try_move(st, big, tgt[0] + 3000, tgt[1] + 4000, false)["key"]), "", "the timed order is a real move")
	var plan_ms := _best_ms(func() -> void: BtMoves.plan_move(st, big, 0, 5000))
	var try_ms := _best_ms(func() -> void: BtMoves.try_move(st, big, tgt[0] + 3000, tgt[1] + 4000, false))
	var far_ms := _best_ms(func() -> void: BtMoves.plan_move(st, big, 30000, 20000))
	var chg_ms := _best_ms(func() -> void: BtMoves.charge_spots(st, big, foe, 12000))
	# the worst case: a house over the whole squad, so every model tries all 111 candidates and stays
	var walled: Array[Dictionary] = st.props.duplicate()
	walled.append(BtBlocking.prep_one("building", 0, 0, 0, 10000, 0, 40000, 40000))
	var props0: Array[Dictionary] = st.props
	st.set_props(walled, true)
	var box_ms := _best_ms(func() -> void: BtMoves.plan_move(st, big, 0, 5000))
	assert_eq(_arr(BtMoves.plan_move(st, big, 0, 5000)), _arr_units(big), "boxed in: everyone stays")
	st.set_props(props0, true)
	print("      time: plan_move %d ms, try_move %d ms, plan_move far %d ms, boxed in %d ms, charge_spots %d ms (best of 3)" % [plan_ms, try_ms, far_ms, box_ms, chg_ms])
	assert_true(box_ms < BUDGET_MS, "boxed in, all 111 candidates for each of 20 models: %d ms < %d ms" % [box_ms, BUDGET_MS])
	assert_true(plan_ms < BUDGET_MS, "plan_move of 20 models among 480 props and 510 models: %d ms < %d ms" % [plan_ms, BUDGET_MS])
	assert_true(try_ms < BUDGET_MS, "try_move (plan + checks): %d ms < %d ms" % [try_ms, BUDGET_MS])
	assert_true(far_ms < BUDGET_MS, "a far order (fallbacks for most models): %d ms < %d ms" % [far_ms, BUDGET_MS])
	assert_true(chg_ms < BUDGET_MS, "charge_spots for 20 chargers: %d ms < %d ms" % [chg_ms, BUDGET_MS])
	assert_eq(_arr(BtMoves.plan_move(st, big, 0, 5000)), _ref_plan(st, big, 0, 5000)["pts"], "and the fast plan equals the reference on the big field")


# ---------------------------------------------------------------- digest
func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the scenario digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtMoves scenario digest is pinned")


## every BtMoves function over two page worlds: plans and try_move answers for every squad, charges onto the first
## real foe, near_foe at each centre, each side's group move to the table centre, then the fall backs applied in order,
## folded with the final positions, flags and facings (not the whole state_ints, so a RULES_V bump leaves it alone)
## into one FNV-1a 64 digest
func _digest_scenario() -> String:
	var v := PackedInt64Array()
	for wi: int in [1, 3]:
		var st := _world(wi)
		for s: BattleState.Squad in st.alive_squads():
			var c := BtSquads.center(s)
			v.append(BtMoves.move_range(s))
			for p: PackedInt64Array in BtMoves.plan_move(st, s, c[0] + 3000, c[1] + 2000):
				v.append_array(p)
			for fb: bool in [false, true]:
				var r := BtMoves.try_move(st, s, c[0] - 2500, c[1] + 4000, fb)
				v.append(Hash.fnv1a64_str(str(r["key"])))
				var act: Dictionary = r["act"]
				for p: Variant in act.get("to", []):
					v.append_array(PackedInt64Array([int(p[0]), int(p[1])]))
			var foes := BtSquads.real_foes(st, s)
			if not foes.is_empty():
				for p: PackedInt64Array in BtMoves.charge_spots(st, s, foes[0], 9000):
					v.append_array(p)
			v.append(1 if BtMoves.near_foe(st, s, c[0], c[1], 800) else 0)
		for side: int in 3:
			st.turn = side
			var run := _group_run(st, BtMoves.group_all(st), 0, 0)
			v.append((run["acts"] as Array).size())
		var out: Array[Dictionary] = []
		for s: BattleState.Squad in st.alive_squads():
			if BtSquads.is_engaged(st, s) and not s.moved:
				var c := BtSquads.center(s)
				var r := BtMoves.try_move(st, s, c[0], c[1] - 5000, true)
				if str(r["key"]) == "":
					BtMoves.apply_smove(st, s, r["act"]["to"], "fb", out)
		v.append(out.size())
		for s: BattleState.Squad in st.squads:
			v.append_array(PackedInt64Array([s.flags(), s.fx, s.fz]))
		for u: BattleState.Unit in st.units:
			v.append_array(PackedInt64Array([Hash.fnv1a64_str(u.id), u.x, u.z]))
	return Hash.digest_hex(v)
