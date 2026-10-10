extends "res://tests/testing.gd"
## Golden replays (R1_PORT_SPEC §8 wave 5 B, ARCHITECTURE §10.2): tests/golden/*.json are seeded bot-vs-bot games
## written by tools/make_golden.gd (2, 3 and 4 teams, obj and kill, every army, generated integer fields). Each one is
## rebuilt from its setup and seats and replayed act by act (the Battle digest after start and after every act), in
## batches (Table.replay), and from a mid-game snapshot; the final Battle digest, BattleState digest and the page-form
## board JSON must match. Then every game is played again from its setup by the bots and must give the same acts.
## CI runs this on x86-64 and arm64, and the exported Windows exe runs it in tests/selftest.gd: the same digests on
## every machine are the cross-device determinism proof. A digest that moves is a rules change: regenerate with
## tools/make_golden.gd in the same PR, give the reason and bump RULES_V; never edit a golden by hand.

const MakeGolden := preload("res://tools/make_golden.gd")
const DIR := "res://tests/golden"
## Acts per batch in the batch replay.
const BATCH := 37

## name -> golden record (numbers back to ints)
var goldens: Dictionary = {}
var load_errors: Array[String] = []


func setup() -> void:
	for g: Dictionary in MakeGolden.games():
		var name: String = g["name"]
		var path := "%s/%s.json" % [DIR, name]
		if not FileAccess.file_exists(path):
			load_errors.append("%s: missing" % path)
			continue
		var err: Array[String] = []
		var raw: Variant = JsonNum.intify(JSON.parse_string(FileAccess.get_file_as_string(path)), name, err)
		if not err.is_empty() or typeof(raw) != TYPE_DICTIONARY:
			load_errors.append("%s: %s" % [path, err])
			continue
		goldens[name] = raw


# ------------------------------------------------------------------ helpers
func _acts(rec: Dictionary) -> Array:
	return rec["acts"]


func _battle(rec: Dictionary) -> Battle:
	return MakeGolden.make_battle(rec["setup"], rec["seats"])


## The first index where two digest lists differ (-1 = equal, including the length).
func _first_diff(got: PackedStringArray, want: Array) -> int:
	for i: int in mini(got.size(), want.size()):
		if got[i] != str(want[i]):
			return i
	return -1 if got.size() == want.size() else mini(got.size(), want.size())


func _final_checks(b: Battle, rec: Dictionary, how: String) -> void:
	var name: String = rec["name"]
	var fin: Dictionary = rec["final"]
	assert_digest(b.digest(), str(fin["digest"]), "%s %s: final Battle digest" % [name, how])
	assert_digest(b.st.digest(), str(fin["state_digest"]), "%s %s: final BattleState digest" % [name, how])


# ------------------------------------------------------------------ the files
func test_files() -> void:
	assert_eq(load_errors, [] as Array[String], "every game of make_golden has a readable golden file")
	var files := 0
	var dir := DirAccess.open(DIR)
	if dir != null:
		for f: String in dir.get_files():
			if f.ends_with(".json"):
				files += 1
	assert_eq(files, MakeGolden.games().size(), "no stray golden file (each file is a game of make_golden)")
	for name: String in goldens:
		var rec: Dictionary = goldens[name]
		assert_eq([rec["format"], rec["name"], rec["rules_v"]], [MakeGolden.FORMAT, name, Version.RULES_V],
			"%s: format, name, rules version" % name)
		var fin: Dictionary = rec["final"]
		assert_eq([_acts(rec).size(), (rec["digest_after"] as Array).size(), int(fin["acts"])],
			[int(fin["acts"]), int(fin["acts"]), int(fin["acts"])], "%s: one digest per act" % name)
		assert_true(bool(fin["over"]) and _acts(rec).size() > 50, "%s: a whole game that ended" % name, fin["acts"])


## 2, 3 and 4 teams, a team game, obj and kill, every army at least once, a table with seeded armies.
func test_coverage() -> void:
	var teams := {}
	var goals := {}
	var armies := {}
	var per_team2 := false
	var seeded := false
	for name: String in goldens:
		var rec: Dictionary = goldens[name]
		var s: Dictionary = rec["setup"]
		teams[int(s["teams"])] = true
		goals[str(s["goal"])] = true
		per_team2 = per_team2 or int(s.get("perTeam", 1)) > 1
		for a: Variant in (rec["final"] as Dictionary)["armies"]:
			armies[str(a)] = true
		var empty := true
		for sd: Variant in rec["seats"]:
			empty = empty and ((sd as Dictionary)["list"] as Dictionary).is_empty()
		seeded = seeded or empty
	assert_true(teams.has(2) and teams.has(3) and teams.has(4), "2, 3 and 4 teams", teams.keys())
	assert_true(goals.has("obj") and goals.has("kill"), "obj and kill goals", goals.keys())
	assert_true(per_team2 and seeded, "a team game and a table with seeded armies")
	var missing: Array = []
	for f: String in GameData.factions():
		if not armies.has(f):
			missing.append(f)
	assert_eq(missing, [], "every army plays in some golden")
	var codes := {}
	for name: String in goldens:
		for a: Variant in _acts(goldens[name]):
			codes[str((a as Dictionary)["a"])] = true
	var want := ["smove", "stay", "skip", "atk", "wnd", "sav", "chg", "ow", "chr", "cmove", "endph"]
	var absent: Array = []
	for c: String in want:
		if not codes.has(c):
			absent.append(c)
	assert_true(absent.is_empty(), "the bot games use the main act codes", [absent, codes.keys()])


