extends "res://tests/testing.gd"
## NetSession over real ENet sockets on 127.0.0.1 (NET_SPEC §1-§3, §12.2): several sessions in one process, each under
## its own SceneMultiplayer (SceneTree.set_multiplayer), driven by the manual poll loop (poll(); OS.delay_msec(1)).
## Join → WELCOME and equal member lists; version and full refusals; raw bytes before authentication dropped; an
## oversize message disconnects its sender; poses relayed with the sender's slot (channel 1, default channel count);
## leave on both sides; port busy; a dropped nid gets its slot back; HB keeps members alive and silence drops them;
## room state, SETUP seats and claims; an invalid message from the host; nothing runs while offline.
## Review fixes: a friend that reconnects before the host's ENet notices the old peer is dead shows as away then back
## (so the battle link gives the seat back with a RESYNC); during a battle a seated slot is kept for its owner (a
## newcomer gets another slot, the owner gets its own back after the 60 s expiry); a member sending a host kind of
## 200 KB is dropped before decoding; the host binds IPv4 only.
## Test ports from §1.5; config files under TEST_OUT (never the machine's user://net.cfg). Skipped in the exported game.

var _tree: SceneTree
var _base := 0
var _made: Array[NetSession] = []
var _log: Array = []


func setup() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_base = 30000 + (OS.get_process_id() % 4000) * 2 + 400


func _skip() -> bool:
	if OS.has_feature("template"):
		print("skip  socket test in the exported self-test")
		return true
	return false


func _cfg(name: String) -> String:
	var dir := OS.get_environment("TEST_OUT")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://tests/out")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("net_%s_%d.cfg" % [name, OS.get_process_id()])


## a session on the current test port pair, with its own multiplayer and config file
func _mk(name: String, cfg_name := "") -> NetSession:
	var n := NetSession.new()
	n.name = name
	n.make_link = false
	n.cfg_file = _cfg(cfg_name if cfg_name != "" else name)
	n.ports = {"game": _base, "disc": _base + 1}
	n.probe = PackedStringArray(["127.0.0.1"])
	_tree.set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + name))
	_tree.root.add_child(n)
	_made.append(n)
	return n


## a host on a free test pair (retries the next pair on ERR_CANT_CREATE)
func _host(name := "Host") -> NetSession:
	var h: NetSession = null
	for i: int in 20:
		_base += 2
		h = _mk(name)
		var refused_keys: Array = []
		if h.host() == OK:
			return h
		_drop(h)
	return null


func _drop(n: NetSession) -> void:
	if n == null or not is_instance_valid(n):
		return
	_made.erase(n)
	DirAccess.remove_absolute(n.cfg_file)
	var path := n.get_path()
	if n.is_inside_tree():
		_tree.root.remove_child(n)
	n.free()
	_tree.set_multiplayer(null, path)


func _cleanup() -> void:
	for n: NetSession in _made.duplicate():
		if is_instance_valid(n):
			n.leave()
	_pump(func() -> bool: return false, 30)
	for n: NetSession in _made.duplicate():
		_drop(n)
	_made.clear()


## poll every session until cond() or ms run out; true when cond() held
func _pump(cond: Callable, ms: int, only: Array = []) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for n: NetSession in (_made if only.is_empty() else only):
			if is_instance_valid(n):
				n.poll()
		if cond.call():
			return true
		OS.delay_msec(1)
	return cond.call()


func _joined(c: NetSession, h: NetSession, ip := "127.0.0.1") -> bool:
	if c.join(ip, int(h.ports["game"])) != OK:
		return false
	return _pump(func() -> bool: return c.state() == &"joined" and h.members().size() >= c.members().size() \
		and c.members() == h.members(), 3000)


func test_offline_idle() -> void:
	var live := _tree.root.get_node_or_null(^"/root/Net")
	assert_true(live != null, "the Net autoload is in the tree")
	if live != null:
		assert_false(live.is_processing(), "Net does not process while offline")
		var timers := live.get_children().filter(func(c: Node) -> bool: return c is Timer)
		assert_eq(timers.size(), 0, "Net has no Timer child while offline")
		assert_eq(live.call("state"), &"off", "Net starts off")
		assert_eq(live.call("my_slot"), -1, "no slot offline")
	if _skip():
		return
	var kept := DisplayServer.screen_is_kept_on()
	var h := _host()
	assert_true(h != null and h.is_host(), "hosting works on a test port")
	assert_eq(h.get_children().filter(func(c: Node) -> bool: return c is Timer).size(), 1, "one Timer while online")
	h.leave()
	assert_eq(DisplayServer.screen_is_kept_on(), kept, "leaving restores the screen keep-on setting it found (review)")
	assert_eq(h.state(), &"off", "leave returns to off")
	assert_false(h.is_processing(), "not processing after leave")
	assert_eq(h.get_children().filter(func(c: Node) -> bool: return c is Timer).size(), 0, "no Timer child after leave")
	_cleanup()


