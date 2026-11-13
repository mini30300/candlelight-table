extends "res://tests/testing.gd"
## Lockstep over the deterministic core (NET_SPEC §4, §12.2), pure: a host NetMatchRunner and client runners joined by
## an in-memory transport (tests/unit/fixtures/net_battle_pair.gd: in order, every message through NetProto encode →
## decode, drop and tamper hooks). 2 teams × 2 seats: host seat 0, client seats 1 and 2 (slots 1, 2), seat 3 a bot;
## 48" table, 300 points; everyone on auto play with fixed dice seeds; plus a spectator (slot 3, no seat).
## Checks: the game ends; after every ACT each client's digest equals the host's at that seq; a dg at least every 8
## seqs; every act's pid matches its seat (bots ""); a client never applies its own act before the echo; a stale base →
## ACT_NO stale; a forged pid, another seat's squad, endph → not_yours with nothing logged; a roll answer that is not the
## client's → not_now; disconnect → SEAT gone, the host plays the seat with pid n2 and bot:2 dice; reconnect from the
## resync → same digest, SEAT back, it plays on; a tampered move → DESYNC within 8 acts (event, log line, state), the
## resync repairs it; a tampered resync too → desync_final and the first differing state_ints index logged.
## Review fixes: the host never rolls a live friend's dice because another seat is gone (no bot:1 while seat 2 is cut);
## a rejoined client (built without start, like the link does) seeds its dice from the device, not the table seed;
## bots never act while the first pending roll is a friend's (3 teams × 1); a client whose seat the host plays sends no
## requests and says so; LEAVE of this game makes the seat "left", LEAVE of an old game is ignored; heavy requests
## (RESYNC_REQ, INTS_REQ, RESEND, DESYNC) have a per-member budget per game, a RESEND far back is one RESYNC.

const PAIR := "res://tests/unit/fixtures/net_battle_pair.gd"
const MEMBERS := [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "หนึ่ง"}, {"slot": 2, "nm": "สอง"}, {"slot": 3, "nm": "ดู"}]


func _choice(seed_v: int, facs: Array = ["kn", "or", "gr", "de"]) -> Dictionary:
	var c := SeatPlan.defaults(seed_v)
	c["teams"] = 2
	c["per_team"] = 2
	c["size"] = "m"
	c["goal"] = "obj"
	c["rounds"] = 3
	c["budget"] = 300
	var owners := [0, 1, 2, -1]
	var seats: Array = []
	for k in 4:
		seats.append({"fac": facs[k], "human": owners[k] == 0, "owner": owners[k]})
	c["seats"] = seats
	return c


func _room(seed_v: int, facs: Array = ["kn", "or", "gr", "de"]) -> RefCounted:
	var pair: RefCounted = load(PAIR).new()
	var ok: bool = pair.make(_choice(seed_v, facs), MEMBERS, {0: 101, 1: 202, 2: 303, 3: 404})
	assert_true(ok, "seed %d: the room starts" % seed_v, pair.bad)
	pair.host.auto_human = true
	for s: int in pair.clients:
		pair.clients[s].auto_human = true
	return pair


## The seat an act belongs to: the acting squad's seat, the target's seat for saves and overwatch choices, -1 for the
## host's phase ends, -2 when unknown (done: its pid is the seat).
func _seat_of(st: BattleState, a: Dictionary) -> int:
	var code := str(a.get("a", ""))
	if code == "endph":
		return -1
	if code == "done":
		return -2
	var id := str(a.get("t", "")) if code == "sav" or code == "ow" else str(a.get("u", ""))
	var sq := st.squad(id)
	return sq.pl if sq != null else -2


func _seat_of_pid(pid: String) -> int:
	return pid.trim_prefix("n").to_int() if pid.begins_with("n") else -1


