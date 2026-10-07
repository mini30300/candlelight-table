extends "res://tests/testing.gd"
## core/data.gd (GameData): every table loads as integers only, TYPES keeps the page order (the cross-device
## contract), datasheets read right, base radii become milli-inches, pools and factions line up, the hidden
## units stay opaque and outside the bot pools, constants come through as ints.


func setup() -> void:
	GameData.load_all(true)


func _raw(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))


func _no_fractions(v: Variant) -> bool:
	match typeof(v):
		TYPE_FLOAT:
			return false
		TYPE_ARRAY:
			for x: Variant in v:
				if not _no_fractions(x):
					return false
		TYPE_DICTIONARY:
			for k: Variant in v:
				if not _no_fractions(v[k]):
					return false
	return true


func test_loads_clean() -> void:
	assert_eq(GameData.problems(), PackedStringArray(), "the data loads without problems")
	assert_eq(GameData.count(), (_raw("types.json") as Array).size(), "every datasheet is loaded")
	assert_true(GameData.count() >= 274, "at least 274 datasheets: %d" % GameData.count())


func test_order_is_the_page_order() -> void:
	var raw: Array = _raw("types.json")
	var bad := []
	for i: int in raw.size():
		var k := str(raw[i]["k"])
		if GameData.key_at(i) != k or GameData.index_of(k) != i:
			bad.append(k)
	assert_eq(bad, [], "key_at / index_of follow types.json order exactly")
	assert_eq(GameData.index_of("no-such-unit"), -1, "an unknown key has no index")
	assert_eq(GameData.ty("no-such-unit"), {}, "an unknown key has no datasheet")


func test_everything_is_an_integer() -> void:
	var bad := []
	for t: Dictionary in GameData.types():
		if not _no_fractions(t):
			bad.append(t["k"])
	assert_eq(bad, [], "no datasheet holds a fractional number after loading")


func test_a_datasheet_reads_right() -> void:
	var h := GameData.ty("hoplite")
	assert_eq([h["n"], h["pts"], h["mv"], h["T"], h["sv"], h["w"], h["ld"], h["oc"]], [5, 65, 6, 3, 4, 1, 7, 2],
		"hoplite: models, points, move, toughness, save, wounds, leadership, objective control")
	assert_eq(h["gun"], null, "hoplite has no ranged weapon (must charge)")
	var m: Dictionary = h["mel"]
	assert_eq([m["a"], m["ws"], m["s"], m["ap"], m["d"]], [2, 3, 4, 0, 1], "hoplite spear: A, WS, S, AP, D")
	assert_eq(typeof(h["pts"]), TYPE_INT, "points are ints")
	assert_eq(GameData.fac_of("hoplite"), "gr", "hoplite belongs to the Greek army")


func test_base_radius_in_milli_inches() -> void:
	assert_eq(GameData.base_r_mi("hoplite"), GameData.BASE_R_MI, "no r: the default base radius (800 MI)")
	assert_eq(GameData.base_r_mi("cavalry"), 1100, "cavalry r 1.1 in -> 1100 MI")
	assert_eq(GameData.base_r_mi("mech"), 1500, "mech r 1.5 in -> 1500 MI")
	assert_eq(GameData.base_r_mi("rscarab"), 900, "r 0.9 in -> 900 MI")
	assert_false(GameData.ty("cavalry").has("r"), "the fractional r is not kept next to r_mi")
	var raw: Array = _raw("types.json")
	var bad := []
	for e: Dictionary in raw:
		if e.has("r"):
			# the decimal text of r, read as milli-inches without any arithmetic on fractions
			var txt := str(e["r"])
			var want := int(txt.get_slice(".", 0)) * 1000
			if txt.contains("."):
				want += int(txt.get_slice(".", 1).rpad(3, "0").left(3))
			if GameData.base_r_mi(str(e["k"])) != want:
				bad.append("%s %s -> %d" % [e["k"], e["r"], GameData.base_r_mi(str(e["k"]))])
	assert_eq(bad, [], "every base radius equals its decimal text in MI")
	assert_eq(GameData.to_mi(1.4), 1400, "1.4 in -> 1400 MI (no truncation below)")
	assert_eq(GameData.to_mi(-0.9), -900, "negative lengths round the same way")


func test_factions_and_pools() -> void:
	var facs := GameData.factions()
	assert_eq(facs.size(), 15, "15 armies")
	assert_false(GameData.faction("gr").is_empty(), "the Greek army has an entry")
	var bad_fac := []
	for t: Dictionary in GameData.types():
		if str(t["fac"]) != "*" and not facs.has(str(t["fac"])):
			bad_fac.append(t["k"])
	assert_eq(bad_fac, [], "every datasheet's army is one of the 15 (or '*')")
	var bad_pool := []
	for fac: String in facs:
		for k: String in GameData.pool(fac):
			if GameData.index_of(k) < 0 or GameData.is_hidden(k):
				bad_pool.append(fac + ":" + k)
	assert_eq(bad_pool, [], "bot pools hold only known, non-hidden units")
	assert_true(GameData.pool("gr").has("hoplite"), "the Greek pool has hoplites")


func test_hidden_units_stay_opaque() -> void:
	var hidden := 0
	for t: Dictionary in GameData.types():
		if GameData.is_hidden(str(t["k"])):
			hidden += 1
	assert_eq(hidden, 2, "two hidden datasheets, flagged only")


func test_constants() -> void:
	assert_eq(GameData.const_int("CHARGE_R"), 12, "charge range 12")
	assert_eq(GameData.const_int("AURA_R"), 6, "aura range 6")
	assert_eq(GameData.const_int("OBJ_R"), 3, "objective radius 3")
	assert_eq(GameData.const_int("SPEC_TOTAL"), 3000, "spectator total 3000")
	assert_eq(GameData.const_int("PROP_CAP"), 480, "prop cap 480")
	assert_eq([GameData.const_int("VP_PER"), GameData.const_int("VP_CAP")], [5, 15], "VP per objective 5, cap 15")
	assert_eq(GameData.const_int("FLY_A", -1), -1, "a fractional constant (visual) is not exposed to the rules")
	assert_eq(GameData.page_rules_v(), 9, "the data came from the v9 page")
	assert_eq(Version.RULES_V, 10, "the new app plays rules v10 (rooms separate from v9)")


func test_reload_is_identical() -> void:
	var a := Hash.fnv1a64_str(JSON.stringify(GameData.types(), "", false))
	GameData.load_all(true)
	var b := Hash.fnv1a64_str(JSON.stringify(GameData.types(), "", false))
	assert_eq(a, b, "loading twice gives the same tables")
