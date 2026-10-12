extends SceneTree
## Golden games of the v10 rules core (R1_PORT_SPEC §8 wave 5 B, ARCHITECTURE §10.2): fixed seeded bot-vs-bot matches
## played headless through Battle (2, 3 and 4 teams, obj and kill goals, every army at least once, one table whose
## armies come from the seeded armies:<seat> streams at match start). Each golden holds the setup, the seats with their
## lists, every logged act, the Battle digest after start and after every act, and the final state (Battle digest,
## BattleState digest, the page-form board JSON). tests/unit/test_golden.gd replays them on every machine (x86-64,
## arm64, the exported Windows exe) and compares every digest; it also plays each game again from the setup with these
## same functions and checks the acts are the recorded ones.
##   <godot> --headless --path godot -s tools/make_golden.gd                 write tests/golden/<name>.json
##   <godot> --headless --path godot -s tools/make_golden.gd -- --check      exit 1 when a written file would change
##   <godot> --headless --path godot -s tools/make_golden.gd -- <name>       only that game
## A rules change that moves a digest regenerates the goldens in the same PR, with the reason and a RULES_V bump.

const OUT_DIR := "res://tests/golden"
## Format of the golden files (test_golden.gd refuses another).
const FORMAT := 1
## The page's botTick loop gets at most this many rounds of bot_step / endph / flush per game.
const MAX_STEPS := 6000

## The games. Lists come from BtArmy.auto_list with the seat's army and a stream "golden:<name>:<seat>" (outside the
## rules: the lists are written into the file, so a replay never depends on how they were made). "seeded" leaves every
## list empty, so start_match fills them from armies:<seat> on every device (§7 #12).
const GAMES := [
	{"name": "g2_obj_greek_vs_soldiers_ruin_48", "facs": ["gr", "mod"],
		"setup": {"seed": 101, "w": 48, "teams": 2, "perTeam": 1, "goal": "obj", "rounds": 3, "budget": 500,
			"theme": "ruin", "terrain": "hills"}},
	{"name": "g2_kill_knights_vs_swarm_ice_44", "facs": ["kn", "sw"],
		"setup": {"seed": 202, "w": 44, "teams": 2, "perTeam": 1, "goal": "kill", "rounds": 3, "budget": 500,
			"theme": "ice", "terrain": "mountain"}},
	{"name": "g3_obj_robots_orcs_siam_desert_60", "facs": ["rb", "or", "th"],
		"setup": {"seed": 303, "w": 60, "teams": 3, "perTeam": 1, "goal": "obj", "rounds": 3, "budget": 600,
			"theme": "desert", "terrain": "forest"}},
	{"name": "g3_kill_japan_norse_egypt_forest_56", "facs": ["jp", "nr", "eg"],
		"setup": {"seed": 404, "w": 56, "teams": 3, "perTeam": 1, "goal": "kill", "rounds": 3, "budget": 600,
			"theme": "forest", "terrain": "flat", "density_h": 60}},
	{"name": "g4_obj_medieval_elves_darkelves_empire_ruin_72", "facs": ["md", "el", "de", "ta"],
		"setup": {"seed": 505, "w": 72, "teams": 4, "perTeam": 1, "goal": "obj", "rounds": 4, "budget": 800,
			"theme": "ruin", "terrain": "hills"}},
	{"name": "g4_kill_fallen_orcs_japan_knights_ice_64", "facs": ["cx", "or", "jp", "kn"],
		"setup": {"seed": 606, "w": 64, "teams": 4, "perTeam": 1, "goal": "kill", "rounds": 3, "budget": 800,
			"theme": "ice", "terrain": "flat", "buildings": 0}},
	{"name": "g2v2_obj_freefire_fallen_greek_vs_empire_robots_desert_64", "facs": ["cx", "gr", "ta", "rb"],
		"setup": {"seed": 707, "w": 64, "teams": 2, "perTeam": 2, "goal": "obj", "rounds": 3, "budget": 800,
			"theme": "desert", "terrain": "hills", "freeFire": 1}},
	{"name": "g2_obj_seeded_armies_forest_40", "facs": [],
		"setup": {"seed": 808, "w": 40, "teams": 2, "perTeam": 1, "goal": "obj", "rounds": 3, "budget": 500,
			"theme": "forest", "terrain": "hills", "density_h": 140}},
]


static func games() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Dictionary in GAMES:
		out.append(g.duplicate(true))
	return out


static func game(name: String) -> Dictionary:
	for g: Dictionary in GAMES:
		if str(g["name"]) == name:
			return g.duplicate(true)
	return {}


## Seats in mkPlayers order (team = k / perTeam), all bots. A seat with an army gets its list from auto_list on a
## scratch state with the dev stream golden:<name>:<k>; lists are {type key: count} in TYPES order.
static func seats_of(g: Dictionary) -> Array[Dictionary]:
	var setup: Dictionary = g["setup"]
	var facs: Array = g["facs"]
	var st := BattleState.make(setup)
	var out: Array[Dictionary] = []
	for k: int in st.teams * st.per_team:
		var team: int = k / st.per_team
		var p := st.add_seat(team, "", true, false, "")
		var sd := {"team": team, "bot": true, "fac": "mod", "list": {}}
		if k < facs.size():
			p.fac = str(facs[k])
			BtArmy.auto_list(st, k, Rng.make("golden:%s:%d" % [g["name"], k], int(setup["seed"])))
			sd["fac"] = p.fac
			var l := {}
			for i: int in p.list.size():
				if p.list[i] > 0:
					l[GameData.key_at(i)] = p.list[i]
			sd["list"] = l
		out.append(sd)
	return out


