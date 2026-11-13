extends "res://tests/testing.gd"
## core/battle/offsets.gd (BtOffsets, R1_PORT_SPEC §1.2): the literal tables are exactly what tools/gen_offsets.gd
## produces (entry by entry and as text), they equal the page's own expressions evaluated in V8
## (fixtures/offsets/page.json, written by tools/record_blocking.js), the spot values the spec lists, the grid and
## shape invariants, FS_RING_K against the page's ring count for r = 1..400, and one pinned digest of every table.

const GEN := "res://tools/gen_offsets.gd"
const SRC := "res://core/battle/offsets.gd"
const FIX := "res://tests/unit/fixtures/offsets/page.json"
const NAMES := ["FREESPOT_NEAR", "ROOM_TO_LAND", "PLAN_RING", "CHARGE_ROT", "SIDESTEP_ROT"]
const SIZES := {"FREESPOT_NEAR": 140, "ROOM_TO_LAND": 24, "PLAN_RING": 61, "CHARGE_ROT": 4, "SIDESTEP_ROT": 4}
## fixture key of each table
const PAGE_KEY := {"FREESPOT_NEAR": "near", "ROOM_TO_LAND": "room", "PLAN_RING": "plan", "CHARGE_ROT": "charge",
	"SIDESTEP_ROT": "side"}

var gen: GDScript
var consts: Dictionary = {}
var page: Dictionary = {}


func setup() -> void:
	gen = load(GEN)
	consts = (load(SRC) as GDScript).get_script_constant_map()
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		page = p


## int rows of a table (JSON numbers come back as floats)
func _rows(v: Variant) -> Array:
	var out: Array = []
	for r: Variant in v:
		out.append([int(r[0]), int(r[1])])
	return out


func test_loaded() -> void:
	assert_true(gen != null, "the generator loads from " + GEN)
	assert_true(page.has("near") and page.has("ring_n"), "page fixture loaded from " + FIX)
	assert_eq(str(page.get("meta", {}).get("app_ver", "")), "9.4", "fixture recorded from page APP_VER 9.4")
	for name: String in NAMES:
		assert_true(consts.has(name), "BtOffsets has " + name)


func test_tables_equal_the_generator() -> void:
	var tb: Dictionary = gen.call("tables")
	assert_eq(tb.keys(), NAMES, "the generator makes the five tables in order")
	for name: String in NAMES:
		var lit: Array = _rows(consts[name])
		var want: Array = _rows(tb[name])
		assert_eq(lit.size(), int(SIZES[name]), "%s has %d rows" % [name, int(SIZES[name])])
		var bad := []
		for i: int in mini(lit.size(), want.size()):
			if lit[i] != want[i] and bad.size() < 5:
				bad.append([i, lit[i], want[i]])
		assert_true(lit.size() == want.size() and bad.is_empty(), name + ": every entry equals the generator", bad)
	var sc: Dictionary = gen.call("scalars")
	for name: String in ["DEP_ANG_STEP", "FS_ANG_STEP", "FS_RING_K"]:
		assert_eq(int(consts[name]), int(sc[name]), name + " equals the generator")


func test_block_text_is_the_generator_output() -> void:
	var text := FileAccess.get_file_as_string(SRC)
	var block: String = gen.call("block_of", text)
	assert_true(block.length() > 1000, "offsets.gd holds the generated block")
	assert_eq(block, str(gen.call("render")), "the block in offsets.gd is byte for byte tools/gen_offsets.gd's render()")
	var gc := gen.get_script_constant_map()
	assert_eq(text.count(str(gc["BEGIN"])), 1, "one BEGIN marker")
	assert_eq(text.count(str(gc["END"])), 1, "one END marker")


func test_tables_equal_the_page() -> void:
	for name: String in NAMES:
		var lit: Array = _rows(consts[name])
		var pg: Array = _rows(page[PAGE_KEY[name]])
		assert_eq(lit, pg, name + " equals the page's expressions rounded in V8 (%d rows)" % pg.size())
	assert_eq(BtOffsets.DEP_ANG_STEP, int(page["dep_ang_step"]), "DEP_ANG_STEP = Math.round(0.7 * 65536) on the page")
	assert_eq(BtOffsets.FS_ANG_STEP, int(page["fs_ang_step"]), "FS_ANG_STEP = Math.round(0.41 * 65536) on the page")


func test_spec_spot_values() -> void:
	var near: Array = _rows(BtOffsets.FREESPOT_NEAR)
	assert_eq(near.slice(0, 4), [[1150, 500], [820, 950], [330, 1210], [-230, 1230]], "FREESPOT_NEAR starts as the spec says")
	assert_eq(near.slice(14, 16), [[1710, 1830], [740, 2390]], "FREESPOT_NEAR ring 2 starts as the spec says")
	assert_eq(_rows(BtOffsets.ROOM_TO_LAND), [[1250, 0], [1083, 625], [625, 1083], [0, 1250], [-625, 1083], [-1083, 625],
		[-1250, 0], [-1083, -625], [-625, -1083], [0, -1250], [625, -1083], [1083, -625], [2500, 0], [2165, 1250],
		[1250, 2165], [0, 2500], [-1250, 2165], [-2165, 1250], [-2500, 0], [-2165, -1250], [-1250, -2165], [0, -2500],
		[1250, -2165], [2165, -1250]], "ROOM_TO_LAND is the spec's list")
	assert_eq(_rows(BtOffsets.PLAN_RING).slice(0, 8), [[0, 0], [750, 290], [430, 670], [-40, 800], [-510, 620], [-770, 200],
		[-750, -290], [-430, -670]], "PLAN_RING starts as the spec says")
	assert_eq(_rows(BtOffsets.CHARGE_ROT), [[55871, 34255], [29727, 58406], [-5185, 65331], [-38568, 52986]], "CHARGE_ROT")
	assert_eq(_rows(BtOffsets.SIDESTEP_ROT), [[60363, 25521], [45659, 47013], [23747, 61082], [-1914, 65508]], "SIDESTEP_ROT")
	assert_eq(BtOffsets.DEP_ANG_STEP, 45875, "DEP_ANG_STEP")
	assert_eq(BtOffsets.FS_ANG_STEP, 26870, "FS_ANG_STEP")
	assert_eq(BtOffsets.FS_RING_K, 6544985, "FS_RING_K")


