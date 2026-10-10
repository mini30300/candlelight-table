extends "res://tests/testing.gd"
## Edge acts against the page (R1_PORT_SPEC §4, the netAct dispatcher): tests/oracle/edges/*.json.gz are made by
## tools/record_act_edges.js from an oracle recording: its acts on the page with seeded edge acts in between (stage
## mismatches, squads that already acted or are dead, phase ends naming another phase, stratagems without CP, unknown
## squads, legacy codes, a done with another pid, explicit move points, acts after the end), each through the Worker's
## sanitiser. The port builds the same match as test_oracle.gd, applies every act through Battle.apply and compares
## the board (test_oracle's compare rules) and the PEND queue (kind, u, t, stage, hits, wounds) after every act.
## The page promotes a finished overwatch (owatk) to charge only when someone rolls, the port after every act (§7 #9):
## both stages compare as one.

const Oracle := preload("res://tests/oracle/test_oracle.gd")
const DIR := "res://tests/oracle/edges"


## env EDGE_DIR = another folder of edge recordings (record_act_edges.js with EDGE_OUT, for exploration)
static func edge_files() -> PackedStringArray:
	var out := PackedStringArray()
	var where := OS.get_environment("EDGE_DIR")
	if where == "":
		where = DIR
	var dir := DirAccess.open(where)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".json.gz"):
			out.append(where + "/" + f)
	out.sort()
	return out


static func read_gz(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {}
	var v: Variant = JSON.parse_string(bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	return v if typeof(v) == TYPE_DICTIONARY else {}


## The port's PEND queue in the page's form.
static func pend_of(st: BattleState) -> Array:
	var out: Array = []
	for p: BattleState.Pend in st.pend:
		out.append([BattleState.KINDS[p.kind], p.u, p.t, _stage(BattleState.STAGES[p.stage]), p.hits, p.wounds])
	return out


static func page_pend(v: Variant) -> Array:
	var out: Array = []
	for e: Variant in v:
		var d: Dictionary = e
		out.append([str(d["kind"]), str(d["u"]), str(d.get("t", "")), _stage(str(d["stage"])), int(d.get("hits", 0)),
			int(d.get("wounds", 0))])
	return out


## §7 #9: a charge waiting for its overwatch and one ready to roll are the same entry
static func _stage(s: String) -> String:
	return "charge" if s == "owatk" else s


func test_edge_files_present() -> void:
	if edge_files().is_empty() and not OS.has_feature("editor"):
		print("SKIP  oracle edges: no recordings in this build (the exported game carries no .json.gz)")
		return
	assert_true(edge_files().size() >= 5, "edge recordings exist (tools/record_act_edges.js)", edge_files())


func test_edges() -> void:
	for path: String in edge_files():
		_replay(path)


func _replay(path: String) -> void:
	var name := path.get_file().trim_suffix(".json.gz")
	var ed := read_gz(path)
	var base := "res://tests/oracle/%s.json.gz" % str(ed.get("base", ""))
	var rec := Oracle.read_rec(base)
	if rec.is_empty():
		assert_true(false, name + ": base recording " + base)
		return
	var problems := PackedStringArray()
	var b := Battle.make(Oracle.setup_of(rec), Oracle.seats_of(rec, problems), Oracle.fixture_of(rec))
	assert_true(problems.is_empty() and b.last_error == "", name + ": table built", problems)
	b.start()
	var acts: Array = ed["acts"]
	var boards: Array = ed["boards"]
	var pends: Array = ed["pend"]
	var edge: Array = ed["edge"]
	var edges := 0
	for i: int in acts.size():
		var raw: Dictionary = Oracle.intify(acts[i])
		var pid := str(raw.get("pid", "A"))
		var a := Oracle.core_act(raw)
		a["pid"] = pid
		var ev := b.apply(a)
		var why := ""
		for e: Dictionary in ev:
			var id := Events.id_of(e)
			if id == Events.Id.BAD_ACT or (id == Events.Id.LOG_LINE and str(e.get("key", "")) == "dice_short"):
				why = "event %s %s" % [Events.name_of(id), str(e.get("key", ""))]
		var diff := Oracle.diff_boards(BtBoard.board(b.st, true), Oracle.intify(boards[i]))
		if why == "" and not diff.is_empty():
			why = "board %s port %s page %s" % [str(diff[0][0]), str(diff[0][1]), str(diff[0][2])]
		var pp := pend_of(b.st)
		var gp := page_pend(pends[i])
		if why == "" and pp != gp:
			why = "pend port %s page %s" % [str(pp), str(gp)]
		if why != "":
			var keys: Array = []
			for j: int in range(maxi(0, b.st.log_lines.size() - 4), b.st.log_lines.size()):
				keys.append(str(b.st.log_lines[j].get("key", "")))
			assert_true(false, "%s act %d (%s) %s: %s (last log %s)" % [name, i, "edge" if int(edge[i]) == 1 else "recorded",
				JSON.stringify(acts[i]).left(160), why, str(keys)])
			return
		edges += int(edge[i])
	assert_true(true, "%s: %d acts (%d edge acts) equal the page" % [name, acts.size(), edges])
