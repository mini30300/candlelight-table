extends "res://tests/testing.gd"
## Bot smoke (R1_PORT_SPEC §8 wave 5 C, ARCHITECTURE §10 item 4): 30 seeded bot-only games through Battle with mixed
## armies (every one of the 15 armies plays), 2-6 seats, obj and kill, tables from 24" to 120" with generated props.
## Every act that reaches Table.apply (bot acts, rolls, phase ends: bot_step and flush call apply) is checked:
## - before: the act is already in the sanitiser's form (BtActs.sanitize changes nothing), <= 60 dice, <= 40 points;
## - after: Table accepted it; every living model is on the table, outside every building footprint (as drawn, without
##   the 0.7" margin of block_at), on the 10 MI grid, with 1 <= hp <= its type's wounds; no model that changed position
##   overlaps a base of another squad (bases of one squad may overlap: plan_move's last resort keeps a model where it
##   stands, as the page does; the oracle recordings show the same, up to coincident bases); an smove moves no model
##   further than its move range plus the rounding of plan_move's probes, a cmove no further than the roll + 1 MI;
##   CP never negative; (round, turn, phase) only goes forward while the game is on, round <= max_round, a new turn
##   never starts on a team with nothing alive (wind bodies count), no turn takes more than TURN_GUARD acts.
## Deployment may overlap bases on a full small table (free_spot's last pass, the page's "rather touch another base than
## stand in a wall"): test_deploy_overlaps_are_the_free_spot_fallback checks that is the only way it happens.
## Every game must end by itself within its round cap; four are replayed from their act log; the 30 end digests are
## pinned together.

## Digest of the 30 end digests in game order; changes only on purpose.
const PINNED_ALL := "9a6408ec76e88e68"
## Acts in one turn of one team before the game counts as stuck (the most seen in these games is about 140).
const TURN_GUARD := 1000
## Driver iterations per game (each is one bot_step, a phase end or a flush).
const MAX_STEPS := 20000
## Games replayed from their act log on a fresh table.
const REPLAYED := [0, 7, 19, 23]

## [teams, per_team, w, goal, budget]; seed, theme, terrain and rounds follow the index (_setup)
const GAMES := [
	[2, 1, 30, "obj", 500], [2, 1, 48, "kill", 500], [3, 1, 36, "obj", 500], [2, 2, 48, "obj", 1000],
	[4, 1, 48, "kill", 500], [2, 1, 96, "obj", 500], [6, 1, 72, "obj", 500], [3, 2, 60, "kill", 1000],
	[2, 3, 48, "obj", 1500], [5, 1, 60, "obj", 500], [2, 1, 24, "kill", 300], [3, 1, 90, "kill", 500],
	[2, 2, 30, "kill", 1000], [4, 1, 36, "obj", 500], [6, 1, 48, "kill", 300], [2, 1, 120, "obj", 1000],
	[3, 2, 48, "obj", 1000], [2, 3, 72, "kill", 1500], [5, 1, 48, "kill", 500], [2, 1, 36, "obj", 2000],
	[4, 1, 120, "obj", 500], [2, 2, 60, "obj", 1000], [3, 1, 24, "obj", 300], [6, 1, 96, "kill", 500],
	[2, 1, 48, "obj", 500], [2, 1, 60, "kill", 1000], [3, 2, 36, "obj", 1000], [4, 1, 72, "kill", 500],
	[2, 3, 30, "obj", 1500], [5, 1, 90, "obj", 500]]