func test_grid_and_shape() -> void:
	var off_grid := []
	for name: String in ["FREESPOT_NEAR", "PLAN_RING"]:
		for r: Array in _rows(consts[name]):
			if r[0] % 10 != 0 or r[1] % 10 != 0:
				off_grid.append([name, r])
	assert_eq(off_grid, [], "freeSpot and planMove offsets are on the 10 MI grid (positions)")
	# ring k of freeSpot lies at k x 1.25 in, of planMove at k x 0.8 in: the 10 MI rounding moves a point <= 7.1 MI
	var worst := 0
	var near: Array = _rows(BtOffsets.FREESPOT_NEAR)
	for i: int in near.size():
		var want := (Fx.idiv(i, 14) + 1) * 1250
		worst = maxi(worst, absi(Fx.isqrt(near[i][0] * near[i][0] + near[i][1] * near[i][1]) - want))
	var plan: Array = _rows(BtOffsets.PLAN_RING)
	for i: int in range(1, plan.size()):
		var want2 := (Fx.idiv(i - 1, 10) + 1) * 800
		worst = maxi(worst, absi(Fx.isqrt(plan[i][0] * plan[i][0] + plan[i][1] * plan[i][1]) - want2))
	assert_true(worst <= 8, "every ring point lies on its circle within the grid rounding (worst %d MI)" % worst)
	var room: Array = _rows(BtOffsets.ROOM_TO_LAND)
	var twice := 0
	for i: int in 12:
		twice = maxi(twice, maxi(absi(room[i + 12][0] - 2 * room[i][0]), absi(room[i + 12][1] - 2 * room[i][1])))
	assert_true(twice <= 1, "the outer roomToLand ring is the inner one doubled (exact MI rounding, worst %d)" % twice)
	for name: String in ["CHARGE_ROT", "SIDESTEP_ROT"]:
		var unit := 0
		for r: Array in _rows(consts[name]):
			unit = maxi(unit, absi(Fx.isqrt(r[0] * r[0] + r[1] * r[1]) - 65536))
		assert_true(unit <= 1, name + ": every [cos, sin] has length 65536 within rounding")
	# the rotation tables agree with the integer sine to within its error (a few Q16 units)
	var dsin := 0
	for k: int in 4:
		var a1 := Fx.js_round((k + 1) * 55 * 65536, 100)
		var a2 := Fx.js_round((k + 1) * 4 * 65536, 10)
		dsin = maxi(dsin, absi(int(BtOffsets.CHARGE_ROT[k][1]) - Fx.isin_q16(a1)))
		dsin = maxi(dsin, absi(int(BtOffsets.SIDESTEP_ROT[k][1]) - Fx.isin_q16(a2)))
		dsin = maxi(dsin, absi(int(BtOffsets.CHARGE_ROT[k][0]) - Fx.isin_q16(a1 + Fx.HALF_PI_Q16)))
		dsin = maxi(dsin, absi(int(BtOffsets.SIDESTEP_ROT[k][0]) - Fx.isin_q16(a2 + Fx.HALF_PI_Q16)))
	assert_true(dsin <= 4, "CHARGE_ROT / SIDESTEP_ROT agree with Fx.isin_q16 (worst %d Q16 units)" % dsin)


func test_fs_ring_n_equals_the_page() -> void:
	var pg: Array = page["ring_n"]
	assert_eq(pg.size(), 400, "the page's ring counts for r = 1..400")
	var bad := []
	for r: int in range(1, 401):
		var want_f: int = maxi(14, int(gen.call("js_round_f", r * 1.25 * TAU / 1.2)))
		var got := BtOffsets.fs_ring_n(r)
		if got != int(pg[r - 1]) or got != want_f:
			if bad.size() < 5:
				bad.append([r, got, int(pg[r - 1]), want_f])
	assert_true(bad.is_empty(), "fs_ring_n(r) = max(14, Math.round(r * 1.25 * TAU / 1.2)) for every r <= 400 [r, port, page, f64]", bad)
	assert_eq(BtOffsets.fs_ring_n(1), 14, "small rings keep 14 points")
	assert_eq(BtOffsets.fs_ring_n(2), 14, "r = 2 still 14")
	assert_eq(BtOffsets.fs_ring_n(3), 20, "r = 3: round(19.63) = 20")
	assert_eq(BtOffsets.fs_ring_n(11), 72, "the first wide ring has 72 points")


func test_pinned_digest() -> void:
	var v := PackedInt64Array([BtOffsets.DEP_ANG_STEP, BtOffsets.FS_ANG_STEP, BtOffsets.FS_RING_K])
	for name: String in NAMES:
		var rows: Array = _rows(consts[name])
		v.append(rows.size())
		for r: Array in rows:
			v.append(r[0])
			v.append(r[1])
	assert_digest(Hash.digest_hex(v), "78aa9dbea4d26c7e", "pinned digest of every BtOffsets table")
