extends "res://tests/testing.gd"
## core/data.gd (GameData): every table loads as integers only, TYPES keeps the page order (the cross-device
## contract), datasheets read right, base radii become milli-inches, pools and factions line up, the hidden
## units stay opaque and outside the bot pools, constants come through as ints, every datasheet carries the page's
## INF(k) as `inf`, and the committed data still hashes to Version.DATA_HASH.

## The page's own INF(k) for a sample of types, read on the page with Playwright (an instrumented copy of
## battle-table.html that calls the real function; it also agreed with BT.kitInfo + veh for all 274): foot soldiers,
## kits of scale 1.3, 1.4 and 1.45 (still below 1.5), mounts, creatures (one of scale 0.85), a vehicle, a scale 2.2
## kit and a kit of exactly scale 1.5 (the page's test is `kitScale(k) < 1.5`).
const INF_SAMPLE := {
	"heavy": true, "hoplite": true, "archer": true, "sniper": true, "medic": true,
	"sobek": true, "boss": true, "ogwar": true,
	"cavalry": false, "obike": false, "rscarab": false, "dmh": false, "ballista": false, "mech": false, "mino": false,
}
## The first 274 datasheets (the page at export time; later ones may only be appended): INF counts and the FNV-1a 64
## digest of their inf bits in TYPES order, computed from the same page sample.
const INF_FIRST := 274
const INF_FOOT := 166
const INF_DIGEST := "c4e6a1c3a50f6d45"


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


func test_inf_matches_the_page() -> void:
	var bad := []
	for k: String in INF_SAMPLE:
		assert_true(GameData.index_of(k) >= 0, "sample type %s exists" % k)
		if GameData.is_inf(k) != bool(INF_SAMPLE[k]):
			bad.append(k)
	assert_eq(bad, [], "is_inf equals the page's INF(k) for every sampled type")
	assert_true(GameData.is_inf("hoplite"), "a hoplite is a foot soldier")
	assert_false(GameData.is_inf("cavalry"), "a mounted squad is not (beast rule)")
	assert_false(GameData.is_inf("ballista"), "a vehicle is not")
	assert_false(GameData.is_inf("mech"), "a big kit is not")
	assert_true(GameData.is_inf("ogwar"), "kit scale 1.45 is still below 1.5: foot soldier")
	assert_false(GameData.is_inf("mino"), "kit scale exactly 1.5 is not below 1.5: not a foot soldier")
	assert_false(GameData.is_inf("dmh"), "a small creature is still a beast: not a foot soldier")
	assert_false(GameData.is_inf("no-such-unit"), "an unknown key is not a foot soldier")


func test_inf_set_is_pinned() -> void:
	assert_true(GameData.count() >= INF_FIRST, "the first %d datasheets are there" % INF_FIRST)
	var bits := PackedInt64Array()
	var foot := 0
	for i: int in INF_FIRST:
		var on := GameData.is_inf(GameData.key_at(i))
		bits.append(1 if on else 0)
		foot += 1 if on else 0
	assert_eq([foot, INF_FIRST - foot], [INF_FOOT, INF_FIRST - INF_FOOT], "166 foot soldiers, 108 not (R1 spec §7 #15)")
	assert_digest(Hash.digest_hex(bits), INF_DIGEST, "the inf bits of the first 274 datasheets equal the page's INF")


