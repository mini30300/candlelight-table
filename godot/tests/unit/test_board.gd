extends "res://tests/testing.gd"
## core/battle/board.gd (BtBoard, R1_PORT_SPEC §1.14 and §5) against the page and by hand.
## Page samples: fixtures/board/page_samples.json (tools/record_board_acts.js runs the page's own boardState() and what
## it calls in Chromium over worlds of MI ints; a live check proved the cut code equals BT.board()):
## - every world: to_json(board(st, false)) equals the page's JSON.stringify(boardState()) byte for byte (the rules
##   version is the one field set to the page's 9 first: v10 says 10), and the fields equal the parsed page board;
##   the two "ties" worlds put squad centres exactly on a toFixed(1) half step, where the page's double mean and the
##   port's js_round centre may print neighbouring tenths (D6, D7): those squads' x/z may differ by one tenth, counted;
## - raw = true carries MI (models exact, centres = BtSquads.center, objectives exact), the rest equal to raw = false;
## - tenths equals +(mi/1000).toFixed(1) for a sweep of -2.6..2.6 inches and the x.x5 steps up to 180 inches;
## - to_json escapes strings like JSON.stringify and prints 40 oracle boards (board0 and the last board of each
##   recording) byte for byte.
## Hand cases: key order, dead models and squads absent, engaged, objective owners, kill goal, cp per seat, rounds,
## board() reads only, and a pinned digest.

const FIX := "res://tests/unit/fixtures/board/page_samples.json"
## Digests of the fixed scenario in _digest_scenario (JSON text, raw positions); change only on purpose.
const PINNED_DIGEST := "91a41dc59d48136a:1a00b411f5b01793"
const TOP_KEYS := ["v", "turn", "round", "phase", "over", "vp", "goal", "rounds", "cp", "obj", "squads", "units"]
const OBJ_KEYS := ["n", "x", "z", "owner"]
const SQUAD_KEYS := ["id", "pl", "team", "k", "n", "n0", "x", "z", "moved", "adv", "fell", "shot", "chDone", "charged",
	"shaken", "engaged"]
const UNIT_KEYS := ["id", "sq", "pl", "team", "k", "hp", "x", "z"]
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


## a parsed page board (inches as floats) in BtBoard's raw = false form: x/z as tenths, other numbers as ints
func _tenths_form(v: Variant, key: String) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return roundi(f * 10.0) if key == "x" or key == "z" else int(f)
		TYPE_INT:
			return int(v) * 10 if key == "x" or key == "z" else v
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_tenths_form(x, ""))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _tenths_form(v[k], str(k))
			return d
	return v


func _page_board(js: String) -> Dictionary:
	var p: Variant = JSON.parse_string(js)
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	return _tenths_form(p, "")


## a fixture world as a BattleState: seats [team, cp or -1], squads [id, k, side, pl, n0, flag bits, -], models
## [id, sq, hp, x, z, -] in units order, objectives [n, x, z]
func _world(w: Dictionary) -> BattleState:
	var st := BattleState.make({"seed": 1, "w": 120, "teams": int(w["teams"]), "goal": str(w["goal"]),
		"rounds": int(w["rounds"]), "freeFire": bool(w["ff"])})
	var k := 0
	for sv: Variant in w["seats"]:
		var p := st.add_seat(int(sv[0]), "", false, false, "P%d" % k)
		p.cp = maxi(0, int(sv[1]))
		k += 1
	st.turn = int(w["turn"])
	st.round_no = int(w["round"])
	st.phase = BattleState.PHASES.find(str(w["phase"]))
	st.over = bool(w["over"])
	var vp: Array = w["vp"]
	for t: int in vp.size():
		st.vp[t] = int(vp[t])
	for rv: Variant in w["squads"]:
		var r: Array = rv
		var s := st.add_squad(str(r[0]), str(r[1]), int(r[2]), int(r[3]), int(r[4]), 0)
		var bits: int = r[5]
		s.moved = (bits & 1) != 0
		s.adv = (bits & 2) != 0
		s.fell = (bits & 4) != 0
		s.shot = (bits & 8) != 0
		s.ch_done = (bits & 16) != 0
		s.charged = (bits & 32) != 0
		s.shaken = (bits & 64) != 0
	for rv: Variant in w["units"]:
		var r: Array = rv
		st.add_unit(str(r[0]), st.squad(str(r[1])), int(r[2]), int(r[3]), int(r[4]))
	for rv: Variant in w["objs"]:
		var r: Array = rv
		st.add_obj(int(r[0]), int(r[1]), int(r[2]))
	return st


