extends "res://tests/testing.gd"
## core/battle/battle.gd (Battle extends Table, R1_PORT_SPEC §1.17): make (seats, injected or generated props,
## objectives, units0 with the squad facing from model 0's rot), start (start_match + advance, no act logged), every code
## through Table.apply (logged with seq, sanitised like the Worker, unknown codes refused), advance (prune + steps),
## state_ints in sync with Table, snapshot/restore mid-game (and a refused bad snapshot), flush offline/online,
## bot_step, a whole bot game and a pinned digest of it. The page's own runs are the oracle replay (tests/oracle).

## Digest of _bot_game(77) at its end; changes only on purpose.
const PINNED_GAME := "e6f79681a816b4b1"


func _setup(seed_v: int, goal: String = "obj", w: int = 48) -> Dictionary:
	return {"seed": seed_v, "w": w, "teams": 2, "perTeam": 1, "goal": goal, "rounds": 3, "budget": 500, "theme": "ruin",
		"terrain": "hills"}


func _bots() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"team": 0, "bot": true}, {"team": 1, "bot": true}]
	return out


## Two seats with one squad of k each, deployed 20" apart on an open table.
func _duel(k0: String, k1: String, bot: bool = false) -> Battle:
	var l0 := PackedInt32Array()
	l0.resize(GameData.count())
	l0[GameData.index_of(k0)] = 1
	var l1 := PackedInt32Array()
	l1.resize(GameData.count())
	l1[GameData.index_of(k1)] = 1
	var seats: Array[Dictionary] = [
		{"team": 0, "bot": bot, "pid": "" if bot else "A", "list": l0, "dep": [0, -10000]},
		{"team": 1, "bot": bot, "pid": "" if bot else "B", "list": l1, "dep": [0, 10000]}]
	var no_props: Array[Dictionary] = []
	return Battle.make(_setup(3, "kill"), seats, {"props": no_props})


func _codes(evs: Array[Dictionary]) -> Array:
	var out: Array = []
	for e: Dictionary in evs:
		out.append(Events.name_of(Events.id_of(e)))
	return out


func _bad(evs: Array[Dictionary]) -> String:
	for e: Dictionary in evs:
		if Events.id_of(e) == Events.Id.BAD_ACT:
			return str(e["key"])
	return ""


## The page's botTick loop, headless: bot_step until nothing is left, then the team's endph (BtBot.finished_act).
## Returns the number of acts applied; stops at over or after max_steps.
func _drive(b: Battle, max_steps: int) -> int:
	for i: int in max_steps:
		if b.st.over:
			break
		var before := b.actlog.size()
		var what := b.bot_step()
		if what == "":
			var e := BtBot.finished_act(b.st)
			if not e.is_empty():
				e["pid"] = ""
				b.apply(e)
		if b.actlog.size() == before:
			b.flush(true, {"online": false})
		if b.actlog.size() == before:
			break
	return b.actlog.size()


func _bot_game(seed_v: int) -> Battle:
	var no_props: Array[Dictionary] = []
	var b := Battle.make(_setup(seed_v), _bots(), {"props": no_props})
	b.start()
	_drive(b, 3000)
	return b


