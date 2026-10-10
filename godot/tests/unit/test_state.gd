extends "res://tests/testing.gd"
## core/battle/state.gd: construction from a setup, index dictionaries kept in sync through add/remove,
## snapshot/restore round trip (also through JSON text), digest stability and sensitivity.


## A small two-seat match: seat 0 has two hoplite squads, seat 1 one heavy squad, one wind body, one objective,
## one pending attack, a used stratagem and a couple of props.
func _small() -> BattleState:
	var st := BattleState.make({"seed": 7, "w": 48, "teams": 2, "perTeam": 1, "mode": "pvp", "goal": "obj",
		"rounds": 4, "buildings": true, "density_h": 100, "theme": "ruin", "terrain": "hills"})
	var a := st.add_seat(0, "A", false, false, "ผู้เล่น 1")
	var b := st.add_seat(1, "", true, false, "บอท")
	a.list[GameData.index_of("hoplite")] = 2
	a.fac = "gr"
	a.cp = 2
	a.has_dep = true
	a.dep_x = -15000
	a.dep_z = -10000
	a.skin = {"loki": 1}
	b.list[GameData.index_of("heavy")] = 1
	b.cp = 1
	for i: int in 2:
		var s := st.add_squad("0:%d" % i, "hoplite", 0, 0, 5, 0)
		for j: int in 5:
			st.add_unit("0:%d.%d" % [i, j], s, 1, -15000 + j * 1700, -10000 + i * 5200)
	var h := st.add_squad("1:0", "heavy", 1, 1, 3, 0)
	for j: int in 3:
		st.add_unit("1:0.%d" % j, h, 2, 15000 + j * 1700, 10000)
	st.on = true
	st.phase = BattleState.PH_SHOOT
	st.vp[1] = 5
	st.used["rr:0:1:0:shoot"] = true
	st.add_obj(1, 0, 0)
	var q := BattleState.Pend.new()
	q.kind = BattleState.K_ATK
	q.stage = BattleState.S_WOUND
	q.u = "0:0"
	q.t = "1:0"
	q.att = 0
	q.def = 1
	q.shots = 5
	q.hits = 3
	q.hit_r = PackedInt32Array([1, 4, 5, 6, 2])
	q.need = 3
	q.wneed = 4
	q.sv = 4
	q.lh = true
	st.pend.append(q)
	var items: Array[Dictionary] = [
		{"kind": "building", "x": 1000, "z": -2000, "rot": 3000, "s_ppm": 905571, "h": 65000, "bw": 11000, "bd": 6000},
		{"kind": "tower", "x": 3563, "z": 2873, "rot": 398416, "s_ppm": 1376855, "h": 47361},
	]
	st.set_props(items, true)
	return st


func test_constants() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/phases.json"))
	assert_eq(BattleState.PHASES, (raw as Dictionary)["order"], "phase names follow data/phases.json order")
	assert_eq(BattleState.PHASES[BattleState.PH_FIGHT], "fight", "PH_FIGHT names fight")
	assert_eq(BattleState.STAGES.size(), BattleState.S_HEAL + 1, "one stage name per stage constant")
	assert_eq(BattleState.KINDS.size(), BattleState.K_HEAL + 1, "one kind name per kind constant")
	assert_eq(BattleState.HOWS[BattleState.HOW_OW], "ow", "attack ways")
	assert_eq(BattleState.GOALS[BattleState.GOAL_KILL], "kill", "goal names")


func test_make_defaults_and_clamps() -> void:
	var st := BattleState.make({})
	assert_eq(st.w, 48, "default width")
	assert_eq(st.d, 34, "depth derived from width")
	assert_eq(st.teams, 2, "default teams")
	assert_eq(st.vp.size(), 2, "vp sized to teams")
	assert_eq(st.max_round(), 5, "default rounds")
	assert_eq(st.phase_name(), "cmd", "starts in the command phase")
	assert_eq(st.winner, BattleState.NO_WINNER, "no winner yet")
	var big := BattleState.make({"w": 180, "teams": 8, "rounds": 99, "goal": "kill", "freeFire": 1, "buildings": false})
	assert_eq(big.d, FieldTerrain.depth_for(180), "depth of a 180 table")
	assert_eq(big.rounds, 10, "rounds clamped to 10")
	assert_eq(big.max_round(), BattleState.KILL_ROUNDS, "kill games run 30 rounds")
	assert_true(big.free_fire and not big.buildings, "bools accept 0/1 and true/false")
	assert_eq(BattleState.make({"rounds": 1}).rounds, 3, "rounds clamped to 3")
	assert_eq(BattleState.make({"rounds": 0}).rounds, 5, "rounds 0 means the default 5, as the page's rounds || 5")
	assert_eq(BattleState.make({"w": 60, "d": 44}).d, 44, "an explicit depth wins")


