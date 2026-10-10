extends "res://tests/testing.gd"
## net/json_num.gd (JsonNum): numbers on the wire of the room protocol (ARCHITECTURE §5, R1_PORT_SPEC §2 wire points,
## §4 act codec). Godot's JSON parser gives every number as a float; JsonNum turns them into the ints core wants
## (points as MI, exact from 0.01" hundredths), rejects non-integral and out-of-range numbers with a message, keeps
## strings, and writes JSON with ints and decimals made from ints (never a float).
## Page samples: fixtures/json_num/page_samples.json (tools/record_json_num.js): the page's own JSON text of act points
## (+(mi/1000).toFixed(2)), of netSend bodies for acts it really sent (oracle recordings) and of curSetup(); the Worker's
## btSetup / btList / btSkins / dep clamp answers. Worker act samples: fixtures/acts/worker_samples.json (shared with
## test_acts.gd): the Worker's btPost answer must read back as the core form test_acts expects.

const FIX := "res://tests/unit/fixtures/json_num/page_samples.json"
const ACT_FIX := "res://tests/unit/fixtures/acts/worker_samples.json"
const BOARD_FIX := "res://tests/unit/fixtures/board/page_samples.json"
## FNV-1a 64 of every output of the page and Worker samples (core forms, written texts) in order; changes only on purpose.
const PINNED_DIGEST := "7d3bfeb4bedd8f86"
var F: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		F = p


# ---------------------------------------------------------------- helpers
func _errs() -> Array[String]:
	var e: Array[String] = []
	return e