# ---------------------------------------------------------------- make / start
func test_make_seats_props_objectives() -> void:
	var l := PackedInt32Array()
	l.resize(GameData.count())
	l[GameData.index_of("infantry")] = 2
	var seats: Array[Dictionary] = [
		{"team": 0, "pid": "A", "list": l, "fac": "mod", "dep": PackedInt64Array([1000, -9000]), "cp": 4, "nm": "x",
			"skin": {"hoplite": 1}},
		{"team": 1, "bot": true, "list": [["bad"], -3], "dep": []},
		{"team": 1, "ai": true, "pid": "C"}]
	var objs := [{"n": 0, "x": 0, "z": 0}, {"n": 1, "x": 5000, "z": 6000}]
	var props: Array[Dictionary] = [BtBlocking.prep_one("boulder", 9000, 0, 0, 10000, 0, 0, 0)]
	var b := Battle.make(_setup(9), seats, {"props": props, "objectives": objs})
	var st := b.st
	assert_eq([st.seats.size(), st.seats[0].pid, st.seats[0].team, st.seats[0].list[GameData.index_of("infantry")],
		st.seats[0].has_dep, st.seats[0].dep_x, st.seats[0].dep_z, st.seats[0].cp, st.seats[0].nm],
		[3, "A", 0, 2, true, 1000, -9000, 4, "x"], "seat 0 as given")
	assert_eq([st.seats[1].bot, st.seats[1].has_dep, st.seats[2].ai, st.seats[2].pid], [true, false, true, "C"],
		"bot and ai flags; an empty dep is none")
	assert_eq(st.seats[1].list.size(), GameData.count(), "an Array list goes through fit_list")
	assert_eq([st.props.size(), st.props_injected, st.objs.size(), st.objs[1].x], [1, true, 2, 5000], "injected props and objectives")
	assert_eq([b.seed, b.last_error, b.actlog.size()], [9, "", 0], "Table seed is the setup seed; nothing logged")
	var g := Battle.make(_setup(9, "obj", 30), _bots(), {})
	assert_true(not g.st.props_injected and g.st.props.size() > 0, "no props in the fixture: generated from the setup", g.st.props.size())
	var g2 := Battle.make(_setup(9, "obj", 30), _bots(), {})
	assert_eq(g2.st.props_hash, g.st.props_hash, "generated props are a function of the setup")


func test_start() -> void:
	var no_props: Array[Dictionary] = []
	var b := Battle.make(_setup(4), _bots(), {"props": no_props})
	var evs := b.start()
	var st := b.st
	assert_true(st.on and not st.over, "the match is on")
	assert_eq([st.round_no, st.turn, st.phase], [1, 0, BattleState.PH_MOVE], "start runs advance: round 1, team 0, cmd done -> move")
	assert_eq([b.turn, b.round_no, b.phase, b.over], [0, 1, BattleState.PH_MOVE, 0], "Table fields follow")
	assert_eq([st.seats[0].cp, st.seats[1].cp], [2, 1], "cp 1 each, +1 for the team in turn")
	assert_true(st.squads.size() > 0 and st.units.size() > 0, "the seeded armies are deployed")
	assert_eq(st.objs.size(), 5, "five objectives placed")
	assert_eq([b.actlog.size(), b.applied], [0, 0], "start logs no act")
	assert_true(_codes(evs).has("PHASE") and _codes(evs).has("TURN"), "start returns the events", _codes(evs))
	var k := Battle.make(_setup(4, "kill"), _bots(), {"props": no_props})
	k.start()
	assert_eq(k.st.objs.size(), 0, "kill: no objectives")
	var k2 := Battle.make(_setup(4, "kill"), _bots(), {"props": no_props})
	k2.start()
	assert_eq(k2.digest(), k.digest(), "start is a pure function of setup, seats and fixture")


func test_units0() -> void:
	var b0 := _duel("infantry", "hoplite")
	assert_eq(b0.st.units.size(), 0, "make without units0 does not deploy (start does)")
	# the ids and order of the v10 deployment, from a started copy
	var ref := _duel("infantry", "hoplite")
	ref.start()
	var rows: Array = []
	var i := 0
	for m: BattleState.Unit in ref.st.units:
		# quarter turn (pi/2 in Q16) for every model, positions shifted by 10 MI per model
		rows.append({"id": m.id, "x": m.x + 10 * (i + 1), "z": m.z - 20, "rot": Fx.HALF_PI_Q16})
		i += 1
	var l0 := ref.st.seats[0].list
	var l1 := ref.st.seats[1].list
	var seats: Array[Dictionary] = [{"team": 0, "pid": "A", "list": l0, "dep": [0, -10000]},
		{"team": 1, "pid": "B", "list": l1, "dep": [0, 10000]}]
	var no_props: Array[Dictionary] = []
	var b := Battle.make(_setup(3, "kill"), seats, {"props": no_props, "units0": rows})
	assert_eq(b.last_error, "", "units0 with the deploy's ids in order is accepted")
	assert_eq(b.st.units.size(), rows.size(), "make deployed")
	var ok := true
	for j: int in rows.size():
		var e: Dictionary = rows[j]
		var m := b.st.units[j]
		if m.id != str(e["id"]) or m.x != int(e["x"]) or m.z != int(e["z"]):
			ok = false
	assert_true(ok, "every model at its units0 position")
	assert_eq([b.st.squads[0].fx, b.st.squads[0].fz], [1000, 0], "squad facing from model 0's rot: (sin, cos) of a quarter turn")
	b.start()
	assert_eq([b.st.units.size(), b.st.units[0].x], [rows.size(), int((rows[0] as Dictionary)["x"])], "start does not deploy again")
	var bad := rows.duplicate(true)
	(bad[0] as Dictionary)["id"] = "9:9.9"
	var c := Battle.make(_setup(3, "kill"), seats, {"props": no_props, "units0": bad})
	assert_eq(c.last_error, "bad_units0", "an unknown id is reported")


