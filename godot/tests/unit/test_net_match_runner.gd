extends "res://tests/testing.gd"
## NetMatchRunner (NET_SPEC §4.3, §4.4, §12.2): host equivalence (a host with no remote humans makes the same act log
## and digest as MatchRunner on the same plan, so the flush override changes nothing offline-like); a client runner
## never calls bot_step, its flush returns 0 and leaves the log alone, can_select is false while a request is in
## flight; wait_remote and waiting_for() names; next_wake_ms() while a remote roll waits, and after 15 s of fake time
## the host rolls it itself (bot:<seat> stream, the seat's pid). Pure (no display, no sockets).

const PAIR := "res://tests/unit/fixtures/net_battle_pair.gd"
const MAX_STEPS := 20000


func _choice(facs: Array, owners: Array, seed_v: int, size: String = "s", per: int = 1) -> Dictionary:
	var c := SeatPlan.defaults(seed_v)
	c["teams"] = facs.size() / per
	c["per_team"] = per
	c["size"] = size
	c["goal"] = "obj"
	c["rounds"] = 3
	c["budget"] = 300
	var seats: Array = []
	for k in facs.size():
		seats.append({"fac": facs[k], "human": int(owners[k]) == 0, "owner": int(owners[k])})
	c["seats"] = seats
	return c


func test_host_equivalence() -> void:
	for seed_v: int in [11, 4242, 777]:
		var c := _choice(["kn", "or"], [0, -1], seed_v)
		var plan := SeatPlan.build(c)
		var mr := MatchRunner.new(plan)
		assert_eq(mr.run_to_end(), "ok", "seed %d: MatchRunner plays to the end" % seed_v)
		var sent: Array = []
		var link := Lockstep.new(func(kind: int, body: Dictionary, to: int) -> void: sent.append([kind, body, to]), true, 0, 1, [0, -1])
		var nr := NetMatchRunner.host(plan, link, int(plan["setup"]["seed"]))
		assert_eq(nr.run_to_end(), "ok", "seed %d: the host NetMatchRunner plays to the end" % seed_v)
		assert_eq(nr.acts().size(), mr.acts().size(), "seed %d: same number of acts (%d)" % [seed_v, mr.acts().size()])
		assert_true(nr.acts() == mr.acts(), "seed %d: the same act log as MatchRunner" % seed_v)
		assert_digest(nr.digest(), mr.digest(), "seed %d: the same digest as MatchRunner" % seed_v)
		var acts_sent := 0
		var with_dg := 0
		for e: Array in sent:
			if int(e[0]) == NetProto.ACT:
				acts_sent += 1
				if (e[1] as Dictionary).has("dg"):
					with_dg += 1
		assert_eq(acts_sent, nr.acts().size(), "seed %d: every logged act was broadcast once" % seed_v)
		assert_true(with_dg >= nr.acts().size() / Lockstep.DIGEST_EVERY, "seed %d: digests travel at least every 8 acts (%d)" % [seed_v, with_dg])
		assert_eq(nr.replayed_digest(), nr.digest(), "seed %d: the host log replays to the same digest" % seed_v)


func test_client_never_runs_bots_or_flush() -> void:
	var pair: RefCounted = load(PAIR).new()
	var members := [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "เพื่อน"}]
	var ok: bool = pair.make(_choice(["kn", "or"], [0, 1], 31), members, {0: 5, 1: 6})
	assert_true(ok, "the room starts", pair.bad)
	var host: NetMatchRunner = pair.host
	var cli: NetMatchRunner = pair.clients[1]
	host.auto_human = true
	cli.auto_human = true
	assert_true(cli.online() and not cli.is_net_host() and host.is_net_host(), "online flags")
	assert_eq(cli.pid, "n1", "the client seat plays as n1")
	assert_eq(host.pid, "n0", "the host seat plays as n0")
	# flush on a client is a no-op
	var n0 := cli.acts().size()
	assert_eq(cli.b.flush(true, MatchRunner.HERE), 0, "client flush returns 0")
	assert_eq(cli.acts().size(), n0, "client flush leaves the log unchanged")
	assert_eq(pair.run(), "over", "a host + one client game ends")
	assert_eq((cli.b as NetMatchRunner.NetRec).bot_steps, 0, "the client never called bot_step")
	assert_true((host.b as NetMatchRunner.NetRec).bot_steps > 0, "the host ran the bots")
	assert_digest(cli.digest(), host.digest(), "client and host end with the same digest")
	assert_eq(pair.bad, [], "every message passed the codec")


