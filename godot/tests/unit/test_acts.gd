extends "res://tests/testing.gd"
## core/battle/acts.gd (BtActs, R1_PORT_SPEC §1.13 and §4) — the codec half: CODES, sanitize, to_wire.
## (The dispatcher half, BtActs.apply and each handler's guard, comes with battle.gd in wave 5.)
## Worker samples: fixtures/acts/worker_samples.json (tools/record_board_acts.js runs the "act" branch of the Worker's
## btPost, cut from candlelight-server/worker.js, on 146 wire acts: 92 made by hand and 54 the page really sent in the
## oracle recordings): sanitize(core form of the wire act) equals the core form of the Worker's answer, key order
## included, for every case (every code, every cap, every default and JS conversion the core form mirrors, the refused
## ones); CODES equals the Worker's allowlist.
## Hand cases: caps (61 dice -> 60, 41 points -> 40, 21-char id -> 20), bad how/ph defaults, chr always with rr and
## keep, smove x/z defaults, pid kept and seq/ts dropped, round trips through to_wire, toFixed(2) hundredths, the
## core-form differences from JS that cannot be mirrored (pinned here, never in the fixture), and a pinned digest.

const FIX := "res://tests/unit/fixtures/acts/worker_samples.json"
## FNV-1a 64 of every fixture case's sanitize() and to_wire() answers as sorted-key JSON, in order; changes only on purpose.
const PINNED_DIGEST := "0bc0540ae1a00b63"
## the 19 codes the page sends (the oracle recordings hold all of them) and the two of rules version 1
const RULES_CODES := ["smove", "stay", "skip", "adv", "atk", "wnd", "sav", "rr", "shoot", "shock", "rez", "chg", "ow", "chr",
	"cmove", "gren", "heal", "done", "endph"]
var F: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		F = _iv(p)


# ---------------------------------------------------------------- helpers
## JSON numbers arrive as floats: whole ones become ints (deep)
func _iv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if f == floorf(f) and absf(f) < 1.0e18 else f
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