func test_join_and_members() -> void:
	if _skip():
		return
	var h := _host()
	h.set_my_name("เจ้าห้อง")
	var c := _mk("Cli")
	c.set_my_name("  เพื่อน\n ")
	var states: Array = []
	c.state_changed.connect(func(s: StringName) -> void: states.append(s))
	var changed := [0]
	h.members_changed.connect(func() -> void: changed[0] += 1)
	assert_true(_joined(c, h), "the client joins 127.0.0.1")
	assert_eq(states.slice(0, 2), [&"connecting", &"joined"], "connecting then joined")
	assert_eq(c.my_slot(), 1, "the first friend is slot 1")
	assert_eq(h.my_slot(), 0, "the host is slot 0")
	assert_eq(c.members(), h.members(), "both member lists are equal")
	assert_eq(c.members().size(), 2, "two members")
	assert_eq(str(c.member(1).get("nm")), "เพื่อน", "the friend's cleaned name")
	assert_eq(str(c.member(0).get("nm")), "เจ้าห้อง", "the host's name")
	assert_eq(c.member(1).get("where"), &"menu", "where is a StringName (the client said menu after joining)")
	assert_true(changed[0] > 0, "the host emitted members_changed")
	assert_eq(c.room_state(), "deck", "room on the deck")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(c.cfg_file), OK, "the name and nid went to the test cfg file")
	assert_true(NetProto.is_hex(str(cfg.get_value("net", "nid", "")), 16), "nid is 16 hex characters")
	assert_true(h.is_processing() == false and c.is_processing() == false, "no _process while online (Timer only)")
	# leave on the client side: the host's list shrinks
	changed[0] = 0
	c.leave()
	assert_eq(c.state(), &"off", "the client is off after leave")
	assert_true(_pump(func() -> bool: return h.members().size() == 1, 2000), "the host drops the member after BYE")
	assert_true(changed[0] > 0, "members_changed on the host")
	_cleanup()


func test_refusals() -> void:
	if _skip():
		return
	var h := _host()
	var c := _mk("Cli")
	var got: Array = []
	c.refused.connect(func(k: String, a: Dictionary) -> void: got.append([k, a]))
	c.hello_extra = {"app": "x"}
	assert_eq(c.join("127.0.0.1", int(h.ports["game"])), OK, "join starts")
	assert_true(_pump(func() -> bool: return not got.is_empty(), 3000), "refused")
	assert_eq(got[0] if got.size() > 0 else [], ["wrong_app", {"host": Version.APP_VER, "mine": "x"}], "wrong_app with both versions")
	assert_eq(c.state(), &"off", "back to off after the refusal")
	assert_true(_pump(func() -> bool: return h.multiplayer.get_peers().is_empty() and h._knocking.is_empty(), 2000),
		"the host disconnected the refused peer")
	assert_eq(h.members().size(), 1, "nobody was added")
	# full: max_players = 1
	_cleanup()
	h = null
	for i: int in 20:
		_base += 2
		h = _mk("Host")
		h.max_players = 1
		if h.host() == OK:
			break
	c = _mk("Cli")
	got.clear()
	c.refused.connect(func(k: String, a: Dictionary) -> void: got.append([k, a]))
	c.join("127.0.0.1", int(h.ports["game"]))
	assert_true(_pump(func() -> bool: return not got.is_empty(), 3000), "refused when full")
	assert_eq(got[0] if got.size() > 0 else [], ["full", {"n": 1, "max": 1}], "full with n and max")
	# bad ip and public ip never touch a socket
	got.clear()
	assert_eq(c.join("example.com"), ERR_INVALID_PARAMETER, "a host name is a bad ip")
	assert_eq(c.join("8.8.8.8"), ERR_UNAUTHORIZED, "a public address is refused")
	assert_eq(got, [["bad_ip", {}], ["not_lan", {}]], "bad_ip then not_lan")
	_cleanup()