func test_full_game_in_lockstep() -> void:
	var pair := _room(4242)
	var host: NetMatchRunner = pair.host
	var c1: NetMatchRunner = pair.clients[1]
	var c2: NetMatchRunner = pair.clients[2]
	var spec: NetMatchRunner = pair.clients[3]
	assert_eq(spec.human, -1, "slot 3 has no seat: a spectator")
	assert_eq(c1.pid, "n1", "client 1 plays as n1")
	assert_eq(c2.pid, "n2", "client 2 plays as n2")
	# a client never applies its own act before the echo: while a request is in flight its log is a prefix of the host's
	var early := {"bad": 0, "seen": 0}
	var stop := func() -> bool:
		early["seen"] += 1
		if c1.acts().size() > host.acts().size() or c1.acts() != host.acts().slice(0, c1.acts().size()):
			early["bad"] += 1
		return false
	assert_eq(pair.run(20000, stop), "over", "4 seats + spectator: the game ends")
	assert_true(early["seen"] > 0 and early["bad"] == 0, "client 1 only ever holds acts the host logged first (%d checks)" % early["seen"])
	assert_true(host.is_over(), "the host game is over (%s)" % host.over_why())
	for s: int in [1, 2, 3]:
		var c: NetMatchRunner = pair.clients[s]
		assert_true(c.is_over(), "client %d is over" % s)
		assert_eq(c.acts().size(), host.acts().size(), "client %d applied every act (%d)" % [s, host.acts().size()])
		assert_digest(c.digest(), host.digest(), "client %d ends with the host digest" % s)
		assert_eq(c.sync_state(), &"ok", "client %d never desynced" % s)
		assert_true(c.checks() >= host.acts().size() / Lockstep.DIGEST_EVERY, "client %d passed %d digest checks (>= %d)" % [s, c.checks(), host.acts().size() / Lockstep.DIGEST_EVERY])
	assert_eq(c1.acts(), host.acts(), "client 1 has the host's act log")
	assert_eq(pair.bad, [], "every message passed the codec")
	# dg at least every 8 seqs; every act pid matches its seat
	var acts: Array = pair.delivered(NetProto.ACT, 1)
	var last_dg := 0
	var gap := 0
	var bad_pid := 0
	for body: Dictionary in acts:
		var seq := int(body["seq"])
		if body.has("dg"):
			gap = maxi(gap, seq - last_dg)
			last_dg = seq
		var a: Dictionary = body["act"]
		var want := _seat_of(host.st, a)
		var got := str(a.get("pid", ""))
		if want == -2:
			continue
		var want_pid := host.st.seats[want].pid if want >= 0 and not host.st.seats[want].bot else ""
		if got != want_pid:
			bad_pid += 1
			if bad_pid < 4:
				print("      pid mismatch: ", a, " want ", want_pid)
	assert_true(gap <= Lockstep.DIGEST_EVERY, "a dg travels at least every 8 seqs (largest gap %d)" % gap)
	assert_eq(bad_pid, 0, "every act's pid matches its seat (bots \"\")")
	var by_seat := {0: 0, 1: 0, 2: 0}
	for a: Dictionary in host.acts():
		var s := _seat_of_pid(str(a.get("pid", "")))
		if by_seat.has(s):
			by_seat[s] += 1
	assert_true(by_seat[1] > 0 and by_seat[2] > 0 and by_seat[0] > 0, "all three humans acted (%s)" % str(by_seat))
	assert_eq(host.replayed_digest(), host.digest(), "the host log replays to the same digest")
	assert_eq((c1.b as NetMatchRunner.NetRec).bot_steps, 0, "clients never ran the bots")
	assert_false(host.st.rngs.has("dice:1") or host.st.rngs.has("dice:2"), "the host never rolled the friends' dice")