func test_seats() -> void:
	var st := _small()
	assert_eq(st.seats.size(), 2, "two seats")
	assert_eq(st.seat(1).id, 1, "seat id is its index")
	assert_eq(st.seat(5), null, "no seat 5")
	assert_eq(st.seat(0).list.size(), GameData.count(), "a list has one slot per type")
	assert_eq(st.pid_index("A"), 0, "pid A sits at seat 0")
	assert_eq(st.pid_index("Z"), -1, "unknown pid")
	assert_eq(st.team_seats(1).size(), 1, "one seat on team 1")
	assert_eq(st.team_seats(1)[0].id, 1, "team 1 is seat 1")


func test_index_consistency() -> void:
	var st := _small()
	assert_eq(st.squads.size(), 3, "three squads")
	assert_eq(st.units.size(), 13, "thirteen models")
	_check_index(st, "after build")
	assert_eq(st.squad("0:1").idx, 1, "squad 0:1 is second")
	assert_eq(st.squad("nope"), null, "unknown squad")
	assert_eq(st.unit("0:0.0").ti, GameData.index_of("hoplite"), "a model knows its type index")
	assert_eq(st.unit("1:0.2").side, 1, "a model takes its side from its squad")
	assert_eq(st.add_squad("0:1", "hoplite", 0, 0, 5, 0), null, "a duplicate squad id is refused")
	assert_eq(st.add_unit("0:0.0", st.squad("0:0"), 1, 0, 0), null, "a duplicate model id is refused")
	# a model dies in the middle: later models shift down, the squad keeps its order
	var dead := st.unit("0:0.2")
	assert_eq(st.remove_unit(dead), 2, "removed from position 2")
	assert_eq(st.remove_unit(dead), -1, "removing twice does nothing")
	assert_eq(st.unit("0:0.2"), null, "the dead model is gone")
	assert_eq(st.unit_index("0:0.3"), 2, "the next model moved down")
	_check_index(st, "after a death")
	# a revived model comes back at the end of units and so at the end of its squad
	var back := st.add_unit("0:0.2", st.squad("0:0"), 1, 0, 0)
	assert_eq(st.unit_index("0:0.2"), st.units.size() - 1, "a revived model is appended")
	assert_eq(st.squad_models("0:0")[4], back, "and is last in its squad")
	_check_index(st, "after a revive")
	# wipe a squad: it stays in squads but leaves alive_squads
	for u: BattleState.Unit in st.squad_models("1:0").duplicate():
		st.remove_unit(u)
	assert_eq(st.squad_alive(st.squad("1:0")), 0, "squad 1:0 has no models")
	assert_true(st.squad("1:0") != null, "a dead squad is still found")
	assert_eq(st.alive_squads().size(), 2, "alive squads skip the dead one")
	assert_eq(st.live_of(1), 0, "team 1 has no models")
	_check_index(st, "after a wipe")


func _check_index(st: BattleState, label: String) -> void:
	var ok := true
	for i: int in st.units.size():
		var u := st.units[i]
		if st.unit_index(u.id) != i or st.unit(u.id) != u or st.squads[u.sqi].id != u.sq:
			ok = false
	var count := 0
	for s: BattleState.Squad in st.squads:
		if st.squad(s.id) != s or st.squads[s.idx] != s:
			ok = false
		var last := -1
		for m: BattleState.Unit in s.models:
			var at := st.unit_index(m.id)
			if at <= last or m.sq != s.id:
				ok = false
			last = at
		count += s.models.size()
	assert_true(ok and count == st.units.size(), "index dictionaries and squad model lists agree with units " + label)