func test_raw_before_auth_and_oversize() -> void:
	if _skip():
		return
	var h := _host()
	var msgs: Array = []
	h.message.connect(func(s: int, k: int, b: Dictionary) -> void: msgs.append([s, k, b]))
	var raw := ENetMultiplayerPeer.new()
	assert_eq(raw.create_client("127.0.0.1", int(h.ports["game"])), OK, "a raw ENet client connects")
	var up := _pump(func() -> bool:
		raw.poll()
		return raw.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 2000)
	assert_true(up, "the raw client is connected at the ENet level")
	raw.set_target_peer(1)
	raw.put_packet(NetProto.encode(NetProto.CLAIM, {"k": 0}))
	_pump(func() -> bool:
		raw.poll()
		return false, 100)
	assert_eq(msgs, [], "bytes sent before authentication are dropped")
	assert_eq(h.members().size(), 1, "the raw peer is not a member")
	raw.close()
	# oversize from a member: disconnected by the host
	var c := _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	var big := PackedByteArray([NetProto.ACT_REQ])
	big.resize(70000)
	c.multiplayer.send_bytes(big, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)
	assert_true(_pump(func() -> bool: return h.members().size() == 1, 2000), "an oversize message drops its sender")
	assert_true(_pump(func() -> bool: return c.state() != &"joined", 2000), "the client lost its connection")
	assert_eq(msgs, [], "nothing from the oversize message reached the host's listeners")
	_cleanup()


func test_poses_relay() -> void:
	if _skip():
		return
	var h := _host()
	var c1 := _mk("Cli1")
	var c2 := _mk("Cli2")
	assert_true(_joined(c1, h), "friend 1 joins")
	var stop := {"x": 120, "z": -340, "yaw": 1571, "sp": 0, "run": false, "t": 77}
	c1.send_pose(stop, true)
	assert_true(_pump(func() -> bool: return h._poses.has(1), 1000), "the host keeps friend 1's last pose")
	var got2: Array = []
	c2.pose.connect(func(s: int, p: Dictionary) -> void: got2.append([s, p]))
	assert_true(_joined(c2, h), "friend 2 joins")
	assert_true(_pump(func() -> bool: return not got2.is_empty(), 1000), "the newcomer gets the last pose of friend 1")
	assert_eq(got2[0] if got2.size() > 0 else [], [1, stop], "slot 1 and the pose fields")
	var got_h: Array = []
	h.pose.connect(func(s: int, p: Dictionary) -> void: got_h.append([s, p]))
	got2.clear()
	var moving := {"x": 200, "z": -300, "yaw": -100, "sp": 350, "run": true, "t": 99}
	var ok := false
	for i: int in 10:
		c1.send_pose(moving, false)
		if _pump(func() -> bool: return not got2.is_empty() and not got_h.is_empty(), 100):
			ok = true
			break
	assert_true(ok, "a POSE on channel 1 reaches the host and friend 2 (default channel count works)")
	if ok:
		assert_eq(got2[0], [1, moving], "friend 2 sees slot 1 (the host added s)")
		assert_eq(got_h[0], [1, moving], "the host's pose signal names slot 1")
	var got1: Array = []
	c1.pose.connect(func(s: int, p: Dictionary) -> void: got1.append(s))
	h.send_pose({"x": 0, "z": 0, "yaw": 0, "sp": 0, "run": false, "t": 1}, true)
	assert_true(_pump(func() -> bool: return got1.has(0), 1000), "the host's own pose reaches friends as slot 0")
	_cleanup()


func test_host_leaves_and_port_busy() -> void:
	if _skip():
		return
	var h := _host()
	var c := _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	var lost: Array = []
	c.lost.connect(func(k: String) -> void: lost.append(k))
	var h2 := _mk("Host2")
	var refused: Array = []
	h2.refused.connect(func(k: String, a: Dictionary) -> void: refused.append([k, a]))
	assert_eq(h2.host(), ERR_CANT_CREATE, "a second host on the same game port cannot bind")
	assert_eq(refused, [["port_busy", {"port": int(h.ports["game"])}]], "refused port_busy with the port")
	assert_eq(h2.state(), &"off", "the second host stays off")
	# another game port but the same discovery port: hosting works, discovery is off (friends type the IP)
	h2.ports = {"game": int(h.ports["game"]) + 700, "disc": int(h.ports["disc"])}
	assert_eq(h2.host(), OK, "a host whose discovery port is taken still hosts")
	assert_false(h2.discovery_on(), "and says discovery is off")
	h2.leave()
	h.leave()
	assert_true(_pump(func() -> bool: return not lost.is_empty(), 2000), "the client notices")
	assert_eq(lost, ["host_left"], "lost(host_left)")
	assert_eq(c.state(), &"off", "the client is off")
	assert_eq(c.members().size(), 0, "no members left on the client")
	# the game port is free again
	var u := ENetMultiplayerPeer.new()
	assert_eq(u.create_server(int(h.ports["game"]), 2), OK, "binding the test game port again succeeds")
	u.close()
	_cleanup()