## only int, bool, String, Array and Dictionary (the core form; no float anywhere)
func _core_clean(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not _core_clean(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not _core_clean(v[k]):
					return false
			return true
	return false


## the net layer's inverse of to_wire for the test: hundredths back to MI on to/x/z
func _from_wire(w: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in w:
		var v: Variant = w[k]
		if k == "to" and typeof(v) == TYPE_ARRAY:
			var pts: Array = []
			for q: Variant in v:
				pts.append([int(q[0]) * 10, int(q[1]) * 10])
			out[k] = pts
		elif (k == "x" or k == "z") and typeof(v) == TYPE_INT:
			out[k] = int(v) * 10
		else:
			out[k] = v
	return out


func _dice(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(1 + i % 6)
	return out


# ---------------------------------------------------------------- codes
func test_codes() -> void:
	assert_eq(BtActs.CODES.size(), 21, "19 rules codes and 2 legacy ones")
	var seen := {}
	for c: String in BtActs.CODES:
		seen[c] = true
	assert_eq(seen.size(), 21, "no code twice")
	for c: String in RULES_CODES:
		assert_true(seen.has(c), "CODES has " + c)
	for c: String in BtActs.LEGACY:
		assert_true(seen.has(c) and not RULES_CODES.has(c), "legacy %s is in CODES and not a page code" % c)
	var worker: Array = F["worker"]["codes"]
	var a := worker.duplicate()
	a.sort()
	var b := BtActs.CODES.duplicate()
	b.sort()
	assert_eq(b, a, "CODES is the Worker's act allowlist exactly (btPost, rules version %d)" % int(F["worker"]["bt_rules"]))


# ---------------------------------------------------------------- Worker samples
func test_sanitize_matches_worker() -> void:
	var cases: Array = F["cases"]
	assert_true(cases.size() >= 140, "%d sampled acts" % cases.size())
	var oracle := 0
	var oracle_codes := {}
	for cv: Variant in cases:
		if str(cv["name"]).begins_with("oracle "):
			oracle += 1
			oracle_codes[str(cv["core"]["a"])] = true
	assert_true(oracle == 54 and oracle_codes.size() == 19,
		"%d acts the page sent (up to three of each of the 19 codes; the recordings hold two rr and one shoot)" % oracle)
	var bad: Array = []
	var refused := 0
	var codes := {}
	for cv: Variant in cases:
		var c: Dictionary = cv
		var got := BtActs.sanitize(c["core"])
		var want: Dictionary = c["want"]
		if c["out"] == null:
			refused += 1
			if not got.is_empty():
				bad.append([c["name"], "should be refused", got])
			continue
		codes[str(want["a"])] = true
		if got != want:
			bad.append([c["name"], got, want])
		elif got.keys() != c["want_keys"]:
			bad.append([c["name"], "key order", got.keys(), c["want_keys"]])
		elif not _core_clean(got):
			bad.append([c["name"], "not core-clean", got])
	assert_eq(refused, 8, "8 refused samples (unknown, upper case, a number, none, room and server-made codes)")
	assert_eq(codes.size(), 21, "the accepted samples cover all 21 codes")
	assert_true(bad.is_empty(), "sanitize equals the Worker's btPost on every sample (fields, values, key order)", bad.slice(0, 4))


func test_sanitize_is_idempotent_and_logs() -> void:
	var bad: Array = []
	var alog := ActLog.new()
	var accepted := 0
	for cv: Variant in F["cases"]:
		var c: Dictionary = cv
		var once := BtActs.sanitize(c["core"])
		if once.is_empty():
			continue
		accepted += 1
		if BtActs.sanitize(once) != once:
			bad.append([c["name"], "twice", BtActs.sanitize(once), once])
		var a := once.duplicate(true)
		if not a.has("pid"):
			a["pid"] = "A"
		if alog.append(a) < 0:
			bad.append([c["name"], "act log", alog.error])
	assert_eq(alog.size(), accepted, "every accepted act (%d) enters the act log as it is (ints, strings, arrays only)" % accepted)
	assert_true(bad.is_empty(), "sanitize(sanitize(a)) == sanitize(a), and the act log takes every answer", bad.slice(0, 4))


func test_round_trip_through_wire() -> void:
	var bad: Array = []
	var n := 0
	for cv: Variant in F["cases"]:
		var c: Dictionary = cv
		var act := BtActs.sanitize(c["core"])
		if act.is_empty():
			continue
		var keep := act.duplicate(true)
		var w := BtActs.to_wire(act)
		if act != keep:
			bad.append([c["name"], "to_wire changed its input"])
		if w.keys() != act.keys():
			bad.append([c["name"], "wire keys", w.keys()])
		for k: String in ["to", "x", "z"]:
			if not w.has(k):
				continue
			if k == "to":
				for i: int in (w["to"] as Array).size():
					var q: Array = w["to"][i]
					var m: Array = act["to"][i]
					if typeof(q[0]) != TYPE_INT or int(q[0]) * 10 != int(m[0]) or int(q[1]) * 10 != int(m[1]):
						bad.append([c["name"], "to", i, q, m])
			elif typeof(w[k]) != TYPE_INT or int(w[k]) * 10 != int(act[k]):
				bad.append([c["name"], k, w[k], act[k]])
		for k: Variant in act:
			if k != "to" and k != "x" and k != "z" and w[k] != act[k]:
				bad.append([c["name"], "field", k])
		var back := BtActs.sanitize(_from_wire(w))
		n += 1
		if back != act:
			bad.append([c["name"], "round trip", back, act])
	assert_true(n >= 80, "%d acts through to_wire and back" % n)
	assert_true(bad.is_empty(), "core -> wire (hundredths ints) -> core is exact for every sampled act (points on the 10 MI grid)", bad.slice(0, 4))


# ---------------------------------------------------------------- hand cases
func test_caps() -> void:
	var a := BtActs.sanitize({"a": "atk", "u": "0:1", "t": "1:0", "hit": _dice(61)})
	assert_eq((a["hit"] as Array).size(), 60, "61 hit dice -> 60")
	var s := BtActs.sanitize({"a": "shoot", "u": "0:1", "t": "1:0", "hit": _dice(60), "wound": _dice(100), "save": _dice(2)})
	assert_eq([(s["hit"] as Array).size(), (s["wound"] as Array).size(), (s["save"] as Array).size()], [60, 60, 2], "each dice row of shoot is cut at 60")
	var pts: Array = []
	for i: int in 41:
		pts.append([i * 10, -i * 10])
	var m := BtActs.sanitize({"a": "smove", "u": "0:1", "to": pts})
	assert_eq((m["to"] as Array).size(), 40, "41 points -> 40")
	assert_eq(m["to"][39], [390, -390], "the first 40 are kept in order")
	var cm := BtActs.sanitize({"a": "cmove", "u": "0:1", "t": "1:0", "to": pts})
	assert_eq((cm["to"] as Array).size(), 40, "cmove: 41 points -> 40")
	var id := BtActs.sanitize({"a": "stay", "u": "abcdefghijklmnopqrstu"})
	assert_eq(id["u"], "abcdefghijklmnopqrst", "an id of 21 chars keeps 20")
	assert_eq(BtActs.sanitize({"a": "stay", "u": "abcdefghijklmnopqrst"})["u"], "abcdefghijklmnopqrst", "20 chars stay")
	assert_eq((BtActs.sanitize({"a": "shock", "u": "x", "roll": [1, 2, 3]})["roll"] as Array).size(), 2, "shock: 2 dice")
	assert_eq((BtActs.sanitize({"a": "chr", "u": "x", "t": "y", "roll": [1, 2, 3]})["roll"] as Array).size(), 2, "chr: 2 dice")
	assert_eq((BtActs.sanitize({"a": "gren", "u": "x", "t": "y", "roll": _dice(9)})["roll"] as Array).size(), 6, "gren: 6 dice")
	assert_eq((BtActs.sanitize({"a": "rez", "u": "x", "roll": _dice(70)})["roll"] as Array).size(), 10, "rez: 10 dice")
	assert_eq(BtActs.sanitize({"a": "atk", "u": "x", "t": "y", "hit": [0, 7, -3, 6, 1]})["hit"], [1, 6, 1, 6, 1], "dice clamp to 1..6 (0 -> 1)")
	var big := BtActs.sanitize({"a": "smove", "u": "x", "to": [[10000000, -10000000], [9999000, -9999001]]})
	assert_eq(big["to"], [[9999000, -9999000], [9999000, -9999000]], "points clamp to +-9999 inches")
	var xz := BtActs.sanitize({"a": "move", "u": "x", "x": 12000000, "z": -5})
	assert_eq([xz["x"], xz["z"]], [9999000, -5], "legacy move: x/z clamp too")


func test_defaults() -> void:
	assert_eq(BtActs.sanitize({"a": "atk", "u": "x", "t": "y", "how": "melee"})["how"], "shoot", "a bad how -> shoot")
	assert_eq(BtActs.sanitize({"a": "atk", "u": "x", "t": "y"})["hit"], [], "missing dice -> []")
	assert_eq(BtActs.sanitize({"a": "shoot", "u": "x", "t": "y", "how": "ow"})["how"], "ow", "ow is a how")
	assert_eq(BtActs.sanitize({"a": "skip", "u": "x", "ph": "deploy"})["ph"], "", "a bad ph -> \"\"")
	assert_eq(BtActs.sanitize({"a": "endph"})["ph"], "", "a missing ph -> \"\"")
	assert_eq(BtActs.sanitize({"a": "done", "ph": "fight"})["ph"], "fight", "a phase name stays")
	assert_eq(BtActs.sanitize({"a": "smove", "u": "x", "how": "run", "to": []})["how"], "move", "a bad smove how -> move")
	assert_eq(BtActs.sanitize({"a": "smove", "u": "x", "how": "fb", "to": []})["how"], "fb", "fb stays")
	var c := BtActs.sanitize({"a": "chr", "u": "x", "t": "y", "roll": [3, 4]})
	assert_eq([c["rr"], c["keep"]], [0, 0], "chr always carries rr and keep (0 when not sent)")
	assert_eq(c.keys(), ["a", "u", "t", "roll", "rr", "keep"], "chr keys in the Worker's order")
	var k := BtActs.sanitize({"a": "chr", "u": "x", "t": "y", "keep": true, "rr": "yes"})
	assert_eq([k["roll"], k["rr"], k["keep"]], [[], 1, 1], "truthy rr/keep -> 1, no roll -> []")
	var sm := BtActs.sanitize({"a": "smove", "u": "x"})
	assert_eq(sm, {"a": "smove", "u": "x", "how": "move", "x": 0, "z": 0}, "smove with neither to nor x/z: a plan to the table centre (page parity)")
	var sx := BtActs.sanitize({"a": "smove", "u": "x", "x": 12300})
	assert_eq([sx["x"], sx["z"], sx.has("to")], [12300, 0, false], "smove x without z: z = 0, no to")
	var st := BtActs.sanitize({"a": "smove", "u": "x", "to": [], "x": 5})
	assert_eq([st["to"], st.has("x")], [[], false], "an empty to array is kept (and x/z dropped)")
	assert_eq(BtActs.sanitize({"a": "adv", "u": "x"})["roll"], 1, "a missing one-die roll -> 1")
	assert_eq(BtActs.sanitize({"a": "rr", "u": "x", "t": "y", "v": 9})["v"], 6, "one die clamps to 6")
	assert_eq(BtActs.sanitize({"a": "heal", "u": "x", "t": "y", "roll": -2})["roll"], 1, "and to 1")
	assert_eq(BtActs.sanitize({"a": "ow", "u": 7, "t": null}), {"a": "ow", "u": "7", "t": "", "use": 0}, "ids: String(7), null -> \"\"")
	assert_eq(BtActs.sanitize({"a": "stay", "u": [1, [2, 3], null]})["u"], "1,2,3,", "an array id joins like JS")
	assert_eq(BtActs.sanitize({"a": "stay", "u": {}})["u"], "[object Object]", "an object id prints like JS")
	assert_eq(BtActs.sanitize({"a": "endturn", "u": "x", "ph": "move"}), {"a": "endturn"}, "legacy endturn has no fields")
	assert_eq(BtActs.sanitize({"a": "stay", "u": "x", "pid": 3}), {"a": "stay", "u": "x", "pid": 3}, "an int pid is kept")


func test_refused() -> void:
	for raw: Dictionary in [{}, {"a": ""}, {"a": "fly"}, {"a": "SMOVE"}, {"a": 5}, {"a": null}, {"a": ["smove"]},
			{"a": "state"}, {"a": "join"}, {"a": "owner"}, {"a": "list"}, {"a": "dep"}, {"a": "board"}, {"a": "nop"}]:
		assert_eq(BtActs.sanitize(raw), {}, "refused: %s" % str(raw))


func test_pid_seq_ts() -> void:
	var a := BtActs.sanitize({"a": "done", "ph": "move", "pid": "L1", "seq": 12, "ts": 1700000000000, "extra": 1})
	assert_eq(a, {"a": "done", "ph": "move", "pid": "L1"}, "pid passes (the Worker adds it from the session); seq, ts and extras do not")
	assert_eq(a.keys(), ["a", "ph", "pid"], "pid comes after the act's own fields")
	assert_false(BtActs.sanitize({"a": "stay", "u": "x", "pid": true}).has("pid"), "a bool pid is not a pid")
	assert_false(BtActs.sanitize({"a": "stay", "u": "x", "pid": ["A"]}).has("pid"), "nor is an array")


func test_hundredths_and_to_wire() -> void:
	var cases := [[0, 0], [10, 1], [-10, -1], [12340, 1234], [-12340, -1234], [125, 13], [-125, -13], [-4, 0], [4, 0],
		[5, 1], [1005, 100], [2675, 267], [9999000, 999900], [-9999000, -999900]]
	for c: Array in cases:
		assert_eq(BtActs.hundredths(int(c[0])), int(c[1]), "hundredths(%d) = %d (+(mi/1000).toFixed(2))" % c)
	var w := BtActs.to_wire({"a": "smove", "u": "0:1", "how": "move", "to": [[1250, -3500], [0, 10]], "pid": "A"})
	assert_eq(w, {"a": "smove", "u": "0:1", "how": "move", "to": [[125, -350], [0, 1]], "pid": "A"}, "to in hundredths, other fields as they are")
	var x := BtActs.to_wire({"a": "smove", "u": "0:1", "how": "move", "x": 12300, "z": -4500})
	assert_eq([x["x"], x["z"]], [1230, -450], "x/z in hundredths")
	var o := BtActs.to_wire({"a": "atk", "u": "0:1", "t": "1:0", "how": "shoot", "hit": [1, 2]})
	assert_eq(o, {"a": "atk", "u": "0:1", "t": "1:0", "how": "shoot", "hit": [1, 2]}, "an act without points is copied")
	var src := {"a": "cmove", "u": "0:1", "t": "1:0", "to": [[20, 30]]}
	var cw := BtActs.to_wire(src)
	(cw["to"] as Array).append([1, 1])
	assert_eq((src["to"] as Array).size(), 1, "to_wire copies (the wire act shares nothing with the core act)")


## the places where the core form cannot mirror JS on purpose (numbers in the core form are ints; net/ intifies JSON
## numbers before core sees them, and the Worker has already converted a sender's strings on the way)
func test_core_form_differences() -> void:
	assert_eq(BtActs.sanitize({"a": "smove", "u": "x", "to": [["12", 3000]]})["to"], [[0, 3000]],
		"a numeric string is not a number in the core form (the Worker's Number(\"12\") gives 12 inches)")
	assert_eq(BtActs.sanitize({"a": "atk", "u": "x", "t": "y", "hit": ["4", [5]]})["hit"], [1, 1],
		"\"4\" and [5] are not dice in the core form (JS gives 4 and 5)")
	assert_eq(BtActs.sanitize({"a": "adv", "u": "x", "roll": 4.0})["roll"], 1, "a float is not a number in the core form")
	var astral := "abcdefghijklmnopqrs" + String.chr(128512)
	assert_eq(BtActs.sanitize({"a": "stay", "u": astral})["u"], "abcdefghijklmnopqrs",
		"an id cut inside a surrogate pair drops the whole character (JS keeps half of it)")
	assert_eq(BtActs.sanitize({"a": "stay", "u": "abcdefghijklmnopqr" + String.chr(128512)})["u"], "abcdefghijklmnopqr" + String.chr(128512),
		"an astral character that fits (two UTF-16 units) stays")
	assert_eq(BtActs.sanitize({"a": "smove", "u": "x", "x": true, "z": false}), {"a": "smove", "u": "x", "how": "move", "x": 1000, "z": 0},
		"a bool coordinate is Number(true) = 1 inch, as the Worker")
	assert_eq(BtActs.sanitize({"a": "stay", "u": PackedInt32Array([1, 2])})["u"], "1,2", "a packed array id joins like an array")
	assert_eq(BtActs.sanitize({"a": "wnd", "u": "x", "t": "y", "wound": PackedInt32Array([9, 0, 3])})["wound"], [6, 1, 3],
		"packed dice rows are arrays too (tests and the roller may hand them)")


func test_digest_pinned() -> void:
	var a := _digest_cases()
	assert_eq(a, _digest_cases(), "the codec digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtActs codec digest over the Worker samples is pinned")


func _digest_cases() -> String:
	var parts := PackedStringArray()
	for cv: Variant in F["cases"]:
		var c: Dictionary = cv
		parts.append(JSON.stringify(BtActs.sanitize(c["core"]), "", true))
		parts.append(JSON.stringify(BtActs.to_wire(BtActs.sanitize(c["core"])), "", true))
	return Hash.hex64(Hash.fnv1a64_str("\n".join(parts)))
