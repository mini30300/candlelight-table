extends "res://tests/testing.gd"
## core/battle/blocking.gd (BtBlocking, R1_PORT_SPEC §1.3) against the page and by hand:
## - fixtures/blocking/page.json (tools/record_blocking.js runs the page's own propBlocks / blockAt / roomToLand /
##   crowded / freeSpot in Chromium on integer-grid inputs): every robust sample must match exactly (freeSpot: the same
##   candidate, so the point within the v10 grid rounding); fragile samples (the page answer flips within 12 MI) are
##   only counted, they are the borderline flips R1_PORT_SPEC §7 #2 allows;
## - hand cases per prop kind inside / outside each edge, table-edge margins 800 / 1200, crowded ties, freeSpot's
##   search order (the point, the first near offset, empty when boxed in with a limit, a wide ring on a packed table,
##   the crowd-off pass, the point back when nothing is free), the 10 MI grid invariant, the quick-reject radius bb never
##   changing a result, free_spot equal to a plain reference built on block_at / crowded, and pinned digests.

const FIX := "res://tests/unit/fixtures/blocking/page.json"
var F: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		F = p


# ---------------------------------------------------------------- helpers
## a w x d table holding prop rows [kind, x, z, rot_q16, s4, h_q16, bw, bd] and unit rows [type key, x, z]
func _state(w: int, d: int, props: Array, units: Array) -> BattleState:
	var st := BattleState.make({"seed": 1, "w": w, "d": d})
	var items: Array[Dictionary] = []
	for r: Variant in props:
		items.append(BtBlocking.prep_one(str(r[0]), int(r[1]), int(r[2]), int(r[3]), int(r[4]), int(r[5]), int(r[6]), int(r[7])))
	st.set_props(items, true)
	_add_units(st, units)
	return st


func _add_units(st: BattleState, units: Array) -> void:
	for r: Variant in units:
		var k := str(r[0])
		var sq := st.squad("s:" + k)
		if sq == null:
			sq = st.add_squad("s:" + k, k, 0, 0, 1, 0)
		st.add_unit("u%d" % st.units.size(), sq, 1, int(r[1]), int(r[2]))


func _p2(a: Variant) -> Array:
	return [] if a == null else [int(a[0]), int(a[1])]


func _arr(p: PackedInt64Array) -> Array:
	return Array(p)


## block_at without the cell grid: the table edges, then every prop in order
func _scan(st: BattleState, x: int, z: int) -> bool:
	if absi(x) > st.w * 500 - 800 or absi(z) > st.d * 500 - 800:
		return true
	for o: Dictionary in st.props:
		if BtBlocking.prop_blocks(o, x, z):
			return true
	return false


## the plain reference of free_spot: the same candidate order, every check through _scan / the public crowded
func _ref_free_spot(st: BattleState, x: int, z: int, skip: BattleState.Unit, from: PackedInt64Array, max_d: int, rad: int) -> Array:
	return _ref_exit(st, x, z, skip, from, max_d, rad)[0]


## [result, exit]: exit is "point", "near", "limited" (from given, nothing near), "wide" (crowd checked),
## "overlap" (the crowd-off pass) or "none" (the point back)
func _ref_exit(st: BattleState, x: int, z: int, skip: BattleState.Unit, from: PackedInt64Array, max_d: int, rad: int) -> Array:
	var lw := st.w * 500 - 1200
	var ld := st.d * 500 - 1200
	var lim := from.size() >= 2
	var ok := func(nx: int, nz: int, crowd: bool) -> bool:
		if absi(nx) > lw or absi(nz) > ld:
			return false
		if lim:
			if max_d < -1 or Fx.dist2(nx, nz, from[0], from[1]) > (max_d + 1) * (max_d + 1):
				return false
		return not _scan(st, nx, nz) and not (crowd and BtBlocking.crowded(st, nx, nz, skip, rad))
	if ok.call(x, z, true):
		return [[x, z], "point"]
	for o: Array in BtOffsets.FREESPOT_NEAR:
		if ok.call(x + int(o[0]), z + int(o[1]), true):
			return [[x + int(o[0]), z + int(o[1])], "near"]
	if lim:
		return [[], "limited"]
	var far := BtBlocking.far_rings(st.w, st.d)
	for pass_no: int in 2:
		for r: int in range(11 if pass_no == 0 else 1, far + 1):
			var n := BtOffsets.fs_ring_n(r)
			for a: int in n:
				var th := Fx.idiv(a * FieldProps.TWO_PI, n) + Fx.js_round(r * 41 * 65536, 100)
				var nx := x + 10 * Fx.js_round(FieldProps.cos_q(th) * r * 125, 65536)
				var nz := z + 10 * Fx.js_round(FieldProps.sin_q(th) * r * 125, 65536)
				if ok.call(nx, nz, pass_no == 0):
					return [[nx, nz], "wide" if pass_no == 0 else "overlap"]
	return [[x, z], "none"]