func test_requests_refused_by_the_gate() -> void:
	var pair := _room(77)
	var host: NetMatchRunner = pair.host
	# play until it is team 0's move phase with client 1 to act
	var st := host.st
	var stop := func() -> bool:
		return st.turn == 0 and st.phase == BattleState.PH_MOVE and not st.seats[1].done and pair.clients[1].in_flight == false and Lockstep.first_live(st) == null
	pair.clients[1].auto_human = false
	pair.run(2000, stop)
	assert_true(st.turn == 0 and st.phase == BattleState.PH_MOVE, "reached team 0's move phase")
	var mine: BattleState.Squad = null
	var theirs: BattleState.Squad = null
	for s: BattleState.Squad in st.alive_squads():
		if s.pl == 1 and mine == null and not s.moved:
			mine = s
		if s.pl == 0 and theirs == null:
			theirs = s
	assert_true(mine != null and theirs != null, "found a squad of seat 1 and one of seat 0")
	var n0 := host.acts().size()
	var base := host.acts().size()
	var noes0: int = pair.delivered(NetProto.ACT_NO, 1).size()
	# stale base
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base - 1, "act": {"a": "stay", "u": mine.id, "pid": "n1"}}, 1)
	pair.deliver()
	var noes: Array = pair.delivered(NetProto.ACT_NO, 1)
	assert_eq(noes.size(), noes0 + 1, "a stale request gets an answer")
	assert_eq(str(noes[noes.size() - 1]["key"]), "stale", "stale base → ACT_NO stale")
	assert_eq(host.acts().size(), n0, "nothing logged for the stale request")
	# forged pid
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base, "act": {"a": "stay", "u": mine.id, "pid": "n2"}}, 1)
	pair.deliver()
	noes = pair.delivered(NetProto.ACT_NO, 1)
	assert_eq(str(noes[noes.size() - 1]["key"]), "not_yours", "a forged pid → not_yours")
	# another seat's squad
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base, "act": {"a": "stay", "u": theirs.id, "pid": "n1"}}, 1)
	pair.deliver()
	noes = pair.delivered(NetProto.ACT_NO, 1)
	assert_eq(str(noes[noes.size() - 1]["key"]), "not_yours", "another seat's squad → not_yours")
	# endph is the host's only
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base, "act": {"a": "endph", "ph": "move", "pid": "n1"}}, 1)
	pair.deliver()
	noes = pair.delivered(NetProto.ACT_NO, 1)
	assert_eq(str(noes[noes.size() - 1]["key"]), "not_yours", "endph from a client → not_yours")
	# a roll answer for an entry that is not this client's
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base, "act": {"a": "sav", "u": theirs.id, "t": mine.id, "save": [6], "gtg": 0, "pid": "n1"}}, 1)
	pair.deliver()
	noes = pair.delivered(NetProto.ACT_NO, 1)
	assert_eq(str(noes[noes.size() - 1]["key"]), "not_now", "a roll answer that is not the client's → not_now")
	# a seat-less member
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base, "act": {"a": "stay", "u": mine.id, "pid": "n3"}}, 3)
	pair.deliver()
	assert_eq(str(pair.delivered(NetProto.ACT_NO, 3).back()["key"]), "not_yours", "a spectator's request → not_yours")
	# an old game's request is dropped silently
	var before: int = pair.log.size()
	host.receive(NetProto.ACT_REQ, {"gen": 0, "base": base, "act": {"a": "stay", "u": mine.id, "pid": "n1"}}, 1)
	pair.deliver()
	assert_eq(pair.log.size(), before, "a request of another game is dropped without an answer")
	assert_eq(host.acts().size(), n0, "nothing was logged by any refused request")
	# a legal one goes through and is echoed
	host.receive(NetProto.ACT_REQ, {"gen": 1, "base": base, "act": {"a": "stay", "u": mine.id, "pid": "n1"}}, 1)
	pair.deliver()
	assert_eq(host.acts().size(), n0 + 1, "a legal request is logged")
	assert_eq(str(host.acts()[n0]["pid"]), "n1", "with the seat's pid")
	assert_digest(pair.clients[2].digest(), host.digest(), "and echoed to everyone")
	# the game continues to the end
	pair.clients[1].auto_human = true
	assert_eq(pair.run(), "over", "the game continues to the end after refused requests")
	assert_digest(pair.clients[1].digest(), host.digest(), "same digest at the end")


