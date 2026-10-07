extends "res://tests/testing.gd"
## core/battle/strats.gd (BtStrats, R1_PORT_SPEC §1.8): cost, key (stratKey), can (canStrat), use (useStrat).
## Page samples: fixtures/strats/page_samples.json (tools/record_squads_strats.js runs the page's own stratKey /
## canStrat / useStrat over seeded operation sequences in Chromium); every result, the CP of every seat and the lock
## each step adds must match. Hand cases pin the rules the spec lists (CP per seat, lock per team, brave per turn,
## rr shared, CP never negative) and the effect on snapshot and digest.

const FIXTURE := "res://tests/unit/fixtures/strats/page_samples.json"
## Digest of the fixed scenario in _digest_scenario; changes only on purpose.
const PINNED_DIGEST := "75c56568f3af9477:e8bca28174029b6b"

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = raw if raw is Dictionary else {}


func _i(v: Variant) -> int:
	return int(v)


## A match in a given phase: seats as [team, cp] pairs.
func _st(seats: Array, round_no: int = 1, turn: int = 0, phase: String = "shoot") -> BattleState:
	var teams := 1
	for sv: Variant in seats:
		teams = maxi(teams, _i((sv as Array)[0]) + 1)
	var st := BattleState.make({"seed": 5, "teams": teams, "perTeam": 1})
	for i: int in seats.size():
		var s: Array = seats[i]
		var p := st.add_seat(_i(s[0]), "L%d" % i, false, false, "P%d" % i)
		p.cp = _i(s[1])
	var none: Array[Dictionary] = []
	st.set_props(none, false)
	st.on = true
	st.round_no = round_no
	st.turn = turn
	st.phase = BattleState.PHASES.find(phase)
	return st


func _cps(st: BattleState) -> Array:
	var out: Array = []
	for p: BattleState.Seat in st.seats:
		out.append(p.cp)
	return out


func _used(st: BattleState) -> Array:
	var keys: Array = st.used.keys()
	keys.sort()
	return keys


# ------------------------------------------------------------------ data and page samples
func test_costs_match_data_and_page() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/strats.json"))
	var data: Dictionary = raw if raw is Dictionary else {}
	assert_eq(Array(data.keys()), BtStrats.KEYS, "KEYS follow data/strats.json order")
	var bad: Array = []
	for k: Variant in data:
		var e: Dictionary = data[k]
		if BtStrats.cost(str(k)) != _i(e["cp"]):
			bad.append(k)
	assert_true(bad.is_empty(), "every cost equals data/strats.json", bad)
	assert_eq(BtStrats.COST.size(), data.size(), "no stratagem beyond the data")
	var page: Array = fx.get("costs", [])
	var pk: Array = []
	for row: Variant in page:
		pk.append((row as Array)[0])
		if BtStrats.cost(str((row as Array)[0])) != _i((row as Array)[1]):
			bad.append(row)
	assert_eq(pk, BtStrats.KEYS, "the page's STRATS has the same keys in the same order")
	assert_true(bad.is_empty(), "and the same costs", bad)
	assert_eq(BtStrats.cost("nope"), -1, "an unknown stratagem has no cost")


