extends "res://tests/testing.gd"
## NetBattleLink (NET_SPEC §5.2) review fixes, without sockets: the link sits under a plain parent (no Net signals) and
## drives the fixture's host runner. When the host's own step waits for a friend's roll, the one-shot wake Timer is set
## within 15 s (it used to start only on `changed`, so a host shooting a friend's squad waited forever if the friend's
## screen was not pumping); once the roll is overdue and the wake has fired, the link does not re-arm a 1 ms timer
## every frame; the next host step rolls it. A client link that cannot reach the room (send fails) leaves no request
## in flight.

const PAIR := "res://tests/unit/fixtures/net_battle_pair.gd"
const MAX_STEPS := 20000


func _choice(seed_v: int) -> Dictionary:
	var c := SeatPlan.defaults(seed_v)
	c["teams"] = 2
	c["per_team"] = 1
	c["size"] = "s"
	c["goal"] = "obj"
	c["rounds"] = 3
	c["budget"] = 300
	c["seats"] = [{"fac": "gr", "human": true, "owner": 0}, {"fac": "kn", "human": false, "owner": 1}]
	return c


func _link() -> Node:
	var parent := Node.new()
	parent.name = "LinkTestParent%d" % randi()
	(Engine.get_main_loop() as SceneTree).root.add_child(parent)
	var link: Node = load("res://ui/battle/net_battle_link.gd").new()
	parent.add_child(link)
	return link


func test_wake_timer_follows_the_hosts_wait() -> void:
	var pair: RefCounted = load(PAIR).new()
	var ok: bool = pair.make(_choice(9), [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "สมหญิง"}], {0: 5, 1: 6})
	assert_true(ok, "the room starts", pair.bad)
	var host: NetMatchRunner = pair.host
	host.auto_human = true
	host.fake_now = 1000
	var link := _link()
	link.call("attach", host)
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
		# the silent friend only ends its phases so the game reaches a roll it must make
		var body := {"gen": 1, "base": host.acts().size(), "act": {"a": "done", "ph": host.st.phase_name(), "pid": "n1"}}
		host.receive(NetProto.ACT_REQ, body, 1)
	assert_true(found, "a roll of the friend's seat waits on the host")
	if not found:
		link.get_parent().queue_free()
		return
	var left: float = link.call("wake_left")
	assert_true(left > 0.0 and left <= Lockstep.ROLL_WAIT_MS / 1000.0, "the host's own wait set the wake timer (%.2f s)" % left)
	# 15 s later the wake fires: the roll is overdue, the screen is not pumping (leave dialog open)
	host.fake_now += Lockstep.ROLL_WAIT_MS
	var timer: Timer = link.get_children().filter(func(c: Node) -> bool: return c is Timer)[0]
	timer.stop()
	var changed := [0]
	host.changed.connect(func() -> void: changed[0] += 1)
	link.call("_on_wake")
	assert_eq(changed[0], 1, "the wake told the screen once")
	assert_eq(float(link.call("wake_left")), -1.0, "overdue and already woken: no 1 ms timer every frame")
	var n0 := host.acts().size()
	host.step()
	assert_true(host.acts().size() > n0, "the next host step rolls for the silent friend")
	assert_eq(str(host.acts()[n0].get("pid")), "n1", "with the seat's pid")
	link.get_parent().queue_free()


func test_client_request_not_in_flight_when_send_fails() -> void:
	var pair: RefCounted = load(PAIR).new()
	var ok: bool = pair.make(_choice(31), [{"slot": 0, "nm": "เจ้าห้อง"}, {"slot": 1, "nm": "สมหญิง"}], {0: 5, 1: 6})
	assert_true(ok, "the room starts", pair.bad)
	var cli: NetMatchRunner = pair.clients[1]
	# a client whose link cannot send (reconnecting): Net.send returns false
	cli.lockstep.send = func(_k: int, _b: Dictionary, _t: int) -> bool: return false
	var host: NetMatchRunner = pair.host
	host.auto_human = true
	var reached := false
	for i in MAX_STEPS:
		var state := str(host.step()["state"])
		pair.deliver()
		if state == "wait_remote":
			reached = true   # the host waits for the client: its turn or its roll
			break
		if host.is_over():
			break
	assert_true(reached, "the host waits for the client")
	if not reached:
		return
	cli.auto_human = true
	var r := cli.step()
	assert_eq(str(r["state"]), "wait_remote", "the client waits")
	assert_false(cli.in_flight, "a request that was not sent is not in flight (no freeze until a RESYNC)")