func test_bodies_and_live() -> void:
	var st := BattleState.make({})
	st.add_seat(0, "", true, false, "")
	var s := st.add_squad("0:0", "hanu", 0, 0, 1, 0)
	var m := st.add_unit("0:0.0", s, 6, 100, 200)
	assert_eq(st.live_of(0), 1, "one live model")
	st.remove_unit(m)
	st.add_body(m)
	assert_true(m.wait, "a body waits for the wind")
	assert_eq(st.live_of(0), 1, "a waiting body still counts as alive")
	assert_eq(st.alive_squads().size(), 0, "but its squad is not in alive_squads")
	assert_eq(st.body_of("0:0"), m, "the body of squad 0:0")
	st.take_body(m)
	assert_eq(st.body_of("0:0"), null, "taken away")
	assert_eq(st.live_of(0), 0, "nothing left")


func test_flags_round_trip() -> void:
	var s := BattleState.Squad.new()
	assert_true(s.still and not s.moved, "a new squad stands still")
	s.moved = true
	s.shaken = true
	s.opened = true
	s.still = false
	var f := s.flags()
	var t := BattleState.Squad.new()
	t.set_flags(f)
	assert_eq(t.flags(), f, "squad flags survive the bitmask")
	assert_true(t.moved and t.shaken and t.opened and not t.still and not t.adv, "and read back field by field")
	s.ch_tgt = "1:0"
	s.adv_r = 4
	s.reset_turn()
	assert_true(s.still and not s.moved and s.ch_tgt == "" and s.adv_r == 0 and s.shaken, "reset_turn clears the turn flags only")
	var q := BattleState.Pend.new()
	q.melee = true
	q.heel = true
	q.wind = true
	var r := BattleState.Pend.new()
	r.set_flags(q.flags())
	assert_true(r.melee and r.heel and r.wind and not r.tr, "pend flags survive the bitmask")


func test_mark_key_and_log() -> void:
	var st := BattleState.make({"teams": 8})
	var seen := {}
	for rd: int in range(1, 31):
		for tm: int in 8:
			st.round_no = rd
			st.turn = tm
			seen[st.mark_key()] = true
	assert_eq(seen.size(), 240, "mark_key is unique per (round, turn)")
	for i: int in BattleState.LOG_CAP + 5:
		st.say("line", [i])
	assert_eq(st.log_lines.size(), BattleState.LOG_CAP, "the log keeps the last lines")
	assert_eq(st.log_lines[0]["args"], [5], "the oldest lines went first")


func test_rng_streams() -> void:
	var st := BattleState.make({"seed": 42})
	st.act_seq = 9
	var a := st.fallback("hit")
	var b := st.fallback("hit")
	var c := st.fallback("wound")
	var sa := [a.d6(), a.d6(), a.d6(), a.d6()]
	assert_eq([b.d6(), b.d6(), b.d6(), b.d6()], sa, "the fallback stream is the same for the same act and stage")
	assert_eq(c.stream, "fallback:9:wound", "fallback stream name")
	assert_eq(st.rng("bot:1"), st.rng("bot:1"), "a named stream is kept")
	var d0 := st.digest()
	st.rng("bot:1").d6()
	assert_eq(st.digest(), d0, "a device-local stream draw does not change the digest")


func test_snapshot_is_int_only_and_round_trips() -> void:
	var st := _small()
	st.rng("bot:1").d6()
	st.say("hello", ["0:0", 3])
	var snap := st.snapshot()
	assert_true(_int_only(snap), "the snapshot holds only int, String, Array and Dictionary")
	var back := BattleState.new()
	assert_true(back.restore(snap), "restore accepts its own snapshot")
	assert_eq(back.snapshot(), snap, "snapshot -> restore -> snapshot is the identity")
	assert_digest(back.digest(), st.digest(), "the digest survives a round trip")
	_check_index(back, "after restore")
	assert_eq(back.squad_models("0:1").size(), 5, "squad model lists rebuilt")
	assert_eq(back.rng("bot:1").state(), st.rng("bot:1").state(), "streams restored")
	assert_eq(back.seat(0).skin, {"loki": 1}, "skin restored")
	assert_eq(back.pend[0].hit_r, PackedInt32Array([1, 4, 5, 6, 2]), "pending dice restored")
	assert_true(back.pend[0].lh and back.pend[0].stage == BattleState.S_WOUND, "pending flags and stage restored")
	# through JSON text, the wire form (numbers parse back as non-integers and are converted)
	var text := JSON.stringify(snap)
	var parsed: Variant = _to_ints(JSON.parse_string(text))
	var viaj := BattleState.new()
	assert_true(viaj.restore(parsed), "restore accepts the snapshot after JSON text")
	assert_digest(viaj.digest(), st.digest(), "same digest after JSON text")


