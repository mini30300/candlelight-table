extends "res://tests/testing.gd"
## Oracle replay (R1_PORT_SPEC §5–§6): build each recorded page game in the v10 core, replay the page's acts and
## compare the board after every act with the page's board (tests/oracle/*.json.gz, made by tools/record_oracle.js).
##
## Until class Battle exists (wave 5) the replay is skipped with a SKIP line; the loader, the fixtures (props through
## BtBlocking.prep_one with page_hash.gd building depths, seats through BtArmy.fit_list/fac_of, objectives, units0) and
## the act conversion are still checked on every recording, so the harness is ready when Battle lands.
##
## Which recordings are replayed: env ORACLE unset = the 3 with the fewest acts (quick run); ORACLE=all = every one
## (`bash godot/tests/run.sh full`); ORACLE=<word> = the ones whose name contains it.
## Differences are accepted only through tests/oracle/allowlist.json: [{scenario, act: int|"*", path, reason}], the reason
## naming an item of R1_PORT_SPEC §7 ("§7 #2 …"). path is like "units[3].x" or "squads[*].engaged" (* = anything;
## "squads.*.engaged" works too); act -1 is board0 (the deployment, before any act).

const PageHash := preload("res://tests/oracle/page_hash.gd")
const DIR := "res://tests/oracle"
const ALLOWLIST := "res://tests/oracle/allowlist.json"
## |port MI - page tenths x 100| for units and squad centres: 50 for the page's toFixed(1) + 10 for the v10 grid (D7)
const POS_TOL := 60
## objectives are injected exactly: only the page's rounding
const OBJ_TOL := 51
## the deployment points are rounded to 0.01" (§7 #14): at most 5 MI from the page's double
const DEP_TOL := 5
const QUICK_N := 3
## the act codes the page sends (§4)
const CODES := ["smove", "stay", "skip", "adv", "atk", "wnd", "sav", "rr", "shoot", "shock", "rez", "chg", "ow", "chr",
	"cmove", "gren", "heal", "done", "endph"]
## top-level keys whose numbers stay as JSON gave them: raw doubles the fixture rounds itself, and the bulky boards and
## log (the compare normalises numbers itself, so intifying them would only cost time)
const RAW_KEYS := ["props", "deps", "obj", "units0", "acts", "scenario_def", "boards", "log"]
const FLAGS := ["moved", "adv", "fell", "shot", "chDone", "charged", "shaken", "engaged"]

static var _cls_cache: Dictionary = {}

var _files: PackedStringArray = PackedStringArray()
var _recs: Dictionary = {}
var _allow: Array = []


func setup() -> void:
	_files = recordings()
	var f := FileAccess.open(ALLOWLIST, FileAccess.READ)
	if f != null:
		var v: Variant = JSON.parse_string(f.get_as_text())
		if typeof(v) == TYPE_ARRAY:
			_allow = v


# ---------------------------------------------------------------- loader
## Every recording in tests/oracle, sorted by name.
static func recordings() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".json.gz"):
			out.append(DIR + "/" + f)
	out.sort()
	return out


