extends "res://tests/testing.gd"
## MatchRunner (LOBBY_SPEC §4.2, §7.4): the only bridge between the battle screen and the rules. Small tables (36",
## 300 points, about 0.1 s a game): bot vs bot to the end with move and death events; a passive human (done only); an
## active human through the public human acts (the canAct gate, a reachable move, too_far, a shot and a charge where
## legal, end_phase refused out of turn); auto play for the human seat; the charge gate taken from the core (advance
## and charge, dark elves from round 3, flyers after falling back); and every game replays from its act log to the
## same digest (so nothing wrote the rules state outside apply). Pure (no display).

const MAX_STEPS := 20000


func _plan(facs: Array, human: int, goal: String, seed_v: int, size: String = "s", per: int = 1, budget: int = 300) -> Dictionary:
	var c := SeatPlan.defaults(seed_v)
	c["teams"] = facs.size() / per
	c["per_team"] = per
	c["size"] = size
	c["goal"] = goal
	c["rounds"] = 3
	c["budget"] = budget
	var seats: Array = []
	for k in facs.size():
		seats.append({"fac": facs[k], "human": k == human})
	c["seats"] = seats
	var plan := SeatPlan.build(c)
	if not (plan["errors"] as PackedStringArray).is_empty():
		assert_eq(PackedStringArray(plan["errors"]), PackedStringArray(), "plan %s seed %d is valid" % [str(facs), seed_v])
	return plan