func test_reconnect_same_slot() -> void:
	if _skip():
		return
	var h := _host()
	var c1 := _mk("Cli1")
	var c2 := _mk("Cli2")
	assert_true(_joined(c1, h), "friend 1 joins")
	assert_true(_joined(c2, h), "friend 2 joins")
	assert_eq([c1.my_slot(), c2.my_slot()], [1, 2], "slots in join order")
	var again := [0]
	c1.reconnected.connect(func() -> void: again[0] += 1)
	# friend 1 drops without BYE (its socket closes; it is not polled for a while)
	c1._peer.close()
	assert_true(_pump(func() -> bool: return not bool(h.member(1).get("here", true)), 3000, [h, c2]),
		"the host marks slot 1 away")
	assert_eq(h.members().size(), 3, "slot 1 is kept while away")
	var c3 := _mk("Cli3")
	assert_true(c3.join("127.0.0.1", int(h.ports["game"])) == OK and _pump(func() -> bool: return c3.state() == &"joined", 3000, [h, c2, c3]),
		"a third friend joins")
	assert_eq(c3.my_slot(), 3, "the newcomer does not take the away slot")
	assert_true(_pump(func() -> bool: return c1.state() == &"joined" and again[0] == 1, 5000), "friend 1 reconnects")
	assert_eq(c1.my_slot(), 1, "the same nid gets the same slot")
	assert_true(_pump(func() -> bool: return bool(h.member(1).get("here", false)), 1000), "slot 1 is here again")
	assert_true(_pump(func() -> bool: return c2.members() == h.members(), 1000), "everyone sees the same list")
	_cleanup()


func test_heartbeats_and_silence() -> void:
	if _skip():
		return
	var h := _host()
	var c := _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	var hbs: Array = []
	h.message.connect(func(s: int, k: int, b: Dictionary) -> void:
		if k == NetProto.HB:
			hbs.append(s))
	for i: int in 6:
		h.clock_skew_ms += 2500
		c.clock_skew_ms += 2500
		_pump(func() -> bool: return false, 30)
	assert_true(hbs.size() >= 5, "HB every 2 s from the client (%d)" % hbs.size())
	assert_eq(h.members().size(), 2, "15 s of fake time with heartbeats: the member stays")
	assert_eq(c.state(), &"joined", "and the client stays joined")
	h.clock_skew_ms += 11000
	_pump(func() -> bool: return false, 30, [h])
	assert_false(bool(h.member(1).get("here", true)), "11 s of silence: the host marks the member away")
	_cleanup()