## only int, bool, String, null, Array and Dictionary with String keys (the core form; no float anywhere)
func _clean(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_NIL:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not _clean(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not _clean(v[k]):
					return false
			return true
	return false


## typed equality: 5 (int) is not 5.0 (float); key order included for dictionaries
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_ARRAY:
			var x: Array = a
			var y: Array = b
			if x.size() != y.size():
				return false
			for i: int in x.size():
				if not _same(x[i], y[i]):
					return false
			return true
		TYPE_DICTIONARY:
			var x: Dictionary = a
			var y: Dictionary = b
			if x.keys() != y.keys():
				return false
			for k: Variant in x:
				if not _same(x[k], y[k]):
					return false
			return true
	return a == b


## a fixture value (parsed JSON, floats) in the core form: whole numbers as ints (test-side only)
func _iv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if f == floorf(f) else f
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_iv(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _iv(v[k])
			return d
	return v


func _parse(text: String) -> Variant:
	var e := _errs()
	var v: Variant = JsonNum.parse(text, e)
	assert_true(e.is_empty(), "fixture text parses", [text.left(80), e])
	return v


# ---------------------------------------------------------------- single numbers
func test_int_of() -> void:
	var e := _errs()
	assert_eq(JsonNum.int_of(5.0, 0, 9, "a", e), 5, "5.0 -> 5")
	assert_eq(typeof(JsonNum.int_of(5.0, 0, 9, "a", e)), TYPE_INT, "result is an int")
	assert_eq(JsonNum.int_of(7, 0, 9, "a", e), 7, "an int passes")
	assert_eq(JsonNum.int_of(-0.0, -1, 1, "a", e), 0, "-0 -> 0")
	assert_eq(JsonNum.int_of(-3.0, -9, 9, "a", e), -3, "negative whole number")
	assert_eq(JsonNum.int_of(JSON.parse_string("9007199254740991"), 0, JsonNum.SAFE, "a", e), JsonNum.SAFE, "2^53 - 1 passes")
	assert_true(e.is_empty(), "no errors so far", e)
	var cases := [[2.5, "not a whole number"], [10.0, "out of range"], [-1.0, "out of range"], ["5", "not a number"],
		[null, "not a number"], [true, "not a number"], [[1], "not a number"], [INF, "not a finite number"],
		[NAN, "not a finite number"], [1.0e300, "out of range"], [0.0000001, "not a whole number"], [11, "out of range"]]
	for c: Array in cases:
		var ce := _errs()
		var got := JsonNum.int_of(c[0], 0, 9, "f.x", ce)
		assert_true(got == 0 and ce.size() == 1 and ce[0].begins_with("f.x: " + str(c[1])),
			"int_of(%s) is refused: %s" % [str(c[0]), c[1]], ce)
	var big := _errs()
	JsonNum.int_of(JSON.parse_string("9007199254740992"), 0, 9223372036854775807, "big", big)
	assert_eq(big.size(), 1, "2^53 is beyond the exact doubles, refused")
	var parsed: Variant = JSON.parse_string("[1e400, -1e400]")
	var pe := _errs()
	JsonNum.int_of(parsed[0], -9, 9, "p", pe)
	JsonNum.int_of(parsed[1], -9, 9, "p", pe)
	assert_eq(pe.size(), 2, "JSON 1e400 (inf) is refused, not clamped")


func test_scaled() -> void:
	var e := _errs()
	assert_eq(JsonNum.scaled(12.34, 2, -999900, 999900, "x", e), 1234, "12.34 -> 1234 hundredths")
	assert_eq(JsonNum.scaled(-0.05, 2, -999900, 999900, "x", e), -5, "-0.05 -> -5")
	assert_eq(JsonNum.scaled(-9999.0, 2, -999900, 999900, "x", e), -999900, "the Worker cap -9999 passes")
	assert_eq(JsonNum.scaled(9999.99, 2, -999999, 999999, "x", e), 999999, "9999.99 exact")
	assert_eq(JsonNum.scaled(0.1 + 0.2, 2, -100, 100, "x", e), 30, "0.1 + 0.2 is 0.30 within the float noise")
	assert_eq(JsonNum.scaled(3, 2, -1000, 1000, "x", e), 300, "an int scales too")
	assert_eq(JsonNum.scaled(12.3, 1, -2000, 2000, "x", e), 123, "tenths")
	assert_eq(JsonNum.scaled(1.25, 2, 5, 250, "density", e), 125, "density 1.25 -> 125")
	assert_eq(JsonNum.scaled(0.05, 2, 5, 250, "density", e), 5, "density 0.05 -> 5")
	assert_true(e.is_empty(), "no errors so far", e)
	for c: Array in [[12.345, "more than 2 decimals"], [-3.333, "more than 2 decimals"], [-0.004, "more than 2 decimals"],
			[10000.0, "out of range"], [9999.01, "out of range"], ["1.5", "not a number"], [false, "not a number"],
			[12.3400001, "more than 2 decimals"]]:
		var ce := _errs()
		var got := JsonNum.scaled(c[0], 2, -999900, 999900, "p", ce)
		assert_true(got == 0 and ce.size() == 1 and ce[0].begins_with("p: " + str(c[1])),
			"scaled(%s, 2) is refused: %s" % [str(c[0]), c[1]], ce)
	var ie := _errs()
	JsonNum.scaled(JsonNum.SAFE + 1, 2, -JsonNum.SAFE, JsonNum.SAFE, "i", ie)
	JsonNum.scaled(5, 4, -JsonNum.SAFE, JsonNum.SAFE, "i", ie)
	assert_eq(ie.size(), 2, "int beyond 2^53 or more than 3 places is refused (no int64 overflow)")


func test_bit_of() -> void:
	var e := _errs()
	assert_eq(JsonNum.bit_of(true, "b", e), 1, "true -> 1")
	assert_eq(JsonNum.bit_of(false, "b", e), 0, "false -> 0")
	assert_eq(JsonNum.bit_of(1.0, "b", e), 1, "1.0 -> 1")
	assert_eq(JsonNum.bit_of(0.0, "b", e), 0, "0.0 -> 0")
	assert_true(e.is_empty(), "no errors", e)
	for v: Variant in [2.0, 0.5, "1", null, -1.0]:
		var ce := _errs()
		JsonNum.bit_of(v, "b", ce)
		assert_eq(ce.size(), 1, "bit_of(%s) refused" % str(v))


func test_intify() -> void:
	var e := _errs()
	var v: Variant = JsonNum.intify(_j("{\"a\":[1,2,{\"b\":-3}],\"s\":\"7\",\"n\":null,\"t\":true}"), "$", e)
	assert_true(e.is_empty(), "intify: no errors", e)
	assert_true(_same(v, {"a": [1, 2, {"b": -3}], "s": "7", "n": null, "t": true}), "intify: ints, string kept, null and bool kept", v)
	var be := _errs()
	JsonNum.intify(_j("{\"a\":[1,2.5],\"b\":{\"c\":0.1}}"), "$", be)
	assert_eq(be.size(), 2, "intify: each fraction is one error")
	assert_true(be.size() == 2 and be[0].begins_with("$.a[1]: not a whole number") and be[1].begins_with("$.b.c:"),
		"intify: the errors name the path", be)


func _j(text: String) -> Variant:
	return JSON.parse_string(text)


## every hundredth up to the Worker's ±9999.99" (stride 7, plus the ends), parsed by Godot's JSON, reads back exactly
func test_hundredths_sweep() -> void:
	var hs := PackedInt64Array()
	var h := -999999
	while h <= 999999:
		hs.append(h)
		h += 7
	hs.append(999999)
	hs.append(-1)
	hs.append(1)
	var parts := PackedStringArray()
	for x: int in hs:
		parts.append(JsonNum.dec_text(x, 2))
	var arr: Array = JSON.parse_string("[" + ",".join(parts) + "]")
	var bad: Array = []
	for i: int in hs.size():
		var e := _errs()
		var got := JsonNum.scaled(arr[i], 2, -999999, 999999, "h", e)
		if (got != hs[i] or not e.is_empty()) and bad.size() < 5:
			bad.append([hs[i], parts[i], got, e])
	assert_true(bad.is_empty(), "%d hundredths read back exactly" % hs.size(), bad)


# ---------------------------------------------------------------- writing
func test_dec_text() -> void:
	var cases := [[1234, 2, "12.34"], [1200, 2, "12"], [1230, 2, "12.3"], [-5, 2, "-0.05"], [0, 2, "0"], [-1200, 2, "-12"],
		[5, 2, "0.05"], [999900, 2, "9999"], [-999999, 2, "-9999.99"], [7, 0, "7"], [-7, 0, "-7"], [12345, 3, "12.345"],
		[10, 3, "0.01"], [-123, 1, "-12.3"], [100, 2, "1"]]
	for c: Array in cases:
		assert_eq(JsonNum.dec_text(c[0], c[1]), c[2], "dec_text(%d, %d)" % [c[0], c[1]])


func test_stringify() -> void:
	var e := _errs()
	var s := JsonNum.stringify({"a": 12, "b": [1, -2, true, null], "c": "x", "d": JsonNum.dec(1234, 2),
		"e": PackedInt32Array([3, 4]), "f": PackedInt64Array([-5]), "g": {}, "h": [], "i": PackedStringArray(["p", "q"])}, e)
	assert_true(e.is_empty(), "stringify: no errors", e)
	assert_eq(s, "{\"a\":12,\"b\":[1,-2,true,null],\"c\":\"x\",\"d\":12.34,\"e\":[3,4],\"f\":[-5],\"g\":{},\"h\":[],\"i\":[\"p\",\"q\"]}",
		"stringify: ints without a decimal point, decimals from ints, insertion order")
	for bad: Variant in [{"x": 1.0}, [0.5], {"y": [JsonNum.dec(1, 2), 2.0]}, {1: 2}, {"z": JsonNum.SAFE + 1}, {"o": Node},
			{"v": Vector2i(1, 2)}, {"d": JsonNum.dec(1, 16)}]:
		var be := _errs()
		var out := JsonNum.stringify(bad, be)
		assert_true(out == "" and be.size() >= 1, "stringify refuses %s" % str(bad), be)
	var fe := _errs()
	JsonNum.stringify({"x": 12.0}, fe)
	assert_true(fe.size() == 1 and fe[0].begins_with("$.x: float on the wire"), "a float names its path", fe)


## JSON.stringify of awkward strings on the page (fixtures/board, sampled by record_board_acts.js)
func test_quote_page_strings() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOARD_FIX))
	assert_eq(typeof(p), TYPE_DICTIONARY, "board fixture loads")
	if typeof(p) != TYPE_DICTIONARY:
		return
	var strs: Array = p["strings"]
	assert_true(strs.size() >= 10, "string samples present")
	for pair: Array in strs:
		assert_eq(JsonNum.quote(str(pair[0])), str(pair[1]), "quote = JSON.stringify for %s" % JSON.stringify(pair[0]))


# ---------------------------------------------------------------- page samples
func test_fixture_shape() -> void:
	for k: String in ["page", "worker", "points", "points_extra", "bodies", "setups", "worker_setups", "worker_lists", "worker_deps"]:
		assert_true(F.has(k), "fixture has " + k)
	if F.has("page"):
		assert_eq(int(F["page"]["rules_v"]), 9, "sampled from the rules-9 page")
	if F.has("worker"):
		assert_eq(int(F["worker"]["list_len"]), JsonNum.LIST_LEN, "LIST_LEN = the Worker's BT_LIST_LEN")
		assert_eq(int(F["worker"]["slot_max"]), JsonNum.SLOT_MAX, "SLOT_MAX = the Worker's BT_SLOT_MAX")


## every point the page writes: dec_text(hundredths(mi)) is the page's text, and the text reads back to 10 * hundredths
func test_points_page() -> void:
	if not F.has("points"):
		return
	var pf: Dictionary = F["points"]
	var from := int(pf["from"])
	var texts := str(pf["text"]).split(",")
	var pairs: Array = []
	for i: int in texts.size():
		pairs.append([from + i, texts[i]])
	for x: Variant in F["points_extra"]:
		pairs.append([int(x[0]), str(x[1])])
	assert_true(pairs.size() > 5000, "point samples present", pairs.size())
	var bad_w: Array = []
	var bad_r: Array = []
	for pr: Array in pairs:
		var mi: int = pr[0]
		var h := BtActs.hundredths(mi)
		if JsonNum.dec_text(h, 2) != pr[1] and bad_w.size() < 5:
			bad_w.append([mi, pr[1], JsonNum.dec_text(h, 2)])
		var e := _errs()
		var back := 10 * JsonNum.scaled(JSON.parse_string(pr[1]), 2, -JsonNum.PT_MAX, JsonNum.PT_MAX, "p", e)
		if (not e.is_empty() or back != 10 * h) and bad_r.size() < 5:
			bad_r.append([mi, pr[1], back, e])
	assert_true(bad_w.is_empty(), "%d page point texts written byte-equal" % pairs.size(), bad_w)
	assert_true(bad_r.is_empty(), "%d page point texts read back to MI exactly" % pairs.size(), bad_r)


## netSend bodies for acts the page sent: read -> core form -> written again is the page's text byte for byte
func test_bodies_page() -> void:
	if not F.has("bodies"):
		return
	var bodies: Array = F["bodies"]
	var codes := {}
	var bad: Array = []
	for b: Dictionary in bodies:
		var text := str(b["text"])
		var body: Dictionary = _parse(text)
		var e := _errs()
		var core := JsonNum.act_from_wire(body["act"], e)
		if not e.is_empty() or core.is_empty() or not _clean(core):
			bad.append(["read", text, e])
			continue
		codes[core["a"]] = true
		var we := _errs()
		var out := JsonNum.act_body(str(b["pid"]), core, we)
		if out != text:
			bad.append(["write", text, out, we])
		if BtActs.sanitize(core).is_empty():
			bad.append(["sanitize", text])
		# points on the 10 MI grid (the page's toFixed(2))
		for q: Variant in core.get("to", []):
			if int(q[0]) % 10 != 0 or int(q[1]) % 10 != 0:
				bad.append(["grid", text])
	assert_true(bodies.size() >= 60, "body samples present", bodies.size())
	assert_eq(codes.size(), 19, "bodies cover all 19 codes the page sends")
	assert_true(bad.is_empty(), "%d page act bodies round-trip byte-equal" % bodies.size(), bad.slice(0, 3))


## curSetup() of the page: read into BattleState.make's form, written back as the page wrote it (v = this app's RULES_V)
func test_setups_page() -> void:
	if not F.has("setups"):
		return
	var dens := []
	for s: Dictionary in F["setups"]:
		var text := str(s["text"])
		var e := _errs()
		var core := JsonNum.setup_from_wire(_parse(text), "setup", e)
		assert_true(e.is_empty() and _clean(core), "page setup reads: " + text.left(60), e)
		assert_false(core.has("density"), "density becomes density_h")
		dens.append(core.get("density_h"))
		var st := BattleState.make(core)
		assert_eq(st.density_h, int(core["density_h"]), "BattleState takes density_h")
		assert_eq(st.buildings, bool(core["buildings"]), "BattleState takes buildings")
		var we := _errs()
		var out := JsonNum.stringify(JsonNum.setup_to_wire(core), we)
		assert_eq(out, text.replace("\"v\":9}", "\"v\":%d}" % Version.RULES_V), "setup written as curSetup() (v = RULES_V)")
	assert_true(_same(dens, [100, 5, 35, 250, 125, 95]), "page densities (quantised) as hundredths", dens)


## the room setup the Worker stores (btSetup), for posted setups from tidy to hostile: every one reads without error
func test_worker_setups() -> void:
	if not F.has("worker_setups"):
		return
	for c: Dictionary in F["worker_setups"]:
		var raw: Dictionary = _parse(str(c["out"]))
		var e := _errs()
		var core := JsonNum.setup_from_wire(raw, "setup", e)
		assert_true(e.is_empty() and _clean(core), "Worker setup reads: " + str(c["in"]).left(60), e)
		var keys: Array = raw.keys()
		keys[keys.find("density")] = "density_h"
		assert_eq(core.keys(), keys, "key order kept (density -> density_h)")
		assert_eq(int(core["density_h"]), roundi(float(raw["density"]) * 100.0), "density_h = density x 100")
		var st := BattleState.make(core)
		assert_true(st.w == int(raw["w"]) and st.d == int(raw["d"]) and st.seed == int(raw["seed"]) and st.teams == int(raw["teams"]),
			"BattleState.make reads w, d, seed, teams")
	var bad := [["{\"w\":48.5}", "setup.w: not a whole number"], ["{\"w\":200}", "setup.w: out of range"],
		["{\"density\":0.333}", "setup.density: more than 2 decimals"], ["{\"density\":3}", "setup.density: out of range"],
		["{\"seed\":0}", "setup.seed: out of range"], ["{\"theme\":3}", "setup.theme: not a string"],
		["{\"buildings\":2}", "setup.buildings: out of range"], ["{\"budget\":-1}", "setup.budget: out of range"],
		["{\"extra\":1.5}", "setup.extra: not a whole number"]]
	for b: Array in bad:
		var e := _errs()
		JsonNum.setup_from_wire(JSON.parse_string(b[0]), "setup", e)
		assert_true(e.size() == 1 and e[0].begins_with(b[1]), "setup %s refused: %s" % [b[0], b[1]], e)
	var ne := _errs()
	assert_true(JsonNum.setup_from_wire([1], "setup", ne).is_empty() and ne.size() == 1, "a non-object setup is refused")


## /list as the Worker stores it (btList, btSkins) through the room's list act
func test_worker_lists() -> void:
	if not F.has("worker_lists"):
		return
	for c: Dictionary in F["worker_lists"]:
		var stored: Dictionary = _parse(str(c["out"]))
		var raw := {"seq": 3.0, "ts": 1760000000000.0, "pid": "b1", "a": "list", "list": stored["list"], "sk": stored["sk"]}
		var e := _errs()
		var act := JsonNum.room_act(raw, e)
		assert_true(e.is_empty() and _clean(act), "Worker list reads: " + str(c["in"]).left(50), e)
		assert_true(_same(act.get("list"), _iv(stored["list"])), "list as ints")
		assert_true(_same(act.get("sk"), _iv(stored["sk"])), "skins as ints")
		assert_eq(act.get("ts"), 1760000000000, "ts (Date.now) as an int")
		assert_eq(BtArmy.fit_list(act["list"]).size(), GameData.count(), "BtArmy.fit_list takes the list")
	var cases := [["[1,2.5]", "l[1]: not a whole number"], ["[100]", "l[0]: out of range"], ["[-1]", "l[0]: out of range"],
		["[\"3\"]", "l[0]: not a number"], ["{}", "l: not an array"]]
	for c: Array in cases:
		var e := _errs()
		JsonNum.list_from_wire(JSON.parse_string(c[0]), "l", e)
		assert_true(e.size() == 1 and e[0].begins_with(c[1]), "list %s refused: %s" % [c[0], c[1]], e)
	var long: Array = []
	long.resize(JsonNum.LIST_LEN + 1)
	long.fill(0.0)
	var le := _errs()
	assert_true(JsonNum.list_from_wire(long, "l", le).is_empty() and le.size() == 1, "513 slots refused")
	var se := _errs()
	JsonNum.skin_from_wire(JSON.parse_string("{\"loki\":1.5,\"x\":0}"), "sk", se)
	assert_eq(se.size(), 2, "skin 1.5 and 0 refused")


## /dep as the Worker stores it: hundredths read exactly; the Worker keeps finer numbers, those are refused
func test_worker_deps() -> void:
	if not F.has("worker_deps"):
		return
	var want := [[12340, -5500], [-200000, 200000], [200000, -200000], [], [], [0, 0], null]
	var deps: Array = F["worker_deps"]
	for i: int in deps.size():
		var e := _errs()
		var got := JsonNum.dep_from_wire(JSON.parse_string(str(deps[i]["out"])), JsonNum.DEP_MAX, "dep", e)
		if want[i] == null:
			assert_true(e.size() == 1 and e[0].begins_with("dep[0]: more than 2 decimals"), "dep %s refused" % deps[i]["out"], e)
		else:
			assert_true(e.is_empty() and _same(got, want[i]), "dep %s -> %s" % [deps[i]["out"], str(want[i])], [got, e])
	for bad: String in ["[1]", "[1,2,3]", "\"x\"", "[200.01,0]", "[0,true]"]:
		var e := _errs()
		JsonNum.dep_from_wire(JSON.parse_string(bad), JsonNum.DEP_MAX, "dep", e)
		assert_eq(e.size(), 1, "dep %s refused" % bad)
	var w := _errs()
	assert_eq(JsonNum.stringify(JsonNum.dep_to_wire(PackedInt64Array([12340, -5500])), w), "[12.34,-5.5]", "dep written in inches")
	assert_eq(JsonNum.stringify(JsonNum.dep_to_wire(PackedInt64Array([12346, -5])), w), "[12.35,-0.01]", "dep off the grid: toFixed(2)")
	assert_eq(JsonNum.stringify(JsonNum.dep_to_wire([]), w), "null", "no dep -> null")
	assert_true(w.is_empty(), "dep writes without errors", w)


## the Worker's btPost answers (fixtures/acts, the room act every device reads) give the core form test_acts uses
func test_worker_acts() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACT_FIX))
	assert_eq(typeof(p), TYPE_DICTIONARY, "act fixture loads")
	if typeof(p) != TYPE_DICTIONARY:
		return
	var n := 0
	var refused: Array = []
	var bad: Array = []
	for c: Dictionary in p["cases"]:
		if c["out"] == null:
			continue
		n += 1
		var room := {"seq": 9.0, "ts": 1.0, "pid": "b7"}
		room.merge(c["out"])
		var e := _errs()
		var got := JsonNum.room_act(room, e)
		if not e.is_empty():
			refused.append(str(c["name"]))
			continue
		var want: Dictionary = _iv(c["want"])
		want.erase("pid")
		got.erase("seq")
		got.erase("ts")
		got.erase("pid")
		if not _same(got, want) or not _clean(got):
			bad.append([c["name"], got, want])
	assert_true(n > 120, "Worker answers present", n)
	assert_true(bad.is_empty(), "%d Worker answers read as the core form (key order kept)" % (n - refused.size()), bad.slice(0, 3))
	# the Worker clamps but never rounds points: a client posting 3 decimals makes a room act every device refuses alike
	assert_eq(refused, ["coords clamp", "smove to object", "points odd shapes"], "only the >2-decimal point answers are refused")