func test_disconnect_bot_takes_over_then_reconnect() -> void:
	# seat 2 has guns (rolls of its own while the host plays it)
	var pair := _room(31, ["gr", "or", "kn", "de"])
	var host: NetMatchRunner = pair.host
	var stop := func() -> bool: return host.acts().size() >= 12
	pair.run(5000, stop)
	assert_true(host.acts().size() >= 12, "the game ran 12 acts")
	# client 2 drops
	pair.cut[2] = true
	host.seat_gone(2)
	pair.deliver()
	var seats: Array = pair.delivered(NetProto.SEAT, 1)
	assert_true(not seats.is_empty() and str(seats.back()["on"]) == "gone" and int(seats.back()["k"]) == 2, "SEAT gone for seat 2 reached the others")
	assert_eq(host.gone_seats(), PackedInt32Array([2]), "the host plays seat 2")
	assert_eq(pair.clients[1].gone_seats(), PackedInt32Array([2]), "client 1 knows seat 2 is played by the host")
	var drop_at := host.acts().size()
	var stop2 := func() -> bool:
		var n := 0
		for i in range(drop_at, host.acts().size()):
			if str(host.acts()[i].get("pid", "")) == "n2":
				n += 1
		return n >= 6 and host.st.rngs.has("bot:2")
	pair.run(5000, stop2)
	var n2 := 0
	for i in range(drop_at, host.acts().size()):
		if str(host.acts()[i].get("pid", "")) == "n2":
			n2 += 1
	assert_true(n2 >= 6, "the host played seat 2 with pid n2 (%d acts)" % n2)
	assert_eq(host.st.seats[2].bot, false, "seat 2 stays a human seat (bot = false)")
	assert_eq(host.st.seats[2].pid, "n2", "seat 2 keeps its pid")
	assert_digest(pair.clients[1].digest(), host.digest(), "client 1 still in step")
	assert_false(host.st.rngs.has("bot:1"), "the host never rolled live seat 1's dice while seat 2 was gone (no bot:1)")
	# reconnect: a fresh client runner (built and not started, as the link does) rebuilt from the resync
	pair.cut.erase(2)
	pair.queue.clear()
	var nc: NetMatchRunner = pair.add_client(2, 0, false)
	nc.auto_human = true
	host.seat_back(2)
	pair.deliver()
	assert_eq(nc.resyncs(), 1, "the rejoined client was rebuilt from RESYNC")
	var dice: Rng = nc.st.rngs.get("dice:2")
	assert_true(dice != null and dice.seed_value != nc.st.seed, "the rejoined client's dice are seeded on the device, not from the table seed")
	assert_digest(nc.digest(), host.digest(), "the rejoined client has the host digest")
	assert_eq(nc.sync_state(), &"ok", "and is in sync")
	seats = pair.delivered(NetProto.SEAT, 1)
	assert_eq(str(seats.back()["on"]), "back", "SEAT back reached the others")
	assert_eq(host.gone_seats(), PackedInt32Array(), "the host no longer plays seat 2")
	var back_at := host.acts().size()
	assert_eq(pair.run(), "over", "the game ends after the rejoin")
	assert_digest(nc.digest(), host.digest(), "the rejoined client ends in step")
	var after := 0
	for i in range(back_at, host.acts().size()):
		if str(host.acts()[i].get("pid", "")) == "n2":
			after += 1
	assert_true(after > 0 or host.st.over, "the rejoined client played on (%d acts)" % after)
	assert_true(host.st.rngs.has("bot:2"), "the host rolled seat 2 from bot:2 while it was gone")
	assert_false(host.st.rngs.has("dice:2"), "the host never used seat 2's own dice stream")
	assert_false(host.st.rngs.has("bot:1"), "the host never rolled live seat 1's dice (no bot:1)")
	assert_eq(pair.bad, [], "every message passed the codec")


## 3 teams × 1 seat: host seat 0, client seat 1 (slot 1), seat 2 a bot.
func _room3(seed_v: int) -> RefCounted:
	var c := SeatPlan.defaults(seed_v)
	c["teams"] = 3
	c["per_team"] = 1
	c["size"] = "m"
	c["goal"] = "obj"
	c["rounds"] = 3
	c["budget"] = 300
	var facs := ["gr", "kn", "or"]
	var owners := [0, 1, -1]
	var seats: Array = []
	for k in 3:
		seats.append({"fac": facs[k], "human": owners[k] == 0, "owner": owners[k]})
	c["seats"] = seats
	var pair: RefCounted = load(PAIR).new()
	var ok: bool = pair.make(c, [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "หนึ่ง"}], {0: 11, 1: 22})
	assert_true(ok, "seed %d: the 3-team room starts" % seed_v, pair.bad)
	pair.host.auto_human = true
	pair.clients[1].auto_human = true
	return pair


