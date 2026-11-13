extends "res://tests/testing.gd"
## core/fx.gd against the JavaScript truth in fixtures/vectors.json (written by tools/gen_vectors.mjs) plus
## property checks: floor division, positive modulo, exact isqrt, norm1000 length and stable_sort stability.

const VEC := "res://tests/unit/fixtures/vectors.json"
var V: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(VEC))
	if typeof(p) == TYPE_DICTIONARY:
		V = p


func test_vectors_loaded() -> void:
	assert_true(V.has("js_round") and V.has("to_fixed") and V.has("isqrt"), "vectors.json loaded from " + VEC)


func test_js_round_matches_math_round() -> void:
	var checked := 0
	var bad := []
	for rg: Dictionary in V["js_round"]["ranges"]:
		var den := int(rg["den"])
		var from := int(rg["from"])
		var r: Array = rg["r"]
		for i: int in r.size():
			var got := Fx.js_round(from + i, den)
			checked += 1
			if got != int(r[i]) and bad.size() < 5:
				bad.append([from + i, den, int(r[i]), got])
	for e: Array in V["js_round"]["extra"]:
		var got := Fx.js_round(int(e[0]), int(e[1]))
		checked += 1
		if got != int(e[2]) and bad.size() < 5:
			bad.append([int(e[0]), int(e[1]), int(e[2]), got])
	assert_true(checked > 5000, "js_round: %d vectors checked" % checked)
	assert_true(bad.is_empty(), "js_round equals Math.round(num / den) for every vector", bad)


func test_js_round_examples() -> void:
	assert_eq(Fx.js_round(-5, 2), -2, "js_round(-5/2): -2.5 rounds to -2 (half toward +inf, unlike round())")
	assert_eq(Fx.js_round(5, 2), 3, "js_round(5/2) == 3")
	assert_eq(Fx.js_round(-7, 2), -3, "js_round(-7/2) == -3")
	assert_eq(Fx.js_round(7, 2), 4, "js_round(7/2) == 4")
	assert_eq(Fx.js_round(149, 100), 1, "1.49 rounds down")
	assert_eq(Fx.js_round(150, 100), 2, "1.50 rounds up")
	assert_eq(Fx.js_round(-150, 100), -1, "-1.50 rounds toward +inf")
	assert_eq(Fx.js_round(-151, 100), -2, "-1.51 rounds down")
	assert_eq(Fx.js_round(1250, 100), 13, "board rounding to a tenth: 1250 MI -> 13 tenths")
	assert_eq(Fx.js_round(0, 5), 0, "zero")
	assert_eq(Fx.js_round(3, 0), 0, "a zero denominator gives 0")


func test_to_fixed_matches_javascript() -> void:
	var tf: Dictionary = V["to_fixed"]
	var from := int(tf["from"])
	var f1: PackedStringArray = String(tf["f1"]).split(",")
	var f2: PackedStringArray = String(tf["f2"]).split(",")
	assert_eq(f1.size(), f2.size(), "both sweeps have the same length")
	var checked := 0
	var bad := []
	for i: int in f1.size():
		var mi := from + i
		var g1 := Fx.to_fixed_1(mi)
		var g2 := Fx.to_fixed_2(mi)
		checked += 1
		if (g1 != f1[i] or g2 != f2[i]) and bad.size() < 5:
			bad.append([mi, f1[i], g1, f2[i], g2])
	for e: Array in tf["extra"]:
		var mi := int(e[0])
		var g1 := Fx.to_fixed_1(mi)
		var g2 := Fx.to_fixed_2(mi)
		checked += 1
		if (g1 != String(e[1]) or g2 != String(e[2])) and bad.size() < 5:
			bad.append([mi, String(e[1]), g1, String(e[2]), g2])
	assert_true(checked > 4000, "to_fixed: %d vectors checked" % checked)
	assert_true(bad.is_empty(), "to_fixed_1/2 equal (mi/1000).toFixed(1/2) [mi, want1, got1, want2, got2]", bad)


func test_to_fixed_examples() -> void:
	assert_eq(Fx.to_fixed_2(125), "0.13", "0.125 is an exact binary tie: toFixed picks the larger n")
	assert_eq(Fx.to_fixed_2(-125), "-0.13", "the sign is handled apart from the magnitude")
	assert_eq(Fx.to_fixed_2(-4), "-0.00", "a negative value that rounds to zero keeps its sign like JS")
	assert_eq(Fx.to_fixed_2(1005), "1.00", "1.005 sits below the tie as a double")
	assert_eq(Fx.to_fixed_2(2675), "2.67", "2.675 sits below the tie as a double")
	assert_eq(Fx.to_fixed_1(350), "0.3", "0.35 sits below the tie as a double")
	assert_eq(Fx.to_fixed_1(250), "0.3", "0.25 is an exact tie: larger n")
	assert_eq(Fx.to_fixed_1(0), "0.0", "zero")
	assert_eq(Fx.to_fixed_2(0), "0.00", "zero with two decimals")
	assert_eq(Fx.to_fixed_1(999), "1.0", "carry into the integer part")
	assert_eq(Fx.to_fixed_2(-999), "-1.00", "negative carry")
	assert_eq(Fx.to_fixed_2(180000000), "180000.00", "the largest table coordinate")


