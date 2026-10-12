extends RefCounted
## Test-side act applier for test_bot.gd and test_roller.gd: the handler table of R1_PORT_SPEC §4 (page netAct) for the
## codes the bot and the roller send, written against the real BtPend / BtMoves / BtStrats appliers, followed by
## BtPend.prune as Battle.advance will do. BtActs.apply (wave 5) replaces it; until then this keeps the tests honest
## about "the caller applies each act before asking for the next". Not a test script (no test_ prefix).


static func apply(st: BattleState, act: Dictionary) -> void:
	var out: Array[Dictionary] = []
	var code := str(act.get("a", ""))
	var s := st.squad(str(act.get("u", "")))
	var t := st.squad(str(act.get("t", "")))
	match code:
		"smove":
			if s != null and not s.moved:
				var to: Array = act.get("to", [])
				if to.is_empty() and act.has("x"):
					to = BtMoves.pts(BtMoves.plan_move(st, s, int(act["x"]), int(act["z"])))
				BtMoves.apply_smove(st, s, to, str(act.get("how", "move")), out)
		"stay":
			if s != null:
				s.moved = true
		"skip":
			if s != null:
				var ph := str(act.get("ph", ""))
				if ph == "":
					ph = st.phase_name()
				if ph == "shoot":
					s.shot = true
				elif ph == "charge":
					s.ch_done = true
				else:
					s.moved = true
		"atk":
			if s != null and t != null:
				var p := BtPend.pend_at(st, s.id, t.id, BattleState.K_ATK)
				if p == null or p.stage != BattleState.S_HIT:
					p = BtPend.mk_atk(st, s, t, BattleState.HOWS.find(str(act.get("how", "shoot"))))
				BtPend.apply_hit(st, p, act.get("hit", []), out)
		"wnd":
			BtPend.apply_wnd(st, BtPend.pend_at(st, str(act["u"]), str(act["t"]), BattleState.K_ATK), act.get("wound", []), out)
		"sav":
			var p := BtPend.pend_at(st, str(act["u"]), str(act["t"]), BattleState.K_ATK)
			if p != null and p.stage == BattleState.S_SAVE:
				var g: bool = int(act.get("gtg", 0)) == 1 and BtStrats.use(st, "gtg", p.def, out)
				BtPend.apply_sav(st, p, act.get("save", []), g, out)
		"shock":
			var p := BtPend.pend_at(st, str(act["u"]), "", BattleState.K_SHOCK)
			if p != null:
				var b: bool = int(act.get("brave", 0)) == 1 and BtStrats.use(st, "brave", p.att, out)
				BtPend.apply_shock(st, p, act.get("roll", []), b, out)
		"rez":
			BtPend.apply_rez(st, BtPend.pend_at(st, str(act["u"]), "", BattleState.K_REZ), act.get("roll", []), out)
		"chg":
			if s != null and t != null and not s.ch_done:
				BtPend.declare_charge(st, s, t, out)
		"ow":
			BtPend.apply_ow(st, BtPend.pend_at(st, str(act["u"]), str(act["t"]), BattleState.K_CHG), int(act.get("use", 0)) == 1, out)
		"chr":
			var p := BtPend.pend_at(st, str(act["u"]), str(act["t"]), BattleState.K_CHG)
			BtPend.chg_ready(st, p)
			if p != null:
				if int(act.get("keep", 0)) == 1:
					BtPend.keep_charge(st, p, out)
				elif int(act.get("rr", 0)) == 1:
					if p.stage == BattleState.S_CHRR and BtStrats.use(st, "rr", p.att, out):
						BtPend.apply_charge(st, p, act.get("roll", []), true, out)
				else:
					BtPend.apply_charge(st, p, act.get("roll", []), false, out)
		"cmove":
			BtPend.apply_cmove(st, BtPend.pend_at(st, str(act["u"]), str(act["t"]), BattleState.K_CHG), act.get("to", []), out)
		"gren":
			if s != null and t != null and BtStrats.use(st, "gren", s.pl, out):
				BtPend.apply_gren(st, s, t, act.get("roll", []), out)
		"heal":
			if s != null and t != null:
				var r: int = int(act.get("roll", 1))
				BtPend.apply_heal(st, s, t, r if r >= 1 and r <= 6 else 1, out)
	BtPend.prune(st, out)


## Roll every pending entry (force = offline: this device rolls for everyone) with the bot's choices, each act applied
## before the next is asked for. Returns the acts in order.
static func flush(st: BattleState, here: Dictionary) -> Array[Dictionary]:
	var sent: Array[Dictionary] = []
	for guard: int in 400:
		var p := BtRoller.flush_plan(st, here)
		if p == null:
			break
		var dice := st.rng(BtRoller.stream_name(st, p, here))
		var acts := BtRoller.roll(st, p, BtBot.choice(st, p), dice)
		if acts.is_empty():
			break
		for a: Dictionary in acts:
			sent.append(a)
			apply(st, a)
	return sent


## The bot team in turn plays the current phase to its end (bot acts, each followed by a flush). Returns the acts.
static func bot_phase(st: BattleState, here: Dictionary) -> Array[Dictionary]:
	var sent: Array[Dictionary] = []
	for guard: int in 400:
		var a := BtBot.next_act(st, st.rng("bot:%d" % _first_bot(st)))
		if a.is_empty():
			break
		sent.append(a)
		apply(st, a)
		sent.append_array(flush(st, here))
	return sent


static func _first_bot(st: BattleState) -> int:
	for q: BattleState.Seat in st.team_seats(st.turn):
		if q.bot:
			return q.id
	return 0