func test_bots_wait_for_a_friends_roll() -> void:
	# replaying the host's log: every bot action (pid "", not a roll) and every endph is applied with no live pending
	# roll, as offline (the old page's botTick waits on PEND too)
	var bad := []
	var games := 0
	for seed_v: int in [3, 17, 29, 41, 58]:
		var pair := _room3(seed_v)
		var host: NetMatchRunner = pair.host
		if pair.run() != "over":
			bad.append("seed %d did not end" % seed_v)
			continue
		games += 1
		var b := Battle.make(pair.wire_plan["setup"], _seats(pair.wire_plan), {})
		b.start()
		for a: Dictionary in host.acts():
			var code := str(a.get("a", ""))
			# a bot's action or the host's phase end (a roll the bot answers has the bot as the first roller, never seat 1)
			if str(a.get("pid", "")) == "" and (Lockstep.ACTION_CODES.has(code) or code == "endph"):
				var p := Lockstep.first_live(b.st)
				if p != null and BtPend.roller_of(p) == 1:
					bad.append("seed %d seq %d: bot %s while seat 1's roll waits" % [seed_v, int(a.get("seq", 0)), code])
			b.apply(a)
		assert_digest(b.digest(), host.digest(), "seed %d: the replay ends with the host digest" % seed_v)
		assert_digest(pair.clients[1].digest(), host.digest(), "seed %d: the client ends in step" % seed_v)
	assert_eq(games, 5, "five games ended")
	assert_eq(bad, [], "no bot action while the first pending roll is the friend's")