# ---------------------------------------------------------------- room acts and room state
func test_room_acts() -> void:
	var good := {
		"{\"seq\":1,\"ts\":5,\"pid\":\"b1\",\"a\":\"join\",\"nm\":\"ไทย\",\"team\":1}": {"seq": 1, "ts": 5, "pid": "b1", "a": "join", "nm": "ไทย", "team": 1},
		"{\"seq\":2,\"ts\":5,\"pid\":\"b1\",\"a\":\"leave\"}": {"seq": 2, "ts": 5, "pid": "b1", "a": "leave"},
		"{\"seq\":3,\"ts\":5,\"pid\":\"b1\",\"a\":\"team\",\"team\":7}": {"seq": 3, "ts": 5, "pid": "b1", "a": "team", "team": 7},
		"{\"seq\":4,\"ts\":5,\"pid\":\"b1\",\"a\":\"dep\",\"dep\":[-12.5,3.07]}": {"seq": 4, "ts": 5, "pid": "b1", "a": "dep", "dep": [-12500, 3070]},
		"{\"seq\":5,\"ts\":5,\"pid\":\"b1\",\"a\":\"dep\",\"dep\":null}": {"seq": 5, "ts": 5, "pid": "b1", "a": "dep", "dep": []},
		"{\"seq\":6,\"ts\":5,\"pid\":\"b1\",\"a\":\"owner\",\"nm\":\"x\"}": {"seq": 6, "ts": 5, "pid": "b1", "a": "owner", "nm": "x"},
		"{\"seq\":7,\"ts\":5,\"pid\":\"b1\",\"a\":\"setup\",\"setup\":{\"w\":50,\"density\":0.35}}": {"seq": 7, "ts": 5, "pid": "b1", "a": "setup", "setup": {"w": 50, "density_h": 35}},
		"{\"seq\":8,\"ts\":5,\"pid\":\"b1\",\"a\":\"state\",\"state\":\"play\",\"bots\":[{\"team\":1,\"list\":[0,2],\"dep\":[-999,12.3]}],\"roster\":[{\"pid\":\"b1\",\"team\":0,\"list\":[1],\"sk\":{\"loki\":1},\"dep\":null}]}":
			{"seq": 8, "ts": 5, "pid": "b1", "a": "state", "state": "play", "bots": [{"team": 1, "list": [0, 2], "dep": [-999000, 12300]}],
			"roster": [{"pid": "b1", "team": 0, "list": [1], "sk": {"loki": 1}, "dep": []}]},
		"{\"seq\":9,\"ts\":5,\"pid\":\"b1\",\"a\":\"smove\",\"u\":\"0:1\",\"how\":\"move\",\"x\":-21.9,\"z\":0}": {"seq": 9, "ts": 5, "pid": "b1", "a": "smove", "u": "0:1", "how": "move", "x": -21900, "z": 0},
		"{\"seq\":10,\"ts\":5,\"pid\":\"b1\",\"a\":\"chr\",\"u\":\"0:1\",\"t\":\"1:0\",\"roll\":[6,1],\"rr\":0,\"keep\":1}": {"seq": 10, "ts": 5, "pid": "b1", "a": "chr", "u": "0:1", "t": "1:0", "roll": [6, 1], "rr": 0, "keep": 1},
		"{\"seq\":11,\"ts\":5,\"pid\":\"b1\",\"a\":\"future\",\"n\":4,\"s\":\"x\"}": {"seq": 11, "ts": 5, "pid": "b1", "a": "future", "n": 4, "s": "x"},
	}
	for text: String in good:
		var e := _errs()
		var got := JsonNum.room_act(JSON.parse_string(text), e)
		assert_true(e.is_empty() and _same(got, good[text]), "room act " + text.left(70), [got, e])
	var bad := [
		["{\"a\":\"atk\",\"u\":\"0:1\",\"t\":\"1:0\",\"how\":\"shoot\",\"hit\":[2.5]}", "act(atk).hit[0]: not a whole number"],
		["{\"a\":\"atk\",\"u\":\"0:1\",\"t\":\"1:0\",\"how\":\"shoot\",\"hit\":[7]}", "act(atk).hit[0]: out of range"],
		["{\"a\":\"wnd\",\"u\":\"0:1\",\"t\":\"1:0\",\"wound\":[\"3\"]}", "act(wnd).wound[0]: not a number"],
		["{\"a\":\"adv\",\"u\":\"0:1\",\"roll\":0}", "act(adv).roll: out of range"],
		["{\"a\":\"heal\",\"u\":\"0:1\",\"t\":\"0:2\",\"roll\":[3]}", "act(heal).roll: not a number"],
		["{\"a\":\"shock\",\"u\":\"0:1\",\"roll\":[1,2,3],\"brave\":0}", "act(shock).roll: more than 2 dice"],
		["{\"a\":\"gren\",\"u\":\"0:1\",\"t\":\"1:0\",\"roll\":[1,1,1,1,1,1,1]}", "act(gren).roll: more than 6 dice"],
		["{\"a\":\"rez\",\"u\":\"0:1\",\"roll\":{}}", "act(rez).roll: not an array"],
		["{\"a\":\"sav\",\"u\":\"0:1\",\"t\":\"1:0\",\"save\":[],\"gtg\":2}", "act(sav).gtg: out of range"],
		["{\"a\":\"cmove\",\"u\":\"0:1\",\"t\":\"1:0\",\"to\":[[1.234,0]]}", "act(cmove).to[0][0]: more than 2 decimals"],
		["{\"a\":\"cmove\",\"u\":\"0:1\",\"t\":\"1:0\",\"to\":[[1]]}", "act(cmove).to[0]: not [x, z]"],
		["{\"a\":\"smove\",\"u\":\"0:1\",\"x\":\"5\",\"z\":0}", "act(smove).x: not a number"],
		["{\"a\":\"smove\",\"u\":\"0:1\",\"x\":10000,\"z\":0}", "act(smove).x: out of range"],
		["{\"a\":\"stay\",\"u\":12}", "act(stay).u: not a string"],
		["{\"a\":\"stay\",\"u\":\"0:1\",\"pid\":7}", "act(stay).pid: not a string"],
		["{\"a\":\"stay\",\"u\":\"0:1\",\"seq\":-1}", "act(stay).seq: out of range"],
		["{\"a\":\"stay\",\"u\":\"0:1\",\"ts\":1.5}", "act(stay).ts: not a whole number"],
		["{\"a\":\"done\",\"ph\":\"move\",\"extra\":0.5}", "act(done).extra: not a whole number"],
		["{\"a\":\"team\",\"team\":8}", "act(team).team: out of range"],
		["{\"a\":\"dep\",\"dep\":[200.5,0]}", "act(dep).dep[0]: out of range"],
		["{\"a\":\"state\",\"bots\":[{\"dep\":[1000,0]}]}", "act(state).bots[0].dep[0]: out of range"],
		["{\"a\":5}", "act.a: not a string"],
		["[1]", "act: not an object"],
	]
	for b: Array in bad:
		var e := _errs()
		var got := JsonNum.room_act(JSON.parse_string(b[0]), e)
		assert_true(got.is_empty() and e.size() >= 1 and e[0].begins_with(b[1]), "refused %s: %s" % [b[0].left(60), b[1]], e)
	var long: Array = []
	for i: int in 61:
		long.append(6.0)
	var de := _errs()
	assert_true(JsonNum.act_from_wire({"a": "atk", "u": "0:1", "t": "1:0", "hit": long}, de).is_empty() and de.size() == 1,
		"61 dice refused (the Worker sends 60 at most)")
	var pts: Array = []
	for i: int in 41:
		pts.append([0.0, 0.0])
	var pe := _errs()
	assert_true(JsonNum.act_from_wire({"a": "smove", "u": "0:1", "to": pts}, pe).is_empty() and pe.size() == 1,
		"41 points refused (the Worker sends 40 at most)")


