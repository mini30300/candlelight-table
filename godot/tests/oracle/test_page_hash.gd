extends "res://tests/testing.gd"
## tests/oracle/page_hash.gd against the page's own hash2/hash3, sampled in Node (V8, the page's engine) by
## `node godot/tools/record_oracle.js --hash-samples` into tests/oracle/page_hash.json.

const PageHash := preload("res://tests/oracle/page_hash.gd")
const SAMPLES := "res://tests/oracle/page_hash.json"

var _data: Dictionary = {}


func setup() -> void:
	var f := FileAccess.open(SAMPLES, FileAccess.READ)
	if f == null:
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	if typeof(v) == TYPE_DICTIONARY:
		_data = v


## The same hash with exact integer arithmetic (no double rounding), to show the samples exercise the rounding.
static func _exact_q(seed: int, ix: int, iy: int) -> int:
	var h: int = PageHash.i32(ix) * 374761393 + PageHash.i32(iy) * 668265263 + seed * 1274126177
	h = PageHash.i32(PageHash.i32(h) ^ (PageHash.u32(h) >> 13)) * 1274126177
	h = PageHash.i32(PageHash.i32(h) ^ (PageHash.u32(h) >> 16))
	return PageHash.u32(h) % 65536


func test_samples_present() -> void:
	assert_true(not _data.is_empty(), "page_hash.json loads (" + SAMPLES + ")")
	if _data.is_empty():
		return
	var h2: Array = _data.get("hash2", [])
	var h3: Array = _data.get("hash3", [])
	var bld: Array = _data.get("bld", [])
	assert_true(h2.size() >= 1000, "at least 1000 hash2 samples", h2.size())
	assert_true(h3.size() >= 1000, "at least 1000 hash3 samples", h3.size())
	assert_true(bld.size() >= 50, "building depths of the recorded props", bld.size())


func test_dbl_rounding() -> void:
	var two53: int = 1 << 53
	assert_eq(PageHash.dbl(two53), two53, "2^53 is a double")
	assert_eq(PageHash.dbl(two53 + 1), two53, "2^53+1 ties to even (down)")
	assert_eq(PageHash.dbl(two53 + 3), two53 + 4, "2^53+3 ties to even (up)")
	assert_eq(PageHash.dbl(two53 + 2), two53 + 2, "2^53+2 exact")
	assert_eq(PageHash.dbl(-(two53 + 1)), -two53, "negative ties to even")
	assert_eq(PageHash.dbl(-(two53 + 3)), -(two53 + 4), "negative ties to even (away)")
	assert_eq(PageHash.dbl((1 << 61) + (1 << 8) - 1), 1 << 61, "below half of the 2^8 step rounds down at 2^61")
	assert_eq(PageHash.dbl((1 << 61) + (1 << 8) + 1), (1 << 61) + (1 << 9), "above half rounds up at 2^61")
	assert_eq(PageHash.dbl((1 << 61) + (1 << 9) + (1 << 8)), (1 << 61) + (1 << 10), "odd quotient tie rounds up to even")
	assert_eq(PageHash.dbl(12345), 12345, "small ints are exact")
	assert_eq(PageHash.dbl(-12345), -12345, "small negative ints are exact")
	assert_eq(PageHash.i32(_two32_plus(5)), 5, "ToInt32 wraps 2^32 + 5")
	assert_eq(PageHash.i32(2147483648), -2147483648, "ToInt32 of 2^31")
	assert_eq(PageHash.i32(-1), -1, "ToInt32 of -1")
	assert_eq(PageHash.u32(-1), 4294967295, "ToUint32 of -1")


static func _two32_plus(v: int) -> int:
	return 4294967296 + v


func test_hash2_matches_page() -> void:
	var rows: Array = _data.get("hash2", [])
	var bad := 0
	var first := ""
	var differs := 0
	for r: Variant in rows:
		var a: Array = r
		var seed := int(a[0])
		var ix := int(a[1])
		var iy := int(a[2])
		var want := int(a[3])
		var got := PageHash.hash2_q(seed, ix, iy)
		if got != want:
			bad += 1
			if first == "":
				first = "seed %d hash2(%d, %d) = %d, page %d" % [seed, ix, iy, got, want]
		if _exact_q(seed, ix, iy) != want:
			differs += 1
	assert_eq(bad, 0, "hash2 equals the page on %d samples %s" % [rows.size(), first])
	var dd: Dictionary = _data.get("differs", {})
	assert_eq(differs, int(dd.get("hash2", -1)), "exact integer arithmetic differs from the page on the same samples as in Node")
	assert_true(differs * 2 > rows.size(), "the samples exercise V8's double rounding (most differ from exact integers)", differs)


func test_hash3_matches_page() -> void:
	var rows: Array = _data.get("hash3", [])
	var bad := 0
	var first := ""
	for r: Variant in rows:
		var a: Array = r
		var seed := int(a[0])
		var got := PageHash.hash3_q(seed, int(a[1]), int(a[2]), int(a[3]))
		if got != int(a[4]):
			bad += 1
			if first == "":
				first = "seed %d hash3(%d, %d, %d) = %d, page %d" % [seed, int(a[1]), int(a[2]), int(a[3]), got, int(a[4])]
	assert_eq(bad, 0, "hash3 equals the page on %d samples %s" % [rows.size(), first])


func test_building_depths_match_page() -> void:
	var rows: Array = _data.get("bld", [])
	var bad := 0
	var first := ""
	for r: Variant in rows:
		var a: Array = r
		var got := PageHash.bld_depth_mi(int(a[0]), float(a[1]), float(a[2]))
		if got != int(a[3]):
			bad += 1
			if first == "":
				first = "seed %d h %s s %s: %d, page %d" % [int(a[0]), str(a[1]), str(a[2]), got, int(a[3])]
	assert_eq(bad, 0, "bldSize depth equals the page for %d recorded buildings %s" % [rows.size(), first])


func test_hand_values() -> void:
	# pinned from the page (seed 1, hash2(0, 0) and the bldSize call shape)
	assert_eq(PageHash.hash2_q(1, 0, 0), 30540, "seed 1 hash2(0, 0)")
	assert_eq(PageHash.hash2_q(1, 0, 1), 4578, "seed 1 hash2(0, 1)")
	assert_eq(PageHash.bld_width_mi(0.5, 1.0), 8500, "bldSize width (5 + h*7)*s at h 0.5, s 1")
	assert_eq(PageHash.js_roundf(-2.5), -2, "Math.round(-2.5) = -2 (half up)")
	assert_eq(PageHash.js_roundf(2.5), 3, "Math.round(2.5) = 3")
