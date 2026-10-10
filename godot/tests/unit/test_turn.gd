extends "res://tests/testing.gd"
## core/battle/turn.gd (BtTurn, R1_PORT_SPEC §1.12): turns and phases. Page parity from
## fixtures/turn/page_samples.json (tools/record_turn.js: startTurn, startFight + fightTarget, endTurn, endRoundCheck on
## seeded worlds), then hand cases: team helpers, start_match (local pids, cp, seeded lists, deploy, objectives), the
## start-of-turn order and PEND order, cp per seat, shields of the own team only, scoring from round 2, the phase chain,
## advance_step (command wait, fight order, end of turn), player_done with mixed teams, end_turn skipping dead teams and
## wrapping rounds, finish / check_over, the VP tie broken by points (30 = lcm of every n), and a pinned digest.

const FIXTURE := "res://tests/unit/fixtures/turn/page_samples.json"
## Digest of the fixed scenario in _digest_scenario; changes only on purpose.
const PINNED_DIGEST := "d87bfac5c3391c9d"
const FLAG_NAMES := ["moved", "adv", "fell", "still", "shot", "charged", "fought", "ch_done", "shaken", "ow_used", "opened"]

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = _iv(raw) if raw is Dictionary else {}


# ------------------------------------------------------------------ helpers
## JSON numbers come back as floats: every whole number becomes an int (recursively).
func _iv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v)
		TYPE_ARRAY:
			var a: Array = []
			for x: Variant in v:
				a.append(_iv(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _iv(v[k])
			return d
	return v


func _flags(s: BattleState.Squad) -> Array:
	return [s.moved, s.adv, s.fell, s.still, s.shot, s.charged, s.fought, s.ch_done, s.shaken, s.ow_used, s.opened].map(
		func(b: bool) -> int: return 1 if b else 0)


## A fixture world as a BattleState (on, in the world's phase).
func _world(w: Dictionary) -> BattleState:
	var g: Dictionary = w["g"]
	var st := BattleState.make({"seed": 5, "w": 60, "teams": int(g["teams"]), "goal": str(g["goal"]), "rounds": int(g["rounds"])})
	st.on = true
	st.round_no = int(g["round"])
	st.turn = int(g["turn"])
	st.phase = BattleState.PHASES.find(str(g["phase"]))
	var vp: Array = g["vp"]
	for t: int in vp.size():
		st.vp[t] = int(vp[t])
	for p: Array in w["seats"]:
		var seat := st.add_seat(int(p[0]), "", int(p[1]) != 0, false, "")
		seat.cp = int(p[2])
		seat.done = int(p[3]) != 0
	for sd: Dictionary in w["squads"]:
		var s := st.add_squad(str(sd["id"]), str(sd["k"]), int(sd["side"]), int(sd["pl"]), int(sd["n0"]), int(sd["vs"]))
		var f: Array = sd["f"]
		var bits := 0
		var masks := [BattleState.F_MOVED, BattleState.F_ADV, BattleState.F_FELL, BattleState.F_STILL, BattleState.F_SHOT,
			BattleState.F_CHARGED, BattleState.F_FOUGHT, BattleState.F_CH_DONE, BattleState.F_SHAKEN, BattleState.F_OW_USED,
			BattleState.F_OPENED]
		for i: int in masks.size():
			if int(f[i]) != 0:
				bits |= int(masks[i])
		s.set_flags(bits)
		s.ch_tgt = str(sd["ct"])
		s.adv_r = int(sd["ar"])
	for u: Array in w["units"]:
		st.add_unit(str(u[0]), st.squad(str(u[1])), int(u[5]), int(u[6]), int(u[7]))
	for b: Array in w["fallen"]:
		var s := st.squad(str(b[1]))
		var m := st.add_unit(str(b[0]), s, 1, 0, 0)
		st.remove_unit(m)
		st.add_body(m)
	return st


func _st(teams: int = 2, round_no: int = 1, turn: int = 0) -> BattleState:
	var st := BattleState.make({"seed": 9, "w": 60, "teams": teams})
	st.on = true
	st.round_no = round_no
	st.turn = turn
	return st


func _sq(st: BattleState, id: String, k: String, side: int, pl: int, pts: Array, hp: int = 0) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, pl, int(t.get("n", 1)), 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, hp if hp > 0 else int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


func _line(n: int, x0: int, z: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append([x0 + i * 1700, z])
	return out


func _pend_rows(st: BattleState) -> Array:
	var out: Array = []
	for p: BattleState.Pend in st.pend:
		out.append([BattleState.KINDS[p.kind], p.u, p.att, p.need, p.n, BattleState.STAGES[p.stage]])
	return out


func _keys(st: BattleState) -> Array:
	var out: Array = []
	for l: Dictionary in st.log_lines:
		out.append(str(l["key"]))
	return out


# ------------------------------------------------------------------ page parity
func test_fixture_loaded() -> void:
	var page: Dictionary = fx.get("page", {})
	assert_eq(int(page.get("rules_v", 0)), GameData.page_rules_v(), "fixture recorded from the page of the data's rules version")
	for k: String in ["start_turn", "fights", "end_turn", "end_round"]:
		assert_true((fx.get(k, []) as Array).size() >= 100, "fixture has the %s samples" % k)
	var c: Dictionary = page.get("consts", {})
	assert_eq([int(c.get("REZ_AURA", 0)), int(c.get("MAX_ROUND", 0)), int(c.get("KILL_ROUNDS", 0))],
		[GameData.const_int("REZ_AURA"), BattleState.MAX_ROUND, BattleState.KILL_ROUNDS], "page constants match the port's")


func test_page_start_turn() -> void:
	var bad: Array = []
	var n := 0
	for c: Dictionary in fx.get("start_turn", []):
		var w: Dictionary = c["in"]
		var want: Dictionary = c["out"]
		var st := _world(w)
		var n_sq := st.squads.size()
		var out: Array[Dictionary] = []
		BtTurn.start_turn(st, out)
		var sqs: Array = []
		for i: int in n_sq:
			var s := st.squads[i]
			sqs.append([s.id, _flags(s), s.ch_tgt, s.adv_r, s.vs])
		var seats: Array = []
		for p: BattleState.Seat in st.seats:
			seats.append([p.cp, 1 if p.done else 0])
		var spawns: Array = []
		for i: int in range(n_sq, st.squads.size()):
			spawns.append(st.squads[i].id.trim_suffix("x"))
		var got := {"squads": sqs, "pend": _pend_rows(st), "seats": seats, "spawns": spawns, "phase": st.phase_name(),
			"cmd_wait": 1 if st.cmd_wait else 0}
		for k: String in got:
			if got[k] != want[k]:
				bad.append([n, k, got[k], want[k]])
		if (want["wind"] as Array) != [st.turn]:
			bad.append([n, "wind called once for the side in turn", want["wind"]])
		n += 1
	assert_true(n >= 100 and bad.is_empty(), "start_turn matches the page in %d worlds (flags, shields, PEND, cp, spawns)" % n, bad.slice(0, 3))


func test_page_fights() -> void:
	var bad: Array = []
	var n := 0
	for c: Dictionary in fx.get("fights", []):
		var st := _world(c["in"])
		var want: Dictionary = c["out"]
		var out: Array[Dictionary] = []
		BtTurn.start_fight(st, out)
		var fought: Array = []
		for s: BattleState.Squad in st.squads:
			fought.append(1 if s.fought else 0)
		var targets: Array = []
		for s: BattleState.Squad in st.alive_squads():
			var t := BtTurn.fight_target(st, s)
			targets.append([s.id, t.id if t != null else null])
		var got := {"order": Array(st.fights), "fought": fought, "targets": targets}
		for k: String in got:
			if got[k] != want[k]:
				bad.append([n, k, got[k], want[k]])
		if st.fights_null or st.fight_at != 0:
			bad.append([n, "fights set"])
		n += 1
	assert_true(n >= 100 and bad.is_empty(), "start_fight order and fight_target match the page in %d worlds" % n, bad.slice(0, 3))


func test_page_end_turn() -> void:
	var bad: Array = []
	var n := 0
	for c: Dictionary in fx.get("end_turn", []):
		var st := _world(c["in"])
		var want: Dictionary = c["out"]
		var calls: Array = want["calls"]
		var out: Array[Dictionary] = []
		BtTurn.end_turn(st, out)
		var done: Array = []
		for p: BattleState.Seat in st.seats:
			done.append(1 if p.done else 0)
		var call := str(calls[0]) if calls.size() == 1 else "?"
		var ok: bool = st.turn == int(want["turn"]) and done == want["done"]
		if call == "start":
			ok = ok and not st.over and st.round_no == int(want["round"]) and st.phase == BattleState.PH_CMD and st.cmd_wait
		elif call.begins_with("round:"):
			ok = ok and st.over and int(call.trim_prefix("round:")) > st.max_round() and st.round_no == st.max_round()
		else:
			ok = false
		if not ok:
			bad.append([n, calls, want["turn"], want["round"], st.turn, st.round_no, st.over])
		n += 1
	assert_true(n >= 100 and bad.is_empty(), "end_turn: next live team, round wrap, end check as the page in %d worlds" % n, bad.slice(0, 3))


func test_page_end_round() -> void:
	var bad: Array = []
	var n := 0
	var draws := 0
	for c: Dictionary in fx.get("end_round", []):
		var st := _world(c["in"])
		var want: Dictionary = c["out"]
		var out: Array[Dictionary] = []
		BtTurn.end_round_check(st, out)
		var fin: Array = want["fin"]
		if fin.size() != 1 or st.winner != int(fin[0]) or not st.over or st.round_no != int(want["round"]):
			bad.append([n, fin, want["round"], st.winner, st.round_no])
		if st.winner == BattleState.DRAW:
			draws += 1
		n += 1
	assert_true(n >= 100 and bad.is_empty(), "end_round_check winner and round match the page in %d worlds (%d draws)" % [n, draws], bad.slice(0, 3))
	assert_true(draws >= 3, "the samples hold draws")


# ------------------------------------------------------------------ team helpers
func test_team_helpers() -> void:
	var st := _st(3)
	st.add_seat(0, "A", false, false, "")
	st.add_seat(0, "", true, false, "")
	st.add_seat(1, "", true, false, "")
	assert_eq([BtTurn.team_is_bot(st, 0), BtTurn.team_is_bot(st, 1), BtTurn.team_is_bot(st, 2)], [false, true, false],
		"team_is_bot: mixed no, all bots yes, no seats no")
	assert_false(BtTurn.all_done(st, 0), "all_done: the human has not pressed")
	st.seats[0].done = true
	assert_true(BtTurn.all_done(st, 0), "all_done: bots are never waited for")
	assert_true(BtTurn.all_done(st, 1) and BtTurn.all_done(st, 2), "a bot team and an empty team are always done")
	assert_eq(BtTurn.teams_alive(st), PackedInt32Array(), "nobody on the table")
	var a := _sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	var h := _sq(st, "2:0", "hanu", 2, 2, [[9000, 0]])
	assert_eq(BtTurn.teams_alive(st), PackedInt32Array([0, 2]), "teams with models, in team order")
	var out: Array[Dictionary] = []
	BtPend.deal_damage(st, h, a, 1, 999, false, out)
	assert_eq(BtTurn.teams_alive(st), PackedInt32Array([0, 2]), "a wind body keeps its team in the running")


func test_pts_lcm_covers_every_n() -> void:
	var bad: Array = []
	for t: Dictionary in GameData.types():
		var n := int(t.get("n", 0))
		if n < 1 or BtTurn.PTS_LCM % n != 0:
			bad.append([t["k"], n])
	assert_true(bad.is_empty(), "30 is a common multiple of every datasheet's n (%d types)" % GameData.count(), bad)


# ------------------------------------------------------------------ start_match
func _match(setup: Dictionary) -> BattleState:
	var st := BattleState.make(setup)
	BtArmy.mk_players(st)
	return st


func test_start_match() -> void:
	var st := _match({"seed": 11, "w": 48, "teams": 2, "perTeam": 2, "mode": "pve"})
	st.seats[1].pid = "srv-pid"
	var out: Array[Dictionary] = []
	BtTurn.start_match(st, out)
	var pids: Array = []
	for p: BattleState.Seat in st.seats:
		pids.append(p.pid)
	assert_eq(pids, ["L0", "srv-pid", "", ""], "D8: a human seat without a pid gets L<seat>, a server pid stays, bots keep \"\"")
	var cps: Array = []
	for p: BattleState.Seat in st.seats:
		cps.append(p.cp)
	assert_eq(cps, [2, 2, 1, 1], "cp 1 for every seat, +1 for the first team's seats at its first command phase")
	var lists_ok := true
	for p: BattleState.Seat in st.seats:
		lists_ok = lists_ok and BtArmy.has_units(st, p.id) and p.has_dep
	assert_true(lists_ok, "every empty seat got a seeded list and a deployment point")
	var twin := _match({"seed": 11, "w": 48, "teams": 2, "perTeam": 2, "mode": "pve"})
	BtArmy.auto_list(twin, 3, null)
	assert_eq(st.seats[3].list, twin.seats[3].list, "the list is BtArmy.auto_list seeded (armies:<seat>)")
	assert_true(st.squads.size() > 0 and st.units.size() > 0, "deployed (%d squads, %d models)" % [st.squads.size(), st.units.size()])
	assert_eq(st.objs.size(), 5, "five objectives placed")
	assert_eq([st.on, st.over, st.round_no, st.turn, st.phase, st.cmd_wait, st.winner, Array(st.vp)],
		[true, false, 1, 0, BattleState.PH_CMD, true, BattleState.NO_WINNER, [0, 0]], "match state at the first command phase")
	assert_true(_keys(st).has("match_start") and _keys(st).has("turn_start"), "match_start and turn_start logged")
	# the page's advance runs next (Battle.start): the command phase ends unless a shock waits
	var guard := 0
	while BtTurn.advance_step(st, out) and guard < BtTurn.ADVANCE_GUARD:
		guard += 1
	assert_eq(st.phase, BattleState.PH_MOVE, "after advance: move phase")
	# kill mode: no objectives; injected objectives are kept
	var k := _match({"seed": 11, "w": 48, "teams": 2, "goal": "kill"})
	k.add_obj(1, 0, 0)
	BtTurn.start_match(k, out)
	assert_eq(k.objs.size(), 0, "kill: no objectives")
	var inj := _match({"seed": 11, "w": 48, "teams": 2})
	inj.add_obj(7, 12340, -5670)
	BtTurn.start_match(inj, out)
	assert_eq([inj.objs.size(), inj.objs[0].n, inj.objs[0].x], [1, 7, 12340], "injected objectives are not replaced")
	# same setup, same digest
	var a := _match({"seed": 21, "w": 60, "teams": 3})
	var b := _match({"seed": 21, "w": 60, "teams": 3})
	BtTurn.start_match(a, out)
	BtTurn.start_match(b, out)
	assert_eq(a.digest(), b.digest(), "start_match is a pure function of the setup")


func test_start_match_skips_an_empty_first_team() -> void:
	# squads placed by hand for teams 1 and 2 only: deploy then does nothing (the table is not empty)
	var out: Array[Dictionary] = []
	var st2 := _match({"seed": 3, "w": 48, "teams": 3})
	_sq(st2, "1:0", "infantry", 1, 1, [[0, 9000]])
	_sq(st2, "2:0", "infantry", 2, 2, [[0, -9000]])
	BtTurn.start_match(st2, out)
	assert_eq([st2.over, st2.turn], [false, 1], "team 0 has no models: team 1 takes the first turn")
	var st3 := _match({"seed": 3, "w": 48, "teams": 2})
	_sq(st3, "1:0", "infantry", 1, 1, [[0, 9000]])
	BtTurn.start_match(st3, out)
	assert_eq([st3.over, st3.winner], [true, 1], "one team on the table: the match is over at once")


# ------------------------------------------------------------------ start_turn
func test_start_turn_order() -> void:
	var st := _st(2, 2, 0)
	var p0 := st.add_seat(0, "L0", false, false, "")
	var p1 := st.add_seat(0, "L1", false, false, "")
	var p2 := st.add_seat(1, "", true, false, "")
	p0.cp = 1
	p1.cp = 3
	p2.cp = 0
	p0.done = true
	p2.done = true
	var rk := "rwar"
	var half := _sq(st, "0:0", "infantry", 0, 0, _line(4, -20000, 0))
	half.n0 = 10
	var brave := _sq(st, "0:1", "spartan", 0, 0, [[-20000, 8000]])
	var rez := _sq(st, "1:0", rk, 0, 1, _line(6, 0, 0))
	var mine := _sq(st, "0:2", "infantry", 0, 0, _line(6, 20000, 20000))
	var theirs := _sq(st, "1:1", "infantry", 1, 2, [[20000, -20000]])
	var dead := _sq(st, "0:3", "infantry", 0, 0, [[-25000, -20000]])
	st.remove_unit(dead.models[0])
	for s: BattleState.Squad in [mine, theirs, dead]:
		s.moved = true
		s.shot = true
		s.shaken = true
		s.ow_used = true
		s.ch_tgt = "x"
	var out: Array[Dictionary] = []
	BtTurn.start_turn(st, out)
	assert_eq([mine.moved, mine.shot, mine.shaken, mine.ow_used, mine.ch_tgt], [false, false, false, false, ""], "own living squad: flags, shaken and overwatch cleared")
	assert_eq([theirs.moved, theirs.shot, theirs.shaken, theirs.ow_used], [true, true, true, false], "the other side: only overwatch is cleared")
	assert_eq([dead.moved, dead.shaken, dead.ow_used], [true, true, true], "a wiped squad is untouched")
	assert_eq([p0.cp, p1.cp, p2.cp], [2, 4, 0], "every seat of the team in turn gains one CP")
	assert_eq([p0.done, p2.done], [false, false], "every seat is not done")
	assert_eq(_pend_rows(st), [["shock", "0:0", 0, 7, 0, "shock"], ["rez", "1:0", 1, 5, 4, "rez"]],
		"PEND: shocks first (half strength, not brave), then rez (need, lost models), attacker = the squad's seat")
	assert_true(BtSquads.half(brave) and _keys(st).has("shock_free_brave"), "a brave squad below half never tests")
	assert_eq([st.phase, st.cmd_wait, st.fights_null, st.fight_at], [BattleState.PH_CMD, true, false, 0], "command phase waits")
	var evs: Array = []
	for e: Dictionary in out:
		if Events.id_of(e) == Events.Id.TURN:
			evs.append([e["team"], e["round"]])
	assert_eq(evs, [[0, 2]], "one TURN event")


func test_start_turn_half_and_brave() -> void:
	var st := _st()
	st.add_seat(0, "L0", false, false, "")
	var one := _sq(st, "0:0", "cmdr", 0, 0, [[0, 0]])
	one.models[0].hp = 1
	var br := _sq(st, "0:1", "spartan", 0, 0, [[20000, 0]])
	var full := _sq(st, "0:2", "infantry", 0, 0, _line(5, -20000, 10000))
	full.n0 = 10
	var out: Array[Dictionary] = []
	BtTurn.start_turn(st, out)
	assert_eq(_pend_rows(st), [["shock", "0:0", 0, BtAbilities.num(one.ti, "ld"), 0, "shock"]],
		"a one-model squad below half wounds tests; exactly half the models does not; brave never")
	assert_true(BtSquads.half(br) and _keys(st).has("shock_free_brave"), "the brave squad was below half and passed")


# ------------------------------------------------------------------ phases
func test_finish_command_scores_from_round_two() -> void:
	var st := _st(2, 1, 0)
	st.add_seat(0, "L0", false, false, "")
	st.add_obj(1, 0, 0)
	_sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	var out: Array[Dictionary] = []
	BtTurn.finish_command(st, out)
	assert_eq([st.vp[0], st.phase, st.cmd_wait], [0, BattleState.PH_MOVE, false], "round 1: no score, move phase")
	st.round_no = 2
	st.phase = BattleState.PH_CMD
	BtTurn.finish_command(st, out)
	assert_eq(st.vp[0], 5, "round 2: the held objective scores")
	var k := BattleState.make({"seed": 1, "teams": 2, "goal": "kill"})
	k.on = true
	k.round_no = 3
	k.add_obj(1, 0, 0)
	_sq(k, "0:0", "infantry", 0, 0, [[0, 0]])
	BtTurn.finish_command(k, out)
	assert_eq(k.vp[0], 0, "kill mode never scores")


func test_next_phase_chain() -> void:
	var st := _st(2, 1, 0)
	var p := st.add_seat(0, "L0", false, false, "")
	st.add_seat(1, "L1", false, false, "")
	_sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	_sq(st, "1:0", "infantry", 1, 1, [[0, 30000]])
	st.phase = BattleState.PH_MOVE
	var out: Array[Dictionary] = []
	var seen: Array = []
	for i: int in 3:
		p.done = true
		BtTurn.next_phase(st, out)
		seen.append(st.phase_name())
		assert_false(p.done, "done cleared on every phase change")
	assert_eq(seen, ["shoot", "charge", "fight"], "move -> shoot -> charge -> fight")
	assert_true(st.fights_null, "the fight order is made later (advance)")
	BtTurn.next_phase(st, out)
	assert_eq([st.turn, st.phase, st.round_no], [1, BattleState.PH_CMD, 1], "fight -> next team's command phase")
	BtTurn.next_phase(st, out)
	assert_eq([st.turn, st.round_no], [0, 2], "cmd -> end of turn too (endph \"\" from cmd), round wraps")
	st.over = true
	BtTurn.next_phase(st, out)
	assert_eq([st.turn, st.phase], [0, BattleState.PH_CMD], "nothing once over")
	var off := _st()
	off.on = false
	off.phase = BattleState.PH_MOVE
	BtTurn.next_phase(off, out)
	assert_eq(off.phase, BattleState.PH_MOVE, "nothing before the match")


func test_advance_command_waits_for_shocks() -> void:
	var st := _st(2, 1, 0)
	st.add_seat(0, "L0", false, false, "")
	var s := _sq(st, "0:0", "infantry", 0, 0, _line(2, 0, 0))
	s.n0 = 10
	_sq(st, "1:0", "infantry", 1, 0, [[0, 30000]])
	var out: Array[Dictionary] = []
	BtTurn.start_turn(st, out)
	assert_eq(st.pend.size(), 1, "a shock waits")
	assert_false(BtTurn.advance_step(st, out), "advance stops while a shock waits")
	assert_eq(st.phase, BattleState.PH_CMD, "still command")
	BtPend.apply_shock(st, st.pend[0], [6, 6], false, out)
	assert_true(BtTurn.advance_step(st, out), "the command phase ends")
	assert_eq([st.phase, st.cmd_wait], [BattleState.PH_MOVE, false], "move phase")
	assert_false(BtTurn.advance_step(st, out), "nothing more happens by itself in move")


func test_fight_flow() -> void:
	var st := _st(2, 1, 0)
	st.add_seat(0, "L0", false, false, "")
	st.add_seat(1, "L1", false, false, "")
	var a := _sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	var b := _sq(st, "0:1", "infantry", 0, 0, [[20000, 0]])
	var x := _sq(st, "1:0", "infantry", 1, 1, [[0, 2000]])
	var y := _sq(st, "1:1", "infantry", 1, 1, [[20000, 2000]])
	var lone := _sq(st, "1:2", "infantry", 1, 1, [[-30000, -20000]])
	b.charged = true
	b.ch_tgt = y.id
	st.phase = BattleState.PH_FIGHT
	st.fights_null = true
	var out: Array[Dictionary] = []
	assert_false(BtTurn.advance_step(st, out), "an attack waits for its roll")
	assert_eq(Array(st.fights), ["0:1", "1:0", "0:0", "1:1"], "chargers first, then the other side and the rest alternating")
	assert_eq([st.fight_at, st.pend.size(), st.pend[0].u, st.pend[0].t, st.pend[0].how], [1, 1, "0:1", "1:1", BattleState.HOW_FIGHT],
		"the charger fights its charge target")
	assert_false(lone.fought, "not engaged: not in the order")
	# resolve every fight with misses
	var who: Array = []
	var ones: Array = []
	ones.resize(60)
	ones.fill(1)
	var guard := 0
	while st.phase == BattleState.PH_FIGHT and not st.pend.is_empty() and guard < 10:
		who.append("%s>%s" % [st.pend[0].u, st.pend[0].t])
		BtPend.apply_hit(st, st.pend[0], ones, out)
		guard += 1
		BtTurn.advance_step(st, out)
	assert_eq(who, ["0:1>1:1", "1:0>0:0", "0:0>1:0", "1:1>0:1"], "each fights once, in order, its target")
	assert_eq([a.fought, b.fought], [true, true], "the side that just ended its turn keeps fought (the next turn is the other side's)")
	assert_eq([st.turn, st.phase], [1, BattleState.PH_CMD], "the fight phase ended the turn")


func test_schedule_fight_skips() -> void:
	var st := _st(2, 1, 0)
	var a := _sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	var x := _sq(st, "1:0", "infantry", 1, 1, [[0, 2000]])
	var far := _sq(st, "0:1", "infantry", 0, 0, [[30000, 0]])
	st.fights = PackedStringArray(["nobody", "0:1", "0:0", "1:0"])
	a.fought = true
	var out: Array[Dictionary] = []
	assert_true(BtTurn.schedule_fight(st, out), "found one")
	assert_eq([st.fight_at, st.pend[0].u], [4, "1:0"], "skips an unknown id, a squad with no target, one that fought")
	assert_false(BtTurn.schedule_fight(st, out), "the order is used up")
	assert_true(far != null and x != null, "squads")
	# fight_target: the charge target only while engaged; else the nearest edge, the earlier squad on ties
	var st2 := _st()
	var s := _sq(st2, "0:0", "infantry", 0, 0, [[0, 0]])
	var p := _sq(st2, "1:0", "infantry", 1, 1, [[1700, 1000]])
	var q := _sq(st2, "1:1", "infantry", 1, 1, [[-1700, 1000]])
	var r := _sq(st2, "1:2", "infantry", 1, 1, [[0, 1900]])
	assert_eq(BtTurn.fight_target(st2, s), r, "nearest edge")
	st2.remove_unit(r.models[0])
	assert_eq(BtTurn.fight_target(st2, s), p, "equal edges: the earlier squad")
	s.ch_tgt = q.id
	assert_eq(BtTurn.fight_target(st2, s), q, "the charge target wins while engaged")
	s.ch_tgt = "1:9"
	assert_eq(BtTurn.fight_target(st2, s), p, "an unknown charge target is ignored")
	assert_eq(BtTurn.fight_target(st2, _sq(st2, "0:1", "infantry", 0, 0, [[30000, 0]])), null, "not engaged: null")


func test_player_done() -> void:
	var st := _st(2, 1, 0)
	var h0 := st.add_seat(0, "L0", false, false, "")
	var h1 := st.add_seat(0, "L1", false, false, "")
	st.add_seat(0, "", true, false, "")
	var o := st.add_seat(1, "L3", false, false, "")
	_sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	_sq(st, "1:0", "infantry", 1, 3, [[0, 30000]])
	st.phase = BattleState.PH_MOVE
	var out: Array[Dictionary] = []
	BtTurn.player_done(st, o.id, "", out)
	assert_false(o.done, "a seat of the other team is ignored")
	BtTurn.player_done(st, h0.id, "shoot", out)
	assert_false(h0.done, "a done for another phase is ignored")
	BtTurn.player_done(st, h0.id, "move", out)
	assert_eq([h0.done, st.phase, _keys(st).back()], [true, BattleState.PH_MOVE, "seat_done"], "first human done: wait for the team-mate")
	BtTurn.player_done(st, h0.id, "", out)
	assert_eq(st.phase, BattleState.PH_MOVE, "a second done of the same seat changes nothing")
	BtTurn.player_done(st, h1.id, "", out)
	assert_eq([st.phase, h0.done, h1.done], [BattleState.PH_SHOOT, false, false], "the last human: next phase (bots are not waited for)")
	BtTurn.player_done(st, 9, "", out)
	assert_eq(st.phase, BattleState.PH_SHOOT, "an unknown seat is ignored")
	st.over = true
	BtTurn.player_done(st, h0.id, "", out)
	assert_false(h0.done, "nothing once over")


# ------------------------------------------------------------------ end of turn and match
func test_end_turn_skips_and_wraps() -> void:
	var st := _st(4, 1, 1)
	for t: int in 4:
		st.add_seat(t, "L%d" % t, false, false, "")
	_sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	_sq(st, "3:0", "infantry", 3, 3, [[0, 30000]])
	var out: Array[Dictionary] = []
	BtTurn.end_turn(st, out)
	assert_eq([st.turn, st.round_no], [3, 1], "team 2 is wiped: skipped")
	BtTurn.end_turn(st, out)
	assert_eq([st.turn, st.round_no], [0, 2], "wraps to team 0 and a new round")
	st.round_no = st.max_round()
	st.turn = 3
	BtTurn.end_turn(st, out)
	assert_eq([st.over, st.round_no], [true, st.max_round()], "past the last round: decided, round stays the last")


func test_finish_and_check_over() -> void:
	var st := _st(3)
	var a := _sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	var b := _sq(st, "1:0", "infantry", 1, 1, [[0, 10000]])
	var p := BattleState.Pend.new()
	BtPend.push(st, p)
	var out: Array[Dictionary] = []
	BtTurn.check_over(st, out)
	assert_false(st.over, "two teams alive: not over")
	st.remove_unit(b.models[0])
	BtTurn.check_over(st, out)
	assert_eq([st.over, st.winner, st.pend.size(), _keys(st).back()], [true, 0, 0, "over_last"], "one team left: it wins, PEND cleared")
	var ov: Array = []
	for e: Dictionary in out:
		if Events.id_of(e) == Events.Id.OVER:
			ov.append(e["result"])
	assert_eq(ov, [0], "one OVER event")
	BtTurn.check_over(st, out)
	assert_eq(ov.size(), 1, "check_over once over: nothing")
	var st2 := _st(2)
	BtTurn.check_over(st2, out)
	assert_eq([st2.over, st2.winner], [true, BattleState.DRAW], "nobody left: a draw")
	var off := _st(2)
	off.on = false
	BtTurn.check_over(off, out)
	assert_false(off.over, "not before the match starts")
	assert_true(a != null, "squad a")


func test_end_round_check_ties() -> void:
	var out: Array[Dictionary] = []
	# VP decides
	var st := _st(3)
	_sq(st, "0:0", "infantry", 0, 0, [[0, 0]])
	_sq(st, "1:0", "infantry", 1, 1, [[0, 10000]])
	st.vp[0] = 10
	st.vp[1] = 15
	st.vp[2] = 99
	BtTurn.end_round_check(st, out)
	assert_eq([st.winner, st.round_no, _keys(st).back()], [1, st.max_round(), "over_rounds"], "most VP among teams still alive wins (a wiped team never)")
	# equal VP: points left, exact 30/n weights; infantry n 10 vs a single model
	var st2 := _st(2)
	var inf := GameData.ty("infantry")
	var big := _sq(st2, "0:0", "infantry", 0, 0, _line(3, 0, 0))
	_sq(st2, "1:0", "infantry", 1, 1, _line(4, 0, 20000))
	BtTurn.end_round_check(st2, out)
	assert_eq(st2.winner, 1, "equal VP: four models beat three")
	assert_eq(BtTurn.left_pts(st2, 0), 3 * int(inf["pts"]) * (30 / int(inf["n"])), "left_pts = sum of pts x 30 / n")
	var st3 := _st(2)
	_sq(st3, "0:0", "infantry", 0, 0, _line(2, 0, 0))
	_sq(st3, "1:0", "infantry", 1, 1, _line(2, 0, 20000))
	BtTurn.end_round_check(st3, out)
	assert_eq(st3.winner, BattleState.DRAW, "equal VP and equal points: a draw")
	# a wind body keeps a team in the running with zero points
	var st4 := _st(2)
	var h := _sq(st4, "0:0", "hanu", 0, 0, [[0, 0]])
	var a := _sq(st4, "1:0", "infantry", 1, 1, [[0, 20000]])
	BtPend.deal_damage(st4, h, a, 1, 999, false, out)
	st4.vp[0] = 20
	st4.vp[1] = 5
	BtTurn.end_round_check(st4, out)
	assert_eq(st4.winner, 0, "a team held only by a wind body can win on VP")
	var st5 := BattleState.make({"seed": 1, "teams": 2, "goal": "kill"})
	st5.on = true
	BtTurn.end_round_check(st5, out)
	assert_eq([st5.winner, st5.round_no, _keys(st5).back()], [BattleState.DRAW, BattleState.KILL_ROUNDS, "over_kill_rounds"], "kill mode: nobody alive is a draw at round 30")
	assert_true(big != null, "big")


# ------------------------------------------------------------------ digest
func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtTurn scenario digest is pinned")


## A two-team match played by fixed rules for up to 400 steps (it ends at round 5, equal VP, decided on points): advance; else resolve the first PEND entry with 4s
## (shock/rez/hit/wound/save/charge) or end the phase; every turn function runs.
func _digest_scenario() -> String:
	var st := _match({"seed": 31, "w": 44, "teams": 2, "budget": 300})
	var out: Array[Dictionary] = []
	BtTurn.start_match(st, out)
	var v := PackedInt64Array()
	for step: int in 400:
		if st.over:
			break
		if BtTurn.advance_step(st, out):
			continue
		if not st.pend.is_empty():
			var p := st.pend[0]
			var four: Array = []
			for i: int in 60:
				four.append(4)
			match p.kind:
				BattleState.K_SHOCK:
					BtPend.apply_shock(st, p, [4, 4], false, out)
				BattleState.K_REZ:
					BtPend.apply_rez(st, p, four, out)
				BattleState.K_ATK:
					if p.stage == BattleState.S_HIT:
						BtPend.apply_hit(st, p, four, out)
					elif p.stage == BattleState.S_WOUND:
						BtPend.apply_wnd(st, p, four, out)
					else:
						BtPend.apply_sav(st, p, four, false, out)
				_:
					BtPend.remove(st, p)
			BtPend.prune(st, out)
			BtTurn.check_over(st, out)
			continue
		if st.phase == BattleState.PH_SHOOT:
			# every squad of the team in turn shoots the first foe it can
			for s: BattleState.Squad in st.alive_squads():
				if s.side != st.turn or s.shot:
					continue
				for t: BattleState.Squad in BtSquads.real_foes(st, s):
					if BtCombat.shot_why_not(st, s, t).get("key", "?") == "":
						BtPend.mk_atk(st, s, t, BattleState.HOW_SHOOT)
						break
				s.shot = true
			if not st.pend.is_empty():
				continue
		BtTurn.next_phase(st, out)
		v.append(Hash.fnv1a64_str(st.digest()))
	v.append(Hash.fnv1a64_str(st.digest()))
	return Hash.digest_hex(v)