## a whole room (btPublic): setup, players, board in tenths, acts; one bad act stays as a {seq, a, bad} marker
func test_room_from_wire() -> void:
	var text := "{\"code\":\"ABCD\",\"kind\":\"bt\",\"state\":\"play\",\"setup\":{\"theme\":\"ruin\",\"terrain\":\"hills\"," + \
		"\"buildings\":true,\"density\":1,\"seed\":7,\"w\":48,\"d\":34,\"mode\":\"pvp\",\"teams\":2,\"perTeam\":1,\"v\":10," + \
		"\"budget\":500,\"freeFire\":false,\"clock\":25,\"goal\":\"obj\",\"rounds\":5},\"seats\":2,\"ownerPid\":\"b1\"," + \
		"\"players\":[{\"pid\":\"b1\",\"nm\":\"A\",\"team\":0,\"bot\":false,\"ai\":false,\"list\":[1,0,2],\"sk\":{},\"dep\":[-20,-12.5]," + \
		"\"owner\":true,\"gone\":false},{\"pid\":\"b2\",\"nm\":\"B\",\"team\":1,\"bot\":true,\"ai\":false,\"list\":[0,0,0,0],\"sk\":{}," + \
		"\"dep\":null,\"owner\":false,\"gone\":true}],\"seq\":12,\"board\":{\"turn\":0,\"round\":1,\"over\":false,\"at\":1760000000000," + \
		"\"units\":[{\"id\":\"0:0.0\",\"pl\":0,\"team\":0,\"k\":\"inf\",\"hp\":1,\"x\":-12.3,\"z\":4,\"sq\":\"0:0\"}]," + \
		"\"obj\":[{\"n\":1,\"x\":0.5,\"z\":-0.5,\"owner\":-1}]},\"acts\":[" + \
		"{\"seq\":11,\"ts\":3,\"pid\":\"b1\",\"a\":\"atk\",\"u\":\"0:0\",\"t\":\"1:0\",\"how\":\"shoot\",\"hit\":[1,6]}," + \
		"{\"seq\":12,\"ts\":4,\"pid\":\"b2\",\"a\":\"wnd\",\"u\":\"0:0\",\"t\":\"1:0\",\"wound\":[2.5]}]}"
	var e := _errs()
	var r := JsonNum.room_from_wire(JSON.parse_string(text), e)
	assert_true(e.size() == 1 and e[0].begins_with("room.acts[1] act(wnd).wound[0]: not a whole number"), "one bad act, named", e)
	assert_true(_clean(r), "room in the core form (no float)", r)
	assert_eq(r.get("seq"), 12, "seq int")
	assert_eq(r["setup"].get("density_h"), 100, "setup density_h")
	assert_true(_same(r["players"][0]["dep"], [-20000, -12500]) and _same(r["players"][1]["dep"], []), "players' deps in MI")
	assert_true(_same(r["players"][0]["list"], [1, 0, 2]), "players' lists as ints")
	assert_eq(r["board"]["units"][0]["x"], -123, "board x in tenths")
	assert_eq(r["board"]["obj"][0]["z"], -5, "board objective z in tenths")
	assert_eq(r["board"]["at"], 1760000000000, "board at (Date.now) as an int")
	var acts: Array = r["acts"]
	assert_eq(acts.size(), 2, "both acts kept")
	assert_true(_same(acts[0], {"seq": 11, "ts": 3, "pid": "b1", "a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [1, 6]}),
		"good act in the core form", acts[0])
	assert_true(acts[1].get("seq") == 12 and acts[1].get("a") == "wnd" and str(acts[1].get("bad")).begins_with("act(wnd).wound[0]"),
		"bad act becomes a marker that keeps its seq", acts[1])
	var ne := _errs()
	var nb := JsonNum.room_from_wire(JSON.parse_string("{\"board\":null,\"ownerPid\":null,\"acts\":[{\"a\":\"x\",\"n\":0.5}]}"), ne)
	assert_true(nb.get("board", 1) == null and nb.get("ownerPid", 1) == null, "null board and owner kept")
	assert_true(ne.size() == 1 and (nb["acts"] as Array).is_empty(), "a bad act without a readable seq is dropped (and named)", [nb, ne])


# ---------------------------------------------------------------- round trips and determinism
## core acts with points on the 10 MI grid survive act_body -> parse -> act_from_wire exactly (every code)
func test_round_trip_core_acts() -> void:
	var rng := Rng.make("test_json_num", 77)
	var bad: Array = []
	var n := 0
	for k: int in 400:
		var code: String = JsonNum.ACT_FIELDS.keys()[k % JsonNum.ACT_FIELDS.size()]
		var act := {"a": code}
		var fields: Dictionary = JsonNum.ACT_FIELDS[code]
		for f: String in fields:
			var kind: String = fields[f]
			if code == "smove" and ((f == "to") == (k % 2 == 0)) and f != "u" and f != "how":
				continue
			match kind:
				"s":
					act[f] = "%d:%d" % [rng.bounded(8), rng.bounded(30)]
				"c":
					act[f] = 10 * (rng.bounded(2 * JsonNum.PT_MAX + 1) - JsonNum.PT_MAX)
				"die":
					act[f] = rng.d6()
				"bit":
					act[f] = rng.bounded(2)
				"pt":
					var pts: Array = []
					for i: int in rng.bounded(41):
						pts.append([10 * (rng.bounded(180001) - 90000), 10 * (rng.bounded(180001) - 90000)])
					act[f] = pts
				_:
					var dice: Array = []
					for i: int in rng.bounded(kind.substr(1).to_int() + 1):
						dice.append(rng.d6())
					act[f] = dice
		var e := _errs()
		var text := JsonNum.act_body("b%d" % k, act, e)
		var body: Variant = JsonNum.parse(text, e)
		var back := JsonNum.act_from_wire(body["act"] if typeof(body) == TYPE_DICTIONARY else null, e)
		n += 1
		if not e.is_empty() or not _same(back, act) or text.contains(".0,") or text.contains(".0]"):
			bad.append([act, text, back, e])
	assert_true(bad.is_empty(), "%d random core acts round-trip exactly" % n, bad.slice(0, 2))
	# a point off the 10 MI grid would be rounded on the wire while the sender keeps it: refused before sending
	for off: Dictionary in [{"a": "smove", "u": "0:1", "how": "move", "x": 12345, "z": 0},
			{"a": "cmove", "u": "0:1", "t": "1:0", "to": [[10, 20], [-15, 0]]}]:
		var oe := _errs()
		var txt := JsonNum.act_body("b1", off, oe)
		assert_true(txt == "" and oe.size() == 1 and oe[0].contains("off the 10 MI grid"), "off-grid point refused: " + str(off), oe)


## setup_to_wire -> stringify -> parse -> setup_from_wire gives BattleState.setup_dict() back (bools stay bools)
func test_round_trip_setup() -> void:
	var st := BattleState.make({"theme": "ice", "seed": 4321, "w": 96, "terrain": "forest", "buildings": 0, "density_h": 35,
		"mode": "ffa", "teams": 6, "perTeam": 1, "budget": 3000, "freeFire": 1, "clock": 50, "goal": "kill", "rounds": 8})
	var core := st.setup_dict()
	var e := _errs()
	var text := JsonNum.stringify(JsonNum.setup_to_wire(core), e)
	assert_eq(text, "{\"theme\":\"ice\",\"seed\":4321,\"w\":96,\"terrain\":\"forest\",\"buildings\":false,\"density\":0.35," + \
		"\"mode\":\"ffa\",\"teams\":6,\"perTeam\":1,\"budget\":3000,\"freeFire\":true,\"clock\":50,\"goal\":\"kill\",\"rounds\":8," + \
		"\"v\":%d}" % Version.RULES_V, "setup text as curSetup()")
	var back := JsonNum.setup_from_wire(JsonNum.parse(text, e), "setup", e)
	assert_true(e.is_empty(), "no errors", e)
	var st2 := BattleState.make(back)
	var d1 := st.setup_dict()
	var d2 := st2.setup_dict()
	d1.erase("d")
	d2.erase("d")
	assert_true(_same(d1, d2), "same BattleState setup after the round trip", [d1, d2])


## one digest over every output of the samples (core forms and written texts), pinned
func test_pinned_digest() -> void:
	var acc := PackedStringArray()
	for b: Dictionary in F.get("bodies", []):
		var e := _errs()
		var core := JsonNum.act_from_wire((JSON.parse_string(str(b["text"])) as Dictionary)["act"], e)
		acc.append(JsonNum.stringify(core, e))
		acc.append(JsonNum.act_body(str(b["pid"]), core, e))
	for s: Dictionary in F.get("setups", []) + F.get("worker_setups", []):
		var e := _errs()
		var core := JsonNum.setup_from_wire(JSON.parse_string(str(s.get("text", s.get("out")))), "s", e)
		acc.append(JsonNum.stringify(core, e))
		acc.append(JsonNum.stringify(JsonNum.setup_to_wire(core), e))
	for c: Dictionary in F.get("worker_lists", []):
		var e := _errs()
		var d: Dictionary = JSON.parse_string(str(c["out"]))
		acc.append(JsonNum.stringify(JsonNum.list_from_wire(d["list"], "l", e), e))
	var dig := Hash.hex64(Hash.fnv1a64_str("\n".join(acc)))
	print("      json_num digest " + dig + " over %d texts" % acc.size())
	assert_true(acc.size() > 150, "digest covers the samples", acc.size())
	if PINNED_DIGEST != "":
		assert_digest(dig, PINNED_DIGEST, "pinned digest of the json_num samples")
	else:
		assert_true(false, "PINNED_DIGEST is set", dig)