## A Battle whose apply checks every act.
class Checked extends Battle:
	var bad: Dictionary = {}
	var acts_in_turn := 0
	var turn_key := -1
	var last_key := -1
	var max_acts_turn := 0
	var last_code := "start"
	var pos: Dictionary = {}

	func note(kind: String, what: String) -> void:
		if not bad.has(kind):
			bad[kind] = []
		var l: Array = bad[kind]
		if l.size() < 5:
			l.append("act %d: %s" % [actlog.last_seq(), what])

	func apply(act: Dictionary) -> Array[Dictionary]:
		_pre(act)
		var code := str(act.get("a", ""))
		var s: BattleState.Squad = null
		var lim := -1
		if code == "smove" or code == "cmove":
			s = st.squad(str(act.get("u", "")))
		if s != null and code == "smove":
			lim = BtMoves.move_range(s)
			# plan_move: ring probes within range + 1, straight back + 9, sidestep x 1002/1000 + 8
			lim += Fx.cdiv(lim * 2, 1000) + 10
		elif s != null:
			var p := BtPend.pend_at(st, s.id, str(act.get("t", "")), BattleState.K_CHG)
			if p != null:
				lim = BtCombat.total(p.roll) * 1000 + 1
		var before := {}
		if s != null:
			for m: BattleState.Unit in s.models:
				before[m.id] = PackedInt64Array([m.x, m.z])
		last_code = code
		var out := super(act)
		if last_error != "":
			note("refused", "%s %s" % [last_error, JSON.stringify(act)])
			return out
		if s != null and lim >= 0:
			for m: BattleState.Unit in s.models:
				if before.has(m.id):
					var b0: PackedInt64Array = before[m.id]
					var d2 := Fx.dist2(m.x, m.z, b0[0], b0[1])
					if d2 > lim * lim:
						note("too_far", "%s %s moved %d > %d" % [code, m.id, Fx.isqrt(d2), lim])
		post()
		return out

	func _pre(act: Dictionary) -> void:
		var san := BtActs.sanitize(act.duplicate(true))
		if JSON.stringify(san, "", true) != JSON.stringify(act, "", true):
			note("unsanitised", "%s -> %s" % [JSON.stringify(act), JSON.stringify(san)])
		for k: String in ["hit", "wound", "save", "roll"]:
			if typeof(act.get(k)) == TYPE_ARRAY and (act[k] as Array).size() > 60:
				note("dice", "%s %s has %d dice" % [str(act.get("a")), k, (act[k] as Array).size()])
		if typeof(act.get("to")) == TYPE_ARRAY and (act["to"] as Array).size() > 40:
			note("points", "%s has %d points" % [str(act.get("a")), (act["to"] as Array).size()])

	func post() -> void:
		var hw := st.w * 500
		var hd := st.d * 500
		var moved: Array[BattleState.Unit] = []
		var seen := {}
		for m: BattleState.Unit in st.units:
			seen[m.id] = true
			var hpmax := BtAbilities.num(m.ti, "w")
			if m.hp < 1 or m.hp > hpmax:
				note("hp", "%s hp %d of %d" % [m.id, m.hp, hpmax])
			var p0: Variant = pos.get(m.id)
			if p0 != null and (p0 as PackedInt64Array)[0] == m.x and (p0 as PackedInt64Array)[1] == m.z:
				continue
			pos[m.id] = PackedInt64Array([m.x, m.z])
			moved.append(m)
			if absi(m.x) > hw or absi(m.z) > hd:
				note("off_table", "%s at %d,%d" % [m.id, m.x, m.z])
			if Fx.imod(m.x, 10) != 0 or Fx.imod(m.z, 10) != 0:
				note("grid", "%s at %d,%d" % [m.id, m.x, m.z])
			for o: Dictionary in st.props:
				if str(o["kind"]) == "building" and in_footprint(o, m.x, m.z):
					note("building", "%s at %d,%d inside the building at %d,%d" % [m.id, m.x, m.z, int(o["x"]), int(o["z"])])
		for k: Variant in pos.keys():
			if not seen.has(k):
				pos.erase(k)
		if last_code != "start":
			for m: BattleState.Unit in moved:
				var q := overlapped(st, m, st.units.size())
				if q != null:
					note("overlap", "%s %s overlaps %s at %d,%d / %d,%d" % [last_code, m.id, q.id, m.x, m.z, q.x, q.z])
		for p: BattleState.Seat in st.seats:
			if p.cp < 0:
				note("cp", "seat %d cp %d" % [p.id, p.cp])
		if st.phase < BattleState.PH_CMD or st.phase > BattleState.PH_FIGHT:
			note("phase", "phase %d" % st.phase)
		if st.round_no < 1 or st.round_no > st.max_round():
			note("round", "round %d of %d" % [st.round_no, st.max_round()])
		# the game's end clamps the round and wraps the turn (page endTurn/endRoundCheck): only checked while it is on
		var key := (st.round_no * 16 + st.turn) * 8 + st.phase
		if key < last_key and not st.over:
			note("order", "round %d turn %d phase %d after key %d" % [st.round_no, st.turn, st.phase, last_key])
		last_key = key
		var tk := st.round_no * 16 + st.turn
		if tk != turn_key:
			turn_key = tk
			acts_in_turn = 0
			if not st.over and st.live_of(st.turn) == 0:
				note("dead_turn", "team %d starts a turn with nothing alive" % st.turn)
		acts_in_turn += 1
		max_acts_turn = maxi(max_acts_turn, acts_in_turn)
		if acts_in_turn > TURN_GUARD:
			note("stuck", "round %d turn %d phase %d: %d acts in one turn" % [st.round_no, st.turn, st.phase, acts_in_turn])

	## Inside a building as drawn: |2 lx| < bw and |2 lz| < bd in the building's frame (Q16 cos/sin).
	static func in_footprint(o: Dictionary, x: int, z: int) -> bool:
		var dx: int = x - int(o["x"])
		var dz: int = z - int(o["z"])
		var lx: int = dx * int(o["c"]) - dz * int(o["sn"])
		var lz: int = dx * int(o["sn"]) + dz * int(o["c"])
		return absi(2 * lx) < int(o["bw"]) * 65536 and absi(2 * lz) < int(o["bd"]) * 65536

	## The first of st.units[0 .. n) of another squad whose base overlaps m's (centres closer than the sum of radii).
	static func overlapped(s: BattleState, m: BattleState.Unit, n: int) -> BattleState.Unit:
		var rm := BtBlocking.unit_rad(m)
		for i: int in n:
			var q := s.units[i]
			if q == m or q.sq == m.sq:
				continue
			var rr := rm + BtBlocking.unit_rad(q)
			if Fx.dist2(m.x, m.z, q.x, q.z) < rr * rr:
				return q
		return null