# ---------------------------------------------------------------- apply
func test_every_code_through_apply() -> void:
	var b := _duel("infantry", "infantry")
	b.start()
	var st := b.st
	assert_eq(b.codes(), PackedStringArray(BtActs.CODES), "codes() is BtActs.CODES")
	var evs := b.apply({"a": "fly", "pid": "A"})
	assert_eq([_bad(evs), b.actlog.size()], ["bad_code", 0], "an unknown code is refused by Table and not logged")
	evs = b.apply({"a": "stay", "u": "0:0"})
	assert_eq([_bad(evs), b.actlog.size()], ["bad_pid", 0], "an act without a pid is refused")
	# move phase
	var s := st.squad("0:0")
	var c0 := BtSquads.center(s)
	b.apply({"a": "smove", "pid": "A", "u": "0:0", "how": "move", "x": c0[0], "z": c0[1] + 4000})
	assert_true(s.moved and BtSquads.center(s)[1] > c0[1] + 3000, "smove x/z through apply")
	assert_eq([b.actlog.size(), st.act_seq, b.actlog.at(1)["seq"]], [1, 1, 1], "logged with seq; act_seq follows")
	b.apply({"a": "move", "pid": "A", "u": "0:0", "x": 0, "z": 0})
	b.apply({"a": "stay", "pid": "B", "u": "1:0"})
	assert_true(st.squad("1:0").moved, "stay through apply")
	b.apply({"a": "endturn", "pid": "A"})
	assert_eq(st.phase, BattleState.PH_SHOOT, "legacy endturn in move: next phase")
	b.apply({"a": "adv", "pid": "A", "u": "0:0", "roll": 9})
	assert_eq(s.adv_r, 6, "the act is sanitised again before the rules (roll 9 -> 6, as the Worker)")
	# shoot phase: a staged attack, then flush rolls the rest
	b.apply({"a": "atk", "pid": "A", "u": "1:0", "t": "0:0", "how": "shoot", "hit": [6, 6, 6, 6, 6]})
	b.apply({"a": "wnd", "pid": "A", "u": "1:0", "t": "0:0", "wound": [6, 6]})
	b.apply({"a": "rr", "pid": "A", "u": "1:0", "t": "0:0", "v": 6})
	b.apply({"a": "sav", "pid": "B", "u": "1:0", "t": "0:0", "save": [6, 6], "gtg": 0})
	assert_eq(st.pend.size(), 0, "atk/wnd/sav through apply")
	b.apply({"a": "shoot", "pid": "A", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [1], "wound": [], "save": []})
	b.apply({"a": "skip", "pid": "A", "u": "0:0", "ph": ""})
	b.apply({"a": "gren", "pid": "A", "u": "0:0", "t": "1:0", "roll": [1, 1, 1, 1, 1, 1]})
	b.apply({"a": "heal", "pid": "A", "u": "0:0", "t": "0:0", "roll": 1})
	b.apply({"a": "done", "pid": "A", "ph": "shoot"})
	assert_eq(st.phase, BattleState.PH_CHARGE, "done of the only human of team 0: next phase")
	b.apply({"a": "chg", "pid": "A", "u": "0:0", "t": "1:0"})
	assert_eq(st.pend.size(), 1, "chg declared")
	b.apply({"a": "ow", "pid": "B", "u": "0:0", "t": "1:0", "use": 0})
	b.apply({"a": "chr", "pid": "A", "u": "0:0", "t": "1:0", "roll": [6, 6]})
	b.apply({"a": "cmove", "pid": "A", "u": "0:0", "t": "1:0", "to": [[0, 0]]})
	b.apply({"a": "shock", "pid": "A", "u": "0:0", "roll": [6, 6]})
	b.apply({"a": "rez", "pid": "A", "u": "0:0", "roll": [6]})
	b.apply({"a": "endph", "pid": "A", "ph": "charge"})
	assert_true(st.phase == BattleState.PH_FIGHT or st.turn == 1, "endph in charge: fight (or the fights already ended the turn)")
	var seen := {}
	for a: Dictionary in b.actlog.acts():
		seen[str(a["a"])] = true
	var missing: Array = []
	for code: String in BtActs.CODES:
		if not seen.has(code):
			missing.append(code)
	assert_eq(missing, [], "every code went through apply and was logged")
	assert_eq(b.applied, b.actlog.size(), "applied counts the logged acts")


