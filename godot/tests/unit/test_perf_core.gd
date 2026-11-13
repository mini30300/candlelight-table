extends "res://tests/testing.gd"
## Time budgets of the rules core, headless (R1_PORT_SPEC §8 wave 5 C). Each case is timed as the best of a few runs
## (the first run also warms GameData and the free-spot ring tables) and must stay under its budget. The budgets are
## several times the numbers measured on the x86 dev container (printed as "info" lines, see each const) so a slow CI
## runner or the exported game's self-test still passes; a real slowdown (an accidental O(n^2) per act, a search that
## lost its early exit) is far larger than that headroom.

## A whole 2-seat bot match on a 48" table with generated props (measured 0.10 s, 250 acts).
const BUDGET_MATCH_MS := 3000
## Deploying 6 seats of the largest seeded armies (493 models) on a 120" table (measured 0.23 s).
const BUDGET_DEPLOY_MS := 4000
## One bot team's whole turn (move, shoot, charge, fight, every roll) on that crowded table (measured 1.2 s, 256 acts;
## 31.6 s before the bot's shoot and charge decisions stopped recomputing the shooter's engagement for every target).
const BUDGET_TURN_MS := 8000


func _bots(n: int, teams: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: int in n:
		out.append({"team": k % teams, "bot": true})
	return out


## The fast paths the bot uses (engagement known, early exit) answer exactly as the plain functions: every pair of
## squads at the start of each shoot and charge phase of a 2v2 free-fire game on a 30" table (melee, engaged squads,
## targets engaged with our side, own-side targets).
func test_fast_paths_are_exact() -> void:
	var b := Battle.make({"seed": 515, "w": 30, "teams": 2, "perTeam": 2, "goal": "kill", "budget": 1000, "theme": "ruin",
		"terrain": "hills", "mode": "team", "freeFire": 1}, _bots(4, 2), {})
	b.start()
	var st := b.st
	var diff: Array = []
	var pairs := 0
	var engaged := 0
	var tgt_eng := 0
	var checks := 0
	var last := -1
	for step: int in 400:
		if st.over:
			break
		var key := (st.round_no * 16 + st.turn) * 8 + st.phase
		if key != last and (st.phase == BattleState.PH_SHOOT or st.phase == BattleState.PH_CHARGE):
			checks += 1
			var sq := st.alive_squads()
			for s: BattleState.Squad in sq:
				var eng := BtSquads.engaged_with(st, s)
				var e := 1 if BtSquads.is_engaged(st, s) else 0
				engaged += e
				if e != (0 if eng.is_empty() else 1):
					diff.append("is_engaged vs engaged_with " + s.id)
				for t: BattleState.Squad in sq:
					pairs += 1
					for lim: int in [-5000, 0, 1001, 6001, 12001]:
						var sum := BtSquads.radius(s) + BtSquads.radius(t) + lim
						var want := sum >= 0 and BtSquads.dist2_min(s, t) <= sum * sum
						if BtSquads.edge_within(s, t, lim) != want:
							diff.append("edge_within %s %s %d" % [s.id, t.id, lim])
					var w := BtCombat.shot_why_not(st, s, t)
					if str(w["key"]) == "target_engaged":
						tgt_eng += 1
					if w != BtCombat.shot_why_not_with(st, s, t, eng):
						diff.append("shot %s %s" % [s.id, t.id])
					if BtCombat.charge_why_not(st, s, t) != BtCombat.charge_why_not_with(st, s, t, e):
						diff.append("charge %s %s" % [s.id, t.id])
					if BtCombat.gren_why_not(st, s, t) != BtCombat.gren_why_not_with(st, s, t, e):
						diff.append("gren %s %s" % [s.id, t.id])
		last = key
		_drive(b, func() -> bool: return ((st.round_no * 16 + st.turn) * 8 + st.phase) != key, 400)
	print("info  fast paths checked at %d phase starts, %d squad pairs, %d engaged squads, %d target_engaged" % [checks,
		pairs, engaged, tgt_eng])
	assert_eq(diff.slice(0, 10), [], "edge_within, and the why-nots with engagement given, equal the plain forms")
	assert_true(checks > 6 and engaged > 0 and tgt_eng > 0, "the game reaches engaged squads and targets engaged with us",
		[checks, engaged, tgt_eng])


## The page's botTick loop, as tests/unit/test_smoke_bots.gd drives it; stops when `until` returns true.
func _drive(b: Battle, until: Callable, max_steps: int) -> void:
	for i: int in max_steps:
		if b.st.over or until.call():
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


func _crowded_setup() -> Dictionary:
	return {"seed": 4242, "w": 120, "teams": 6, "perTeam": 1, "goal": "kill", "budget": 3000, "theme": "ruin",
		"terrain": "hills", "mode": "ffa"}


func test_full_match() -> void:
	var best := 1 << 40
	var acts := 0
	var over := false
	for run: int in 3:
		var b := Battle.make({"seed": 77, "w": 48, "teams": 2, "perTeam": 1, "goal": "obj", "rounds": 5, "budget": 500,
			"theme": "ruin", "terrain": "hills"}, _bots(2, 2), {})
		var t0 := Time.get_ticks_usec()
		b.start()
		_drive(b, func() -> bool: return false, 20000)
		best = mini(best, Time.get_ticks_usec() - t0)
		acts = b.actlog.size()
		over = b.st.over
	print("info  full 2-seat match: %d acts in %d ms (best of 3)" % [acts, best / 1000])
	assert_true(over and acts > 50, "the timed match is a real game that ends", [over, acts])
	assert_true(best / 1000 < BUDGET_MATCH_MS, "a full 2-seat match < %d ms" % BUDGET_MATCH_MS, best / 1000)


func test_six_seat_deploy() -> void:
	var best := 1 << 40
	var n := 0
	for run: int in 3:
		var b := Battle.make(_crowded_setup(), _bots(6, 6), {})
		for p: BattleState.Seat in b.st.seats:
			BtArmy.auto_list(b.st, p.id, null)
		var out: Array[Dictionary] = []
		var t0 := Time.get_ticks_usec()
		BtArmy.deploy(b.st, out)
		best = mini(best, Time.get_ticks_usec() - t0)
		n = b.st.units.size()
	print("info  6-seat deploy: %d models in %d ms (best of 3)" % [n, best / 1000])
	assert_true(n >= 400, "the deploy places a crowded field", n)
	assert_true(best / 1000 < BUDGET_DEPLOY_MS, "a 6-seat deploy < %d ms" % BUDGET_DEPLOY_MS, best / 1000)


func test_bot_turn_crowded() -> void:
	var best := 1 << 40
	var acts := 0
	var n := 0
	for run: int in 2:
		var b := Battle.make(_crowded_setup(), _bots(6, 6), {})
		b.start()
		n = b.st.units.size()
		var a0 := b.actlog.size()
		var t0 := Time.get_ticks_usec()
		# team 0's turn: until the turn passes to team 1
		_drive(b, func() -> bool: return b.st.turn != 0, 5000)
		best = mini(best, Time.get_ticks_usec() - t0)
		acts = b.actlog.size() - a0
		assert_eq([b.st.turn, b.st.round_no], [1, 1], "the timed turn ends and passes to the next team")
	print("info  one bot turn on a %d-model field: %d acts in %d ms (best of 2)" % [n, acts, best / 1000])
	assert_true(n >= 400 and acts > 20, "a crowded field and a real turn", [n, acts])
	assert_true(best / 1000 < BUDGET_TURN_MS, "one bot turn on a crowded table < %d ms" % BUDGET_TURN_MS, best / 1000)