## the board with the page's rules version (the one field v10 changes on purpose)
func _as_page(b: Dictionary) -> Dictionary:
	var c := b.duplicate(true)
	c["v"] = int(F["page"]["rules_v"])
	return c


## a type key with this oc (and, when r > 0, this base radius in MI), not hidden
func _type_with(oc: int, r: int = 0) -> String:
	for t: Dictionary in GameData.types():
		var k := str(t["k"])
		if int(t.get("oc", -1)) == oc and not GameData.is_hidden(k) and (r == 0 or BtSquads.radius_of(GameData.index_of(k)) == r):
			return k
	return ""


# ---------------------------------------------------------------- page samples
func test_fixture_loaded() -> void:
	for k: String in ["page", "flags", "live_check", "tenths", "strings", "worlds", "oracle"]:
		assert_true(F.has(k), "fixture has " + k)
	assert_eq(F["flags"], ["moved", "adv", "fell", "shot", "chDone", "charged", "shaken"], "the flag bit order the worlds use")
	var live_ok := true
	for c: Variant in F["live_check"]:
		live_ok = live_ok and bool(c["same"])
	assert_true(live_ok and (F["live_check"] as Array).size() >= 3, "the recorder's cut boardState equalled the live page's BT.board()")


func test_worlds_match_page() -> void:
	var exact := 0
	var tie_worlds := 0
	var tie_diff := 0
	var tie_same := 0
	var engaged := 0
	var owned := 0
	var bad: Array = []
	for wv: Variant in F["worlds"]:
		var w: Dictionary = wv
		var st := _world(w)
		var b := BtBoard.board(st, false)
		var page := _page_board(str(w["json"]))
		if page.is_empty():
			bad.append([w["name"], "page json"])
			continue
		if b["v"] != Version.RULES_V:
			bad.append([w["name"], "v", b["v"]])
		var mine := _as_page(b)
		var ties: Array = w["tie"]
		if ties.is_empty():
			if BtBoard.to_json(mine) != str(w["json"]):
				bad.append([w["name"], BtBoard.to_json(mine).left(300), str(w["json"]).left(300)])
			elif mine != page:
				bad.append([w["name"], "fields"])
			else:
				exact += 1
		else:
			tie_worlds += 1
			# everything but the listed squads' centres exactly, those within one tenth
			var ms: Array = mine["squads"]
			var ps: Array = page["squads"]
			if ms.size() != ps.size():
				bad.append([w["name"], "squad count"])
				continue
			for i: int in ms.size():
				var a: Dictionary = ms[i]
				var q: Dictionary = ps[i]
				if ties.has(a["id"]):
					for ax: String in ["x", "z"]:
						var dv := absi(int(a[ax]) - int(q[ax]))
						if dv > 1:
							bad.append([w["name"], a["id"], ax, a[ax], q[ax]])
						elif dv == 1:
							tie_diff += 1
						else:
							tie_same += 1
					a["x"] = q["x"]
					a["z"] = q["z"]
			if mine != page:
				bad.append([w["name"], "fields beyond the tie centres"])
		for s: Variant in b["squads"]:
			engaged += 1 if bool(s["engaged"]) else 0
		for o: Variant in b["obj"]:
			owned += 1 if int(o["owner"]) >= 0 else 0
	assert_true(exact >= 35, "%d worlds byte-equal to the page's JSON.stringify(boardState())" % exact)
	assert_eq(tie_worlds, 2, "two worlds with centres on a half step")
	assert_true(tie_diff >= 8 and tie_diff + tie_same >= 20,
		"tie centres: %d axes print the same tenth, %d the neighbouring one (D6, D7: the js_round centre, not the double mean)" % [tie_same, tie_diff])
	assert_true(engaged >= 40 and owned >= 25, "the worlds cover engaged squads (%d) and held objectives (%d)" % [engaged, owned])
	assert_true(bad.is_empty(), "board/to_json equal the page's boardState() in every world", bad.slice(0, 4))