func test_advance_prunes_and_steps() -> void:
	var b := _duel("infantry", "infantry")
	b.start()
	var st := b.st
	var p := BtPend.mk_atk(st, st.squad("0:0"), st.squad("1:0"), BattleState.HOW_SHOOT)
	assert_true(p != null and st.pend.size() == 1, "an attack queued by hand")
	for m: BattleState.Unit in st.squad("1:0").models.duplicate():
		st.remove_unit(m)
	b.advance()
	assert_true(st.pend.is_empty() and st.over and b.over == 1, "advance prunes the attack on a dead squad, then check_over ends the match")
	var c := _duel("infantry", "infantry")
	c.start()
	c.st.phase = BattleState.PH_CMD
	c.st.cmd_wait = true
	c.advance()
	assert_eq([c.st.phase, c.phase], [BattleState.PH_MOVE, BattleState.PH_MOVE], "advance finishes the command phase")


# ---------------------------------------------------------------- ints, snapshot
func test_state_ints_in_sync() -> void:
	var b := _duel("infantry", "infantry")
	b.start()
	var d0 := b.digest()
	b.apply({"a": "endph", "pid": "A", "ph": "move"})
	var v := b.state_ints()
	var head := PackedInt64Array([b.rules_v, b.seed, b.actlog.last_seq(), b.applied, b.st.turn, b.st.round_no, b.st.phase,
		1 if b.st.over else 0])
	assert_eq(v.slice(0, 8), head, "Table part first, with turn/round/phase/over of the BattleState")
	assert_eq(v.slice(8), b.st.state_ints(), "then BattleState.state_ints()")
	assert_ne(b.digest(), d0, "an act changes the digest")
	b.st.turn = 1
	assert_eq(b.state_ints()[4], 1, "state_ints syncs Table.turn even after a direct change")


func test_snapshot_restore_mid_game() -> void:
	var no_props: Array[Dictionary] = []
	var a := Battle.make(_setup(12), _bots(), {"props": no_props})
	a.start()
	_drive(a, 40)
	assert_true(a.actlog.size() > 10 and not a.st.over, "mid-game", a.actlog.size())
	var snap := a.snapshot()
	var b := Battle.make(_setup(12), _bots(), {"props": no_props})
	assert_true(b.restore(snap), "restore", b.last_error)
	assert_eq(b.digest(), a.digest(), "the restored table has the same digest")
	assert_eq([b.turn, b.round_no, b.phase, b.actlog.size()], [a.turn, a.round_no, a.phase, a.actlog.size()], "Table fields and log")
	_drive(a, 30)
	_drive(b, 30)
	assert_eq(b.digest(), a.digest(), "both continue identically (bot streams travel in the snapshot)")
	var d := b.digest()
	var bad := snap.duplicate(true)
	bad.erase("battle")
	assert_false(b.restore(bad), "no battle part: refused")
	var bad2 := snap.duplicate(true)
	bad2["turn"] = int(bad2["turn"]) + 1
	assert_false(b.restore(bad2), "Table and battle parts that disagree: refused")
	var bad3 := snap.duplicate(true)
	(bad3["battle"] as Dictionary)["v"] = 3
	assert_false(b.restore(bad3), "a wrong rules version inside: refused")
	assert_eq(b.digest(), d, "a refused restore changes nothing")
	# generated props stay out of the snapshot and come back from the setup
	var g := Battle.make(_setup(12, "obj", 30), _bots(), {})
	g.start()
	var gs := g.snapshot()
	assert_false((gs["battle"] as Dictionary).has("props"), "generated props are not in the snapshot")
	var g2 := Battle.make(_setup(12, "obj", 30), _bots(), {})
	assert_true(g2.restore(gs) and g2.digest() == g.digest(), "restored on a table built from the same setup")