func test_isqrt_small_sweep() -> void:
	var small: Array = V["isqrt"]["small"]
	assert_true(small.size() >= 5001, "sweep covers 0..5000 (%d values)" % small.size())
	var bad := []
	for n: int in small.size():
		var got := Fx.isqrt(n)
		if got != int(small[n]) and bad.size() < 5:
			bad.append([n, int(small[n]), got])
	assert_true(bad.is_empty(), "isqrt matches the BigInt truth for 0..5000", bad)


func test_isqrt_big_values() -> void:
	var bad := []
	var checked := 0
	for pair: Array in V["isqrt"]["big"]:
		var n := String(pair[0]).to_int()
		var want := String(pair[1]).to_int()
		var got := Fx.isqrt(n)
		checked += 1
		if got != want and bad.size() < 5:
			bad.append([n, want, got])
	assert_true(checked >= 50, "isqrt: %d big vectors checked" % checked)
	assert_true(bad.is_empty(), "isqrt matches the BigInt truth for big values up to 2^63-1", bad)
	assert_eq(Fx.isqrt(9223372036854775807), 3037000499, "isqrt(int64 max)")
	assert_eq(Fx.isqrt(-5), 0, "negative input gives 0")
	assert_eq(Fx.isqrt(0), 0, "isqrt(0)")
	assert_eq(Fx.isqrt(1), 1, "isqrt(1)")
	assert_eq(Fx.isqrt(3), 1, "isqrt(3)")
	assert_eq(Fx.isqrt(4), 2, "isqrt(4)")


func test_isqrt_floor_property() -> void:
	var rng := Rng.make("test:isqrt", 5)
	var bad := 0
	for i: int in 3000:
		var n: int = (rng.next_u32() << 30) ^ rng.next_u32()
		var r := Fx.isqrt(n)
		if r * r > n or (r + 1) * (r + 1) <= n:
			bad += 1
	assert_eq(bad, 0, "r*r <= n < (r+1)*(r+1) for 3000 seeded values up to 2^62")


func test_idiv_imod() -> void:
	var bad := []
	for a: int in range(-30, 31):
		for b: int in range(-7, 8):
			if b == 0:
				continue
			var q := Fx.idiv(a, b)
			var r := Fx.imod(a, b)
			var in_range := (b > 0 and r >= 0 and r < b) or (b < 0 and r <= 0 and r > b)
			if a != b * q + r or not in_range:
				if bad.size() < 5:
					bad.append([a, b, q, r])
	assert_true(bad.is_empty(), "a == b*idiv(a,b) + imod(a,b) with imod in [0, b) for b > 0", bad)
	assert_eq(Fx.idiv(7, 2), 3, "idiv(7, 2)")
	assert_eq(Fx.idiv(-7, 2), -4, "idiv(-7, 2) floors (GDScript / gives -3)")
	assert_eq(Fx.idiv(7, -2), -4, "idiv(7, -2)")
	assert_eq(Fx.idiv(-7, -2), 3, "idiv(-7, -2)")
	assert_eq(Fx.idiv(-8, 2), -4, "exact negative division")
	assert_eq(Fx.idiv(5, 0), 0, "idiv by zero gives 0")
	assert_eq(Fx.imod(-7, 3), 2, "imod(-7, 3) is positive (GDScript % gives -1)")
	assert_eq(Fx.imod(7, 3), 1, "imod(7, 3)")
	assert_eq(Fx.imod(-6, 3), 0, "imod exact")
	assert_eq(Fx.imod(7, -3), -2, "imod takes the divisor's sign")
	assert_eq(Fx.imod(5, 0), 0, "imod by zero gives 0")