func test_sequences_match_page() -> void:
	var seqs: Array = fx.get("seqs", [])
	assert_true(seqs.size() >= 10, "%d operation sequences from the page" % seqs.size())
	var bad: Array = []
	var n_ops := 0
	var n_used := 0
	for qi: int in seqs.size():
		var q: Dictionary = seqs[qi]
		var g: Dictionary = q["g"]
		var seats: Array = []
		for sv: Variant in q["seats"]:
			var sd: Dictionary = sv
			seats.append([sd["team"], sd["cp"]])
		var st := _st(seats, _i(g["round"]), _i(g["turn"]), str(g["phase"]))
		var ops: Array = q["ops"]
		var steps: Array = q["steps"]
		var events := 0
		var out: Array[Dictionary] = []
		for oi: int in ops.size():
			var op: Array = ops[oi]
			var want: Array = steps[oi]
			var before := _used(st)
			var got: Variant = null
			match str(op[0]):
				"use":
					got = BtStrats.use(st, str(op[1]), _i(op[2]), out)
					if bool(got):
						events += 1
						n_used += 1
				"can":
					got = BtStrats.can(st, str(op[1]), _i(op[2]))
				"key":
					got = BtStrats.key(st, str(op[1]), _i(op[2]))
				"set":
					var ch: Dictionary = op[1]
					if ch.has("round"):
						st.round_no = _i(ch["round"])
					if ch.has("turn"):
						st.turn = _i(ch["turn"])
					if ch.has("phase"):
						st.phase = BattleState.PHASES.find(str(ch["phase"]))
					if ch.has("over"):
						st.over = bool(ch["over"])
				"cp":
					st.seats[_i(op[1])].cp = _i(op[2])
			n_ops += 1
			# the lock this step added ("" when none)
			var added := ""
			for k: Variant in _used(st):
				if not before.has(k):
					added = str(k)
			if got != want[0] or _cps(st) != Array(want[1]).map(func(x: Variant) -> int: return int(x)) or added != str(want[2]):
				bad.append([qi, oi, op, got, want, _cps(st), added])
		if _used(st) != q["used"]:
			bad.append([qi, "final locks", _used(st), q["used"]])
		if out.size() != events:
			bad.append([qi, "events", out.size(), events])
	assert_true(n_ops >= 500 and n_used >= 50, "%d operations, %d successful uses" % [n_ops, n_used])
	assert_true(bad.is_empty(), "every result, CP and added lock equals the page's", bad.slice(0, 5))


# ------------------------------------------------------------------ hand cases
func test_key_format() -> void:
	var st := _st([[0, 1], [1, 1]], 3, 1, "charge")
	assert_eq(BtStrats.key(st, "rr", 0), "rr:0:3:1:charge", "k:team:round:turn:phase")
	assert_eq(BtStrats.key(st, "brave", 1), "brave:1:3:1:", "brave leaves the phase part empty")
	st.phase = BattleState.PH_CMD
	assert_eq(BtStrats.key(st, "gtg", 7), "gtg:7:3:1:cmd", "the team is whatever the caller passes")


func test_once_per_team_per_phase() -> void:
	var st := _st([[0, 3], [0, 2], [1, 2]])
	var out: Array[Dictionary] = []
	assert_true(BtStrats.can(st, "rr", 0), "seat 0 may re-roll")
	assert_true(BtStrats.use(st, "rr", 0, out), "and does")
	assert_eq(_cps(st), [2, 2, 2], "one CP off seat 0 only (CP is per seat)")
	assert_false(BtStrats.can(st, "rr", 0), "not twice in the same phase")
	assert_false(BtStrats.can(st, "rr", 1), "a team-mate with CP cannot reuse the team's key")
	assert_false(BtStrats.use(st, "rr", 1, out), "use refuses too")
	assert_eq(_cps(st), [2, 2, 2], "and spends nothing")
	assert_true(BtStrats.use(st, "rr", 2, out), "the other team has its own lock")
	assert_true(BtStrats.use(st, "gtg", 1, out), "another stratagem is a different lock")
	st.phase = BattleState.PH_CHARGE
	assert_true(BtStrats.can(st, "rr", 1), "a new phase opens the lock again")
	# rr serves the hit re-roll and the charge re-roll: one key for both in a phase
	assert_true(BtStrats.use(st, "rr", 1, out), "a charge re-roll in the charge phase")
	assert_false(BtStrats.can(st, "rr", 0), "then no hit re-roll for that team in the same phase")
	st.turn = 1
	st.phase = BattleState.PH_SHOOT
	assert_true(BtStrats.can(st, "rr", 0), "the same phase name in another turn is a new lock")
	st.turn = 0
	st.round_no = 2
	assert_true(BtStrats.can(st, "rr", 0), "and in another round")
	assert_eq(out.size(), 4, "one event per use")
	assert_eq(out[0], Events.make(Events.Id.STRAT, {"k": "rr", "team": 0}), "STRAT {k, team}")
	assert_eq(out[2]["team"], 0, "the gtg event names team 0")
	assert_eq(st.log_lines.back(), {"key": "strat_used", "args": [1, "rr", 1]}, "the page's log line as key + args [seat, k, cp]")