# ---------------------------------------------------------------- flush, bots
func test_flush() -> void:
	var b := _duel("infantry", "infantry")
	b.start()
	var st := b.st
	b.apply({"a": "endph", "pid": "A", "ph": "move"})
	b.apply({"a": "atk", "pid": "A", "u": "0:0", "t": "1:0", "how": "shoot", "hit": [6, 6, 6, 6, 6]})
	assert_eq(st.pend.size(), 1, "a pending attack at wound")
	var n0 := b.actlog.size()
	assert_eq(b.flush(false, {"online": true, "owner": true, "pid": "Z"}), 0, "online, nobody's roll on this device: nothing")
	var n := b.flush(true, {"online": false})
	assert_true(n >= 2 and st.pend.is_empty(), "offline flush rolls wound and save", n)
	assert_eq(b.actlog.size(), n0 + n, "each roll is a logged act")
	var acts := b.actlog.acts()
	assert_eq([acts[n0]["a"], acts[n0]["pid"], acts[n0 + 1]["a"], acts[n0 + 1]["pid"]], ["wnd", "A", "sav", "B"],
		"the wound roll is the attacker's (pid A), the save the defender's (pid B)")
	assert_eq(b.flush(true, {"online": false}), 0, "nothing left")


func test_bot_step() -> void:
	var b := _duel("infantry", "infantry", true)
	b.start()
	var st := b.st
	var w := b.bot_step()
	assert_eq(w, "move", "move phase: the first bot squad moves (or stays and the next one moves)")
	var a0 := b.actlog.at(1)
	assert_eq(a0["pid"], "", "bot acts carry pid ''")
	var guard := 0
	while b.bot_step() != "" and guard < 20:
		guard += 1
	assert_eq(b.bot_step(), "", "nothing left for the bots in this phase")
	var e := BtBot.finished_act(st)
	assert_eq(e.get("a"), "endph", "the caller ends the bot team's phase")
	assert_eq(BtBot.acting_squad(st), null, "acting_squad: nobody left in this phase")
	e["pid"] = ""
	b.apply(e)
	assert_eq([st.phase, BtBot.acting_squad(st).id], [BattleState.PH_SHOOT, "0:0"], "acting_squad in shoot: the first bot squad that has not shot")
	st.phase = BattleState.PH_CMD
	assert_eq(BtBot.acting_squad(st), null, "acting_squad in cmd: none (not a bot phase)")
	st.phase = BattleState.PH_SHOOT
	var h := _duel("infantry", "infantry")
	h.start()
	assert_eq([BtBot.acting_squad(h.st), h.bot_step()], [null, ""], "no bot seats: no acting squad, bot_step does nothing")
	# the stream is the acting squad's seat: same acts as asking next_act with bot:<seat>
	var c := _duel("infantry", "infantry", true)
	c.start()
	var d := _duel("infantry", "infantry", true)
	d.start()
	var sq := BtBot.acting_squad(d.st)
	var want := BtBot.next_act(d.st, d.st.rng("bot:%d" % sq.pl))
	c.bot_step()
	var got := c.actlog.at(1)
	var exp := ActLog.canon(want.merged({"pid": ""}), 1)
	assert_eq(JSON.stringify(got, "", true), JSON.stringify(exp, "", true),
		"bot_step applies next_act with the bot:<seat> stream of the acting squad")


func test_bot_game() -> void:
	var b := _bot_game(77)
	assert_true(b.st.over, "a whole bot game ends", [b.st.round_no, b.st.turn, b.st.phase, b.actlog.size()])
	assert_true(b.actlog.size() > 50, "with many acts", b.actlog.size())
	var c := _bot_game(77)
	assert_eq(c.digest(), b.digest(), "the same game twice: the same digest")
	# replaying the logged acts on a fresh table reproduces the game (what a late joiner does)
	var no_props: Array[Dictionary] = []
	var r := Battle.make(_setup(77), _bots(), {"props": no_props})
	r.start()
	var acts := b.actlog.acts()
	assert_eq(r.replay(acts), acts.size(), "every logged act replays")
	assert_eq(r.st.digest(), b.st.digest(), "replay gives the same battle state")
	assert_digest(b.digest(), PINNED_GAME, "the bot game digest is pinned")