func test_raw_board_carries_mi() -> void:
	var bad: Array = []
	var n := 0
	for wv: Variant in F["worlds"]:
		var w: Dictionary = wv
		var st := _world(w)
		var b := BtBoard.board(st, false)
		var r := BtBoard.board(st, true)
		var us: Array = r["units"]
		for i: int in us.size():
			var u: Dictionary = us[i]
			var m := st.units[i]
			n += 1
			if int(u["x"]) != m.x or int(u["z"]) != m.z or int(b["units"][i]["x"]) != BtBoard.tenths(m.x):
				bad.append([w["name"], u["id"], u["x"], m.x])
		var alive := st.alive_squads()
		for i: int in alive.size():
			var c := BtSquads.center(alive[i])
			if int(r["squads"][i]["x"]) != c[0] or int(r["squads"][i]["z"]) != c[1]:
				bad.append([w["name"], alive[i].id, "centre"])
		for i: int in st.objs.size():
			if int(r["obj"][i]["x"]) != st.objs[i].x or int(r["obj"][i]["z"]) != st.objs[i].z:
				bad.append([w["name"], "obj", i])
		# the rest is the same as the tenths form
		for part: String in ["obj", "squads", "units"]:
			var pr: Array = r[part]
			var pb: Array = b[part]
			for i: int in pr.size():
				var x: Dictionary = (pr[i] as Dictionary).duplicate()
				x["x"] = pb[i]["x"]
				x["z"] = pb[i]["z"]
				if x != pb[i]:
					bad.append([w["name"], part, i])
		for k: String in ["v", "turn", "round", "phase", "over", "vp", "goal", "rounds", "cp"]:
			if r[k] != b[k]:
				bad.append([w["name"], k])
	assert_true(n >= 300, "%d models checked" % n)
	assert_true(bad.is_empty(), "raw = true: models and objectives in MI, centres = BtSquads.center, other fields as raw = false", bad.slice(0, 4))


func test_tenths_match_page() -> void:
	var tf: Dictionary = F["tenths"]
	var want: PackedStringArray = str(tf["t"]).split(",")
	var from: int = tf["from"]
	assert_eq(want.size(), int(tf["to"]) - from + 1, "the sweep is complete")
	var bad: Array = []
	for i: int in want.size():
		if BtBoard.tenths(from + i) != want[i].to_int() and bad.size() < 5:
			bad.append([from + i, want[i], BtBoard.tenths(from + i)])
	var extra: Array = tf["extra"]
	for e: Variant in extra:
		if BtBoard.tenths(int(e[0])) != int(e[1]) and bad.size() < 10:
			bad.append([e[0], e[1], BtBoard.tenths(int(e[0]))])
	assert_true(extra.size() >= 250, "%d x.x5 steps up to 180 inches" % extra.size())
	assert_true(bad.is_empty(), "tenths(mi) = +(mi/1000).toFixed(1) x 10 for -2600..2600 MI and the extra steps [mi, page, port]", bad)


func test_strings_like_json_stringify() -> void:
	var bad: Array = []
	for sv: Variant in F["strings"]:
		var s := str(sv[0])
		var got := BtBoard.to_json({"k": s})
		if got != "{\"k\":" + str(sv[1]) + "}":
			bad.append([s, got, sv[1]])
	assert_true((F["strings"] as Array).size() >= 10, "awkward strings sampled")
	assert_true(bad.is_empty(), "to_json escapes strings exactly like JSON.stringify (quotes, backslash, controls; Thai and emoji raw)", bad)


func test_oracle_boards_to_json() -> void:
	var bad: Array = []
	var n := 0
	var units := 0
	for ov: Variant in F["oracle"]:
		var js := str(ov["json"])
		var b := _page_board(js)
		n += 1
		units += (b["units"] as Array).size()
		if BtBoard.to_json(b) != js:
			bad.append([ov["scenario"], ov["which"], BtBoard.to_json(b).left(200), js.left(200)])
		if b.keys() != TOP_KEYS:
			bad.append([ov["scenario"], ov["which"], "top keys", b.keys()])
	assert_eq(n, 40, "board0 and the last board of the 20 recordings")
	assert_true(units >= 900, "%d models printed" % units)
	assert_true(bad.is_empty(), "to_json prints the oracle boards byte for byte as the page did", bad.slice(0, 3))


