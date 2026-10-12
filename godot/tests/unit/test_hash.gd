extends "res://tests/testing.gd"
## core/hash.gd: ihash2/ihash3 and FNV-1a 64 against tools/gen_vectors.mjs (BigInt), 32-bit output range,
## mixing sanity and the 16-character hex digest.

const VEC := "res://tests/unit/fixtures/vectors.json"
var V: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(VEC))
	if typeof(p) == TYPE_DICTIONARY:
		V = p


func test_ihash2_vectors() -> void:
	var bad := []
	var checked := 0
	for v: Array in V["ihash"]["h2"]:
		var got := Hash.ihash2(int(v[0]), int(v[1]), int(v[2]))
		checked += 1
		if got != int(v[3]) and bad.size() < 5:
			bad.append([int(v[0]), int(v[1]), int(v[2]), int(v[3]), got])
	assert_true(checked >= 300, "ihash2: %d vectors checked" % checked)
	assert_true(bad.is_empty(), "ihash2 matches the BigInt reference [x, y, salt, want, got]", bad)


func test_ihash3_vectors() -> void:
	var bad := []
	var checked := 0
	for v: Array in V["ihash"]["h3"]:
		var got := Hash.ihash3(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
		checked += 1
		if got != int(v[4]) and bad.size() < 5:
			bad.append([int(v[0]), int(v[1]), int(v[2]), int(v[3]), int(v[4]), got])
	assert_true(checked >= 70, "ihash3: %d vectors checked" % checked)
	assert_true(bad.is_empty(), "ihash3 matches the BigInt reference [x, y, z, salt, want, got]", bad)


func test_ihash_range_and_mixing() -> void:
	var bad := 0
	var seen := {}
	for x: int in 1000:
		var h := Hash.ihash2(x, 0, 0)
		if h < 0 or h > 4294967295:
			bad += 1
		seen[h] = true
	assert_eq(bad, 0, "ihash2 outputs are 0..2^32-1")
	assert_true(seen.size() >= 995, "1000 neighbouring x give %d distinct hashes" % seen.size())
	assert_ne(Hash.ihash2(1, 2, 0), Hash.ihash2(2, 1, 0), "x and y are not interchangeable")
	assert_ne(Hash.ihash2(1, 2, 0), Hash.ihash2(1, 2, 1), "the salt matters")
	assert_ne(Hash.ihash3(1, 2, 3, 0), Hash.ihash2(1, 2, 0), "ihash3 differs from ihash2")
	assert_eq(Hash.ihash2(-1, 5, 0), Hash.ihash2(4294967295, 5, 0), "inputs are masked to 32 bits")
	assert_eq(Hash.ihash2(1, 2, 3), Hash.ihash2(1, 2, 3), "deterministic")
	assert_eq(Hash.mix32(0), 0, "mix32(0) == 0 (lowbias32 has no additive constant)")
	assert_eq(Hash.mix32(4294967296 + 7), Hash.mix32(7), "mix32 masks its input")


func test_fnv1a64_vectors() -> void:
	var bad := []
	for e: Dictionary in V["fnv"]["ints"]:
		var ints := PackedInt64Array()
		for s: Variant in e["v"]:
			ints.append(String(s).to_int())
		var got := Hash.hex64(Hash.fnv1a64(ints))
		if got != String(e["hex"]):
			bad.append([Array(ints), String(e["hex"]), got])
	assert_true(bad.is_empty(), "fnv1a64 over int64 arrays (8 little-endian bytes each) matches [ints, want, got]", bad)
	var bad_s := []
	for e: Dictionary in V["fnv"]["strs"]:
		var got := Hash.hex64(Hash.fnv1a64_str(String(e["s"])))
		if got != String(e["hex"]):
			bad_s.append([String(e["s"]), String(e["hex"]), got])
	assert_true(bad_s.is_empty(), "fnv1a64_str over UTF-8 (Thai included) matches [s, want, got]", bad_s)
	assert_eq(Hash.hex64(Hash.fnv1a64_str("")), "cbf29ce484222325", "empty string = offset basis")
	assert_eq(Hash.hex64(Hash.fnv1a64_str("a")), "af63dc4c8601ec8c", "FNV-1a 64 of \"a\" (published value)")


func test_hex64() -> void:
	assert_eq(Hash.hex64(0), "0000000000000000", "zero")
	assert_eq(Hash.hex64(255), "00000000000000ff", "255")
	assert_eq(Hash.hex64(-1), "ffffffffffffffff", "-1 prints as unsigned")
	assert_eq(Hash.hex64((-9223372036854775807) - 1), "8000000000000000", "int64 min")
	assert_eq(Hash.hex64(9223372036854775807), "7fffffffffffffff", "int64 max")
	assert_eq(Hash.hex64(0x1234ABCD), "000000001234abcd", "lowercase hex, 16 characters")


func test_digest_hex() -> void:
	var a := PackedInt64Array([10, 1, 0, 0, 0, 0, 0, 0])
	var d := Hash.digest_hex(a)
	assert_eq(d.length(), 16, "digest is 16 characters")
	assert_eq(d, Hash.hex64(Hash.fnv1a64(a)), "digest_hex is hex64 of fnv1a64")
	var b := PackedInt64Array([10, 1, 0, 0, 0, 0, 0, 1])
	assert_ne(Hash.digest_hex(b), d, "one changed int changes the digest")
	assert_eq(Hash.digest_hex(PackedInt64Array()), "cbf29ce484222325", "empty digest = offset basis")
	var ok := true
	for c: String in d:
		if not "0123456789abcdef".contains(c):
			ok = false
	assert_true(ok, "digest uses lowercase hex only")