func test_brave_once_per_turn() -> void:
	var st := _st([[0, 3], [1, 3]], 1, 0, "cmd")
	var out: Array[Dictionary] = []
	assert_true(BtStrats.use(st, "brave", 0, out), "brave in the command phase")
	st.phase = BattleState.PH_FIGHT
	assert_false(BtStrats.can(st, "brave", 0), "not again in a later phase of the same turn")
	assert_true(BtStrats.can(st, "brave", 1), "the other team may")
	st.turn = 1
	st.phase = BattleState.PH_CMD
	assert_true(BtStrats.can(st, "brave", 0), "a new turn opens it")
	assert_eq(_used(st), ["brave:0:1:0:"], "the lock has no phase part")


func test_cp_never_negative() -> void:
	var st := _st([[0, 0], [0, 1], [1, -2]])
	var out: Array[Dictionary] = []
	assert_false(BtStrats.can(st, "ow", 0), "no CP, no stratagem")
	assert_false(BtStrats.use(st, "ow", 0, out), "use refuses")
	assert_eq(st.seats[0].cp, 0, "CP stays at 0")
	assert_true(BtStrats.use(st, "ow", 1, out), "a seat with 1 CP pays")
	assert_eq(st.seats[1].cp, 0, "down to exactly 0")
	st.phase = BattleState.PH_CHARGE
	assert_false(BtStrats.use(st, "ow", 1, out), "and cannot go below in the next phase")
	assert_false(BtStrats.can(st, "gren", 2), "a negative CP (bad snapshot) never pays")
	assert_eq(_cps(st), [0, 0, -2], "nothing else changed")
	var low: int = BtStrats.cost("gren")
	assert_true(low >= 1, "every stratagem costs at least 1")


func test_refusals_touch_nothing() -> void:
	var st := _st([[0, 2], [1, 2]])
	var out: Array[Dictionary] = []
	BtStrats.use(st, "rr", 0, out)
	var d0 := st.digest()
	var n_log := st.log_lines.size()
	assert_false(BtStrats.use(st, "rr", 0, out), "a used lock")
	assert_false(BtStrats.use(st, "nope", 0, out), "an unknown stratagem")
	assert_false(BtStrats.can(st, "nope", 0), "can refuses an unknown stratagem")
	assert_false(BtStrats.use(st, "rr", 2, out), "no seat 2")
	assert_false(BtStrats.use(st, "rr", -1, out), "no seat -1")
	st.over = true
	assert_false(BtStrats.can(st, "gtg", 1), "nothing after the end")
	assert_false(BtStrats.use(st, "gtg", 1, out), "use refuses after the end")
	st.over = false
	assert_eq(st.digest(), d0, "refusals leave the digest alone")
	assert_eq(st.log_lines.size(), n_log, "and the log")
	assert_eq(out.size(), 1, "and send no event")


func test_lock_in_digest_and_snapshot() -> void:
	var st := _st([[0, 2], [1, 2]])
	var out: Array[Dictionary] = []
	var d0 := st.digest()
	BtStrats.use(st, "gtg", 1, out)
	assert_ne(st.digest(), d0, "a use changes the digest (CP and lock)")
	var copy := BattleState.new()
	assert_true(copy.restore(st.snapshot(false)), "the snapshot restores")
	assert_eq(copy.digest(), st.digest(), "the restored state has the same digest")
	assert_false(BtStrats.can(copy, "gtg", 1), "the lock survives a snapshot round trip")
	assert_eq(copy.seats[1].cp, 1, "and so does the spent CP")
	assert_true(BtStrats.can(copy, "gtg", 0), "team 0 is still free")


func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the scenario digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtStrats scenario digest is pinned")


## Four seats on two teams play two rounds of every phase, each seat trying every stratagem in seat order;
## the BattleState digest at the end (CP, locks) plus the outcome bits.
func _digest_scenario() -> String:
	var st := _st([[0, 2], [0, 3], [1, 1], [1, 4]])
	var out: Array[Dictionary] = []
	var bits := PackedInt64Array()
	for r: int in range(1, 3):
		st.round_no = r
		for t: int in 2:
			st.turn = t
			for p: BattleState.Seat in st.seats:
				if p.team == t:
					p.cp += 1
			for ph: int in BattleState.PHASES.size():
				st.phase = ph
				for pi: int in st.seats.size():
					for k: String in BtStrats.KEYS:
						bits.append(1 if BtStrats.use(st, k, pi, out) else 0)
	bits.append(out.size())
	return Hash.digest_hex(bits) + ":" + st.digest()
