extends "res://tests/testing.gd"
## The v10 bots and roller against the page's (R1_PORT_SPEC §1.15–§1.17): in every bot-only oracle recording page A
## played with BT.botStep (one bot action, then every pending roll, as Battle.bot_step), so before each recorded act
## the port, standing on the same state (test_oracle.gd checks the boards), must want to send the same act:
## - PEND empty, move/shoot/charge: BtBot.next_act (or the team's endph from BtBot.finished_act when it is empty);
## - PEND not empty: BtRoller.roll of the entry BtRoller.flush_plan picks, with BtBot.choice.
## Compared: code, u, t, how, ph and the choices (ow use, sav gtg, shock brave, chr rr/keep); dice values come from other
## streams (§3) and are not compared, move points only by count (plan_move's grid, §7 #2/#3).

const Oracle := preload("res://tests/oracle/test_oracle.gd")
const KEYS := ["a", "u", "t", "how", "ph", "use", "gtg", "brave", "rr", "keep"]


func _want(st: BattleState) -> Dictionary:
	if not st.pend.is_empty():
		var p := BtRoller.flush_plan(st, {"online": false, "force": true})
		if p == null:
			return {"a": "?pend"}
		var acts := BtRoller.roll(st, p, BtBot.choice(st, p), Rng.make("probe", 1))
		return acts[0] if not acts.is_empty() else {"a": "?roll"}
	var a := BtBot.next_act(st, Rng.make("probe", 1))
	if a.is_empty():
		a = BtBot.finished_act(st)
	return a


static func _key(a: Dictionary) -> Array:
	var out: Array = []
	for k: String in KEYS:
		var v: Variant = a.get(k)
		out.append(Oracle._norm(Oracle._ints(v)) if v != null else null)
	if a.has("to"):
		out.append((a["to"] as Array).size())
	return out


func test_bots_and_roller_choose_as_the_page() -> void:
	if Oracle.recordings().is_empty() and not OS.has_feature("editor"):
		print("SKIP  oracle bots: no recordings in this build (the exported game carries no .json.gz)")
		return
	var want_env := OS.get_environment("ORACLE")
	var n_files := 0
	for path: String in Oracle.recordings():
		var rec := Oracle.read_rec(path)
		var sdef: Dictionary = rec["scenario_def"]
		if sdef.has("human"):
			continue
		var name := path.get_file().trim_suffix(".json.gz")
		if want_env != "all" and want_env != "" and not name.contains(want_env):
			continue
		if want_env == "" and (rec["acts"] as Array).size() > 300:
			continue
		n_files += 1
		_one(name, rec)
	assert_true(n_files >= 3, "bot-only recordings compared", n_files)


func _one(name: String, rec: Dictionary) -> void:
	var problems := PackedStringArray()
	var b := Battle.make(Oracle.setup_of(rec), Oracle.seats_of(rec, problems), Oracle.fixture_of(rec))
	b.start()
	var st := b.st
	var acts: Array = rec["acts"]
	var same := 0
	for i: int in acts.size():
		var page_a := Oracle.core_act(acts[i])
		var port_a := _want(st)
		var pk := _key(page_a)
		var qk := _key(port_a)
		if pk != qk:
			assert_true(false, "%s act %d (round %d turn %d %s): page %s, port wants %s" % [name, i, st.round_no, st.turn,
				st.phase_name(), JSON.stringify(acts[i]).left(200), JSON.stringify(port_a).left(200)])
			return
		same += 1
		b.apply(page_a)
	assert_true(true, "%s: the port chooses all %d acts as the page" % [name, same])