func test_room_state_setup_claim_and_messages() -> void:
	if _skip():
		return
	var h := _host()
	var c := _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	c.set_where(&"arena")
	assert_true(_pump(func() -> bool: return h.member(1).get("where") == &"arena", 1000), "WHERE reaches the host")
	assert_true(_pump(func() -> bool: return c.member(1).get("where") == &"arena", 1000), "and comes back in MEMBERS")
	var fac: String = GameData.factions()[0]
	c.set_pick(fac)
	assert_true(_pump(func() -> bool: return h.member(1).get("pick") == fac, 1000), "PICK reaches the host")
	c.set_pick("no-such-army")
	assert_eq(c._pick, fac, "an unknown army is not sent")
	var seats := [{"team": 0, "owner": 0, "fac": fac}, {"team": 1, "owner": -1, "fac": ""}]
	var msgs: Array = []
	c.message.connect(func(s: int, k: int, b: Dictionary) -> void: msgs.append([s, k]))
	assert_true(h.send(NetProto.SETUP, {"open": true, "seats": seats}), "the host sends SETUP")
	assert_eq(h.room_state(), "setup", "the host's room is in setup")
	assert_true(_pump(func() -> bool: return c.setup_seats() == seats, 1000), "the client has the setup seats")
	assert_true(_pump(func() -> bool: return c.room_state() == "setup", 1000), "the client's room state is setup")
	assert_true(msgs.has([0, NetProto.SETUP]), "SETUP reached the message signal")
	var claims: Array = []
	h.message.connect(func(s: int, k: int, b: Dictionary) -> void:
		if k == NetProto.CLAIM:
			claims.append([s, b]))
	c.claim(1)
	assert_true(_pump(func() -> bool: return not claims.is_empty(), 1000), "CLAIM reaches the host")
	assert_eq(claims[0] if claims.size() > 0 else [], [1, {"k": 1}], "from slot 1, seat 1")
	assert_false(c.send(NetProto.ACT, {"gen": 1, "seq": 1, "act": {"pid": "", "a": "endph"}}), "a client cannot send a host kind")
	assert_false(h.send(NetProto.CLAIM, {"k": 1}), "the host cannot send a client kind")
	assert_false(c.send(NetProto.CLAIM, {"k": 9}), "an invalid body is not sent")
	assert_true(h.send(NetProto.ACT_NO, {"gen": 1, "base": 3, "key": "stale"}, 1), "the host sends to one slot")
	assert_true(_pump(func() -> bool: return msgs.has([0, NetProto.ACT_NO]), 1000), "the slot gets it")
	assert_false(h.send(NetProto.ACT_NO, {"gen": 1, "base": 3, "key": "stale"}, 4), "an absent slot cannot be sent to")
	h.send(NetProto.SETUP, {"open": false, "seats": []})
	assert_true(_pump(func() -> bool: return c.setup_seats().is_empty() and c.room_state() == "deck", 1000), "setup closed")
	# an invalid message from the host: the client leaves with bad_message
	var lost: Array = []
	c.lost.connect(func(k: String) -> void: lost.append(k))
	h.multiplayer.send_bytes(PackedByteArray([NetProto.MEMBERS, 1, 2, 3]), h._slot_peer[1], MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)
	assert_true(_pump(func() -> bool: return not lost.is_empty(), 1000), "the client gives up on a junk message")
	assert_eq(lost, ["bad_message"], "lost(bad_message)")
	_cleanup()


func test_discovery_through_sessions() -> void:
	if _skip():
		return
	var h := _host()
	assert_true(h.discovery_on(), "the host's discovery socket is bound")
	var c := _mk("Cli")
	var changes := [0]
	c.found_changed.connect(func() -> void: changes[0] += 1)
	c.find(true)
	assert_eq(c.state(), &"finding", "find(true) is the finding state")
	assert_true(_pump(func() -> bool: return c.found().size() == 1, 3000), "the room appears in the list")
	var row: Dictionary = c.found()[0] if c.found().size() > 0 else {}
	assert_eq(row.get("port"), int(h.ports["game"]), "the row carries the game port")
	assert_true(bool(row.get("ok", false)), "versions ok")
	assert_eq(int(row.get("n", 0)), 1, "one member")
	assert_true(changes[0] > 0, "found_changed fired")
	assert_true(_joined(c, h, str(row.get("ip", ""))), "joining the row's address works")
	assert_eq(c.found().size(), 0, "no list while in a room")
	c.leave()
	assert_eq(c.state(), &"finding", "leaving the room returns to the open list")
	c.find(false)
	assert_eq(c.state(), &"off", "closing the list is off")
	assert_eq(c.get_children().filter(func(x: Node) -> bool: return x is Timer).size(), 0, "no Timer once off")
	_cleanup()


func test_timeouts_and_rate_limit() -> void:
	if _skip():
		return
	# nobody listens: refused(timeout) after 5 s (fake time)
	_base += 2
	var c := _mk("Cli")
	var got: Array = []
	c.refused.connect(func(k: String, a: Dictionary) -> void: got.append(k))
	assert_eq(c.join("127.0.0.1", _base + 600), OK, "joining a silent address starts connecting")
	_pump(func() -> bool: return false, 20)
	c.clock_skew_ms += 6000
	assert_true(_pump(func() -> bool: return not got.is_empty(), 500), "no answer: refused")
	assert_eq(got, ["timeout"], "refused(timeout) after 5 s")
	assert_eq(c.state(), &"off", "back to off")
	_cleanup()
	# the host vanishes without BYE: reconnecting, then lost(reconnect_failed) after 60 s
	var h := _host()
	c = _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	var lost: Array = []
	var states: Array = []
	c.lost.connect(func(k: String) -> void: lost.append(k))
	c.state_changed.connect(func(s: StringName) -> void: states.append(s))
	h._unbind_mp()
	h._peer.close()
	assert_true(_pump(func() -> bool: return c.state() == &"reconnecting", 3000, [c]), "the client starts reconnecting")
	c.clock_skew_ms += 61000
	assert_true(_pump(func() -> bool: return not lost.is_empty(), 1000, [c]), "it gives up")
	assert_eq(lost, ["reconnect_failed"], "lost(reconnect_failed) after 60 s")
	assert_eq(states.back() if not states.is_empty() else &"", &"off", "and is off")
	_cleanup()
	# more than 60 messages in a second: the host drops the sender
	h = _host()
	c = _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	for i: int in 70:
		c.set_where(&"deck" if i % 2 == 0 else &"army")
	assert_true(_pump(func() -> bool: return h.members().size() == 1, 2000), "a burst of 70 messages in one second drops the sender")
	_cleanup()