func test_dist_dot_cross() -> void:
	assert_eq(Fx.dist2(0, 0, 3000, 4000), 25000000, "dist2 of a 3-4-5 triangle in MI")
	assert_eq(Fx.dist(0, 0, 3000, 4000), 5000, "dist of a 3-4-5 triangle")
	assert_eq(Fx.dist(1000, 1000, 1000, 1000), 0, "zero distance")
	assert_eq(Fx.dist(0, 0, 180000, 180000), 254558, "the table diagonal fits int64 maths")
	assert_eq(Fx.dist(-5000, 2000, 5000, 2000), 10000, "distance with negative coordinates")
	assert_eq(Fx.dot(1, 0, 0, 1), 0, "dot of perpendicular vectors")
	assert_eq(Fx.dot(2, 3, 4, 5), 23, "dot")
	assert_eq(Fx.cross(1, 0, 0, 1), 1, "cross: z axis is left of x axis")
	assert_eq(Fx.cross(0, 1, 1, 0), -1, "cross is antisymmetric")
	assert_eq(Fx.cross(2, 3, 4, 6), 0, "cross of parallel vectors")


func test_norm1000() -> void:
	assert_eq(Array(Fx.norm1000(3000, 4000)), [600, 800], "norm1000 scales a 3-4-5 vector to length 1000")
	assert_eq(Array(Fx.norm1000(-7, 0)), [-1000, 0], "a tiny axis vector still normalises")
	assert_eq(Array(Fx.norm1000(0, 0)), [0, 0], "the zero vector stays zero (caller picks a facing)")
	assert_eq(Array(Fx.norm1000(1000, 1000)), [707, 707], "diagonal")
	assert_eq(Array(Fx.norm1000(-1000, 1000)), [-707, 707], "negative diagonal")
	var rng := Rng.make("test:norm", 9)
	var worst := 0
	for i: int in 500:
		var dx := rng.bounded(360001) - 180000
		var dz := rng.bounded(360001) - 180000
		if dx * dx + dz * dz < 1000000:
			continue
		var n := Fx.norm1000(dx, dz)
		var l := Fx.isqrt(n[0] * n[0] + n[1] * n[1])
		worst = maxi(worst, absi(l - 1000))
		if Fx.cross(dx, dz, n[0], n[1]) != 0 and absi(Fx.cross(dx, dz, n[0], n[1])) > absi(dx) + absi(dz):
			worst = 9999
	assert_true(worst <= 1, "normalised length is 999..1001 and the direction is kept (worst %d)" % worst)


func test_stable_sort_keeps_input_order_of_equal_keys() -> void:
	var less := func(a: Dictionary, b: Dictionary) -> bool: return int(a["k"]) < int(b["k"])
	var input: Array = [{"k": 1, "i": 0}, {"k": 0, "i": 1}, {"k": 1, "i": 2}, {"k": 0, "i": 3}, {"k": 2, "i": 4}]
	var sorted := Fx.stable_sort(input, less)
	var order: Array = []
	for d: Dictionary in sorted:
		order.append(int(d["i"]))
	assert_eq(order, [1, 3, 0, 2, 4], "equal keys keep their input order")
	assert_eq(input.size(), 5, "the input is not mutated (size)")
	assert_eq(int(input[0]["i"]), 0, "the input is not mutated (order)")
	assert_eq(Fx.stable_sort([], less), [], "empty")
	assert_eq(Fx.stable_sort([{"k": 5, "i": 0}], less), [{"k": 5, "i": 0}], "single element")
	var ints := Fx.stable_sort([3, 1, 2, 1], func(a: int, b: int) -> bool: return a < b)
	assert_eq(ints, [1, 1, 2, 3], "ints ascending")
	var desc := Fx.stable_sort([3, 1, 2], func(a: int, b: int) -> bool: return a > b)
	assert_eq(desc, [3, 2, 1], "ints descending")


func test_stable_sort_random_arrays() -> void:
	var less := func(a: Dictionary, b: Dictionary) -> bool: return int(a["k"]) < int(b["k"])
	var rng := Rng.make("test:sort", 11)
	var bad := 0
	for trial: int in 40:
		var n := rng.bounded(130)
		var arr: Array = []
		for i: int in n:
			arr.append({"k": rng.bounded(7), "i": i})
		var before := arr.duplicate(true)
		var sorted := Fx.stable_sort(arr, less)
		if arr != before or sorted.size() != n:
			bad += 1
		for j: int in range(1, sorted.size()):
			var p: Dictionary = sorted[j - 1]
			var q: Dictionary = sorted[j]
			if int(p["k"]) > int(q["k"]) or (int(p["k"]) == int(q["k"]) and int(p["i"]) > int(q["i"])):
				bad += 1
	assert_eq(bad, 0, "40 seeded arrays (up to 130 items, 7 distinct keys) come back sorted and stable")


func test_clampi_and_sign() -> void:
	assert_eq(Fx.clampi(7, 0, 5), 5, "clampi above")
	assert_eq(Fx.clampi(-3, 0, 5), 0, "clampi below")
	assert_eq(Fx.clampi(3, 0, 5), 3, "clampi inside")
	assert_eq(Fx.sign(-9), -1, "sign negative")
	assert_eq(Fx.sign(0), 0, "sign zero")
	assert_eq(Fx.sign(4), 1, "sign positive")
	assert_eq(Fx.MI, 1000, "1 inch = 1000 MI")