func _setup(i: int) -> Dictionary:
	var g: Array = GAMES[i]
	var terrains := GameData.terrain_names()
	var themes := GameData.theme_names()
	var team := int(g[1]) > 1
	return {"seed": 1000 + 37 * i, "w": int(g[2]), "teams": int(g[0]), "perTeam": int(g[1]), "goal": str(g[3]),
		"rounds": 3 + i % 3, "budget": int(g[4]), "theme": themes[i % themes.size()], "terrain": terrains[i % terrains.size()],
		"buildings": 1, "density_h": 100, "mode": "team" if team else ("ffa" if int(g[0]) > 2 else "pvp"),
		"freeFire": 1 if team and i % 4 == 1 else 0}


## Bot seats with lists from auto_list for a chosen army (all 15 armies over the 30 games).
func _seats(i: int, setup: Dictionary) -> Array[Dictionary]:
	var tmp := BattleState.make(setup)
	var facs := GameData.factions()
	var out: Array[Dictionary] = []
	for k: int in tmp.teams * tmp.per_team:
		var team := k % tmp.teams
		var p := tmp.add_seat(team, "", true, false, "")
		p.fac = facs[(i * 7 + k * 4) % facs.size()]
		BtArmy.auto_list(tmp, k, Rng.make("smoke:%d:%d" % [i, k], tmp.seed))
		out.append({"team": team, "bot": true, "list": p.list, "fac": p.fac})
	return out


func _plain(i: int) -> Battle:
	var setup := _setup(i)
	return Battle.make(setup, _seats(i, setup), {})


func _make(i: int) -> Checked:
	var base := _plain(i)
	var b := Checked.new()
	b.st = base.st
	b.seed = base.seed
	b.start()
	b.post()
	return b


## The page's botTick loop: bot_step until nothing is left, then the team's endph, else flush. False when the driver
## found nothing to do in a game that is not over.
func _drive(b: Battle) -> bool:
	for i: int in MAX_STEPS:
		if b.st.over:
			return true
		var before := b.actlog.size()
		if b.bot_step() == "":
			var e := BtBot.finished_act(b.st)
			if not e.is_empty():
				e["pid"] = ""
				b.apply(e)
		if b.actlog.size() == before:
			b.flush(true, {"online": false})
		if b.actlog.size() == before:
			return false
	return b.st.over


var _games: Array[Checked] = []
var _ended: Array[bool] = []


func setup() -> void:
	for i: int in GAMES.size():
		var t0 := Time.get_ticks_msec()
		var b := _make(i)
		_ended.append(_drive(b))
		_games.append(b)
		print("info  game %d %s: %d acts, round %d of %d, winner %d, max %d acts in a turn, %d ms" % [i, str(GAMES[i]),
			b.actlog.size(), b.st.round_no, b.st.max_round(), b.st.winner, b.max_acts_turn, Time.get_ticks_msec() - t0])


func test_every_game_ends_legally() -> void:
	for i: int in _games.size():
		var b := _games[i]
		var st := b.st
		var tag := "game %d %s" % [i, str(GAMES[i])]
		assert_true(_ended[i] and st.over, tag + ": ends by itself", [st.round_no, st.turn, st.phase, b.actlog.size()])
		assert_true(st.round_no <= st.max_round() and (st.winner == BattleState.DRAW or (st.winner >= 0 and st.winner < st.teams)),
			tag + ": within the round cap, with a result", [st.round_no, st.max_round(), st.winner])
		assert_eq(b.bad, {}, tag + ": every act legal")
		assert_true(st.pend.is_empty() and b.actlog.size() > 20, tag + ": nothing left to roll; a real game", [st.pend.size(), b.actlog.size()])