## The seats of a golden file as Battle.make takes them (lists back to TYPES order).
static func battle_seats(seats: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Variant in seats:
		var sd: Dictionary = v
		var l := PackedInt32Array()
		l.resize(GameData.count())
		var lv: Dictionary = sd["list"]
		for key: Variant in lv:
			var i := GameData.index_of(str(key))
			if i >= 0:
				l[i] = int(lv[key])
		out.append({"team": int(sd["team"]), "bot": bool(sd["bot"]), "pid": "", "fac": str(sd["fac"]), "list": l})
	return out


## The table of a golden: generated props (the integer field), no fixture.
static func make_battle(setup: Dictionary, seats: Array) -> Battle:
	return Battle.make(setup, battle_seats(seats), {})


## The page's botTick loop headless (as test_battle._drive): bot_step until the team has nothing left, then the
## team's endph, else flush; stops at over, when nothing moves, or after max_steps.
static func drive(b: Battle, max_steps: int) -> void:
	for i: int in max_steps:
		if b.st.over:
			return
		var before := b.actlog.size()
		if b.bot_step() == "":
			var e := BtBot.finished_act(b.st)
			if not e.is_empty():
				e["pid"] = ""
				b.apply(e)
		if b.actlog.size() == before:
			b.flush(true, {"online": false})
		if b.actlog.size() == before:
			return


## The final state of a table as written in a golden (armies = each seat's army, the seeded ones included).
static func final_of(b: Battle) -> Dictionary:
	var st := b.st
	var armies: Array = []
	for p: BattleState.Seat in st.seats:
		armies.append(p.fac)
	return {"digest": b.digest(), "state_digest": st.digest(), "acts": b.actlog.size(), "over": st.over,
		"winner": st.winner, "round": st.round_no, "turn": st.turn, "phase": BattleState.PHASES[st.phase],
		"vp": Array(st.vp), "units": st.units.size(), "armies": armies, "board": BtBoard.to_json(BtBoard.board(st, false))}


## Plays one game and returns its golden record.
static func play(g: Dictionary) -> Dictionary:
	var setup: Dictionary = g["setup"]
	var seats := seats_of(g)
	var b := make_battle(setup, seats)
	b.start()
	var digest0 := b.digest()
	drive(b, MAX_STEPS)
	var after := PackedStringArray()
	# bot_step and flush apply several acts per call: digests after each are recomputed by a replay
	var r := make_battle(setup, seats)
	r.start()
	for a: Dictionary in b.actlog.acts():
		r.apply(a)
		after.append(r.digest())
	return {"format": FORMAT, "name": g["name"], "rules_v": Version.RULES_V, "data_hash": Version.DATA_HASH,
		"setup": setup, "seats": seats, "digest0": digest0, "acts": b.actlog.acts(), "digest_after": after,
		"final": final_of(b), "replay_final": r.digest()}


## The file text: one act and one digest per line so a diff shows where a game changed.
static func to_text(rec: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("{")
	for k: String in ["format", "name", "rules_v", "data_hash", "setup", "seats", "digest0"]:
		lines.append("%s: %s," % [JSON.stringify(k), JSON.stringify(rec[k])])
	lines.append("\"acts\": [")
	var acts: Array = rec["acts"]
	for i: int in acts.size():
		lines.append(JSON.stringify(acts[i]) + ("," if i + 1 < acts.size() else ""))
	lines.append("],")
	lines.append("\"digest_after\": [")
	var dg: PackedStringArray = rec["digest_after"]
	for i: int in dg.size():
		lines.append(JSON.stringify(dg[i]) + ("," if i + 1 < dg.size() else ""))
	lines.append("],")
	lines.append("\"final\": %s" % JSON.stringify(rec["final"]))
	lines.append("}")
	return "\n".join(lines) + "\n"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var check := args.has("--check")
	var only := ""
	for a: String in args:
		if not a.begins_with("--"):
			only = a
	var bad := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for g: Dictionary in games():
		if only != "" and str(g["name"]) != only:
			continue
		var t0 := Time.get_ticks_msec()
		var rec := play(g)
		var fin: Dictionary = rec["final"]
		var dg: PackedStringArray = rec["digest_after"]
		var ok := bool(fin["over"]) and dg.size() > 0 and dg[dg.size() - 1] == str(fin["digest"]) \
			and str(rec["replay_final"]) == str(fin["digest"])
		print("%s %s: %d acts, over %s, winner %d, round %d, vp %s, %d ms" % ["ok  " if ok else "BAD ", g["name"],
			(rec["acts"] as Array).size(), fin["over"], fin["winner"], fin["round"], fin["vp"], Time.get_ticks_msec() - t0])
		if not ok:
			bad += 1
			continue
		var path := "%s/%s.json" % [OUT_DIR, g["name"]]
		var text := to_text(rec)
		if check:
			if FileAccess.get_file_as_string(path) != text:
				print("DIFF %s" % path)
				bad += 1
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("BAD  cannot write %s" % path)
			bad += 1
			continue
		f.store_string(text)
		f.close()
		print("     wrote %s (%d bytes)" % [path, text.length()])
	quit(1 if bad > 0 else 0)