func test_snapshot_without_props() -> void:
	var st := _small()
	var lean := st.snapshot(false)
	assert_false(lean.has("props"), "a lean snapshot leaves props out")
	var same := _small()
	same.vp[0] = 99
	assert_true(same.restore(lean), "restore keeps the receiver's props when the hash matches")
	assert_digest(same.digest(), st.digest(), "and ends equal to the source")
	var other := BattleState.make({})
	assert_false(other.restore(lean), "restore refuses a lean snapshot when the props differ")


func test_restore_rejects_bad_input() -> void:
	var st := _small()
	var d0 := st.digest()
	var snap := st.snapshot()
	var cases := {}
	var v := snap.duplicate(true)
	v["v"] = 9
	cases["old rules version"] = v
	var m := snap.duplicate(true)
	m.erase("match")
	cases["no match"] = m
	var u := snap.duplicate(true)
	(u["units"] as Array)[0][1] = "9:9"
	cases["model of an unknown squad"] = u
	var dup := snap.duplicate(true)
	(dup["units"] as Array).append((dup["units"] as Array)[0])
	cases["duplicate model"] = dup
	var fl := snap.duplicate(true)
	(fl["squads"] as Array)[0][2] = "0"
	cases["string where an int belongs"] = fl
	var pk := snap.duplicate(true)
	(pk["pend"] as Array)[0]["stage"] = 99
	cases["unknown stage"] = pk
	var ph := snap.duplicate(true)
	ph["props_hash"] = 1
	cases["props hash mismatch"] = ph
	for name: String in cases:
		assert_false(st.restore(cases[name]), "restore refuses: " + name)
	assert_digest(st.digest(), d0, "a refused restore leaves the state untouched")


func test_digest_stable_and_sensitive() -> void:
	var a := _small()
	var b := _small()
	assert_digest(a.digest(), b.digest(), "two identical builds give one digest")
	assert_eq(a.digest().length(), 16, "16 hex characters")
	var d0 := a.digest()
	a.seat(0).nm = "someone else"
	a.say("x", [])
	assert_digest(a.digest(), d0, "names and log lines are not rules state")
	for name: String in PROBES:
		var c := _small()
		_probe(name, c)
		assert_ne(c.digest(), d0, "the digest sees a change of " + name)


const PROBES := ["hp", "position", "squad flag", "facing", "cp", "done", "vp", "phase", "round", "used",
	"pend stage", "pend dice", "fights", "objective", "winner", "unit order", "body", "seat pid"]


## One small rules-state change per probe name.
func _probe(name: String, s: BattleState) -> void:
	match name:
		"hp": s.unit("0:0.1").hp = 0
		"position": s.unit("1:0.0").x += 10
		"squad flag": s.squad("0:0").shot = true
		"facing": s.squad("0:0").fx = 600
		"cp": s.seat(1).cp = 2
		"done": s.seat(0).done = true
		"vp": s.vp[0] = 5
		"phase": s.phase = BattleState.PH_CHARGE
		"round": s.round_no = 2
		"used": s.used["gtg:1:1:0:shoot"] = true
		"pend stage": s.pend[0].stage = BattleState.S_SAVE
		"pend dice": s.pend[0].hit_r[0] = 2
		"fights": s.fights_null = true
		"objective": s.objs[0].x = 10
		"winner": s.winner = 1
		"unit order": s.units.reverse()
		"body":
			var m := s.unit("1:0.0")
			s.remove_unit(m)
			s.add_body(m)
		"seat pid": s.seat(0).pid = "B"


## True when v holds only int, bool-free String/Array/Dictionary values (no float).
func _int_only(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not _int_only(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not _int_only(v[k]):
					return false
			return true
	return false


## JSON numbers come back as floats; whole numbers become ints again (what Net does before restore).
func _to_ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_to_ints(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _to_ints(v[k])
			return d
		TYPE_FLOAT:
			return int(v)
	return v