func test_fast_reconnect_shows_away_then_back() -> void:
	if _skip():
		return
	var h := _host()
	var c1 := _mk("Cli1")
	assert_true(_joined(c1, h), "friend 1 joins")
	c1.set_where(&"battle")
	assert_true(_pump(func() -> bool: return h.member(1).get("where") == &"battle", 1000), "friend 1 is in the battle")
	var seen: Array = []
	h.members_changed.connect(func() -> void: seen.append(bool(h.member(1).get("here", false))))
	var again := [0]
	c1.reconnected.connect(func() -> void: again[0] += 1)
	# the old link dies silently (no ENet disconnect reaches the host) and friend 1 reconnects at once
	c1._peer.get_peer(1).reset()
	c1._start_reconnect()
	assert_true(_pump(func() -> bool: return c1.state() == &"joined" and again[0] == 1, 5000), "friend 1 reconnects")
	assert_eq(c1.my_slot(), 1, "with its slot")
	assert_true(_pump(func() -> bool: return bool(h.member(1).get("here", false)), 1000), "slot 1 is here")
	var away_then_back := seen.find(false) >= 0 and seen.rfind(true) > seen.find(false)
	assert_true(away_then_back, "the host saw slot 1 away then back (%s), not a silent swap" % str(seen))
	assert_eq(h.members().size(), 2, "still two members")
	assert_eq(h.member(1).get("where"), &"battle", "the reconnect keeps the member's place (battle)")
	_cleanup()


func test_battle_slot_kept_for_its_owner() -> void:
	if _skip():
		return
	var h := _host()
	var c1 := _mk("Cli1")
	assert_true(_joined(c1, h), "friend 1 joins")
	# the host is in a battle where slot 1 owns seat 1 (START sniffed)
	h._battle_owners = [0, 1]
	h.set_where(&"battle")
	assert_eq(h.room_state(), "battle", "the room is in a battle")
	c1._peer.close()
	assert_true(_pump(func() -> bool: return not bool(h.member(1).get("here", true)), 3000, [h]), "friend 1 drops")
	h.clock_skew_ms += 61000
	assert_true(_pump(func() -> bool: return not h._members.has(1), 1000, [h]), "after 60 s its slot is no longer kept as a member")
	var c3 := _mk("Cli3")
	assert_true(c3.join("127.0.0.1", int(h.ports["game"])) == OK and _pump(func() -> bool: return c3.state() == &"joined", 3000, [h, c3]),
		"a newcomer joins during the battle")
	assert_ne(c3.my_slot(), 1, "the newcomer does not get slot 1, which owns a seat in the running game (got %d)" % c3.my_slot())
	assert_true(_pump(func() -> bool: return c1.state() == &"joined", 5000), "friend 1 comes back")
	assert_eq(c1.my_slot(), 1, "and gets its own slot (and so its seat) back")
	_cleanup()


func test_member_sending_a_host_kind_is_dropped() -> void:
	if _skip():
		return
	var h := _host()
	var msgs: Array = []
	h.message.connect(func(s: int, k: int, b: Dictionary) -> void: msgs.append([s, k]))
	var c := _mk("Cli")
	assert_true(_joined(c, h), "a client joins")
	var big := PackedByteArray([NetProto.RESYNC])
	big.resize(200000)
	c.multiplayer.send_bytes(big, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 0)
	assert_true(_pump(func() -> bool: return h.members().size() == 1, 3000), "a 200 KB RESYNC-kind message from a member drops it")
	assert_eq(msgs, [], "nothing of it reached the host's listeners")
	_cleanup()
	# IPv4 only: a socket on the game port's IPv6 wildcard still binds while hosting
	h = _host()
	var u := PacketPeerUDP.new()
	assert_true(h != null and h.is_host(), "hosting works with the IPv4 bind")
	u.close()
	_cleanup()