## A recording: gunzip, JSON, then integers for everything but the raw doubles of RAW_KEYS ({} when unreadable).
static func read_rec(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {}
	var text := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	var v: Variant = JSON.parse_string(text)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var rec: Dictionary = v
	for k: Variant in rec.keys():
		if not RAW_KEYS.has(str(k)):
			rec[k] = intify(rec[k])
	return rec


## Integral floats become ints (recursively); other floats (board positions with one decimal) stay floats.
static func intify(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if f == floor(f) and absf(f) < 9.0e15 else f
		TYPE_ARRAY:
			var arr: Array = v
			var out: Array = []
			for x: Variant in arr:
				out.append(intify(x))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var o := {}
			for k: Variant in d:
				o[k] = intify(d[k])
			return o
	return v


func _rec(path: String) -> Dictionary:
	if not _recs.has(path):
		_recs[path] = read_rec(path)
	return _recs[path]


# ---------------------------------------------------------------- fixture
## inches (a page double) to MI, Math.round
static func mi(v: Variant) -> int:
	return PageHash.js_roundf(float(v) * 1000.0)


## inches to MI on the 0.01" grid (deployment points, act points)
static func mi_grid(v: Variant) -> int:
	return 10 * PageHash.js_roundf(float(v) * 100.0)


## Room setup for BattleState.make (§6 step 2): density -> density_h, v ignored.
static func setup_of(rec: Dictionary) -> Dictionary:
	var s: Dictionary = rec["setup"]
	return {
		"theme": str(s.get("theme", "ruin")), "seed": int(s["seed"]), "w": int(s["w"]), "d": int(s["d"]),
		"terrain": str(s.get("terrain", "hills")), "buildings": bool(s.get("buildings", true)),
		"density_h": PageHash.js_roundf(float(s.get("density", 1)) * 100.0), "mode": str(s.get("mode", "pvp")),
		"teams": int(s["teams"]), "perTeam": int(s.get("perTeam", 1)), "budget": int(s.get("budget", 500)),
		"freeFire": bool(s.get("freeFire", false)), "clock": int(s.get("clock", 0)), "goal": str(s.get("goal", "obj")),
		"rounds": int(s.get("rounds", 5)),
	}


## Seats for Battle.make (§6 step 3), in mkPlayers order. The army code is checked against the page's.
static func seats_of(rec: Dictionary, problems: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seats: Array = rec["seats"]
	var lists: Array = rec["lists"]
	var deps: Array = rec["deps"]
	var sdef: Dictionary = rec["scenario_def"]
	var sdef_seats: Array = sdef.get("seats", [])
	for k: int in seats.size():
		var rs: Dictionary = seats[k]
		var counts: Array = []
		counts.resize(GameData.count())
		counts.fill(0)
		for e: Variant in lists[k]:
			var pair: Array = e
			var ti := GameData.index_of(str(pair[0]))
			if ti < 0:
				problems.append("seat %d: unknown unit key %s" % [k, str(pair[0])])
				continue
			counts[ti] = int(counts[ti]) + int(pair[1])
		var list := BtArmy.fit_list(counts)
		var fac := BtArmy.fac_of(list, "mod")
		if fac != str(rs["fac"]):
			problems.append("seat %d: fac_of gives %s, the page %s" % [k, fac, str(rs["fac"])])
		var skin := {}
		if k < sdef_seats.size():
			var sd: Dictionary = sdef_seats[k]
			var raw_skin: Dictionary = intify(sd.get("skin", {}))
			skin = BtArmy.fit_skin(raw_skin)
		var dep: Array = deps[k]
		var bot := bool(rs["bot"])
		out.append({
			"team": int(rs["team"]), "bot": bot, "ai": false, "pid": "" if bot else "A", "list": list, "fac": fac,
			"skin": skin, "dep": PackedInt64Array([mi_grid(dep[0]), mi_grid(dep[1])]), "cp": 0, "done": false,
		})
	return out


## Largest |deployment point in MI - page double x 1000| over the seats (the 0.01" rounding of §7 #14).
static func dep_error(rec: Dictionary) -> int:
	var worst := 0
	for d: Variant in rec["deps"]:
		var dep: Array = d
		for a: int in 2:
			var exact := float(dep[a]) * 1000.0
			worst = maxi(worst, int(ceil(absf(float(mi_grid(dep[a])) - exact))))
	return worst


## Fixture for Battle.make (§6 step 4): prepared props (injected), objectives, units0 (positions on the 10 MI grid).
static func fixture_of(rec: Dictionary) -> Dictionary:
	var seed := int((rec["setup"] as Dictionary)["seed"])
	var props: Array[Dictionary] = []
	for p: Variant in rec["props"]:
		var o: Dictionary = p
		var kind := str(o["kind"])
		var h := float(o.get("h", 0))
		var s := float(o.get("s", 1))
		var bw := 0
		var bd := 0
		if kind == "building":
			bw = PageHash.bld_width_mi(h, s)
			bd = PageHash.bld_depth_mi(seed, h, s)
		props.append(BtBlocking.prep_one(kind, mi(o["x"]), mi(o["z"]), PageHash.js_roundf(float(o.get("rot", 0)) * 65536.0),
			PageHash.js_roundf(s * 10000.0), PageHash.js_roundf(h * 65536.0), bw, bd))
	var objs: Array[Dictionary] = []
	for p: Variant in rec.get("obj", []):
		var o: Dictionary = p
		objs.append({"n": int(o["n"]), "x": mi(o["x"]), "z": mi(o["z"])})
	var units0: Array[Dictionary] = []
	for p: Variant in rec.get("units0", []):
		var o: Dictionary = p
		units0.append({"id": str(o["id"]), "x": mi_grid(o["x"]), "z": mi_grid(o["z"]),
			"rot": PageHash.js_roundf(float(o.get("rot", 0)) * 65536.0)})
	return {"props": props, "objectives": objs, "units0": units0}


# ---------------------------------------------------------------- acts
## A recorded act (as netSend got it) in core form (§6 step 6): points and x/z in MI on the 0.01" grid, every other
## number an int, pid "A"; then BtActs.sanitize when it exists (the Worker's cut), else the Worker's chr defaults.
static func core_act(raw: Dictionary) -> Dictionary:
	var a := {"pid": "A"}
	for k: Variant in raw:
		var key := str(k)
		var v: Variant = raw[k]
		if key == "to":
			var pts: Array = []
			for p: Variant in v:
				var pp: Array = p
				pts.append([mi_grid(pp[0]), mi_grid(pp[1])])
			a[key] = pts
		elif key == "x" or key == "z":
			a[key] = mi_grid(v)
		else:
			a[key] = _ints(v)
	var san := _script_of("BtActs")
	if san != null and san.has_method("sanitize"):
		var out: Variant = san.call("sanitize", a)
		if typeof(out) != TYPE_DICTIONARY:
			return {}
		var d: Dictionary = out
		if not d.is_empty() and not d.has("pid"):
			d["pid"] = "A"
		return d
	if str(a.get("a", "")) == "chr":
		a["rr"] = int(a.get("rr", 0))
		a["keep"] = int(a.get("keep", 0))
	return a


static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return PageHash.js_roundf(float(v))
		TYPE_BOOL:
			return 1 if bool(v) else 0
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_ints(x))
			return out
	return v


## Every point of a core act on the 10 MI grid.
static func on_grid(a: Dictionary) -> bool:
	for p: Variant in a.get("to", []):
		var pp: Array = p
		if int(pp[0]) % 10 != 0 or int(pp[1]) % 10 != 0:
			return false
	for key: String in ["x", "z"]:
		if a.has(key) and int(a[key]) % 10 != 0:
			return false
	return true


# ---------------------------------------------------------------- compare
## Differences between the port's raw board (MI) and the page's board (inches, one decimal): [[path, port, page], …].
static func diff_boards(port: Dictionary, page: Dictionary) -> Array:
	var out: Array = []
	for k: String in ["turn", "round", "phase", "over", "goal", "rounds", "vp", "cp"]:
		var a: Variant = _norm(port.get(k))
		var b: Variant = _norm(page.get(k))
		if a != b:
			out.append([k, a, b])
	_diff_list(port.get("obj", []), page.get("obj", []), "obj", "n", ["owner"], OBJ_TOL, out)
	_diff_list(port.get("squads", []), page.get("squads", []), "squads", "id", ["pl", "team", "k", "n", "n0"] + FLAGS, POS_TOL, out)
	_diff_list(port.get("units", []), page.get("units", []), "units", "id", ["sq", "pl", "team", "k", "hp"], POS_TOL, out)
	return out


static func _diff_list(pa: Variant, pb: Variant, name: String, idk: String, exact: Array, tol: int, out: Array) -> void:
	var a: Array = pa if typeof(pa) == TYPE_ARRAY else []
	var b: Array = pb if typeof(pb) == TYPE_ARRAY else []
	if a.size() != b.size():
		out.append([name + ".length", a.size(), b.size()])
	for i: int in mini(a.size(), b.size()):
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		var p := "%s[%d]" % [name, i]
		if _norm(x.get(idk)) != _norm(y.get(idk)):
			out.append([p + "." + idk, _norm(x.get(idk)), _norm(y.get(idk))])
			return   # the sequence differs from here on: one difference is enough
		for k: Variant in exact:
			var u: Variant = _norm(x.get(k))
			var v: Variant = _norm(y.get(k))
			if u != v:
				out.append([p + "." + str(k), u, v])
		for k: String in ["x", "z"]:
			var mi_v := int(x.get(k, 0))
			var tenths := PageHash.js_roundf(float(y.get(k, 0)) * 10.0)
			if absi(mi_v - tenths * 100) > tol:
				out.append([p + "." + k, mi_v, float(tenths) / 10.0])


static func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if f == floor(f) else f
		TYPE_STRING_NAME:
			return str(v)
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_norm(x))
			return out
	return v


## Is this difference allowed for (scenario, act index)?
func allowed(scenario: String, act: int, path: String) -> bool:
	var dotted := path.replace("[", ".").replace("]", "")
	for e: Variant in _allow:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if str(d.get("scenario", "")) != scenario and str(d.get("scenario", "")) != "*":
			continue
		var at: Variant = d.get("act", "*")
		if not (typeof(at) == TYPE_STRING and str(at) == "*") and int(at) != act:
			continue
		var pat := str(d.get("path", ""))
		if path.match(pat) or dotted.match(pat):
			return true
	return false


## The first difference not in the allowlist ([] when none).
func first_blocking(scenario: String, act: int, diffs: Array) -> Array:
	for d: Variant in diffs:
		var row: Array = d
		if not allowed(scenario, act, str(row[0])):
			return row
	return []


# ---------------------------------------------------------------- the global classes of later waves
## The script of a global class (null while it does not exist): Battle (wave 5), BtActs, BtBoard.
static func _script_of(cls: String) -> GDScript:
	if _cls_cache.has(cls):
		return _cls_cache[cls]
	var found: GDScript = null
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == cls:
			found = load(str(c["path"])) as GDScript
			break
	_cls_cache[cls] = found
	return found


static func _battle_ready() -> bool:
	var b := _script_of("Battle")
	return b != null and b.has_method("make")


func _board_raw(battle: Object) -> Dictionary:
	if battle.has_method("board_raw"):
		return battle.call("board_raw")
	var bb := _script_of("BtBoard")
	if bb != null:
		return bb.call("board", battle.get("st"), true)
	return {}


# ---------------------------------------------------------------- tests
func test_recordings_present() -> void:
	if _files.is_empty() and not OS.has_feature("editor"):
		print("SKIP  oracle: no recordings in this build (the exported game carries no .json.gz)")
		return
	var scen_text := FileAccess.get_file_as_string(DIR + "/scenarios.json")
	var scen: Variant = JSON.parse_string(scen_text)
	assert_true(typeof(scen) == TYPE_DICTIONARY, "scenarios.json parses")
	if typeof(scen) != TYPE_DICTIONARY:
		return
	var defs: Array = (scen as Dictionary).get("scenarios", [])
	assert_eq(_files.size(), defs.size(), "one recording per scenario")
	assert_true(defs.size() >= 24, "the 20 scenarios plus the four of R1 Q2", defs.size())


func test_allowlist() -> void:
	var f := FileAccess.open(ALLOWLIST, FileAccess.READ)
	assert_true(f != null, "allowlist.json exists")
	if f == null:
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	assert_true(typeof(v) == TYPE_ARRAY, "allowlist.json is an array")
	var bad := 0
	for e: Variant in _allow:
		var d: Dictionary = e if typeof(e) == TYPE_DICTIONARY else {}
		var reason := str(d.get("reason", ""))
		if str(d.get("scenario", "")) == "" or str(d.get("path", "")) == "" or not reason.contains("§7"):
			bad += 1
	assert_eq(bad, 0, "every allowlist entry has a scenario, a path and a reason naming a §7 item")


func test_allow_matching() -> void:
	var keep := _allow
	_allow = [{"scenario": "s", "act": "*", "path": "squads.*.engaged", "reason": "§7 #4 test"},
		{"scenario": "s", "act": 3, "path": "units[2].x", "reason": "§7 #2 test"}]
	assert_true(allowed("s", 7, "squads[4].engaged"), "dotted wildcard matches an indexed path")
	assert_true(allowed("s", 3, "units[2].x"), "exact path at its act")
	assert_false(allowed("s", 4, "units[2].x"), "not at another act")
	assert_false(allowed("t", 3, "units[2].x"), "not in another scenario")
	assert_eq(first_blocking("s", 3, [["units[2].x", 1, 2], ["units[2].z", 1, 2]]), ["units[2].z", 1, 2], "first blocking skips allowed")
	_allow = keep


func test_compare_rules() -> void:
	var page := {"turn": 0, "round": 1, "phase": "move", "over": false, "goal": "obj", "rounds": 3, "vp": [0, 0], "cp": [1, 1],
		"obj": [{"n": 0, "x": 1.5, "z": -2.0, "owner": -1}],
		"squads": [{"id": "0:0", "pl": 0, "team": 0, "k": "hoplite", "n": 5, "n0": 5, "x": 10.0, "z": -0.1, "moved": false,
			"adv": false, "fell": false, "shot": false, "chDone": false, "charged": false, "shaken": false, "engaged": false}],
		"units": [{"id": "0:0.0", "sq": "0:0", "pl": 0, "team": 0, "k": "hoplite", "hp": 1, "x": -3.4, "z": 0.0}]}
	var port: Dictionary = page.duplicate(true)
	port["obj"] = [{"n": 0, "x": 1500, "z": -2051, "owner": -1}]
	port["squads"][0]["x"] = 10060
	port["squads"][0]["z"] = -100
	port["units"][0]["x"] = -3460
	port["units"][0]["z"] = 0
	port["vp"] = PackedInt64Array([0, 0])
	assert_eq(diff_boards(port, page), [], "positions within 60 MI (51 for objectives), packed arrays equal plain ones")
	port["units"][0]["x"] = -3461
	port["obj"][0]["z"] = -2052
	var d := diff_boards(port, page)
	assert_eq(d.size(), 2, "one MI beyond the tolerances is a difference " + str(d))
	port["units"][0]["x"] = -3400
	port["obj"][0]["z"] = -2000
	port["squads"][0]["engaged"] = true
	port["cp"] = [1, 0]
	d = diff_boards(port, page)
	assert_eq(d, [["cp", [1, 0], [1, 1]], ["squads[0].engaged", true, false]], "exact fields and flags compared exactly")
	port["squads"][0]["engaged"] = false
	port["cp"] = [1, 1]
	port["units"] = [{"id": "0:0.1", "sq": "0:0", "pl": 0, "team": 0, "k": "hoplite", "hp": 1, "x": -3400, "z": 0}]
	assert_eq(diff_boards(port, page), [["units[0].id", "0:0.1", "0:0.0"]], "the unit id sequence is compared (victim order)")


func test_core_act_conversion() -> void:
	var a := core_act({"a": "smove", "u": "0:1", "to": [[1.25, -3.5], [-0.01, 0.05]], "how": "move"})
	assert_eq(a.get("to"), [[1250, -3500], [-10, 50]], "points to MI on the grid (two decimals exactly)")
	assert_eq(a.get("pid"), "A", "pid A added")
	var c := core_act({"a": "smove", "u": "0:1", "x": -12.3, "z": 4.1, "how": "adv"})
	assert_eq([c.get("x"), c.get("z")], [-12300, 4100], "Claude-form x/z to MI")
	var r := core_act({"a": "chr", "u": "0:1", "t": "1:0", "roll": [3, 4]})
	assert_eq([r.get("rr"), r.get("keep"), r.get("roll")], [0, 0, [3, 4]], "chr carries rr and keep as the Worker adds them")
	var s := core_act({"a": "sav", "u": "0:1", "t": "1:0", "save": [1, 6], "gtg": true})
	assert_eq(s.get("gtg"), 1, "bools become 0/1")
	assert_eq(mi(-2.5005), -2500, "Math.round half up for negatives (MI)")
	assert_eq(mi_grid(-21.000000000000004), -21000, "page autoDep doubles land on the grid")


## Every recording: loads, its fixture builds, its seats match the page's armies, deployment rounding stays within
## 5 MI, units0 matches board0, every act converts to a legal ActLog entry on the grid. Then the replay, or SKIP.
func test_recordings_and_fixtures() -> void:
	if _files.is_empty():
		return
	var problems := PackedStringArray()
	var worst_dep := 0
	var n_acts := 0
	var n_props := 0
	var codes_seen := {}
	for path: String in _files:
		var rec := _rec(path)
		var name := path.get_file().trim_suffix(".json.gz")
		if rec.is_empty():
			problems.append(name + ": does not load")
			continue
		if int(rec.get("format", 0)) < 2 or not rec.has("units0"):
			problems.append(name + ": format < 2 (no units0): re-record with tools/record_oracle.js")
			continue
		var acts: Array = rec["acts"]
		var boards: Array = rec["boards"]
		var meta: Array = rec["acts_meta"]
		if boards.size() != acts.size() or meta.size() != acts.size():
			problems.append(name + ": acts/boards/acts_meta lengths differ")
		var p0 := problems.size()
		var seats := seats_of(rec, problems)
		if seats.size() != (rec["seats"] as Array).size():
			problems.append(name + ": seats")
		for i: int in range(p0, problems.size()):
			problems[i] = name + ": " + problems[i]
		worst_dep = maxi(worst_dep, dep_error(rec))
		var fx := fixture_of(rec)
		n_props += (fx["props"] as Array).size()
		for p: Variant in fx["props"]:
			var o: Dictionary = p
			if str(o["kind"]) == "building" and (int(o["bw"]) <= 0 or int(o["bd"]) <= 0):
				problems.append(name + ": a building without a footprint")
		var b0: Dictionary = rec["board0"]
		var u0: Array = fx["units0"]
		var bu: Array = b0["units"]
		if u0.size() != bu.size():
			problems.append(name + ": units0 has %d models, board0 %d" % [u0.size(), bu.size()])
		else:
			for i: int in u0.size():
				var x: Dictionary = u0[i]
				var y: Dictionary = bu[i]
				if str(x["id"]) != str(y["id"]):
					problems.append(name + ": units0[%d] is %s, board0 %s" % [i, str(x["id"]), str(y["id"])])
					break
				for k: String in ["x", "z"]:
					if absi(int(x[k]) - 100 * PageHash.js_roundf(float(y[k]) * 10.0)) > 55:
						problems.append(name + ": units0[%d].%s %d vs board0 %s" % [i, k, int(x[k]), str(y[k])])
		var alog := ActLog.new()
		for i: int in acts.size():
			var raw: Dictionary = acts[i]
			var code := str(raw.get("a", ""))
			codes_seen[code] = int(codes_seen.get(code, 0)) + 1
			if not CODES.has(code):
				problems.append(name + ": act %d has an unknown code %s" % [i, code])
			var a := core_act(raw)
			if a.is_empty():
				problems.append(name + ": act %d refused by BtActs.sanitize: %s" % [i, JSON.stringify(raw)])
				continue
			if not on_grid(a):
				problems.append(name + ": act %d off the 10 MI grid: %s" % [i, JSON.stringify(a)])
			if alog.append(a) < 0:
				problems.append(name + ": act %d not a legal ActLog entry (%s): %s" % [i, alog.error, JSON.stringify(a)])
		n_acts += acts.size()
	assert_eq(problems, PackedStringArray(), "%d recordings load and build their fixtures (%d acts, %d props)" % [_files.size(), n_acts, n_props])
	assert_true(worst_dep <= DEP_TOL, "deployment points within %d MI of the page's doubles (worst %d)" % [DEP_TOL, worst_dep])
	var missing: Array = []
	for c: String in CODES:
		if not codes_seen.has(c):
			missing.append(c)
	assert_eq(missing, [], "the recordings hold all 19 act codes")


## The coverage the four R1 Q2 scenarios add (chr keep, Claude-form smove, staged human shot, human heal and grenade).
func test_q2_coverage() -> void:
	if _files.is_empty():
		return
	var seen := {"keep": 0, "xz": 0, "human_atk": 0, "human_heal": 0, "human_gren": 0}
	for path: String in _files:
		var rec := _rec(path)
		if rec.is_empty():
			continue
		var sdef: Dictionary = rec["scenario_def"]
		var human := int((sdef["human"] as Dictionary)["seat"]) if sdef.has("human") else -1
		var acts: Array = rec["acts"]
		var meta: Array = rec["acts_meta"]
		for i: int in acts.size():
			var a: Dictionary = acts[i]
			var m: Dictionary = meta[i]
			var by_human: bool = human >= 0 and typeof(m.get("seat")) == TYPE_INT and int(m["seat"]) == human
			var code := str(a["a"])
			if code == "chr" and int(a.get("keep", 0)) == 1:
				seen["keep"] += 1
			if code == "smove" and a.has("x") and not a.has("to"):
				seen["xz"] += 1
			if by_human and code == "atk":
				seen["human_atk"] += 1
			if by_human and code == "heal":
				seen["human_heal"] += 1
			if by_human and code == "gren":
				seen["human_gren"] += 1
	for k: String in seen:
		assert_true(int(seen[k]) > 0, "recordings cover " + k, seen)


func _replay_set() -> PackedStringArray:
	var want := OS.get_environment("ORACLE")
	if want == "all":
		return _files
	if want != "":
		var out := PackedStringArray()
		for f: String in _files:
			if f.get_file().contains(want):
				out.append(f)
		return out
	var by_n: Array = []
	for f: String in _files:
		var rec := _rec(f)
		by_n.append([(rec.get("acts", []) as Array).size(), f])
	by_n.sort()
	var quick := PackedStringArray()
	for i: int in mini(QUICK_N, by_n.size()):
		quick.append(str((by_n[i] as Array)[1]))
	return quick


func test_replay() -> void:
	if _files.is_empty():
		return
	if not _battle_ready():
		print("SKIP  oracle replay: class Battle does not exist yet (R1 wave 5); loader, fixtures and act conversion were checked on %d recordings" % _files.size())
		return
	for path: String in _replay_set():
		_replay_one(path)


func _replay_one(path: String) -> void:
	var rec := _rec(path)
	var name := path.get_file().trim_suffix(".json.gz")
	var problems := PackedStringArray()
	var seats := seats_of(rec, problems)
	var fx := fixture_of(rec)
	var bscript := _script_of("Battle")
	var battle: Object = bscript.call("make", setup_of(rec), seats, fx)
	if battle == null:
		assert_true(false, name + ": Battle.make returned null")
		return
	battle.call("start")
	var st: BattleState = battle.get("st")
	# units0: the page's raw deployed positions replace the v10 deployment (Q1), same ids in the same order
	var u0: Array = fx["units0"]
	var ids_ok := st.units.size() == u0.size()
	for i: int in mini(st.units.size(), u0.size()):
		var e: Dictionary = u0[i]
		if st.units[i].id != str(e["id"]):
			ids_ok = false
			break
		st.units[i].x = int(e["x"])
		st.units[i].z = int(e["z"])
	assert_true(ids_ok, name + ": the v10 deployment has the page's model ids in the page's order")
	if not ids_ok:
		return
	var d0 := first_blocking(name, -1, diff_boards(_board_raw(battle), rec["board0"]))
	if not d0.is_empty():
		assert_true(false, "%s board0: %s port %s page %s" % [name, str(d0[0]), str(d0[1]), str(d0[2])])
		return
	var acts: Array = rec["acts"]
	var boards: Array = rec["boards"]
	var meta: Array = rec["acts_meta"]
	for i: int in acts.size():
		var m: Dictionary = meta[i]
		var now := [st.turn, st.round_no, st.phase_name()]
		var want := [int(m["turn"]), int(m["round"]), str(m["phase"])]
		if now != want:
			_report(name, i, acts[i], "turn/round/phase before the act", now, want, st)
			return
		var a := core_act(acts[i])
		var ev: Array = battle.call("apply", a)
		for e: Variant in ev:
			var d: Dictionary = e
			var id := Events.id_of(d)
			if id == Events.Id.BAD_ACT or (id == Events.Id.LOG_LINE and str(d.get("key", "")) == "dice_short"):
				_report(name, i, acts[i], "event", Events.name_of(id), str(d.get("key", "")), st)
				return
		var diff := first_blocking(name, i, diff_boards(_board_raw(battle), boards[i]))
		if not diff.is_empty():
			_report(name, i, acts[i], str(diff[0]), diff[1], diff[2], st)
			return
	var fin: Dictionary = rec["final"]
	var alive: Array = []
	for t: int in st.teams:
		if st.live_of(t) > 0:
			alive.append(t)
	var cp: Array = []
	for p: BattleState.Seat in st.seats:
		cp.append(p.cp)
	var got := [st.over, st.round_no, st.turn, st.phase_name(), _norm(st.vp), cp, alive, st.units.size()]
	var page_fin := [bool(fin["over"]), int(fin["round"]), int(fin["turn"]), str(fin["phase"]), _norm(fin["vp"]), _norm(fin["cp"]),
		_norm(fin["alive"]), int(fin["units"])]
	assert_eq(got, page_fin, name + ": final over, round, turn, phase, vp, cp, alive teams, unit count")


## The first difference, printed like tests/battle/net_sync.js: scenario, act index, act, field, port, page, last log keys.
func _report(name: String, i: int, act: Variant, field: String, port: Variant, page: Variant, st: BattleState) -> void:
	var keys: Array = []
	for j: int in range(maxi(0, st.log_lines.size() - 5), st.log_lines.size()):
		keys.append(str(st.log_lines[j].get("key", "")))
	assert_true(false, "%s act %d %s: %s port %s page %s (last log %s)" % [name, i, JSON.stringify(act), field, str(port), str(page), str(keys)])
