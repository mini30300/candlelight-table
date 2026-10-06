extends "res://tests/testing.gd"
## core/rng.gd: PCG32 known answers from tools/gen_vectors.mjs (computed in BigInt), bounded() range,
## a d6 histogram, stream independence and snapshot/restore replay.

const VEC := "res://tests/unit/fixtures/vectors.json"
var V: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(VEC))
	if typeof(p) == TYPE_DICTIONARY:
		V = p


func _ints(a: Variant) -> Array:
	var out: Array = []
	for x: Variant in a:
		out.append(int(x))
	return out


func test_known_answers() -> void:
	var entries: Array = V["pcg32"]
	assert_true(entries.size() >= 8, "%d PCG32 vectors loaded" % entries.size())
	for e: Dictionary in entries:
		var r := Rng.make(String(e["stream"]), int(e["seed"]))
		var label := "seed %d stream %s" % [int(e["seed"]), String(e["stream"])]
		assert_eq(Hash.hex64(r.state()["inc"]), String(e["inc"]), label + ": increment derived from the stream name")
		var first: Array = []
		for i: int in 16:
			first.append(r.next_u32())
		assert_eq(first, _ints(e["first"]), label + ": first 16 outputs")
		assert_eq(Hash.hex64(r.state()["s"]), String(e["state16"]), label + ": state after 16 draws")
		var d6: Array = []
		for i: int in 24:
			d6.append(r.d6())
		assert_eq(d6, _ints(e["d6"]), label + ": 24 d6 with rejection sampling")
		var b100: Array = []
		for i: int in 8:
			b100.append(r.bounded(100))
		assert_eq(b100, _ints(e["b100"]), label + ": bounded(100)")
		var bbig: Array = []
		for i: int in 4:
			bbig.append(r.bounded(4294967295))
		assert_eq(bbig, _ints(e["bbig"]), label + ": bounded(2^32-1)")
		var last := 0
		for i: int in 1000:
			last = r.next_u32()
		assert_eq(last, int(e["at1000"]), label + ": 1000 draws later")


func test_next_u32_is_32_bit() -> void:
	var r := Rng.make("terrain", 3)
	var bad := 0
	var high := 0
	for i: int in 2000:
		var v := r.next_u32()
		if v < 0 or v > 4294967295:
			bad += 1
		if v >= 2147483648:
			high += 1
	assert_eq(bad, 0, "2000 outputs in 0..2^32-1")
	assert_true(high > 800 and high < 1200, "about half the outputs have the top bit set (%d of 2000)" % high)
	assert_eq(r.draws, 2000, "draws counts every output")


func test_bounded_range() -> void:
	var r := Rng.make("test:range", 3)
	var bad := []
	for n: int in [1, 2, 3, 6, 7, 10, 100, 1000, 65537, 1000000007, 4294967295, 4294967296]:
		var lo := 1 << 40
		var hi := -1
		for i: int in 300:
			var v := r.bounded(n)
			if v < 0 or v >= n:
				bad.append([n, v])
			lo = mini(lo, v)
			hi = maxi(hi, v)
		if n <= 10 and (lo != 0 or hi != n - 1):
			bad.append([n, "ends not reached", lo, hi])
	assert_true(bad.is_empty(), "bounded(n) stays in 0..n-1 and reaches both ends for small n", bad)
	assert_eq(r.bounded(0), 0, "bounded(0) is 0")
	assert_eq(r.bounded(-3), 0, "bounded(negative) is 0")
	assert_eq(r.bounded(1), 0, "bounded(1) is 0 without drawing")


func test_d6_histogram() -> void:
	var r := Rng.make("test:d6", 2024)
	var counts := [0, 0, 0, 0, 0, 0, 0]
	var bad := 0
	for i: int in 60000:
		var d := r.d6()
		if d < 1 or d > 6:
			bad += 1
		else:
			counts[d] += 1
	assert_eq(bad, 0, "every d6 is 1..6")
	var worst := 0
	for face: int in range(1, 7):
		worst = maxi(worst, absi(counts[face] - 10000))
	assert_true(worst <= 500, "60k d6: every face within 5%% of 10000 (worst deviation %d): %s" % [worst, str(counts.slice(1))])


func test_streams_and_seeds_differ() -> void:
	var a := Rng.make("terrain", 1)
	var b := Rng.make("props", 1)
	var c := Rng.make("terrain", 2)
	var d := Rng.make("bot:0", 1)
	var e := Rng.make("bot:1", 1)
	var sa: Array = []
	var sb: Array = []
	var sc: Array = []
	var sd: Array = []
	var se: Array = []
	for i: int in 8:
		sa.append(a.next_u32())
		sb.append(b.next_u32())
		sc.append(c.next_u32())
		sd.append(d.next_u32())
		se.append(e.next_u32())
	assert_ne(sa, sb, "terrain and props streams differ for the same seed")
	assert_ne(sa, sc, "seed 1 and seed 2 differ on the same stream")
	assert_ne(sd, se, "bot:0 and bot:1 differ")
	assert_eq(sa, _first8("terrain", 1), "the same stream and seed replay the same numbers")


func _first8(stream: String, seed_v: int) -> Array:
	var r := Rng.make(stream, seed_v)
	var out: Array = []
	for i: int in 8:
		out.append(r.next_u32())
	return out


func test_snapshot_restore_replays() -> void:
	var r := Rng.make("deploy", 77)
	for i: int in 5:
		r.next_u32()
	var snap := r.state()
	assert_eq(snap["draws"], 5, "snapshot carries the draw count")
	var a: Array = []
	for i: int in 10:
		a.append(r.d6())
	var draws_after := r.draws
	assert_true(r.restore(snap), "restore accepts its own snapshot")
	assert_eq(r.draws, 5, "restore rewinds the draw count")
	var b: Array = []
	for i: int in 10:
		b.append(r.d6())
	assert_eq(b, a, "restore replays the same dice")
	assert_eq(r.draws, draws_after, "the replay consumed the same number of draws")
	assert_false(r.restore({"s": 1}), "a snapshot without inc is refused")
	assert_false(r.restore({"s": 1, "inc": 2}), "an even increment is refused")
	assert_false(r.restore({"s": "1", "inc": 3}), "a string state is refused")
	var c := r.copy()
	assert_eq(c.next_u32(), r.next_u32(), "copy() continues the same sequence")
	assert_eq(c.stream, "deploy", "copy keeps the stream name")
	assert_eq(c.seed_value, 77, "copy keeps the seed")