static func _seats(plan: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sd: Variant in plan.get("seats", []):
		out.append((sd as Dictionary).duplicate(true))
	return out


func test_client_with_a_played_seat_waits() -> void:
	var pair := _room(64)
	var host: NetMatchRunner = pair.host
	var c1: NetMatchRunner = pair.clients[1]
	pair.run(5000, func() -> bool: return host.acts().size() >= 10)
	# the host plays seat 1 for the rest of the game (e.g. a LEAVE that crossed a START)
	host.seat_gone(1, "left")
	pair.deliver()
	assert_true(c1.my_seat_gone(), "client 1 knows the host plays its seat")
	var said := false
	for n: Dictionary in c1.take_notices():
		said = said or str(n.get("key", "")) == "mine"
	assert_true(said, "client 1 gets the notice that a bot plays its seat")
	assert_false(c1.is_human_turn(), "not client 1's turn any more")
	var reqs0: int = 0
	for e: Array in pair.log:
		if int(e[0]) == 1 and int(e[2]) == NetProto.ACT_REQ:
			reqs0 += 1
	assert_eq(pair.run(), "over", "the game ends with seat 1 played by the host")
	var reqs := 0
	for e: Array in pair.log:
		if int(e[0]) == 1 and int(e[2]) == NetProto.ACT_REQ:
			reqs += 1
	assert_eq(reqs, reqs0, "client 1 sent no request once its seat was played by the host")
	assert_digest(c1.digest(), host.digest(), "client 1 still ends in step")
	# a stray request of a played seat: ACT_NO gone_seat, the client marks its own seat
	var pair2 := _room(65)
	pair2.run(5000, func() -> bool: return pair2.host.acts().size() >= 6)
	pair2.host.lockstep.gone[2] = "left"
	var c2: NetMatchRunner = pair2.clients[2]
	pair2.host.receive(NetProto.ACT_REQ, {"gen": 1, "base": pair2.host.acts().size(), "act": {"a": "stay", "u": "x", "pid": "n2"}}, 2)
	pair2.deliver()
	assert_true(c2.my_seat_gone(), "ACT_NO gone_seat: client 2 marks its seat as played by the host")


func test_leave_of_this_game_only() -> void:
	var pair := _room(66)
	var host: NetMatchRunner = pair.host
	pair.run(5000, func() -> bool: return host.acts().size() >= 6)
	pair.post(2, NetProto.LEAVE, {"gen": 0}, -1)
	pair.deliver()
	assert_eq(host.gone_seats(), PackedInt32Array(), "a LEAVE of an old game is ignored")
	pair.post(2, NetProto.LEAVE, {"gen": 1}, -1)
	pair.deliver()
	assert_eq(host.gone_seats(), PackedInt32Array([2]), "a LEAVE of this game: the host plays seat 2")
	assert_eq(str(host.lockstep.gone[2]), "left", "as left (no seat back in this game)")
	host.seat_back(2)
	assert_eq(host.gone_seats(), PackedInt32Array([2]), "a left seat is not given back")
	var seats: Array = pair.delivered(NetProto.SEAT, 1)
	assert_true(not seats.is_empty() and str(seats.back()["on"]) == "left", "the others hear SEAT left")
	pair.cut[2] = true
	assert_eq(pair.run(), "over", "the game ends")
	assert_digest(pair.clients[1].digest(), host.digest(), "client 1 ends in step")


func test_heavy_requests_have_a_budget() -> void:
	var pair := _room(67)
	var host: NetMatchRunner = pair.host
	pair.run(5000, func() -> bool: return host.acts().size() >= NetMatchRunner.RESEND_MAX + 10)
	assert_true(host.acts().size() > NetMatchRunner.RESEND_MAX, "a game long enough for a far RESEND (%d acts)" % host.acts().size())
	var before: int = pair.log.size()
	var resyncs := func() -> int:
		var n := 0
		for i in range(before, pair.log.size()):
			if int(pair.log[i][2]) == NetProto.RESYNC and int(pair.log[i][1]) == 1:
				n += 1
		return n
	# a RESEND far back: one RESYNC, not a flood of ACTs
	var acts0: int = pair.delivered(NetProto.ACT, 1).size()
	host.receive(NetProto.RESEND, {"gen": 1, "from": 1}, 1)
	pair.deliver()
	assert_eq(resyncs.call(), 1, "a RESEND from seq 1 is answered with one RESYNC")
	assert_eq(pair.delivered(NetProto.ACT, 1).size(), acts0, "and no resent ACT")
	# RESYNC_REQ: at most ASK_MAX per member per game (the far RESEND counted as one), then the seat is played
	for i in 10:
		host.receive(NetProto.RESYNC_REQ, {"gen": 1, "why": "desync"}, 1)
	pair.deliver()
	var cap := int(NetMatchRunner.ASK_MAX[NetProto.RESYNC_REQ])
	assert_eq(resyncs.call(), cap, "RESYNCs answered for slot 1 stop at %d" % cap)
	assert_true(host.gone_seats().has(1), "asking on and on: the host plays that seat to the end")
	# INTS_REQ and DESYNC
	for i in 6:
		host.receive(NetProto.INTS_REQ, {"gen": 1}, 2)
	pair.deliver()
	var ints := 0
	for i in range(before, pair.log.size()):
		if int(pair.log[i][2]) == NetProto.INTS and int(pair.log[i][1]) == 2:
			ints += 1
	assert_eq(ints, int(NetMatchRunner.ASK_MAX[NetProto.INTS_REQ]), "INTS answers stop at the budget")
	var l0 := host.lockstep.log_lines.size()
	for i in 30:
		host.receive(NetProto.DESYNC, {"gen": 1, "seq": 1, "dg": "0000000000000000", "n": 1}, 2)
	var lines := 0
	for l: String in host.lockstep.log_lines.slice(l0):
		if l.contains("desync reported"):
			lines += 1
	assert_eq(lines, int(NetMatchRunner.ASK_MAX[NetProto.DESYNC]), "DESYNC reports logged up to the budget only (%d)" % lines)
	for i in 400:
		host.lockstep._log("info", "x")
	assert_true(host.lockstep.log_lines.size() <= Lockstep.LOG_KEEP, "the lockstep keeps at most %d log lines" % Lockstep.LOG_KEEP)


## Moves the end point of one smove by 0.2" in a copy of `a` (the state must differ whether or not the core accepts it).
static func _shift(a: Dictionary) -> bool:
	if str(a.get("a", "")) != "smove" or not a.get("to") is Array or (a["to"] as Array).is_empty():
		return false
	var to: Array = a["to"]
	var last: Variant = to[to.size() - 1]
	if not last is Array or (last as Array).size() < 2:
		return false
	(last as Array)[0] = int((last as Array)[0]) + 200
	return true


## Shifts the first smove ACT to `slot` at or after `from_seq` (once); state["seq"] = its seq.
func _move_tamper(slot: int, from_seq: int, state: Dictionary) -> Callable:
	return func(to: int, kind: int, body: Dictionary) -> Dictionary:
		if state.get("done", false) or to != slot or kind != NetProto.ACT or int(body["seq"]) < from_seq:
			return body
		var b := body.duplicate(true)
		if not _shift(b["act"]):
			return body
		state["done"] = true
		state["seq"] = int(body["seq"])
		return b


func test_desync_is_loud_and_repaired() -> void:
	var pair := _room(555)
	var host: NetMatchRunner = pair.host
	var c2: NetMatchRunner = pair.clients[2]
	var t := {}
	pair.tamper = _move_tamper(2, 1, t)
	var lg := get_log()
	var l0: int = lg.size() if lg != null else 0
	var stop := func() -> bool:
		return c2.sync_state() != &"ok" or (t.has("seq") and c2.acts().size() > int(t["seq"]) + Lockstep.DIGEST_EVERY + 1 and c2.sync_state() == &"ok" and c2.resyncs() > 0)
	pair.run(5000, stop)
	assert_true(t.has("seq"), "one move was tampered on the way to client 2 (seq %d)" % int(t.get("seq", -1)))
	var desyncs := 0
	var evs: Array = pair.events.get(2, [])
	for e: Dictionary in evs:
		if Events.id_of(e) == Events.Id.DESYNC:
			desyncs += 1
			assert_true(int(e["seq"]) - int(t.get("seq", 0)) <= Lockstep.DIGEST_EVERY, "DESYNC raised within 8 acts (at %d, tampered %d)" % [int(e["seq"]), int(t.get("seq", 0))])
			assert_ne(str(e["local_digest"]), str(e["remote_digest"]), "the event carries both digests")
	assert_eq(desyncs, 1, "one DESYNC event in client 2's queue")
	var line := ""
	for l: String in c2.lockstep.log_lines:
		if l.begins_with("error desync gen=1"):
			line = l
	assert_true(line.contains("seq=") and line.contains("local=") and line.contains("host="), "an error log line with seq and both digests", line)
	if lg != null:
		var found := false
		for l: String in lg.call("lines").slice(l0):
			if l.contains("desync gen=1"):
				found = true
		assert_true(found, "the line reached the app log")
	assert_true(not pair.delivered(NetProto.DESYNC, 0).is_empty(), "the host was told (DESYNC)")
	assert_true(not pair.delivered(NetProto.RESYNC, 2).is_empty(), "the host sent a RESYNC")
	assert_eq(c2.sync_state(), &"ok", "the resync repaired client 2")
	assert_eq(c2.resyncs(), 1, "one resync")
	assert_digest(c2.digest(), host.digest(), "client 2 matches the host after the resync")
	pair.tamper = Callable()
	assert_eq(pair.run(), "over", "the game ends after the repair")
	assert_digest(c2.digest(), host.digest(), "client 2 ends in step")
	assert_eq(pair.bad, [], "every message passed the codec")


func test_desync_final_logs_the_first_difference() -> void:
	var pair := _room(808)
	var host: NetMatchRunner = pair.host
	var c2: NetMatchRunner = pair.clients[2]
	var t := {}
	var die := _move_tamper(2, 1, t)
	pair.tamper = func(to: int, kind: int, body: Dictionary) -> Dictionary:
		if to == 2 and kind == NetProto.RESYNC:
			# the resync is tampered too: the first smove of the log
			var b := body.duplicate(true)
			for a: Dictionary in b["acts"]:
				if _shift(a):
					break
			return b
		return die.call(to, kind, body)
	var stop := func() -> bool: return c2.sync_state() == &"desync_final" and not c2.lockstep.waiting_ints()
	assert_eq(pair.run(5000, stop), "stop", "client 2 reached desync_final")
	assert_eq(c2.sync_state(), &"desync_final", "a tampered resync leaves the client in desync_final")
	var n2 := 0
	for d: Dictionary in pair.delivered(NetProto.DESYNC, 0):
		if int(d["n"]) == 2:
			n2 += 1
	assert_eq(n2, 1, "the host got DESYNC n = 2")
	assert_true(not pair.delivered(NetProto.INTS, 2).is_empty(), "the host answered INTS")
	var line := ""
	for l: String in c2.lockstep.log_lines:
		if l.contains("desync ints") and l.contains("first index"):
			line = l
	assert_true(line != "", "the first differing state_ints index is logged with both values", c2.lockstep.log_lines)
	assert_eq(host.gone_seats(), PackedInt32Array([2]), "the host plays the seat of the desynced client")
	pair.cut[2] = true
	assert_eq(pair.run(), "over", "the game still ends for the others")
	assert_digest(pair.clients[1].digest(), host.digest(), "client 1 ends in step")


func test_gate_is_pure() -> void:
	var pair := _room(13)
	var st: BattleState = pair.host.st
	assert_eq(Lockstep.gate(st, 9, {"a": "stay"}), "not_yours", "no such seat → not_yours")
	assert_eq(Lockstep.gate(st, 1, {"a": "move"}), "not_yours", "legacy move → not_yours")
	assert_eq(Lockstep.gate(st, 1, {"a": "endturn"}), "not_yours", "endturn → not_yours")


func get_log() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null(^"Log") if loop is SceneTree else null