func test_in_flight_and_waiting() -> void:
	var pair: RefCounted = load(PAIR).new()
	var members := [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "สมชาย"}]
	# the remote seat goes first (team 0) so the game waits for it at once
	var ok: bool = pair.make(_choice(["kn", "or"], [1, 0], 52), members, {0: 5, 1: 6})
	assert_true(ok, "the room starts", pair.bad)
	var host: NetMatchRunner = pair.host
	var cli: NetMatchRunner = pair.clients[1]
	var r := host.step()
	for i in 50:
		if str(r["state"]) != "acted":
			break
		r = host.step()
	assert_eq(str(r["state"]), "wait_remote", "the host waits for the remote seat")
	assert_eq(host.waiting_for(), PackedStringArray(["สมชาย"]), "the host waits for สมชาย by name")
	assert_eq(host.next_wake_ms(), 0, "no wake timer while a friend has to act (not a roll)")
	pair.deliver()
	var cr := cli.step()
	assert_eq(str(cr["state"]), "wait_human", "the client waits for its player")
	var mine := cli.selectable()
	assert_true(not mine.is_empty(), "the client has squads to order")
	var n0 := cli.acts().size()
	var why := cli.stay(mine[0])
	assert_eq(why, "", "stay is sent as a request")
	assert_true(cli.in_flight, "the request is in flight")
	assert_eq(cli.acts().size(), n0, "the client does not apply its own act before the echo")
	assert_false(cli.can_select(mine[0]), "can_select is false while in flight")
	assert_eq(str(cli.step()["state"]), "wait_remote", "the client waits for the host while in flight")
	var sent0: int = pair.queue.size()
	assert_ne(cli.stay(mine[0]), "", "a second request while in flight is refused locally")
	assert_eq(pair.queue.size(), sent0, "nothing more was sent while in flight")
	pair.deliver()
	assert_false(cli.in_flight, "the echo cleared the request")
	assert_eq(cli.acts().size(), n0 + 1, "the echo was applied")
	assert_eq(str(cli.acts()[n0].get("pid")), "n1", "the echo carries the client pid")
	assert_digest(cli.digest(), host.digest(), "same digest after the echo")
	# client waiting_for: its own turn is not in the list; the host's seat is named "" (the screen says เจ้าห้อง)
	assert_true(not cli.waiting_for().has("สมชาย"), "a client never waits for itself")


func test_remote_roll_waits_then_host_rolls() -> void:
	var pair: RefCounted = load(PAIR).new()
	var members := [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "สมหญิง"}]
	var ok: bool = pair.make(_choice(["gr", "kn"], [0, 1], 9), members, {0: 5, 1: 6})
	assert_true(ok, "the room starts", pair.bad)
	var host: NetMatchRunner = pair.host
	host.auto_human = true
	host.fake_now = 1000
	var found := false
	for i in MAX_STEPS:
		var r := host.step()
		var state := str(r["state"])
		if state == "over":
			break
		if state != "wait_remote":
			continue
		if host.next_wake_ms() > 0:
			found = true
			break
		# the silent friend only ends its phases (a request with its pid) so the game reaches a roll it must make
		var st := host.st
		var body := {"gen": 1, "base": host.acts().size(), "act": {"a": "done", "ph": st.phase_name(), "pid": "n1"}}
		host.receive(NetProto.ACT_REQ, body, 1)
	assert_true(found, "a roll of the remote seat waits on the host (wake in %d ms)" % host.next_wake_ms())
	if not found:
		return
	var wake := host.next_wake_ms()
	assert_true(wake > 0 and wake <= Lockstep.ROLL_WAIT_MS, "next_wake_ms is within 15 s (%d)" % wake)
	assert_true(host.waiting_for().has("สมหญิง"), "the host waits for สมหญิง's roll")
	var n0 := host.acts().size()
	host.fake_now += 5000
	assert_eq(str(host.step()["state"]), "wait_remote", "5 s later the host still waits")
	assert_eq(host.acts().size(), n0, "nothing was rolled yet")
	host.fake_now += Lockstep.ROLL_WAIT_MS
	host.step()
	assert_true(host.acts().size() > n0, "after 15 s the host rolled for the silent friend")
	assert_eq(str(host.acts()[n0].get("pid")), "n1", "the roll carries the seat's pid n1")
	assert_true(host.st.rngs.has("bot:1"), "the host rolled from bot:1")
	assert_false(host.st.rngs.has("dice:1"), "the host never touched the friend's dice stream")
