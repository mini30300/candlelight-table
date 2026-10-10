extends "res://tests/testing.gd"
## core/battle/acts.gd (BtActs, R1_PORT_SPEC §1.13 and §4): the codec half (CODES, sanitize, to_wire) and the
## dispatcher half (BtActs.apply = the page's netAct: every code and each handler's guard, CP spent in the handler
## before the applier's own guards, t "" matching no entry, check_over after every act, a pinned digest). The page's
## netAct itself is sampled end to end by the oracle replay (tests/oracle, every recorded act through Battle.apply).
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


# ================================================================ the dispatcher: BtActs.apply (page netAct)
## A match in progress on an open 60" table: two seats (pids L0, L1, cp each), team 0 in turn, phase ph.
func _st(ph: int, cp: int = 3) -> BattleState:
	var st := BattleState.make({"seed": 11, "w": 60, "teams": 2})
	st.on = true
	st.phase = ph
	for i: int in 2:
		var p := st.add_seat(i, "L%d" % i, false, false, "")
		p.cp = cp
	return st


func _sq(st: BattleState, id: String, k: String, side: int, pts: Array) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, side, int(t.get("n", 1)), 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


func _line(n: int, x0: int, z: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append([x0 + i * 1700, z])
	return out


func _do(st: BattleState, act: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	BtActs.apply(st, act, out)
	return out


func _logged(st: BattleState, key: String) -> int:
	var n := 0
	for l: Dictionary in st.log_lines:
		if str(l["key"]) == key:
			n += 1
	return n


func _pos(s: BattleState.Squad) -> Array:
	var out: Array = []
	for m: BattleState.Unit in s.models:
		out.append([m.x, m.z])
	return out


func test_apply_smove() -> void:
	var st := _st(BattleState.PH_MOVE)
	var s := _sq(st, "0:0", "infantry", 0, _line(2, 0, 0))
	_sq(st, "1:0", "infantry", 1, _line(2, 0, 30000))
	_do(st, {"a": "smove", "u": "0:0", "how": "move", "to": []})
	assert_false(s.moved, "smove with an empty to: nothing happens, moved stays false (page netAct)")
	_do(st, {"a": "smove", "u": "0:0", "how": "move", "to": [[0, 3000], [1700, 3000]]})
	assert_eq([_pos(s), s.moved, s.still], [[[0, 3000], [1700, 3000]], true, false], "smove to: every model to its point")
	_do(st, {"a": "smove", "u": "0:0", "how": "move", "to": [[0, 6000], [1700, 6000]]})
	assert_eq(_pos(s), [[0, 3000], [1700, 3000]], "a squad that moved ignores the next smove")
	_do(st, {"a": "smove", "u": "9:9", "how": "move", "to": [[0, 0]]})
	assert_eq(st.units.size(), 4, "an unknown squad: nothing")
	# Claude form: x/z planned on every device with plan_move
	var st2 := _st(BattleState.PH_MOVE)
	var c := _sq(st2, "0:0", "infantry", 0, _line(2, 0, 0))
	_sq(st2, "1:0", "infantry", 1, _line(2, 0, 30000))
	var want := BtMoves.pts(BtMoves.plan_move(st2, c, 2000, 4000))
	_do(st2, BtActs.sanitize({"a": "smove", "u": "0:0", "how": "fb", "x": 2000, "z": 4000}))
	assert_eq([_pos(c), c.moved, c.fell], [want, true, true], "smove x/z: the plan_move points, how fb sets fell")
	var st3 := _st(BattleState.PH_MOVE)
	var d := _sq(st3, "0:0", "infantry", 0, _line(1, 4000, 4000))
	_do(st3, BtActs.sanitize({"a": "smove", "u": "0:0"}))
	assert_true(d.moved and Fx.dist2(d.models[0].x, d.models[0].z, 0, 0) < Fx.dist2(4000, 4000, 0, 0),
		"smove with neither to nor x/z plans to the table centre (the Worker's num(undefined) = 0)")


func test_apply_stay_skip_adv() -> void:
	var st := _st(BattleState.PH_SHOOT)
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	_do(st, {"a": "stay", "u": "0:0"})
	assert_true(s.moved, "stay sets moved in any phase (no phase guard, as the page)")
	_do(st, {"a": "skip", "u": "0:0", "ph": ""})
	assert_eq([s.shot, s.ch_done], [true, false], "skip with ph '' uses the current phase (shoot)")
	_do(st, {"a": "skip", "u": "0:0", "ph": "charge"})
	assert_true(s.ch_done, "skip charge sets ch_done")
	var t := _sq(st, "0:1", "infantry", 0, _line(1, 0, 5000))
	_do(st, {"a": "skip", "u": "0:1", "ph": "move"})
	assert_eq([t.moved, t.shot, t.ch_done], [true, false, false], "skip in any other phase sets moved")
	st.phase = BattleState.PH_CMD
	var c := _sq(st, "0:2", "infantry", 0, _line(1, 0, 9000))
	_do(st, {"a": "skip", "u": "0:2", "ph": ""})
	assert_true(c.moved, "skip '' in cmd: moved")
	_do(st, {"a": "adv", "u": "0:1", "roll": 4})
	assert_eq([t.adv, t.adv_r], [true, 4], "adv keeps the roll")
	_do(st, {"a": "adv", "u": "0:1", "roll": 6})
	assert_eq(t.adv_r, 4, "a second adv is ignored (not s.adv)")
	_do(st, {"a": "adv", "u": "0:2"})
	assert_eq([c.adv, c.adv_r], [true, 1], "adv without a roll: 1 (roll|0 || 1), never a draw")
	assert_eq(st.pend.size(), 0, "adv leaves nothing in the queue")


func test_apply_atk_wnd_sav() -> void:
	var st := _st(BattleState.PH_SHOOT)
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(5, 0, 15000))
	_do(st, {"a": "atk", "u": "0:0", "t": "", "how": "shoot", "hit": [6, 6]})
	assert_eq([st.pend.size(), s.shot], [0, false], "atk without a target squad: nothing")
	_do(st, {"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 1, 1]})
	assert_eq(st.pend.size(), 1, "atk: a new attack")
	var p := st.pend[0]
	assert_eq([p.stage, p.hits, s.shot], [BattleState.S_WOUND, 3, true], "hit dice applied, the shooter has shot")
	_do(st, {"a": "wnd", "u": "0:0", "t": "", "wound": [6, 6, 6]})
	assert_eq(p.stage, BattleState.S_WOUND, "wnd with t '' matches no entry (page pendAt compares P.t === '')")
	_do(st, {"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 6, 6]})
	assert_eq([st.pend.size(), _logged(st, "atk_new")], [2, 1], "atk while the entry is past hit: a second attack (page), logged atk_new")
	st.pend.remove_at(1)
	_do(st, {"a": "wnd", "u": "0:0", "wound": [6, 6, 6]})
	assert_eq([p.stage, p.wounds], [BattleState.S_SAVE, 3], "wnd without a t key: any target (pendAt with tid null)")
	_do(st, {"a": "sav", "u": "0:0", "t": "1:0", "save": [1, 1, 1], "gtg": 0})
	assert_eq([st.pend.size(), st.squad_alive(t), st.seat(1).cp], [0, 2, 3], "sav: three failed saves kill three, no CP spent")
	# gtg spends the defender's CP only at stage save, even when it cannot help
	var q := BtPend.mk_atk(st, s, t, BattleState.HOW_SHOOT)
	_do(st, {"a": "sav", "u": "0:0", "t": "1:0", "save": [6], "gtg": 1})
	assert_eq([st.seat(1).cp, q.stage], [3, BattleState.S_HIT], "sav at stage hit: ignored, no CP")
	_do(st, {"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 1, 1]})
	_do(st, {"a": "wnd", "u": "0:0", "t": "1:0", "wound": [6, 6, 6]})
	assert_eq([q.stage, st.pend.size()], [BattleState.S_SAVE, 1], "the queued entry at stage hit takes the atk dice")
	_do(st, {"a": "sav", "u": "0:0", "t": "1:0", "save": [6, 6, 6], "gtg": 1})
	assert_eq([st.seat(1).cp, q.gtg, st.squad_alive(t)], [2, true, 2], "gtg at save: CP spent, sv improved")
	var nogun := _sq(st, "0:1", "hoplite", 0, _line(1, 0, 2000))
	_do(st, {"a": "atk", "u": "0:1", "t": "1:0", "how": "shoot", "hit": [6]})
	assert_eq([st.pend.size(), nogun.shot], [0, false], "atk with no weapon for that how: nothing (mkAtk null)")
	_do(st, {"a": "shoot", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 6, 6], "wound": [6, 6, 6, 6, 6],
		"save": [1, 1, 1, 1, 1]})
	assert_true(st.squad_alive(t) == 0 and st.over and st.winner == 0, "shoot: the whole attack; the last enemy dies and the match is over (check_over)")


func test_apply_rr() -> void:
	var st := _st(BattleState.PH_SHOOT)
	var s := _sq(st, "0:0", "infantry", 0, _line(5, 0, 0))
	_sq(st, "1:0", "infantry", 1, _line(5, 0, 15000))
	_do(st, {"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 1, 1, 6, 6]})
	var p := st.pend[0]
	_do(st, {"a": "rr", "u": "0:0", "t": "", "v": 6})
	assert_eq([st.seat(0).cp, p.hits], [3, 3], "rr with t '': no entry, no CP")
	_do(st, {"a": "rr", "u": "0:0", "t": "1:0", "v": 6})
	assert_eq([st.seat(0).cp, p.hits, p.rr], [2, 4, true], "rr: CP spent, the lowest failed die re-rolled")
	_do(st, {"a": "rr", "u": "0:0", "t": "1:0", "v": 6})
	assert_eq([st.seat(0).cp, p.hits], [2, 4], "a second rr on the same attack: nothing (P.rr)")
	# CP is spent before apply_reroll's own guards: a torrent attack and an attack with no failed die
	var st2 := _st(BattleState.PH_SHOOT)
	var a := _sq(st2, "0:0", "infantry", 0, _line(5, 0, 0))
	_sq(st2, "1:0", "infantry", 1, _line(5, 0, 15000))
	_do(st2, {"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 6, 6]})
	_do(st2, {"a": "rr", "u": "0:0", "t": "1:0", "v": 1})
	assert_eq([st2.seat(0).cp, st2.pend[0].rr, st2.pend[0].hits], [2, false, 5], "no failed die: the CP is spent anyway, nothing changes (page)")
	st2.pend[0].tr = true
	st2.used.clear()
	_do(st2, {"a": "rr", "u": "0:0", "t": "1:0", "v": 1})
	assert_eq(st2.seat(0).cp, 1, "torrent: the handler spends the CP, apply_reroll then refuses (tr)")
	st2.pend[0].tr = false
	st2.used.clear()
	st2.seat(0).cp = 0
	_do(st2, {"a": "rr", "u": "0:0", "t": "1:0", "v": 1})
	assert_eq([st2.seat(0).cp, st2.pend[0].rr], [0, false], "no CP: nothing")
	st2.seat(0).cp = 1
	st2.pend[0].stage = BattleState.S_SAVE
	_do(st2, {"a": "rr", "u": "0:0", "t": "1:0", "v": 1})
	assert_eq(st2.seat(0).cp, 1, "not at stage wound: no CP")
	assert_true(a != null and s != null, "squads built")


func test_apply_shock_rez() -> void:
	var st := _st(BattleState.PH_CMD)
	var s := _sq(st, "0:0", "infantry", 0, _line(2, 0, 0))
	_sq(st, "1:0", "infantry", 1, _line(2, 0, 30000))
	for i: int in 2:
		var p := BattleState.Pend.new()
		p.kind = BattleState.K_SHOCK
		p.stage = BattleState.S_SHOCK
		p.u = s.id
		p.att = 0
		p.need = 7
		BtPend.push(st, p)
	_do(st, {"a": "shock", "u": "0:0", "roll": [1, 1], "brave": 0})
	assert_eq([s.shaken, st.pend.size(), st.seat(0).cp], [true, 1, 3], "shock: the roll fails, no CP")
	s.shaken = false
	_do(st, {"a": "shock", "u": "0:0", "roll": [], "brave": 1})
	assert_eq([s.shaken, st.pend.size(), st.seat(0).cp], [false, 0, 2], "brave: CP spent, passes without dice")
	_do(st, {"a": "shock", "u": "0:0", "roll": [1, 1], "brave": 0})
	assert_false(s.shaken, "no shock entry: nothing")
	var r := _sq(st, "0:1", "rwar", 0, _line(10, -20000, 6000))
	st.remove_unit(r.models[9])
	st.remove_unit(r.models[8])
	var z := BattleState.Pend.new()
	z.kind = BattleState.K_REZ
	z.stage = BattleState.S_REZ
	z.u = r.id
	z.att = 0
	z.need = 5
	z.n = 2
	BtPend.push(st, z)
	_do(st, {"a": "rez", "u": "0:1", "roll": [5, 1]})
	assert_eq([st.squad_alive(r), st.pend.size()], [9, 0], "rez: one 5+ brings one back")


func test_apply_charge_codes() -> void:
	var st := _st(BattleState.PH_CHARGE, 0)
	var s := _sq(st, "0:0", "hoplite", 0, _line(2, 0, 0))
	var t := _sq(st, "1:0", "infantry", 1, _line(2, 0, 6000))
	s.ch_done = true
	_do(st, {"a": "chg", "u": "0:0", "t": "1:0"})
	assert_eq(st.pend.size(), 0, "chg from a squad that is ch_done: ignored")
	s.ch_done = false
	var far := _sq(st, "1:1", "infantry", 1, _line(1, 0, 50000))
	_do(st, {"a": "chg", "u": "0:0", "t": "1:1"})
	assert_eq([st.pend.size(), s.ch_done], [1, true], "chg is declared without a why-not on receive (40\" away)")
	st.pend.clear()
	s.ch_done = false
	_do(st, {"a": "chg", "u": "0:0", "t": "1:0"})
	var p := st.pend[0]
	assert_eq(p.stage, BattleState.S_CHARGE, "no CP for overwatch: straight to the charge roll")
	_do(st, {"a": "cmove", "u": "0:0", "t": "1:0", "to": [[0, 4000], [1700, 4000]]})
	assert_eq(_pos(s), [[0, 0], [1700, 0]], "cmove before the roll succeeds: ignored")
	_do(st, {"a": "chr", "u": "0:0", "t": "", "roll": [6, 6], "rr": 0, "keep": 0})
	assert_eq(p.stage, BattleState.S_CHARGE, "chr with t '': no entry")
	_do(st, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [1, 1], "rr": 0, "keep": 0})
	assert_eq([st.pend.size(), p.stage], [0, BattleState.S_DONE], "chr fails and the team has no CP to re-roll: done")
	# with CP: chrr, then keep or re-roll
	for i: int in 2:
		st.seat(i).cp = 2
	s.ch_done = false
	_do(st, {"a": "chg", "u": "0:0", "t": "1:0"})
	var o := st.pend[0]
	assert_eq(o.stage, BattleState.S_OW, "the target has CP and a gun in range: overwatch is offered")
	_do(st, {"a": "ow", "u": "0:0", "t": "1:0", "use": 1})
	assert_eq([st.pend.size(), st.pend[0].kind, st.pend[0].ow, st.pend[1] == o, st.seat(1).cp, o.stage],
		[2, BattleState.K_ATK, true, true, 1, BattleState.S_OWATK], "ow use 1: CP spent, the overwatch attack sits before the charge")
	_do(st, {"a": "atk", "u": "1:0", "t": "0:0", "how": "ow", "hit": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]})
	assert_eq(st.pend.size(), 1, "the overwatch misses")
	_do(st, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [1, 1], "rr": 0, "keep": 0})
	assert_eq(o.stage, BattleState.S_CHRR, "chr promotes owatk (chg_ready) and the failed roll waits for a re-roll choice")
	var cp0 := st.seat(0).cp
	_do(st, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [6, 6], "rr": 1, "keep": 0})
	assert_eq([o.stage, st.seat(0).cp], [BattleState.S_MOVE, cp0 - 1], "chr rr at chrr: CP spent and the charge re-rolled")
	_do(st, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [6, 6], "rr": 1, "keep": 0})
	assert_eq(st.seat(0).cp, cp0 - 1, "chr rr past chrr: nothing, no CP")
	_do(st, {"a": "cmove", "u": "0:0", "t": "1:0", "to": [[0, 4500], [1700, 4500]]})
	assert_eq([_pos(s), s.charged, s.ch_tgt, st.pend.size()], [[[0, 4500], [1700, 4500]], true, "1:0", 0], "cmove at stage move: in")
	# keep
	var st2 := _st(BattleState.PH_CHARGE, 1)
	var a := _sq(st2, "0:0", "hoplite", 0, _line(1, 0, 0))
	_sq(st2, "1:0", "hoplite", 1, _line(1, 0, 9000))
	_do(st2, {"a": "chg", "u": "0:0", "t": "1:0"})
	_do(st2, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [1, 1], "rr": 0, "keep": 0})
	assert_eq(st2.pend[0].stage, BattleState.S_CHRR, "fail with CP: chrr")
	_do(st2, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [1, 1], "rr": 0, "keep": 1})
	assert_eq([st2.pend.size(), st2.seat(0).cp, _logged(st2, "chg_fail")], [0, 1, 1], "keep: the charge fails, no CP")
	# a plain chr (rr 0, keep 0) at chrr is applied as a roll (the receiver trusts the sender, page applyCharge)
	a.ch_done = false
	_do(st2, {"a": "chg", "u": "0:0", "t": "1:0"})
	_do(st2, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [1, 1], "rr": 0, "keep": 0})
	var w := st2.pend[0]
	_do(st2, {"a": "chr", "u": "0:0", "t": "1:0", "roll": [6, 6], "rr": 0, "keep": 0})
	assert_eq([w.stage, st2.seat(0).cp], [BattleState.S_MOVE, 1], "plain chr at chrr: rolled again without CP (page parity)")
	assert_true(a != null and t != null and far != null, "squads built")


func test_apply_gren_heal() -> void:
	var st := _st(BattleState.PH_SHOOT, 0)
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	var t := _sq(st, "1:0", "heavy", 1, _line(3, 0, 6000))
	_do(st, {"a": "gren", "u": "0:0", "t": "1:0", "roll": [6, 6, 6, 6, 6, 6]})
	assert_eq([s.shot, st.squad_alive(t)], [false, 3], "gren without CP: the whole act is ignored")
	st.seat(0).cp = 1
	_do(st, {"a": "gren", "u": "0:0", "t": "1:0", "roll": [4, 4, 4, 1, 1, 1]})
	assert_eq([s.shot, st.squad_alive(t), st.seat(0).cp], [true, 2, 0], "gren with CP: spent, three mortal wounds spill")
	var med := _sq(st, "1:1", "medic", 1, _line(1, 10000, 6000))
	_do(st, {"a": "heal", "u": "1:1", "t": "1:0", "roll": 3})
	assert_eq([med.shot, t.models[0].hp], [true, 2], "heal: no can-heal check on receive, a 3 heals")
	_do(st, {"a": "heal", "u": "1:1", "t": "1:0"})
	assert_eq(st.squad_alive(t), 2, "heal without a roll is a 1 (fails), never a draw")
	_do(st, {"a": "heal", "u": "1:1", "t": "9:9", "roll": 6})
	assert_eq(st.squad_alive(t), 2, "heal on an unknown squad: nothing")


func test_apply_done_endph_legacy() -> void:
	var st := _st(BattleState.PH_MOVE)
	st.add_seat(0, "L2", false, false, "")
	_sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	_sq(st, "1:0", "infantry", 1, _line(1, 0, 30000))
	_do(st, {"a": "done", "ph": "move", "pid": "nobody"})
	_do(st, {"a": "done", "ph": "move", "pid": 0})
	assert_false(st.seat(0).done, "done with an unknown or non-string pid: nothing")
	_do(st, {"a": "done", "ph": "shoot", "pid": "L0"})
	assert_false(st.seat(0).done, "done for another phase: nothing")
	_do(st, {"a": "done", "ph": "move", "pid": "L0"})
	assert_eq([st.seat(0).done, st.phase], [true, BattleState.PH_MOVE], "one of two humans done: the phase waits")
	_do(st, {"a": "done", "ph": "", "pid": "L2"})
	assert_eq(st.phase, BattleState.PH_SHOOT, "the team's last human done (ph ''): next phase")
	_do(st, {"a": "endph", "ph": "move"})
	assert_eq(st.phase, BattleState.PH_SHOOT, "endph for another phase: nothing")
	_do(st, {"a": "endph", "ph": "shoot"})
	assert_eq(st.phase, BattleState.PH_CHARGE, "endph of the phase: next phase")
	_do(st, {"a": "endturn"})
	assert_eq(st.phase, BattleState.PH_FIGHT, "legacy endturn outside cmd/fight: next phase")
	_do(st, {"a": "endturn"})
	assert_eq(st.phase, BattleState.PH_FIGHT, "legacy endturn in fight: nothing")
	st.phase = BattleState.PH_CMD
	_do(st, {"a": "endturn"})
	assert_eq([st.phase, st.turn], [BattleState.PH_CMD, 0], "legacy endturn in cmd: nothing")
	_do(st, {"a": "endph", "ph": ""})
	assert_eq([st.turn, st.phase], [1, BattleState.PH_CMD], "endph '' in cmd ends the turn (page parity)")
	var d0 := st.digest()
	_do(st, {"a": "move", "u": "0:0", "x": 1000, "z": 1000})
	_do(st, {"a": "nosuch", "u": "0:0"})
	assert_eq(st.digest(), d0, "legacy move and an unknown code change nothing")


func test_apply_after_over() -> void:
	var st := _st(BattleState.PH_MOVE)
	var s := _sq(st, "0:0", "infantry", 0, _line(1, 0, 0))
	_sq(st, "1:0", "infantry", 1, [])
	_do(st, {"a": "stay", "u": "0:0"})
	assert_true(st.over and st.winner == 0, "apply ends with check_over: one team left is the winner")
	assert_true(s.moved, "acts after over are still applied (page)")
	st.seat(0).cp = 3
	var t := _sq(st, "1:1", "heavy", 1, _line(1, 0, 6000))
	_do(st, {"a": "gren", "u": "0:0", "t": "1:1", "roll": [6, 6, 6, 6, 6, 6]})
	assert_eq([st.seat(0).cp, st.squad_alive(t)], [3, 1], "but no stratagem can be used after over")


## A fixed sequence of hand acts on one state: the dispatcher's digest is pinned.
func test_apply_digest_pinned() -> void:
	var a := _apply_digest()
	assert_eq(a, _apply_digest(), "the dispatcher is deterministic")
	assert_digest(a, PINNED_APPLY, "BtActs.apply digest of the fixed act sequence is pinned")


const PINNED_APPLY := "2220fc2a22dc73dd"


func _apply_digest() -> String:
	var st := _st(BattleState.PH_MOVE, 2)
	_sq(st, "0:0", "infantry", 0, _line(5, -4000, -8000))
	_sq(st, "0:1", "hoplite", 0, _line(5, -4000, -11000))
	_sq(st, "1:0", "infantry", 1, _line(5, -4000, 8000))
	_sq(st, "1:1", "heavy", 1, _line(3, 6000, 9000))
	var acts: Array = [
		{"a": "smove", "u": "0:0", "how": "move", "x": -2000, "z": -3000},
		{"a": "smove", "u": "0:1", "how": "adv", "to": [[-4000, -6000], [-2300, -6000], [-600, -6000], [1100, -6000], [2800, -6000]]},
		{"a": "endph", "ph": "move"},
		{"a": "atk", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [1, 2, 3, 4, 5]},
		{"a": "rr", "u": "0:0", "t": "1:0", "v": 6},
		{"a": "wnd", "u": "0:0", "t": "1:0", "wound": [6, 5, 4]},
		{"a": "sav", "u": "0:0", "t": "1:0", "save": [1, 2, 3], "gtg": 1},
		{"a": "endph", "ph": "shoot"},
		{"a": "chg", "u": "0:1", "t": "1:0"},
		{"a": "ow", "u": "0:1", "t": "1:0", "use": 1},
	]
	for a: Variant in acts:
		var act: Dictionary = a
		_do(st, BtActs.sanitize(act))
	return st.digest()