func test_every_datasheet_carries_inf() -> void:
	var raw: Array = _raw("types.json")
	var missing := []
	var differ := []
	var vehicles := 0
	for e: Dictionary in raw:
		var k := str(e["k"])
		if not e.has("inf") or (e["inf"] != 0 and e["inf"] != 1):
			missing.append(k)
		elif GameData.is_inf(k) != (e["inf"] == 1):
			differ.append(k)
		if e.has("veh"):
			vehicles += 1
			if GameData.is_inf(k):
				differ.append(k + " (vehicle)")
	assert_eq(missing, [], "every datasheet in types.json has inf 0 or 1")
	assert_eq(differ, [], "is_inf reads the inf field, and no vehicle is a foot soldier")
	assert_true(vehicles > 0, "the vehicle check saw %d vehicles" % vehicles)
	var not_int := []
	for t: Dictionary in GameData.types():
		if typeof(t.get("inf")) != TYPE_INT:
			not_int.append(t["k"])
	assert_eq(not_int, [], "inf loads as an int for every datasheet")
	var bt: Dictionary = _raw("bt_data.json")
	var bt_types: Array = bt["types"]
	assert_eq(bt_types.size(), raw.size(), "bt_data.json has every datasheet")
	var stale := []
	for i: int in mini(raw.size(), bt_types.size()):
		if (bt_types[i] as Dictionary).get("inf", -1) != (raw[i] as Dictionary).get("inf", -2):
			stale.append(raw[i]["k"])
	assert_eq(stale, [], "bt_data.json carries the same inf (gen_bt_data.py --snapshot was re-run)")


func test_inf_problem() -> void:
	assert_eq(GameData.inf_problem("x", {"inf": 1}), "", "inf 1 is fine")
	assert_eq(GameData.inf_problem("x", {"inf": 0}), "", "inf 0 is fine")
	assert_ne(GameData.inf_problem("x", {}), "", "a missing inf is a problem")
	assert_ne(GameData.inf_problem("x", {"inf": 2}), "", "inf 2 is a problem")
	assert_ne(GameData.inf_problem("x", {"inf": -1}), "", "inf -1 is a problem")
	assert_ne(GameData.inf_problem("x", {"inf": true}), "", "a bool inf is a problem (the data says 1/0)")
	assert_ne(GameData.inf_problem("x", {"inf": "1"}), "", "a string inf is a problem")
	assert_true(GameData.inf_problem("sample9", {}).contains("sample9"), "the problem names the type")


func test_new_rules_constants() -> void:
	assert_eq(GameData.const_int("GREN_R", -1), 8, "grenade range 8 (page var GREN_R)")
	assert_eq(GameData.const_int("HEAL_ON", -1), 3, "heal succeeds on 3+ (page var HEAL_ON)")
	assert_eq(GameData.const_int("PAIN_ROUND", -1), 3, "dark-elf pain from round 3 (page var PAIN_ROUND)")
	var raw: Dictionary = _raw("constants.json")
	for name: String in ["GREN_R", "HEAL_ON", "PAIN_ROUND"]:
		assert_true(raw.has(name), "constants.json has " + name)
	var full := {}
	var unset := []
	for name: String in GameData.RULES_CONSTS:
		full[name] = GameData.const_int(name, -1)
		if full[name] == -1:
			unset.append(name)
	assert_eq(unset, [], "every rules constant is in constants.json as a whole number")
	assert_eq(GameData.const_problems(full), PackedStringArray(), "a full table has no problem")
	var short := full.duplicate()
	short.erase("GREN_R")
	var p := GameData.const_problems(short)
	assert_eq(p.size(), 1, "a missing rules constant is one problem")
	assert_true(p.size() == 1 and p[0].contains("GREN_R"), "the problem names it", p)
	var wrong := full.duplicate()
	wrong["HEAL_ON"] = "3"
	assert_eq(GameData.const_problems(wrong).size(), 1, "a rules constant that is not an int is a problem")


## Drift: the committed data/*.json still hashes to Version.DATA_HASH and data/version.json (validate_data.py
## computes the same: sha256 over every data/*.json except version.json, in sorted file-name order).
func test_data_files_match_the_version_hash() -> void:
	var names := PackedStringArray()
	for f: String in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json") and f != "version.json":
			names.append(f)
	names.sort()
	assert_true(names.has("types.json") and names.has("constants.json"), "the data folder lists %d tables" % names.size())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for f: String in names:
		ctx.update(FileAccess.get_file_as_bytes("res://data/" + f))
	var got := ctx.finish().hex_encode()
	assert_eq(got, Version.DATA_HASH, "sha256 of data/*.json equals Version.DATA_HASH (run validate_data.py --write-version)")
	var v: Dictionary = _raw("version.json")
	assert_eq(str(v.get("data_hash", "")), Version.DATA_HASH, "data/version.json agrees with Version.DATA_HASH")