# ---------------------------------------------------------------- hand cases
## two teams: A (team 0, two models) 0.95 inch from B (team 1): engaged; C (team 1) wiped out; D (team 0, shaken)
## lost one of two models. Objectives: by A (team 0 holds), between A and B with equal OC (tie), far away (nobody)
func _hand() -> BattleState:
	var k := _type_with(2, 800)
	var st := BattleState.make({"seed": 3, "w": 60, "teams": 2, "rounds": 4})
	var p0 := st.add_seat(0, "A", false, false, "one")
	var p1 := st.add_seat(1, "", true, false, "two")
	var p2 := st.add_seat(0, "", true, false, "three")
	p0.cp = 2
	p1.cp = 0
	p2.cp = 5
	st.turn = 1
	st.round_no = 3
	st.phase = BattleState.PH_CHARGE
	st.vp[0] = 10
	st.vp[1] = 5
	var a := st.add_squad("0:0", k, 0, 0, 3, 0)
	var b := st.add_squad("1:0", k, 1, 1, 2, 0)
	var c := st.add_squad("1:1", k, 1, 1, 1, 0)
	var d := st.add_squad("2:0", k, 0, 2, 2, 0)
	st.add_unit("0:0.0", a, 1, -1050, 0)
	st.add_unit("1:0.0", b, 2, 1500, 0)
	st.add_unit("0:0.1", a, 2, -1150, -49)
	st.add_unit("1:1.0", c, 1, 30000, 5000)
	st.add_unit("2:0.0", d, 1, -20000, 15000)
	st.add_unit("2:0.1", d, 1, -21000, 15000)
	st.add_unit("1:0.1", b, 1, 1500, 1000)
	a.moved = true
	b.charged = true
	d.shaken = true
	# C dies, D loses a model
	st.remove_unit(st.unit("1:1.0"))
	st.remove_unit(st.unit("2:0.1"))
	st.add_obj(1, -4000, 0)
	st.add_obj(2, 250, 0)
	st.add_obj(3, 40000, -40000)
	return st


func test_hand_board() -> void:
	var st := _hand()
	var before := st.digest()
	var b := BtBoard.board(st, false)
	assert_eq(st.digest(), before, "board() only reads the state")
	assert_eq(b.keys(), TOP_KEYS, "top-level keys in the page's order")
	assert_eq([b["v"], b["turn"], b["round"], b["phase"], b["over"], b["goal"], b["rounds"]],
		[Version.RULES_V, 1, 3, "charge", false, "obj", 4], "v (rules version 10), turn, round, phase name, over, goal, rounds")
	assert_eq(b["vp"], [10, 5], "vp per team")
	assert_eq(b["cp"], [2, 0, 5], "cp per seat in seat order")
	var sq: Array = b["squads"]
	var ids: Array = []
	for s: Variant in sq:
		ids.append(s["id"])
		assert_eq((s as Dictionary).keys(), SQUAD_KEYS, "squad %s keys in the page's order" % s["id"])
	assert_eq(ids, ["0:0", "1:0", "2:0"], "living squads in creation order (the wiped-out one is gone)")
	assert_eq([sq[0]["n"], sq[0]["n0"], sq[2]["n"], sq[2]["n0"]], [2, 3, 1, 2], "n = living models, n0 = the starting count")
	assert_eq([sq[0]["x"], sq[0]["z"]], [-11, 0], "centre of A: (-1100, -24.5 -> -24) MI to tenths: -1.1 and -0.0 -> 0")
	assert_eq([sq[0]["moved"], sq[1]["charged"], sq[2]["shaken"], sq[0]["shot"]], [true, true, true, false], "flags")
	assert_eq([sq[0]["engaged"], sq[1]["engaged"], sq[2]["engaged"]], [true, true, false], "A and B engaged, D alone")
	var us: Array = b["units"]
	var uids: Array = []
	for u: Variant in us:
		uids.append(u["id"])
		assert_eq((u as Dictionary).keys(), UNIT_KEYS, "unit %s keys in the page's order" % u["id"])
	assert_eq(uids, ["0:0.0", "1:0.0", "0:0.1", "2:0.0", "1:0.1"], "living models in units order (dead ones gone)")
	assert_eq([us[0]["x"], us[0]["z"], us[2]["x"], us[2]["z"]], [-11, 0, -11, 0], "-1.05 -> -1.1, -1.15 -> -1.1, -0.049 -> 0")
	assert_eq([us[1]["k"], us[1]["hp"], us[1]["pl"], us[1]["team"], us[1]["sq"]], [st.unit("1:0.0").t, 2, 1, 1, "1:0"], "unit fields")
	var ob: Array = b["obj"]
	assert_eq((ob[0] as Dictionary).keys(), OBJ_KEYS, "objective keys in the page's order")
	assert_eq([ob[0]["owner"], ob[1]["owner"], ob[2]["owner"]], [0, -1, -1], "owners: held, tied, nobody")
	assert_eq([ob[1]["x"], ob[2]["x"], ob[2]["z"]], [3, 400, -400], "0.25 -> 0.3 (exact binary tie rounds up), 40 inches")
	# the shaken squad's model stands on objective 3 now: it still holds nothing
	st.unit("2:0.0").x = 40000
	st.unit("2:0.0").z = -40000
	assert_eq(int(BtBoard.board(st, false)["obj"][2]["owner"]), -1, "a shaken squad does not hold an objective")
	st.squad("2:0").shaken = false
	assert_eq(int(BtBoard.board(st, false)["obj"][2]["owner"]), 0, "once steady it does")
	st.over = true
	st.phase = 99
	var b2 := BtBoard.board(st, false)
	assert_eq([b2["over"], b2["phase"]], [true, ""], "over, and an unknown phase prints as an empty name")