func _names(evs: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in evs:
		var n := Events.name_of(Events.id_of(e))
		out[n] = int(out.get(n, 0)) + 1
	return out


func test_bot_vs_bot_reaches_the_end() -> void:
	var r := MatchRunner.new(_plan(["kn", "or"], -1, "obj", 4242))
	var evs: Array = r.start()
	var states := {}
	for i in MAX_STEPS:
		var res := r.step()
		evs.append_array(res["events"])
		states[str(res["state"])] = true
		if str(res["state"]) == "over" or str(res["state"]) == "stuck":
			break
	assert_true(r.is_over(), "bot vs bot: the game is over (round %d)" % r.st.round_no)
	assert_false(states.has("stuck"), "bot vs bot: never stuck")
	assert_false(states.has("wait_human"), "bot vs bot: never waits for a human")
	assert_true(r.winner() == BattleState.DRAW or (r.winner() >= 0 and r.winner() < 2), "bot vs bot: a winner or a draw (%d)" % r.winner())
	assert_true(["over_last", "over_rounds", "over_kill_rounds"].has(r.over_why()), "bot vs bot: the end reason is known (%s)" % r.over_why())
	var names := _names(evs)
	assert_true(int(names.get("MOVE_STEP", 0)) > 0, "bot vs bot: MOVE_STEP events are captured (%d)" % int(names.get("MOVE_STEP", 0)))
	assert_true(int(names.get("DEATH", 0)) > 0, "bot vs bot: DEATH events are captured (%d)" % int(names.get("DEATH", 0)))
	assert_eq(int(names.get("OVER", 0)), 1, "bot vs bot: one OVER event")
	assert_eq(int(names.get("BAD_ACT", 0)), 0, "bot vs bot: no refused act")
	assert_eq(r.take_events(), [], "step hands out every event (the queue is empty)")
	assert_eq(r.replayed_digest(), r.digest(), "bot vs bot: the act log replays to the same digest")
	assert_eq(str(r.step()["state"]), "over", "a step after the end stays over")


func test_passive_human_reaches_the_end() -> void:
	var r := MatchRunner.new(_plan(["kn", "or"], 0, "obj", 11))
	r.start()
	assert_eq(r.pid, "L0", "the human seat plays as L0")
	assert_eq(r.human_team(), 0, "the human is in team 0")
	var waits := 0
	var refused := 0
	for i in MAX_STEPS:
		var res := r.step()
		if str(res["state"]) == "wait_human":
			waits += 1
			if r.end_phase() != "":
				refused += 1
		elif str(res["state"]) != "acted":
			break
	assert_true(r.is_over(), "passive human: the game is over (%s)" % r.over_why())
	assert_true(waits >= 3, "passive human: the runner waited for the human (%d times)" % waits)
	assert_eq(refused, 0, "passive human: every end_phase was accepted")
	var mine := 0
	for a: Dictionary in r.acts():
		if str(a.get("pid", "")) == "L0":
			mine += 1
	assert_true(mine >= waits, "passive human: the done acts carry the human pid (%d)" % mine)
	assert_eq(r.replayed_digest(), r.digest(), "passive human: the act log replays to the same digest")


## Plays the human seat by hand through the public acts; returns counters.
func _play_active(r: MatchRunner) -> Dictionary:
	var got := {"move": 0, "shoot": 0, "charge": 0, "too_far": 0, "gate": 0, "refused": 0}
	for i in MAX_STEPS:
		var res := r.step()
		var state := str(res["state"])
		if state == "over" or state == "stuck":
			break
		if state != "wait_human":
			continue
		var st := r.st
		var mine := r.selectable()
		if st.phase == BattleState.PH_MOVE:
			for s in mine:
				if not r.can_select(s):
					continue
				var foes := BtSquads.real_foes(st, s)
				var why := ""
				if not foes.is_empty() and not BtSquads.is_engaged(st, s):
					var c := BtSquads.center(s)
					if got["too_far"] == 0:
						var far := r.move(s, c[0] + BtMoves.move_range(s) * 3, c[1], false)
						if far == "too_far" and r.why_args.size() == 2:
							got["too_far"] += 1
					var f := BtSquads.center(foes[0])
					var dx := f[0] - c[0]
					var dz := f[1] - c[1]
					var d := maxi(1, Fx.isqrt(dx * dx + dz * dz))
					var step_mi := mini(BtMoves.move_range(s) - 500, maxi(0, d - 3000))
					why = r.move(s, c[0] + Fx.idiv(dx * step_mi, d), c[1] + Fx.idiv(dz * step_mi, d), false)
					if why == "":
						got["move"] += 1
						if r.can_select(s):
							got["gate"] += 1   # a moved squad must not be selectable
				if why != "" or r.can_select(s):
					if r.stay(s) != "":
						got["refused"] += 1
		elif st.phase == BattleState.PH_SHOOT:
			for s in mine:
				var done := false
				for t in BtSquads.real_foes(st, s):
					if str(BtCombat.shot_why_not(st, s, t)["key"]) == "":
						if r.shoot(s, t) == "":
							got["shoot"] += 1
						else:
							got["refused"] += 1
						done = true
						break
				if not done and r.can_select(s):
					r.skip(s)
		elif st.phase == BattleState.PH_CHARGE:
			for s in mine:
				for t in BtSquads.real_foes(st, s):
					if str(BtCombat.charge_why_not(st, s, t)["key"]) == "" and BtSquads.edge_within(s, t, 8000):
						if r.charge(s, t) == "":
							got["charge"] += 1
						break
		if not r.is_over() and r.is_human_turn() and r.st.pend.is_empty():
			if r.end_phase() != "":
				got["refused"] += 1
	return got


func test_active_human_through_the_public_acts() -> void:
	var r := MatchRunner.new(_plan(["kn", "or"], 0, "obj", 11))
	r.start()
	# the first wait: the human's move phase
	var res := {}
	for i in 200:
		res = r.step()
		if str(res["state"]) != "acted":
			break
	assert_eq(str(res["state"]), "wait_human", "the runner stops for the human")
	assert_eq(r.st.phase, BattleState.PH_MOVE, "the first human phase is move")
	var mine := r.selectable()
	assert_true(not mine.is_empty(), "the human has selectable squads (%d)" % mine.size())
	var foe: BattleState.Squad = null
	for s in r.st.alive_squads():
		if s.pl != 0:
			foe = s
			break
	assert_false(r.can_select(foe), "an enemy squad is not selectable")
	assert_eq(r.move(foe, 0, 0), "not_now", "moving an enemy squad is refused")
	var s0: BattleState.Squad = mine[0]
	var c := BtSquads.center(s0)
	var far := r.move(s0, c[0], c[1] + BtMoves.move_range(s0) * 4)
	assert_eq(far, "too_far", "a point far away gives too_far")
	assert_eq(r.why_args.size(), 2, "too_far carries [distance, move inches]")
	var n0 := r.acts().size()
	var toward := -1 if c[1] > 0 else 1
	var near := r.move(s0, c[0], c[1] + toward * 2000)
	assert_eq(near, "", "a move to a reachable point applies")
	assert_eq(r.acts().size(), n0 + 1, "the move is one act in the log")
	var evs := r.take_events()
	assert_true(int(_names(evs).get("MOVE_STEP", 0)) > 0, "the move sends MOVE_STEP events")
	assert_false(r.can_select(s0), "a moved squad is no longer selectable")
	assert_eq(r.move(s0, c[0], c[1]), "not_now", "a moved squad cannot move again")
	assert_eq(r.shoot(mine[0], foe), "not_now", "shooting in the move phase is refused")
	assert_eq(r.end_phase(), "", "end_phase in the move phase is accepted")
	assert_eq(r.st.phase, BattleState.PH_SHOOT, "the phase moved on to shoot")
	# play the rest by hand
	var got := _play_active(r)
	assert_true(r.is_over(), "active human: the game is over (%s)" % r.over_why())
	assert_true(int(got["move"]) > 0, "active human: moves applied (%d)" % int(got["move"]))
	assert_true(int(got["shoot"]) > 0, "active human: shots applied (%d)" % int(got["shoot"]))
	assert_true(int(got["charge"]) > 0, "active human: charges applied (%d)" % int(got["charge"]))
	assert_eq(int(got["gate"]), 0, "active human: moved squads were never selectable")
	assert_eq(int(got["refused"]), 0, "active human: no legal act was refused")
	assert_eq(r.end_phase(), "not_now", "end_phase after the end is refused")
	assert_eq(r.replayed_digest(), r.digest(), "active human: the act log replays to the same digest")


## Review of 12 Nov: the UI charge gate comes from the core (BtCombat.charge_gate), so the human may charge after
## advancing with flag ac or as dark elves from round 3, and after falling back as a flyer or a titan, exactly as
## BtCombat.charge_why_not allows (the bot already could); a plain squad that advanced is refused with "advanced".
func test_charge_gate_follows_the_core() -> void:
	for kind in ["ac", "de", "fly", "plain"]:
		var c := _charge_case(kind)
		if c.is_empty():
			assert_true(false, "%s: a charge position was set up" % kind)
			continue
		var r: MatchRunner = c["r"]
		var s: BattleState.Squad = c["s"]
		var t: BattleState.Squad = c["t"]
		var core := str(BtCombat.charge_why_not(r.st, s, t)["key"])
		if kind == "plain":
			assert_eq(core, "advanced", "plain squad after advancing: the core refuses with advanced")
			assert_false(r.can_select(s), "plain squad after advancing: not selectable in the charge phase")
			assert_eq(r.select_why(s), "advanced", "plain squad after advancing: the tap explains it with the core's reason")
			assert_eq(r.charge(s, t), "not_now", "plain squad after advancing: the charge is refused")
			continue
		var label: String = {"ac": "flag ac after advancing", "de": "dark elves in round 3 after advancing", "fly": "flyer or titan after falling back"}[kind]
		assert_eq(core, "", "%s: the core allows the charge" % label)
		assert_true(r.can_select(s), "%s: the UI lets the human select it" % label)
		assert_eq(r.select_why(s), "", "%s: no reason to refuse" % label)
		var n0 := r.acts().size()
		assert_eq(r.charge(s, t), "", "%s: the human's charge is accepted" % label)
		assert_true(r.acts().size() > n0 and s.ch_done, "%s: the charge went through Battle.apply (acts %d -> %d)" % [label, n0, r.acts().size()])


## A human squad of the wanted kind, in its own charge phase of round 3, placed about 8-12" from an enemy squad.
func _charge_case(kind: String) -> Dictionary:
	var key := ""
	var fac := ""
	for t in GameData.types():
		var k := str(t["k"])
		if GameData.is_hidden(k):
			continue
		var ok := false
		match kind:
			"ac":
				ok = bool(t.get("ac", false)) and str(t.get("fac", "")) != "de"
			"de":
				ok = str(t.get("fac", "")) == "de" and not bool(t.get("ac", false))
			"fly":
				ok = bool(t.get("fly", false)) or bool(t.get("ttn", false))
			"plain":
				ok = not bool(t.get("ac", false)) and not bool(t.get("fly", false)) and not bool(t.get("ttn", false)) \
					and str(t.get("fac", "")) != "de" and str(t.get("fac", "")) != ""
		if ok:
			key = k
			fac = str(t.get("fac", ""))
			break
	if key == "":
		return {}
	var choice := SeatPlan.defaults(4242)
	choice["goal"] = "kill"
	var list := PackedInt32Array()
	list.resize(GameData.types().size())
	list[GameData.index_of(key)] = 1
	choice["seats"] = [{"fac": fac, "human": true, "list": list}, {"fac": "or" if fac != "or" else "kn", "human": false}]
	var plan := SeatPlan.build(choice)
	if not (plan["errors"] as PackedStringArray).is_empty():
		return {}
	var r := MatchRunner.new(plan)
	r.start()
	var st := r.st
	var s: BattleState.Squad = null
	var t: BattleState.Squad = null
	for q in st.alive_squads():
		if q.pl == r.human and s == null and GameData.key_at(q.ti) == key:
			s = q
		elif q.pl != r.human and t == null:
			t = q
	if s == null or t == null:
		return {}
	st.round_no = 3
	st.turn = st.seats[r.human].team
	st.phase = BattleState.PH_CHARGE
	st.seats[r.human].done = false
	st.pend.clear()
	var tc := BtSquads.center(t)
	for dz in [0, 4000, -4000, 8000, -8000]:
		for dx in [12000, -12000, 10000, -10000, 8000, -8000]:
			var sc := BtSquads.center(s)
			for m in s.models:
				m.x += int(tc[0]) + dx - int(sc[0])
				m.z += int(tc[1]) + dz - int(sc[1])
			if str(BtCombat.charge_why_not(st, s, t)["key"]) == "":
				if kind == "fly":
					s.fell = true
				else:
					s.adv = true
				return {"r": r, "s": s, "t": t}
	return {}


func test_end_phase_only_in_the_humans_phases() -> void:
	var r := MatchRunner.new(_plan(["kn", "or"], 1, "obj", 23))
	r.start()
	# team 0 (a bot) starts: the human cannot end its phases
	assert_ne(r.st.turn, r.human_team(), "the bot team moves first")
	assert_eq(r.end_phase(), "not_now", "end_phase on the bot's turn is refused")
	assert_eq(r.auto_step(), "not_now", "auto_step on the bot's turn is refused")
	var n0 := r.acts().size()
	r.end_phase()
	assert_eq(r.acts().size(), n0, "a refused end_phase writes nothing")
	for i in MAX_STEPS:
		var res := r.step()
		if str(res["state"]) == "wait_human":
			break
	assert_true(r.is_human_turn(), "the runner reaches the human's turn")
	assert_true(r.st.phase in [BattleState.PH_MOVE, BattleState.PH_SHOOT, BattleState.PH_CHARGE], "the human waits only in move, shoot or charge")


func test_auto_human_finishes_games() -> void:
	var cases := [[["kn", "or"], 0, "obj", 7, "s", 1], [["gr", "el", "de"], 1, "kill", 23, "m", 1],
		[["kn", "gr", "or", "sw"], 0, "obj", 53, "m", 2]]
	for cs in cases:
		var plan := _plan(cs[0], cs[1], cs[2], cs[3], cs[4], cs[5])
		var r := MatchRunner.new(plan)
		r.start()
		var t0 := Time.get_ticks_msec()
		var why := r.run_to_end(MAX_STEPS)
		var tag := "%s %s seed %d" % [str(cs[0]), cs[2], cs[3]]
		assert_eq(why, "ok", tag + ": auto play reaches the end in %d ms (round %d)" % [Time.get_ticks_msec() - t0, r.st.round_no])
		var mine := 0
		for a: Dictionary in r.acts():
			if str(a.get("pid", "")) == r.pid:
				mine += 1
		assert_true(mine > 0, tag + ": the human seat acted with its pid (%d acts)" % mine)
		assert_eq(r.replayed_digest(), r.digest(), tag + ": the act log replays to the same digest")


func test_switching_auto_mid_game() -> void:
	var r := MatchRunner.new(_plan(["th", "jp"], 0, "obj", 99))
	r.start()
	var waits := 0
	for i in MAX_STEPS:
		var res := r.step()
		if str(res["state"]) == "wait_human":
			waits += 1
			if waits == 2:
				r.auto_human = true   # the ให้บอทเล่นแทน button
			else:
				r.end_phase()
		elif str(res["state"]) != "acted":
			break
	assert_true(r.is_over(), "switching to auto mid-game still ends the game")
	assert_eq(r.replayed_digest(), r.digest(), "auto mid-game: the act log replays to the same digest")