# ------------------------------------------------------------------ replays
func test_replay_act_by_act() -> void:
	for name: String in goldens:
		var rec: Dictionary = goldens[name]
		var b := _battle(rec)
		assert_eq(b.last_error, "", "%s: table built" % name)
		b.start()
		assert_digest(b.digest(), str(rec["digest0"]), "%s: digest after start" % name)
		var got := PackedStringArray()
		var bad := ""
		for a: Variant in _acts(rec):
			b.apply(a)
			if b.last_error != "" and bad == "":
				bad = "%s at seq %d" % [b.last_error, got.size() + 1]
			got.append(b.digest())
		assert_eq(bad, "", "%s: every act accepted" % name)
		var want: Array = rec["digest_after"]
		var i := _first_diff(got, want)
		var detail := "" if i < 0 else "act %d %s: got %s want %s" % [i + 1, JSON.stringify(_acts(rec)[mini(i, _acts(rec).size() - 1)]),
			got[i] if i < got.size() else "-", str(want[i]) if i < want.size() else "-"]
		assert_true(i < 0, "%s: the digest after each of %d acts" % [name, want.size()], detail)
		_final_checks(b, rec, "act by act")
		var fin: Dictionary = rec["final"]
		assert_eq(BtBoard.to_json(b.board()), str(fin["board"]), "%s: final board JSON" % name)
		var st := b.st
		var armies: Array = []
		for p: BattleState.Seat in st.seats:
			armies.append(p.fac)
		assert_eq([st.over, st.winner, st.round_no, st.turn, st.phase_name(), Array(st.vp), st.units.size(), armies],
			[fin["over"], fin["winner"], fin["round"], fin["turn"], fin["phase"], fin["vp"], fin["units"], fin["armies"]],
			"%s: over, winner, round, turn, phase, vp, units, armies" % name)


func test_replay_in_batches() -> void:
	for name: String in goldens:
		var rec: Dictionary = goldens[name]
		var acts := _acts(rec)
		var want: Array = rec["digest_after"]
		var b := _battle(rec)
		b.start()
		var ok := true
		var at := 0
		while at < acts.size():
			var part := acts.slice(at, mini(at + BATCH, acts.size()))
			var n := b.replay(part)
			at += part.size()
			if n != part.size() or b.digest() != str(want[at - 1]):
				ok = false
				break
		assert_true(ok, "%s: Table.replay in batches of %d, digest at each batch end" % [name, BATCH], at)
		var w := _battle(rec)
		w.start()
		assert_eq(w.replay(acts), acts.size(), "%s: the whole log in one replay" % name)
		_final_checks(w, rec, "one replay")


## A late joiner: the snapshot of the half-played table restored on a fresh table, then the rest of the acts.
func test_snapshot_mid_game() -> void:
	for name: String in goldens:
		var rec: Dictionary = goldens[name]
		var acts := _acts(rec)
		var half: int = acts.size() / 2
		var a := _battle(rec)
		a.start()
		a.replay(acts.slice(0, half))
		# through JSON text and back, as a snapshot travels
		var err: Array[String] = []
		var snap: Variant = JsonNum.intify(JSON.parse_string(JSON.stringify(a.snapshot())), "snap", err)
		var b := _battle(rec)
		assert_true(err.is_empty() and typeof(snap) == TYPE_DICTIONARY and b.restore(snap), "%s: restore at act %d" % [name, half],
			[err, b.last_error])
		assert_digest(b.digest(), str((rec["digest_after"] as Array)[half - 1]), "%s: restored digest" % name)
		assert_eq(b.replay(acts.slice(half)), acts.size() - half, "%s: the rest replays" % name)
		_final_checks(b, rec, "from a snapshot")


## The bots play every game again from its setup: the same lists, the same acts, the same digests.
func test_bots_play_the_same_games() -> void:
	for g: Dictionary in MakeGolden.games():
		var name: String = g["name"]
		if not goldens.has(name):
			continue
		var rec: Dictionary = goldens[name]
		var fresh := MakeGolden.play(g)
		assert_eq(JSON.stringify(fresh["seats"]), JSON.stringify(rec["seats"]), "%s: the same seats and lists" % name)
		var fa: Array = fresh["acts"]
		var ra := _acts(rec)
		var i := 0
		while i < mini(fa.size(), ra.size()) and JSON.stringify(fa[i]) == JSON.stringify(ra[i]):
			i += 1
		var same := i == fa.size() and i == ra.size()
		assert_true(same, "%s: the bots make the same %d acts" % [name, ra.size()],
			"" if same else "first difference at act %d: got %s want %s" % [i + 1,
				JSON.stringify(fa[i]) if i < fa.size() else "-", JSON.stringify(ra[i]) if i < ra.size() else "-"])
		assert_eq(MakeGolden.to_text(fresh), FileAccess.get_file_as_string("%s/%s.json" % [DIR, name]),
			"%s: make_golden writes the same file byte for byte" % name)