func test_kill_goal_and_rounds() -> void:
	var st := BattleState.make({"seed": 1, "w": 48, "goal": "kill", "rounds": 7})
	var b := BtBoard.board(st, false)
	assert_eq([b["goal"], b["rounds"], b["obj"], b["squads"], b["units"], b["cp"]], ["kill", 30, [], [], [], []],
		"kill: 30 rounds, no objectives; an empty match gives empty lists")
	assert_eq(BtBoard.to_json(b), "{\"v\":%d,\"turn\":0,\"round\":1,\"phase\":\"cmd\",\"over\":false,\"vp\":[0,0],\"goal\":\"kill\",\"rounds\":30,\"cp\":[],\"obj\":[],\"squads\":[],\"units\":[]}" % Version.RULES_V,
		"the JSON of an empty kill board")
	for pair: Array in [[0, 5], [2, 3], [3, 3], [7, 7], [10, 10], [12, 10]]:
		var s2 := BattleState.make({"seed": 1, "rounds": int(pair[0])})
		assert_eq(int(BtBoard.board(s2, false)["rounds"]), int(pair[1]), "rounds %d -> %d (the page's clamp(rounds || 5, 3, 10))" % pair)


func test_tenths_examples() -> void:
	var cases := [[0, 0], [1, 0], [-1, 0], [49, 0], [-49, 0], [50, 1], [-50, -1], [250, 3], [-250, -3], [350, 3],
		[-350, -3], [1050, 11], [-1050, -11], [1150, 11], [-1150, -11], [999, 10], [-999, -10], [12345, 123], [89999, 900],
		[-89950, -900], [180000, 1800]]
	for c: Array in cases:
		assert_eq(BtBoard.tenths(int(c[0])), int(c[1]), "tenths(%d) = %d" % c)


func test_to_json_numbers_and_shapes() -> void:
	assert_eq(BtBoard.to_json({"x": 120, "z": 123}), "{\"x\":12,\"z\":12.3}", "a whole number of inches has no point")
	assert_eq(BtBoard.to_json({"x": -5, "z": 5}), "{\"x\":-0.5,\"z\":0.5}", "the leading zero stays")
	assert_eq(BtBoard.to_json({"x": 0, "z": -120}), "{\"x\":0,\"z\":-12}", "zero and negative whole inches")
	assert_eq(BtBoard.to_json({"n": 120, "hp": -3, "owner": -1}), "{\"n\":120,\"hp\":-3,\"owner\":-1}", "other keys print plain ints")
	assert_eq(BtBoard.to_json({"a": [], "b": {}, "c": [true, false], "d": [[1, 2]]}), "{\"a\":[],\"b\":{},\"c\":[true,false],\"d\":[[1,2]]}",
		"empty containers, bools, nested arrays")
	assert_eq(BtBoard.to_json({"units": [{"x": 15, "z": -15}]}), "{\"units\":[{\"x\":1.5,\"z\":-1.5}]}", "x/z inside lists")
	assert_eq(BtBoard.to_json({"vp": PackedInt64Array([3, 4])}), "{\"vp\":[3,4]}", "packed int arrays print as arrays")
	assert_eq(BtBoard.to_json({"k": "a\"b\\c\n\t\u0001"}), "{\"k\":\"a\\\"b\\\\c\\n\\t\\u0001\"}", "escapes")


func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the board digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtBoard scenario digest is pinned")


## the hand state's board as JSON text, then the raw board's positions, each folded into FNV-1a 64
func _digest_scenario() -> String:
	var st := _hand()
	var js := BtBoard.to_json(BtBoard.board(st, false))
	var r := BtBoard.board(st, true)
	var v := PackedInt64Array()
	for part: String in ["obj", "squads", "units"]:
		for e: Variant in r[part]:
			v.append(int(e["x"]))
			v.append(int(e["z"]))
	return Hash.hex64(Hash.fnv1a64_str(js)) + ":" + Hash.digest_hex(v)