func test_index_invariants_at_the_end() -> void:
	var bad: Array = []
	for i: int in _games.size():
		var st := _games[i].st
		for s: BattleState.Squad in st.squads:
			var want: Array[BattleState.Unit] = []
			for m: BattleState.Unit in st.units:
				if m.sq == s.id:
					want.append(m)
			if want != s.models:
				bad.append("game %d squad %s models" % [i, s.id])
		for k: int in st.units.size():
			if st.unit_index(st.units[k].id) != k or st.unit(st.units[k].id) != st.units[k]:
				bad.append("game %d unit %s index" % [i, st.units[k].id])
	assert_eq(bad, [], "squad models follow units order and the indexes are true after every game")


func test_all_armies_and_shapes_play() -> void:
	var facs := {}
	var seats := {}
	var goals := {}
	var widths := {}
	for b: Checked in _games:
		for p: BattleState.Seat in b.st.seats:
			facs[p.fac] = true
		seats[b.st.seats.size()] = true
		goals[b.st.goal] = true
		widths[b.st.w] = true
	var missing: Array = []
	for f: String in GameData.factions():
		if not facs.has(f):
			missing.append(f)
	assert_eq(missing, [], "all 15 armies played in the smoke games")
	assert_eq([seats.has(2), seats.has(3), seats.has(4), seats.has(5), seats.has(6), goals.size()],
		[true, true, true, true, true, 2], "2 to 6 seats and both goals")
	assert_true(widths.has(24) and widths.has(120), "the smallest and a big table", widths.keys())


func test_replay_gives_the_same_game() -> void:
	for i: int in REPLAYED:
		var b := _games[i]
		var r := _plain(i)
		r.start()
		var acts := b.actlog.acts()
		assert_eq(r.replay(acts), acts.size(), "game %d: every logged act replays" % i)
		assert_eq(r.digest(), b.digest(), "game %d: the replay ends in the same state" % i)


func test_pinned_digests() -> void:
	var all := ""
	for b: Checked in _games:
		all += b.digest()
	assert_digest(Hash.hex64(Hash.fnv1a64_str(all)), PINNED_ALL, "the 30 smoke games are pinned")


## Deployment overlaps only where free_spot had no free point (its crowd-off pass or its last fallback): replays each
## overlapping game's deploy model by model (later models taken away) and asks free_spot again for that model's slot.
func test_deploy_overlaps_are_the_free_spot_fallback() -> void:
	var games := 0
	var checked := 0
	for i: int in GAMES.size():
		var b := _plain(i)
		var none: Array[Dictionary] = []
		BtArmy.deploy(b.st, none)
		var st := b.st
		var bad: Array = []
		var any := false
		for k: int in range(st.units.size() - 1, -1, -1):
			var u := st.units[k]
			var q := Checked.overlapped(st, u, k)
			st.remove_unit(u)
			if q == null:
				continue
			any = true
			checked += 1
			var slot := _deploy_slot(st, u)
			var r := BtSquads.radius_of(u.ti)
			var sp := BtBlocking.free_spot(st, slot[0], slot[1], null, PackedInt64Array(), 0, r)
			if sp != PackedInt64Array([u.x, u.z]) or not BtBlocking.crowded(st, sp[0], sp[1], null, r):
				bad.append("%s at %d,%d over %s: free_spot gives %s" % [u.id, u.x, u.z, q.id, str(sp)])
		if any:
			games += 1
		assert_eq(bad, [], "game %d: every deploy overlap is free_spot's fallback on a full table" % i)
	print("info  deploy overlaps on %d of %d tables, %d models checked" % [games, GAMES.size(), checked])
	assert_true(games < GAMES.size() / 3, "most deployments have no overlap at all", games)


## The formation slot BtArmy.deploy gave model u (squad "<seat>:<i>", model "<sq>.<j>").
func _deploy_slot(st: BattleState, u: BattleState.Unit) -> PackedInt64Array:
	var s := st.squad(u.sq)
	var p := st.seat(s.pl)
	var i := int(s.id.get_slice(":", 1))
	var j := int(u.id.get_slice(".", 1))
	var face := Fx.norm1000(-p.dep_x, -p.dep_z)
	if face[0] == 0 and face[1] == 0:
		face = PackedInt64Array([0, -1000])
	var cx := p.dep_x
	var cz := p.dep_z
	if i > 0:
		var ring := 1 + Fx.idiv(i - 1, 6)
		var th := Fx.idiv(Fx.imod(i - 1, 6) * FieldProps.TWO_PI, 6) + ring * BtOffsets.DEP_ANG_STEP
		cx += 10 * Fx.js_round(FieldProps.cos_q(th) * ring * BtArmy.RING_10, 65536)
		cz += 10 * Fx.js_round(FieldProps.sin_q(th) * ring * BtArmy.RING_10, 65536)
	return BtSquads.formation(s.n0, cx, cz, face[0], face[1], BtSquads.radius_of(u.ti))[j]