## JSON numbers come back as floats; whole numbers become ints again (what Net does before restore)
func _to_ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_to_ints(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _to_ints(v[k])
			return d
		TYPE_FLOAT:
			return int(v)
	return v


func _ruin48() -> FieldProps:
	return FieldProps.generate(FieldTerrain.make(48, FieldTerrain.depth_for(48), "ruin", "hills", 1), true, 1000)


# ---------------------------------------------------------------- the page
func test_fixture_loaded() -> void:
	assert_true(F.has("single") and F.has("fields") and F.has("crowded") and F.has("free_spot") and F.has("far"),
		"page fixture loaded from " + FIX)
	assert_eq(str(F.get("meta", {}).get("app_ver", "")), "9.4", "recorded from page APP_VER 9.4")
	assert_eq(int(F.get("meta", {}).get("eps_mi", 0)), 12, "robust = the same page answer 12 MI around")


func test_single_props_match_page() -> void:
	var robust := 0
	var fragile := 0
	var fragile_same := 0
	var bad := []
	var per_kind := {}
	for c: Dictionary in F["single"]:
		var st := _state(48, 34, [c["prop"]], [])
		var kind := str(c["prop"][0])
		if not per_kind.has(kind):
			per_kind[kind] = [0, 0]
		for p: Array in c["pts"]:
			var got := BtBlocking.block_at(st, int(p[0]), int(p[1]))
			var want := int(p[2]) == 1
			if int(p[3]) == 1:
				robust += 1
				per_kind[kind][1 if want else 0] += 1
				if got != want and bad.size() < 8:
					bad.append([c["prop"], p, got])
			else:
				fragile += 1
				fragile_same += 1 if got == want else 0
	assert_true(robust > 10000, "%d robust single-prop points (%d fragile, %d of them agree too)" % [robust, fragile, fragile_same])
	assert_true(bad.is_empty(), "propBlocks: every robust point of 19 kinds x 6 props equals the page [prop, point, port]", bad)
	var shape_bad := []
	for kind: String in per_kind:
		var free_n: int = per_kind[kind][0]
		var blk_n: int = per_kind[kind][1]
		var zero := kind == "crater" or kind == "arch" or kind == "bush"
		if free_n < 50 or (blk_n == 0) != zero:
			shape_bad.append([kind, free_n, blk_n])
	assert_true(shape_bad.is_empty(), "every kind has free and (unless crater/arch/bush) blocked page points [kind, free, blocked]", shape_bad)


func test_fields_match_page() -> void:
	for f: Dictionary in F["fields"]:
		var st := _state(int(f["w"]), int(f["d"]), f["props"], [])
		var tag := "%s %d (seed %d, %d props)" % [str(f["theme"]), int(f["w"]), int(f["seed"]), (f["props"] as Array).size()]
		var bad := []
		var robust := 0
		var fragile := 0
		for p: Array in f["block"]:
			var got := BtBlocking.block_at(st, int(p[0]), int(p[1]))
			if int(p[3]) == 1:
				robust += 1
				if got != (int(p[2]) == 1) and bad.size() < 5:
					bad.append(p)
			else:
				fragile += 1
		assert_true(robust > 1100 and bad.is_empty(), tag + ": blockAt equals the page at %d robust points (%d fragile)" % [robust, fragile], bad)
		bad = []
		robust = 0
		var yes := 0
		for p: Array in f["room"]:
			var got2 := BtBlocking.room_to_land(st, int(p[0]), int(p[1]))
			if int(p[3]) == 1:
				robust += 1
				yes += 1 if got2 else 0
				if got2 != (int(p[2]) == 1) and bad.size() < 5:
					bad.append(p)
		assert_true(robust > 200 and bad.is_empty(), tag + ": roomToLand equals the page at %d robust points (%d can land)" % [robust, yes], bad)


func test_crowded_matches_page() -> void:
	for c: Dictionary in F["crowded"]:
		var st := _state(48, 34, [], c["units"])
		var bad := []
		var robust := 0
		var hits := 0
		for q: Array in c["q"]:
			var sk := int(q[2])
			var got := BtBlocking.crowded(st, int(q[0]), int(q[1]), st.units[sk] if sk >= 0 else null, int(q[3]))
			if int(q[5]) == 1:
				robust += 1
				hits += 1 if got else 0
				if got != (int(q[4]) == 1) and bad.size() < 5:
					bad.append(q)
		assert_true(robust >= 390 and bad.is_empty(), "crowded with %d bases: %d robust queries equal the page (%d crowded)" % [st.units.size(), robust, hits], bad)


func test_free_spot_matches_page() -> void:
	var kinds := {"self": 0, "near": 0, "wide": 0, "null": 0, "back": 0, "none": 0}
	for sc: Dictionary in F["free_spot"]:
		var f: Dictionary = sc["field"]
		var st := _state(int(f["w"]), int(f["d"]), f["props"], sc["units"])
		var bad := []
		var fragile := 0
		var fragile_same := 0
		for e: Dictionary in sc["q"]:
			var q: Array = e["q"]
			var x := int(q[0])
			var z := int(q[1])
			var sk := int(q[2])
			var from := PackedInt64Array([int(q[3]), int(q[4])]) if int(q[5]) == 1 else PackedInt64Array()
			var got := _arr(BtBlocking.free_spot(st, x, z, st.units[sk] if sk >= 0 else null, from, int(q[6]), int(q[7])))
			var n := int(e["n"])
			var ok := false
			var kind := "none"
			if e["r"] == null:
				kind = "null"
				ok = got.is_empty()
			else:
				var px: float = float(e["r"][0]) * 1000.0
				var pz: float = float(e["r"][1]) * 1000.0
				if absf(px - x) < 0.001 and absf(pz - z) < 0.001:
					kind = "self" if n == 1 else "back"
					ok = got == [x, z]
				elif got.size() == 2:
					# near rings: the page point rounded to the 10 MI grid; wide rings also carry Q16 trig (r/10 MI)
					var ring := Fx.js_round(Fx.isqrt(Fx.dist2(x, z, got[0], got[1])), 1250)
					kind = "near" if n <= 141 else "wide"
					var tol := 5.0 if n <= 141 else 6.0 + ring / 10.0
					ok = absf(got[0] - px) <= tol + 0.000001 and absf(got[1] - pz) <= tol + 0.000001
			if int(e["robust"]) == 1:
				kinds[kind] += 1
				if not ok and bad.size() < 5:
					bad.append([q, e["r"], n, got])
			else:
				fragile += 1
				fragile_same += 1 if ok else 0
		assert_true(bad.is_empty(), "%s: %d freeSpot queries, every robust one finds the page's spot (%d fragile, %d agree) [q, page, n, port]" % [
			str(sc["name"]), (sc["q"] as Array).size(), fragile, fragile_same], bad)
	assert_true(int(kinds["self"]) >= 10 and int(kinds["near"]) > 20 and int(kinds["wide"]) >= 10 and int(kinds["null"]) >= 10 and int(kinds["back"]) >= 1,
		"the page samples cover every exit of freeSpot " + str(kinds))


func test_far_rings_match_page() -> void:
	var bad := []
	for r: Array in F["far"]:
		var got := BtBlocking.far_rings(int(r[0]), int(r[1]))
		if got != int(r[2]) and bad.size() < 5:
			bad.append([r, got])
	assert_true((F["far"] as Array).size() > 100 and bad.is_empty(), "far_rings = Math.ceil(Math.hypot(w, d) / 1.25) for %d tables" % (F["far"] as Array).size(), bad)
	assert_eq(BtBlocking.far_rings(48, 36), 48, "48 x 36: the diagonal is exactly 60 in, 48 rings")
	assert_eq(BtBlocking.far_rings(48, 34), 48, "48 x 34")
	assert_eq(BtBlocking.far_rings(180, 130), 178, "the largest table")


# ---------------------------------------------------------------- prepared shapes
func test_prep_one_fields() -> void:
	var b := BtBlocking.prep_one("building", 1000, -2000, 0, 12000, 100, 9000, 7000)
	assert_eq(b["kind"], "building", "kind kept")
	assert_eq([int(b["x"]), int(b["z"]), int(b["s4"]), int(b["h"]), int(b["bw"]), int(b["bd"])], [1000, -2000, 12000, 100, 9000, 7000], "building keeps x, z, s4, h, bw, bd")
	assert_eq([int(b["c"]), int(b["sn"])], [FieldProps.cos_q(0), FieldProps.sin_q(0)], "c and sn are the Q16 cos/sin of rot")
	assert_false(b.has("rb") or b.has("segs") or b.has("p0x"), "a building has no disc radius, segments or posts")
	var segs := []
	for h: int in [0, 10922, 10923, 32767, 32768, 54613, 54614, 65535]:
		segs.append(int(BtBlocking.prep_one("wall", 0, 0, 0, 10000, h, 0, 0)["segs"]))
	assert_eq(segs, [3, 3, 4, 4, 5, 5, 6, 6], "wall segments = 3 + Math.round(3h): ties go up (h = 1/2 gives 5)")
	var pl := BtBlocking.prep_one("pillars", 0, 0, 0, 10000, 0, 0, 0)
	assert_eq([int(pl["p0x"]), int(pl["p0z"]), int(pl["p1x"]), int(pl["p1z"]), int(pl["p2x"]), int(pl["p2z"]), int(pl["p3x"]), int(pl["p3z"])],
		[3200, 0, 0, 3200, -3200, 0, 0, -3200], "pillars: four posts 3.2 in out at rot + k quarter turns")
	var pl2 := BtBlocking.prep_one("pillars", 0, 0, 0, 14500, 0, 0, 0)
	assert_eq(int(pl2["p1z"]), 4640, "posts scale with s (3.2 x 1.45 = 4.64 in)")
	var rbs := []
	for k: String in ["crater", "arch", "bush", "rubble", "barricade", "log", "pipe", "tower", "boulder", "iceslab", "obelisk",
			"buried", "tree", "deadtree", "pine", "statue"]:
		rbs.append(int(BtBlocking.prep_one(k, 0, 0, 0, 10000, 0, 0, 0)["rb"]))
	assert_eq(rbs, [0, 0, 0, 1500, 1500, 1100, 1900, 3000, 2200, 2200, 1800, 1600, 1100, 1100, 1200, 2000], "BLOCK_R in MI; an unknown kind blocks 2 in")
	assert_eq(int(BtBlocking.prep_one("crater", 0, 0, 0, 10000, 0, 0, 0)["bb"]), 0, "a zero-radius kind has bb 0")
	var st := BattleState.make({"w": 48})
	var items: Array[Dictionary] = [b, pl, BtBlocking.prep_one("tree", 5, 6, 7, 8000, 9, 0, 0)]
	st.set_props(items, true)
	var snap := st.snapshot(true)
	var back := BattleState.make({})
	assert_true(back.restore(snap), "prepared props pass the snapshot's ints-and-Strings check and restore")
	assert_eq(back.props_hash, st.props_hash, "and keep their hash")
	var viaj := BattleState.make({})
	assert_true(viaj.restore(_to_ints(JSON.parse_string(JSON.stringify(snap)))), "and survive JSON text (numbers made whole again, as Net does)")
	assert_eq(viaj.props, st.props, "with every prepared field equal")


func test_prep_field_pinned() -> void:
	var fp := _ruin48()
	var items := BtBlocking.prep_field(fp)
	assert_eq(items.size(), fp.items.size(), "one prepared prop per generated prop, same order")
	var same := true
	for i: int in items.size():
		var o: Dictionary = fp.items[i]
		var p: Dictionary = items[i]
		if p["kind"] != o["kind"] or int(p["x"]) != int(o["x"]) or int(p["z"]) != int(o["z"]) or int(p["s4"]) != int(o["s"]) * 10 or int(p["h"]) != int(o["h"]):
			same = false
		if o["kind"] == "building":
			var bs := fp.bld_size(o)
			if int(p["bw"]) != bs[0] or int(p["bd"]) != bs[1]:
				same = false
	assert_true(same, "prep_field keeps kind, x, z, h, s4 = s permille x 10, and bld_size for buildings")
	var st := BattleState.make({"seed": 1, "w": 48})
	st.set_props(items, false)
	assert_digest(Hash.hex64(st.props_hash), "0827137c3288cb21", "prep_field of seed 1 / 48 in / ruin hills: pinned props hash")


func test_bb_never_changes_a_result() -> void:
	var props: Array[Dictionary] = []
	for c: Dictionary in F["single"]:
		var r: Array = c["prop"]
		props.append(BtBlocking.prep_one(str(r[0]), int(r[1]), int(r[2]), int(r[3]), int(r[4]), int(r[5]), int(r[6]), int(r[7])))
	props.append_array(BtBlocking.prep_field(_ruin48()))
	props.append(BtBlocking.prep_one("building", 0, 0, 34315, 10000, 0, 30000, 20000))
	props.append(BtBlocking.prep_one("wall", 0, 0, 77777, 200000, 65535, 0, 0))
	props.append(BtBlocking.prep_one("pillars", 0, 0, 12345, 200000, 0, 0, 0))
	props.append(BtBlocking.prep_one("tower", 0, 0, 0, 200000, 0, 0, 0))
	var rng := Rng.make("test:bb", 4)
	var outside_hit := 0
	var inside_diff := 0
	var hits := 0
	for o: Dictionary in props:
		var bb: int = o["bb"]
		for k: int in 60:
			var a := rng.bounded(FieldProps.TWO_PI)
			var dist := bb + 1 + rng.bounded(3000)
			var dx := Fx.js_round(FieldProps.cos_q(a) * dist, 65536)
			var dz := Fx.js_round(FieldProps.sin_q(a) * dist, 65536)
			if dx * dx + dz * dz > bb * bb and BtBlocking._hit(o, dx, dz):
				outside_hit += 1
			var r2 := rng.bounded(bb + 1)
			var ix := Fx.js_round(FieldProps.cos_q(a) * r2, 65536)
			var iz := Fx.js_round(FieldProps.sin_q(a) * r2, 65536)
			var h := BtBlocking._hit(o, ix, iz)
			hits += 1 if h else 0
			if BtBlocking.prop_blocks(o, int(o["x"]) + ix, int(o["z"]) + iz) != h and ix * ix + iz * iz <= bb * bb:
				inside_diff += 1
	assert_eq(outside_hit, 0, "no point beyond bb is inside the exact shape (%d props x 60 points, s4 up to 200000)" % props.size())
	assert_eq(inside_diff, 0, "inside bb prop_blocks is exactly the shape test (%d of the points were blocked)" % hits)
	assert_false(BtBlocking.prop_blocks(props[props.size() - 1], 3000000, -3000000), "a point far off the table is rejected before any big product")


# ---------------------------------------------------------------- hand cases per kind
func test_building_edges() -> void:
	# bw 10 in, bd 6 in: blocks |lx| < 5.7, |lz| < 3.7 (bw/2 + 0.7)
	var o := BtBlocking.prep_one("building", 0, 0, 0, 10000, 0, 10000, 6000)
	assert_true(BtBlocking.prop_blocks(o, 5699, 0) and BtBlocking.prop_blocks(o, -5699, 0), "inside the long side, 1 MI from the edge")
	assert_false(BtBlocking.prop_blocks(o, 5700, 0) or BtBlocking.prop_blocks(o, -5700, 0), "on the edge is outside (strict <, like the page)")
	assert_true(BtBlocking.prop_blocks(o, 0, 3699) and BtBlocking.prop_blocks(o, 0, -3699), "inside the short side")
	assert_false(BtBlocking.prop_blocks(o, 0, 3700), "on the short edge is outside")
	assert_true(BtBlocking.prop_blocks(o, 5699, 3699), "the corner is inside")
	assert_false(BtBlocking.prop_blocks(o, 5699, 3700) or BtBlocking.prop_blocks(o, 5700, 3699), "just past the corner is outside")
	# turned by 30 degrees (rot Q16 34315): corners checked in the building's own frame
	var r := 34315
	var t := BtBlocking.prep_one("building", 2000, -1000, r, 10000, 0, 10000, 6000)
	var c := cos(r / 65536.0)
	var s := sin(r / 65536.0)
	var bad := []
	for corner: Array in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		for e: Array in [[5690, 3690, true], [5710, 3690, false], [5690, 3710, false], [5710, 3710, false]]:
			var lx: float = corner[0] * float(e[0])
			var lz: float = corner[1] * float(e[1])
			var wx := 2000 + roundi(lx * c + lz * s)
			var wz := -1000 + roundi(-lx * s + lz * c)
			if BtBlocking.prop_blocks(t, wx, wz) != bool(e[2]):
				bad.append([corner, e, wx, wz])
	assert_true(bad.is_empty(), "a turned building blocks its own rectangle: 10 MI in / out of all four corners", bad)
	# a quarter turn swaps the extents
	var q := BtBlocking.prep_one("building", 0, 0, 102944, 10000, 0, 10000, 6000)
	assert_true(BtBlocking.prop_blocks(q, 0, 5690) and BtBlocking.prop_blocks(q, 3690, 0), "quarter turn: the long side lies along z")
	assert_false(BtBlocking.prop_blocks(q, 0, 5710) or BtBlocking.prop_blocks(q, 3710, 0), "quarter turn: and ends where it should")


func test_wall_edges() -> void:
	# h 0 = 3 segments, s 1: |ax| < 3 x 1.2 + 0.6 = 4.2 in, |az| < 0.9 + 0.6 = 1.5 in
	var o := BtBlocking.prep_one("wall", 0, 0, 0, 10000, 0, 0, 0)
	assert_true(BtBlocking.prop_blocks(o, 4199, 0) and BtBlocking.prop_blocks(o, -4199, 0), "inside the wall's ends")
	assert_false(BtBlocking.prop_blocks(o, 4200, 0) or BtBlocking.prop_blocks(o, -4200, 0), "past the wall end is free")
	assert_true(BtBlocking.prop_blocks(o, 0, 1499) and BtBlocking.prop_blocks(o, 4199, -1499), "inside the thickness, at the end too")
	assert_false(BtBlocking.prop_blocks(o, 0, 1500), "beside the wall is free")
	var big := BtBlocking.prep_one("wall", 1000, 1000, 0, 15000, 65535, 0, 0)
	# 6 segments, s 1.5: |ax| < 6 x 1.8 + 0.6 = 11.4 in, |az| < 1.35 + 0.6 = 1.95 in
	assert_true(BtBlocking.prop_blocks(big, 1000 + 11399, 1000 + 1949), "a long, scaled wall: corner inside")
	assert_false(BtBlocking.prop_blocks(big, 1000 + 11400, 1000) or BtBlocking.prop_blocks(big, 1000, 1000 + 1950), "and its edges outside")


func test_pillars_and_discs() -> void:
	var o := BtBlocking.prep_one("pillars", 0, 0, 0, 10000, 0, 0, 0)
	assert_false(BtBlocking.prop_blocks(o, 0, 0), "the middle of the pillars is a free standing spot")
	assert_false(BtBlocking.prop_blocks(o, 1900, 0), "exactly 1.3 in from a post is free (strict)")
	assert_true(BtBlocking.prop_blocks(o, 1901, 0) and BtBlocking.prop_blocks(o, 3200, 0) and BtBlocking.prop_blocks(o, 4499, 0), "next to and on a post")
	assert_false(BtBlocking.prop_blocks(o, 4500, 0), "1.3 in out past the post is free (no +0.6, as the page)")
	assert_false(BtBlocking.prop_blocks(o, 2262, 2262), "between two posts (on the diagonal) is free")
	assert_true(BtBlocking.prop_blocks(o, 0, -3200) and BtBlocking.prop_blocks(o, -3200, 0) and BtBlocking.prop_blocks(o, 0, 3200), "all four posts block")
	var tree := BtBlocking.prep_one("tree", -500, 700, 1234, 10000, 0, 0, 0)
	assert_true(BtBlocking.prop_blocks(tree, -500 + 1699, 700), "a tree blocks r x s + 0.6 = 1.7 in")
	assert_false(BtBlocking.prop_blocks(tree, -500 + 1700, 700), "and not at 1.7 in")
	assert_true(BtBlocking.prop_blocks(tree, -500 - 1201, 700 - 1201), "diagonal inside (1698.5 MI)")
	var tower := BtBlocking.prep_one("tower", 0, 0, 0, 14500, 0, 0, 0)
	assert_true(BtBlocking.prop_blocks(tower, 0, 4949), "a scaled tower: 3 x 1.45 + 0.6 = 4.95 in")
	assert_false(BtBlocking.prop_blocks(tower, 0, 4950), "and not at 4.95 in")
	var odd := BtBlocking.prep_one("statue", 0, 0, 0, 10000, 0, 0, 0)
	assert_true(BtBlocking.prop_blocks(odd, 2599, 0) and not BtBlocking.prop_blocks(odd, 2600, 0), "an unknown kind blocks 2 in + 0.6")
	for k: String in ["crater", "arch", "bush"]:
		var f := BtBlocking.prep_one(k, 0, 0, 0, 14500, 0, 0, 0)
		assert_false(BtBlocking.prop_blocks(f, 0, 0) or BtBlocking.prop_blocks(f, 300, -200), k + " never blocks (cover you can stand in)")


func test_block_at_table_edges() -> void:
	var st := BattleState.make({"w": 48, "d": 34})
	assert_false(BtBlocking.block_at(st, 23200, 0) or BtBlocking.block_at(st, -23200, 16200), "0.8 in from the edge is still on the table")
	assert_true(BtBlocking.block_at(st, 23201, 0) and BtBlocking.block_at(st, -23201, 0), "closer than 0.8 in to a side edge blocks")
	assert_true(BtBlocking.block_at(st, 0, 16201) and BtBlocking.block_at(st, 0, -16201), "closer than 0.8 in to a far edge blocks")
	assert_false(BtBlocking.block_at(st, 0, 0), "an empty table blocks nothing")
	var odd := BattleState.make({"w": 47, "d": 33})
	assert_false(BtBlocking.block_at(odd, 22700, 15700), "odd sizes: w/2 is exact in MI (23.5 - 0.8)")
	assert_true(BtBlocking.block_at(odd, 22701, 0) and BtBlocking.block_at(odd, 0, -15701), "odd sizes: and past it blocks")
	var items: Array[Dictionary] = [BtBlocking.prep_one("tree", 5000, 0, 0, 10000, 0, 0, 0), BtBlocking.prep_one("crater", -5000, 0, 0, 10000, 0, 0, 0)]
	st.set_props(items, false)
	assert_true(BtBlocking.block_at(st, 5000, 1000), "a prop on the table blocks")
	assert_false(BtBlocking.block_at(st, -5000, 0), "a crater does not")


func test_crowded_hand_cases() -> void:
	var st := _state(48, 34, [], [["hoplite", 0, 0], ["cavalry", 5000, 0], ["mech", -6000, -6000]])
	assert_eq([BtBlocking.unit_rad(st.units[0]), BtBlocking.unit_rad(st.units[1]), BtBlocking.unit_rad(st.units[2])], [800, 1100, 1500],
		"base radii: no r = 800, cavalry 1.1 in, mech 1.5 in")
	var off: Array = []
	var u := BattleState.Unit.new()
	for ti: int in GameData.count():
		u.ti = ti
		if BtBlocking.unit_rad(u) != BtSquads.radius_of(ti):
			off.append([GameData.key_at(ti), BtBlocking.unit_rad(u), BtSquads.radius_of(ti)])
	assert_true(off.is_empty(), "unit_rad's cache equals BtSquads.radius_of for all %d types" % GameData.count(), off)
	assert_true(BtBlocking.crowded(st, 1599, 0, null, -1), "default 0.8 in base 1599 MI from a 0.8 in base overlaps")
	assert_false(BtBlocking.crowded(st, 1600, 0, null, -1), "touching exactly is not overlapping (strict <)")
	assert_true(BtBlocking.crowded(st, -1599, 0, null, -1) and BtBlocking.crowded(st, 0, -1599, null, -1), "negative side too")
	assert_true(BtBlocking.crowded(st, 799, 0, null, 0) and not BtBlocking.crowded(st, 800, 0, null, 0), "r 0: only the other base counts")
	assert_false(BtBlocking.crowded(st, 0, 0, st.units[0], -1), "skip: a model never crowds itself")
	assert_true(BtBlocking.crowded(st, 1899, 0, st.units[1], -1), "r omitted: the skipped model's own radius (1.1 + 0.8 in)")
	assert_false(BtBlocking.crowded(st, 1900, 0, st.units[1], -1), "and exactly touching is free")
	assert_true(BtBlocking.crowded(st, 5000 - 2349, 0, null, 1250), "an explicit r (1.25 + 1.1 in)")
	assert_false(BtBlocking.crowded(st, 5000 - 2350, 0, null, 1250), "an explicit r, touching")
	assert_false(BtBlocking.crowded(st, -6000 + 2300, -6000, null, -1), "a big base: 0.8 + 1.5 in, touching")
	assert_true(BtBlocking.crowded(st, -6000 + 2299, -6000, null, -1), "a big base: overlapping")
	assert_false(BtBlocking.crowded(BattleState.make({}), 0, 0, null, -1), "no models, nothing crowded")


# ---------------------------------------------------------------- free_spot by hand
func test_free_spot_order() -> void:
	var st := _state(48, 34, [], [])
	var none := PackedInt64Array()
	assert_eq(_arr(BtBlocking.free_spot(st, 1230, -4560, null, none, 0, 800)), [1230, -4560], "a free point comes back as it is")
	assert_eq(_arr(BtBlocking.free_spot(st, 22800, 0, null, none, 0, 800)), [22800, 0], "1.2 in from the edge is allowed")
	assert_eq(_arr(BtBlocking.free_spot(st, 22810, 0, null, none, 0, 800)), [22580, 1230], "closer than 1.2 in: the first near offset inside")
	# a tree west of the point blocks it; the first near offset (1.15, 0.5) is clear of it
	var t := _state(48, 34, [["tree", -1000, 0, 0, 10000, 0, 0, 0]], [])
	assert_eq(_arr(BtBlocking.free_spot(t, 0, 0, null, none, 0, 800)), [1150, 500], "a blocked point moves to the first near-ring offset")
	assert_eq(_arr(BtBlocking.free_spot(t, 0, 0, null, PackedInt64Array([0, 0]), 1253, 800)), [1150, 500], "with a limit just reaching it (1.254 in <= 1.253 + 0.001)")
	assert_eq(_arr(BtBlocking.free_spot(t, 0, 0, null, PackedInt64Array([0, 0]), 1000, 800)), [], "a limit short of every near ring: empty (the page's null)")
	assert_eq(_arr(BtBlocking.free_spot(t, 0, 0, null, PackedInt64Array([0, 0]), 1 << 40, 800)), [1150, 500], "a huge limit (2^40 MI) acts as no limit, no overflow")
	# a tree on the point: ring 1 lies inside it (1.25 < 1.7), ring 2 is the first clear
	var c := _state(48, 34, [["tree", 0, 0, 0, 10000, 0, 0, 0]], [])
	assert_eq(_arr(BtBlocking.free_spot(c, 0, 0, null, none, 0, 800)), [1710, 1830], "ring 1 is inside the tree: the first offset of ring 2")
	# a model in the way, and the same model skipped
	var m := _state(48, 34, [], [["hoplite", 3000, 3000]])
	assert_eq(_arr(BtBlocking.free_spot(m, 3000, 3000, null, none, 0, 800)), [3000 + 1710, 3000 + 1830], "a base on the point pushes to ring 2")
	assert_eq(_arr(BtBlocking.free_spot(m, 3000, 3000, m.units[0], none, 0, 800)), [3000, 3000], "the model itself (skip) does not crowd its own spot")
	assert_eq(_arr(BtBlocking.free_spot(m, 3000, 3000, null, none, 0, 0)), [3000 + 1150, 3000 + 500], "rad 0: a base 0.8 in wide only needs ring 1")
	# limits: maxD below -0.001 in rejects even the point; -1 MI is a zero limit
	assert_eq(_arr(BtBlocking.free_spot(st, 0, 0, null, PackedInt64Array([0, 0]), -2, 800)), [], "maxD < -1 MI: nothing is in reach (the page's null)")
	assert_eq(_arr(BtBlocking.free_spot(st, 0, 0, null, PackedInt64Array([0, 0]), -1, 800)), [0, 0], "maxD = -1 MI: the point itself is in reach")
	assert_eq(_arr(BtBlocking.free_spot(st, 0, 0, null, PackedInt64Array([5000, 0]), 4999, 800)), [0, 0], "a free point exactly 5 in away is in reach of maxD 4.999 in (+ 0.001)")
	assert_eq(_arr(BtBlocking.free_spot(st, 0, 0, null, PackedInt64Array([5000, 0]), 4998, 800)), [1150, 500], "one MI less and the point is out of reach: the first near offset in reach")


func test_free_spot_boxed_wide_and_full() -> void:
	var none := PackedInt64Array()
	# one building over the whole table: nothing anywhere
	var full := _state(40, 28, [["building", 0, 0, 0, 100000, 0, 50000, 45000]], [])
	assert_eq(_arr(BtBlocking.free_spot(full, 1230, -4560, null, none, 0, 800)), [1230, -4560], "a fully blocked table gives the point back")
	assert_eq(_arr(BtBlocking.free_spot(full, 0, 0, null, PackedInt64Array([0, 0]), 3000, 800)), [], "boxed in with a limit: empty")
	# a packed block of models round the centre: the near rings are all taken, the wide pass finds room
	var us := []
	for i: int in range(-8, 9):
		for j: int in range(-8, 9):
			us.append(["hoplite", i * 1600, j * 1600])
	var packed := _state(48, 34, [], us)
	var open_near := 0
	for o: Array in BtOffsets.FREESPOT_NEAR:
		if not BtBlocking.crowded(packed, int(o[0]), int(o[1]), null, 800):
			open_near += 1
	assert_eq(open_near, 0, "setup: every near offset of (0, 0) is crowded by the packed block")
	var w := _arr(BtBlocking.free_spot(packed, 0, 0, null, none, 0, 800))
	var dw := Fx.isqrt(Fx.dist2(0, 0, w[0], w[1]))
	assert_true(dw >= 11 * 1250 - 10 and dw <= 12 * 1250 + 10, "a packed table: the spot is on wide ring 11 or 12 (%d MI out)" % dw)
	assert_false(BtBlocking.block_at(packed, w[0], w[1]) or BtBlocking.crowded(packed, w[0], w[1], null, 800), "and it is free")
	# a small table covered with models: the crowd-off pass picks open ground next to the point
	var cover := []
	for i: int in range(-7, 8):
		for j: int in range(-5, 6):
			cover.append(["hoplite", i * 1600, j * 1600])
	var cv := _state(24, 18, [["building", 0, 0, 0, 10000, 0, 2000, 2000]], cover)
	var p := _arr(BtBlocking.free_spot(cv, 0, 0, null, none, 0, 800))
	assert_false(BtBlocking.block_at(cv, p[0], p[1]), "covered table: the spot is open ground")
	assert_true(BtBlocking.crowded(cv, p[0], p[1], null, 800), "covered table: it overlaps a base (crowd-off pass)")
	assert_true(Fx.dist2(0, 0, p[0], p[1]) <= 2600 * 2600, "covered table: the pass starts from ring 1 again (%s)" % str(p))


func test_free_spot_equals_plain_reference() -> void:
	var fp := _ruin48()
	var st := BattleState.make({"seed": 1, "w": 48, "d": 34})
	st.set_props(BtBlocking.prep_field(fp), false)
	var rng := Rng.make("test:fsref", 8)
	var keys := ["hoplite", "cavalry", "mech", "rscarab"]
	var us := []
	for i: int in 70:
		us.append([keys[rng.bounded(4)], (rng.bounded(4601) - 2300) * 10, (rng.bounded(3201) - 1600) * 10])
	_add_units(st, us)
	var before := st.digest()
	var bad := []
	var off_grid := []
	var moved := 0
	for i: int in 260:
		var x := (rng.bounded(4801) - 2400) * 10
		var z := (rng.bounded(3401) - 1700) * 10
		var skip: BattleState.Unit = st.units[rng.bounded(st.units.size())] if rng.bounded(3) == 0 else null
		var from := PackedInt64Array()
		var max_d := 0
		if rng.bounded(3) == 0:
			from = PackedInt64Array([x + (rng.bounded(601) - 300) * 10, z + (rng.bounded(601) - 300) * 10])
			max_d = rng.bounded(9000)
		var rad: int = [-1, 0, 800, 1100, 2200][rng.bounded(5)]
		var got := _arr(BtBlocking.free_spot(st, x, z, skip, from, max_d, rad))
		var want := _ref_free_spot(st, x, z, skip, from, max_d, rad)
		if got != want and bad.size() < 5:
			bad.append([x, z, from, max_d, rad, got, want])
		if got.size() == 2:
			if got[0] % 10 != 0 or got[1] % 10 != 0:
				off_grid.append(got)
			if got != [x, z]:
				moved += 1
	assert_true(bad.is_empty(), "free_spot equals the plain reference for 260 seeded queries (%d moved)" % moved, bad)
	assert_eq(off_grid, [], "every result of an on-grid query is on the 10 MI grid")
	assert_eq(st.digest(), before, "free_spot leaves the state as it was")


func test_grid_equals_full_scan() -> void:
	var rng := Rng.make("test:grid", 6)
	for cfg: Array in [[48, "ruin", "hills", 1, 1000], [120, "ruin", "mountain", 5, 2500], [180, "forest", "forest", 3, 2500], [33, "desert", "flat", 7, 1000]]:
		var fp := FieldProps.generate(FieldTerrain.make(cfg[0], FieldTerrain.depth_for(cfg[0]), cfg[1], cfg[2], cfg[3]), true, cfg[4])
		var st := BattleState.make({"seed": cfg[3], "w": cfg[0]})
		st.set_props(BtBlocking.prep_field(fp), false)
		var hw := st.w * 500
		var hd := st.d * 500
		var bad := []
		var blocked := 0
		for i: int in 6000:
			var x := rng.bounded(2 * hw + 1) - hw
			var z := rng.bounded(2 * hd + 1) - hd
			if i % 3 == 0:
				# on and next to the cell borders (cells are 4 in from the table's -x / -z edge)
				x = -hw + BtBlocking.CELL * rng.bounded(maxi(1, Fx.idiv(2 * hw, BtBlocking.CELL))) + rng.bounded(3) - 1
			if i % 3 == 1:
				z = -hd + BtBlocking.CELL * rng.bounded(maxi(1, Fx.idiv(2 * hd, BtBlocking.CELL))) + rng.bounded(3) - 1
			var g := BtBlocking.block_at(st, x, z)
			blocked += 1 if g else 0
			if g != _scan(st, x, z) and bad.size() < 5:
				bad.append([x, z, g])
		assert_true(bad.is_empty(), "%d in %s (%d props): block_at through the cell grid equals the full scan at 6000 points (%d blocked)" % [
			int(cfg[0]), str(cfg[1]), st.props.size(), blocked], bad)


func test_grid_follows_the_props() -> void:
	var a := _state(48, 34, [["tree", 0, 0, 0, 10000, 0, 0, 0]], [])
	var b := _state(48, 34, [["tree", 8000, 0, 0, 10000, 0, 0, 0]], [])
	assert_true(BtBlocking.block_at(a, 0, 0) and not BtBlocking.block_at(a, 8000, 0), "state A: its own tree")
	assert_true(BtBlocking.block_at(b, 8000, 0) and not BtBlocking.block_at(b, 0, 0), "state B right after: B's tree, not A's")
	assert_true(BtBlocking.block_at(a, 0, 0) and not BtBlocking.block_at(a, 8000, 0), "back to A: A's tree again")
	var items: Array[Dictionary] = [BtBlocking.prep_one("tower", -9000, 3000, 0, 10000, 0, 0, 0)]
	a.set_props(items, false)
	assert_true(BtBlocking.block_at(a, -9000, 3000) and not BtBlocking.block_at(a, 0, 0), "set_props: the new props block, the old ones are gone")
	var snap := a.snapshot(true)
	var c := _state(48, 34, [], [])
	assert_false(BtBlocking.block_at(c, -9000, 3000), "an empty table blocks nothing")
	assert_true(c.restore(snap) and BtBlocking.block_at(c, -9000, 3000), "restore brings the props and the grid follows")
	var w := _state(48, 34, [["tree", 20000, 0, 0, 10000, 0, 0, 0]], [])
	assert_true(BtBlocking.block_at(w, 20000, 0), "a tree near the east edge")
	w.w = 60
	w.d = 44
	assert_true(BtBlocking.block_at(w, 20000, 0) and not BtBlocking.block_at(w, 23500, 0), "a wider table (same props) rebuilds the cells")


func test_room_to_land() -> void:
	var st := _state(48, 34, [["building", 0, 0, 0, 10000, 0, 12000, 9000], ["tree", 10000, 5000, 0, 10000, 0, 0, 0]], [])
	assert_true(BtBlocking.room_to_land(st, -15000, -10000), "open ground: room to land")
	assert_false(BtBlocking.room_to_land(st, 0, 0), "the middle of a big building: no room even 2.5 in around")
	assert_true(BtBlocking.block_at(st, 10000, 5000) and BtBlocking.room_to_land(st, 10000, 5000), "on a tree: blocked, but the 2.5 in ring is clear")
	assert_true(BtBlocking.room_to_land(st, 0, 4500 + 700 - 1000), "inside the building near its edge: a probe reaches out")
	assert_true(BtBlocking.room_to_land(st, 23500, 0), "past the table edge margin: probes inside the table count")
	var full := _state(40, 28, [["building", 0, 0, 0, 100000, 0, 50000, 45000]], [])
	assert_false(BtBlocking.room_to_land(full, 5000, 5000), "a fully covered table has no room anywhere")


func test_pinned_scenario_digest() -> void:
	var fp := _ruin48()
	var st := BattleState.make({"seed": 1, "w": 48, "d": 34})
	st.set_props(BtBlocking.prep_field(fp), false)
	var rng := Rng.make("test:blocking_pin", 1)
	var us := []
	for i: int in 40:
		us.append([["hoplite", "cavalry", "mech"][rng.bounded(3)], (rng.bounded(4401) - 2200) * 10, (rng.bounded(3001) - 1500) * 10])
	_add_units(st, us)
	var v := PackedInt64Array([st.props_hash])
	for z: int in range(-17, 18):
		var row := 0
		for x: int in range(-24, 25):
			row = row * 2 + (1 if BtBlocking.block_at(st, x * 1000, z * 1000) else 0)
		v.append(row)
	for z: int in range(-5, 6):
		for x: int in range(-7, 8):
			v.append(1 if BtBlocking.room_to_land(st, x * 3000, z * 3000) else 0)
			v.append(1 if BtBlocking.crowded(st, x * 3000, z * 3000, null, 800) else 0)
	for i: int in 60:
		var from := PackedInt64Array()
		if i % 3 == 0:
			from = PackedInt64Array([(rng.bounded(4001) - 2000) * 10, (rng.bounded(2801) - 1400) * 10])
		var p := BtBlocking.free_spot(st, (rng.bounded(4801) - 2400) * 10, (rng.bounded(3401) - 1700) * 10,
			st.units[i % st.units.size()] if i % 4 == 0 else null, from, 6000, 800)
		v.append(p.size())
		v.append_array(p)
	assert_digest(Hash.digest_hex(v), "acab69e902257125", "pinned digest: block_at / room_to_land / crowded / free_spot on seed 1 / 48 in ruin")


func test_free_spot_speed() -> void:
	# deploy-like work: 400 bases set down one by one round formation points on a dense ruin table
	var fp := FieldProps.generate(FieldTerrain.make(72, FieldTerrain.depth_for(72), "ruin", "hills", 3), true, 2500)
	var st := BattleState.make({"seed": 3, "w": 72})
	st.set_props(BtBlocking.prep_field(fp), false)
	var sq := st.add_squad("s", "hoplite", 0, 0, 1, 0)
	var rng := Rng.make("test:speed", 2)
	var t0 := Time.get_ticks_msec()
	for i: int in 400:
		var p := BtBlocking.free_spot(st, (rng.bounded(5001) - 2500) * 10, (rng.bounded(3201) - 1600) * 10, null, PackedInt64Array(), 0, 800)
		st.add_unit("m%d" % i, sq, 1, p[0], p[1])
	var ms := Time.get_ticks_msec() - t0
	var overlap := 0
	for i: int in st.units.size():
		if BtBlocking.crowded(st, st.units[i].x, st.units[i].z, st.units[i], 800):
			overlap += 1
	print("info  400 free_spot placements on a dense 72 in ruin (%d props): %d ms" % [st.props.size(), ms])
	assert_eq(overlap, 0, "400 bases placed with free_spot never overlap")
	assert_true(ms < 20000, "400 placements take %d ms (< 20 s even on a slow runner)" % ms)


## the recorded 48 in ruin with six seats (fixtures/army/page_samples.json, the page's own deploy case)
func _deploy6() -> BattleState:
	var all: Dictionary = _to_ints(JSON.parse_string(FileAccess.get_file_as_string("res://tests/unit/fixtures/army/page_samples.json")))
	var c: Dictionary = {}
	for cv: Variant in all["deploy"]:
		var d: Dictionary = cv
		if str(d["field"]) == "ruin48" and (d["seats"] as Array).size() == 6:
			c = d
	var f: Dictionary = all["fields"]["ruin48"]
	var setup: Dictionary = c["setup"]
	var st := BattleState.make({"seed": f["seed"], "w": f["w"], "d": f["d"], "teams": setup["teams"],
		"perTeam": setup["perTeam"], "mode": setup["mode"], "budget": setup["budget"]})
	var items: Array[Dictionary] = []
	for r: Variant in f["props"]:
		items.append(BtBlocking.prep_one(str(r[0]), r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
	st.set_props(items, true)
	for sv: Variant in c["seats"]:
		var s: Dictionary = sv
		var p := st.add_seat(int(s["team"]), "", bool(s.get("bot", false)), false, "")
		var list := PackedInt32Array()
		list.resize(GameData.count())
		for e: Variant in s.get("list", []):
			list[int(e[0])] = int(e[1])
		p.list = list
		if s.get("dep") != null:
			var dp: Array = s["dep"]
			p.has_dep = true
			p.dep_x = dp[0]
			p.dep_z = dp[1]
	return st


func test_deploy_speed() -> void:
	var st := _deploy6()
	var ev: Array[Dictionary] = []
	var t0 := Time.get_ticks_msec()
	BtArmy.deploy(st, ev)
	var ms := Time.get_ticks_msec() - t0
	print("info  deploy of the recorded 48 in ruin, %d seats / %d models: %d ms, digest %s" % [st.seats.size(), st.units.size(), ms, st.digest()])
	assert_eq(st.digest(), "e195700554aa40b1", "deploy of the recorded six-seat ruin is the same as with the plain scan (digest from before the grids)")
	assert_eq(st.units.size(), 280, "280 models deployed")
	# measured headless on the dev container: 6425 ms with the plain scan, about 650 ms with the grids;
	# the bound is loose because the self-test also runs on phones
	assert_true(ms < 10000, "deploy of 280 models takes %d ms" % ms)


## random props of every kind (turned, scaled, walls of 3..6 parts, zero-radius kinds), on any table size
func _rand_props(rng: Rng, w: int, d: int, n: int) -> Array[Dictionary]:
	var kinds := ["building", "wall", "pillars", "tree", "tower", "crater", "bush", "boulder", "rubble", "zz"]
	var out: Array[Dictionary] = []
	for i: int in n:
		var k: String = kinds[rng.bounded(kinds.size())]
		var x := rng.bounded(w * 1000 + 8001) - w * 500 - 4000
		var z := rng.bounded(d * 1000 + 8001) - d * 500 - 4000
		out.append(BtBlocking.prep_one(k, x, z, rng.bounded(BtBlocking.ONE * 7), 4000 + rng.bounded(26001), rng.bounded(BtBlocking.ONE),
			1000 + rng.bounded(9001), 1000 + rng.bounded(7001)))
	return out


func test_free_spot_grids_equal_plain_scan() -> void:
	# the unit grid, the packed prop shapes, the ring cache and the ring / block skips against the plain reference:
	# random tables (tiny to wide), random props, unit sets from empty to a covered table (any type, unknown types,
	# models off the table), skip / rad / from / max_d mixed; every exit of free_spot is reached
	var rng := Rng.make("test:fsgrid", 3)
	var exits := {}
	var bad := []
	var queries := 0
	var tables := [[2, 2, 0, 0], [6, 4, 3, 20], [24, 18, 12, 300], [30, 22, 25, 60], [48, 34, 18, 140], [60, 44, 40, 30], [33, 23, 0, 0]]
	for cfg: Array in tables:
		for rep: int in 2:
			var st := BattleState.make({"seed": 1, "w": cfg[0], "d": cfg[1]})
			st.set_props(_rand_props(rng, cfg[0], cfg[1], cfg[2]), false)
			var us := []
			var nu: int = cfg[3] if rep == 0 else Fx.idiv(int(cfg[3]), 3)
			for i: int in nu:
				var k := GameData.key_at(rng.bounded(GameData.count())) if rng.bounded(8) != 0 else "zz_unknown"
				us.append([k, rng.bounded(int(cfg[0]) * 1000 + 6001) - int(cfg[0]) * 500 - 3000,
					rng.bounded(int(cfg[1]) * 1000 + 6001) - int(cfg[1]) * 500 - 3000])
			_add_units(st, us)
			var before := st.digest()
			for q: int in 40:
				var x := (rng.bounded(int(cfg[0]) * 100 + 201) - int(cfg[0]) * 50 - 100) * 10
				var z := (rng.bounded(int(cfg[1]) * 100 + 201) - int(cfg[1]) * 50 - 100) * 10
				var skip: BattleState.Unit = st.units[rng.bounded(st.units.size())] if st.units.size() > 0 and rng.bounded(3) == 0 else null
				var from := PackedInt64Array()
				var max_d := 0
				if rng.bounded(4) == 0:
					from = PackedInt64Array([x + (rng.bounded(401) - 200) * 10, z + (rng.bounded(401) - 200) * 10])
					max_d = rng.bounded(6000) - 3
				var rad: int = [-1, 0, 800, 1100, 2200, 6000][rng.bounded(6)]
				var got := _arr(BtBlocking.free_spot(st, x, z, skip, from, max_d, rad))
				var want := _ref_exit(st, x, z, skip, from, max_d, rad)
				exits[want[1]] = int(exits.get(want[1], 0)) + 1
				queries += 1
				if got != want[0] and bad.size() < 5:
					bad.append([cfg, x, z, from, max_d, rad, got, want])
			if st.digest() != before:
				bad.append(["state changed", cfg])
	print("info  %d random free_spot queries, exits %s" % [queries, str(exits)])
	assert_true(bad.is_empty(), "free_spot equals the plain scan on %d random queries" % queries, bad)
	for e: String in ["point", "near", "limited", "wide", "overlap", "none"]:
		assert_true(int(exits.get(e, 0)) > 0, "the random queries reach the '%s' exit (%d)" % [e, int(exits.get(e, 0))])


func test_free_spot_rings_follow_the_table() -> void:
	# the ring cache grows with the widest table seen and stays right for a small table afterwards
	var big := _state(180, 120, [["building", 0, 0, 0, 10000, 0, 170000, 110000]], [])
	var small := _state(24, 18, [["building", 0, 0, 0, 10000, 0, 20000, 14000]], [])
	var none := PackedInt64Array()
	for st: BattleState in [small, big, small]:
		for p: Array in [[0, 0], [5000, -3000], [-11000, 8000]]:
			var got := _arr(BtBlocking.free_spot(st, p[0], p[1], null, none, 0, 800))
			assert_eq(got, _ref_free_spot(st, p[0], p[1], null, none, 0, 800), "%d in table from %s: the same spot as the plain scan" % [st.w, str(p)])