func test_cdiv() -> void:
	var bad := []
	for a: int in range(-30, 31):
		for b: int in range(-7, 8):
			if b == 0:
				continue
			var q := Fx.cdiv(a, b)
			var want := ceili(float(a) / float(b))
			var r := a - q * b
			var in_range := (b > 0 and r <= 0 and r > -b) or (b < 0 and r >= 0 and r < -b)
			if q != want or not in_range:
				if bad.size() < 5:
					bad.append([a, b, q, want])
	assert_true(bad.is_empty(), "cdiv(a, b) is the ceiling of a / b for a in -30..30, b in -7..7", bad)
	assert_eq(Fx.cdiv(7, 2), 4, "cdiv(7, 2)")
	assert_eq(Fx.cdiv(-7, 2), -3, "cdiv(-7, 2) rounds up towards +inf (GDScript / gives -3 too, idiv -4)")
	assert_eq(Fx.cdiv(7, -2), -3, "cdiv(7, -2)")
	assert_eq(Fx.cdiv(-7, -2), 4, "cdiv(-7, -2)")
	assert_eq(Fx.cdiv(6, 3), 2, "exact division")
	assert_eq(Fx.cdiv(-6, 3), -2, "exact negative division")
	assert_eq(Fx.cdiv(0, 5), 0, "zero")
	assert_eq(Fx.cdiv(1, 1250), 1, "any positive remainder rounds up")
	assert_eq(Fx.cdiv(60000, 1250), 48, "the 48 x 36 table: 60 in / 1.25 in = 48 rings exactly")
	assert_eq(Fx.cdiv(5, 0), 0, "cdiv by zero gives 0 (like idiv)")
	var rng := Rng.make("test:cdiv", 3)
	var bad2 := 0
	for i: int in 2000:
		var a2: int = ((rng.next_u32() << 20) ^ rng.next_u32()) - (1 << 51)
		var b2: int = rng.bounded(100000) + 1
		var q2 := Fx.cdiv(a2, b2)
		if q2 * b2 < a2 or (q2 - 1) * b2 >= a2 or q2 != Fx.idiv(a2, b2) + (0 if Fx.imod(a2, b2) == 0 else 1):
			bad2 += 1
	assert_eq(bad2, 0, "q*b >= a > (q-1)*b for 2000 seeded big values (+-2^51, b up to 10^5)")


func test_isqrt_ceil() -> void:
	var bad := []
	for n: int in 5001:
		var r := Fx.isqrt_ceil(n)
		var ok := r * r >= n and (r == 0 or (r - 1) * (r - 1) < n)
		if not ok and bad.size() < 5:
			bad.append([n, r])
	assert_true(bad.is_empty(), "(r-1)^2 < n <= r^2 for n = 0..5000", bad)
	assert_eq(Fx.isqrt_ceil(0), 0, "isqrt_ceil(0)")
	assert_eq(Fx.isqrt_ceil(1), 1, "isqrt_ceil(1)")
	assert_eq(Fx.isqrt_ceil(2), 2, "isqrt_ceil(2)")
	assert_eq(Fx.isqrt_ceil(4), 2, "a perfect square stays exact")
	assert_eq(Fx.isqrt_ceil(5), 3, "isqrt_ceil(5)")
	assert_eq(Fx.isqrt_ceil(3600000000), 60000, "the 48 x 36 diagonal in MI is exact (60 in)")
	assert_eq(Fx.isqrt_ceil(3600000001), 60001, "one more MI^2 rounds up")
	assert_eq(Fx.isqrt_ceil(-9), 0, "negative input gives 0")
	assert_eq(Fx.isqrt_ceil(9223372036854775807), 3037000500, "isqrt_ceil(int64 max) without overflow")
	assert_eq(Fx.isqrt_ceil(9223372030926249001), 3037000499, "the largest int64 perfect square")
	var rng := Rng.make("test:isqrt_ceil", 13)
	var bad2 := 0
	for i: int in 3000:
		var n2: int = (rng.next_u32() << 30) ^ rng.next_u32()
		var r2 := Fx.isqrt_ceil(n2)
		var f := Fx.isqrt(n2)
		if not ((f * f == n2 and r2 == f) or (f * f < n2 and r2 == f + 1)):
			bad2 += 1
	assert_eq(bad2, 0, "isqrt_ceil = isqrt, plus one unless n is a perfect square, for 3000 seeded values up to 2^62")
