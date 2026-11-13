extends SceneTree
## Two app processes on one machine find each other and share a room (NET_SPEC §12.3, the NET-CORE part): this process
## hosts through the live Net autoload, a second Godot process (tests/net/lan_peer.gd) finds the room by discovery
## (probe 127.0.0.1), joins as slot 1, walks 2 m and stops; the host's pose stream converges on the peer's reported
## spot, the peer sees the host's pose, the host opens a setup and the peer claims seat 1, then the host kills the peer
## (only that PID) and marks the slot away, closes the room, and binds the game port again. Everything runs on frames:
## the SceneTree polls ENet and Net's Timer does discovery and heartbeats (no manual poll). Test ports from §1.5, cfg
## files under TEST_OUT, this machine's user://net.cfg untouched.
## The lobby screen, deck and battle steps of §12.3 (1, 3-6 with the real UI) need the DECK and BATTLE tracks and are
## added at integration on top of this transport flow. Run:
##   TEST_OUT=<dir> timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_lan_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const PEER_SCRIPT := "tests/net/lan_peer.gd"
const STEP_CAP_MS := 30000

var _net: Node
var _out := ""
var _status := ""
var _pid := -1
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _t0 := 0
var _poses: Array = []
var _claims: Array = []
var _cfg_before := {}


func _initialize() -> void:
	Engine.max_fps = 60
	_out = OS.get_environment("TEST_OUT")
	if _out == "":
		_out = ProjectSettings.globalize_path("res://tests/out")
	DirAccess.make_dir_recursive_absolute(_out)
	_status = _out.path_join("lan_peer_status.txt")
	DirAccess.remove_absolute(_status)
	DirAccess.remove_absolute(_out.path_join("net_peer.cfg"))
	DirAccess.remove_absolute(_out.path_join("net_host.cfg"))
	_cfg_before = _machine_cfg()


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	await process_frame
	_net = root.get_node_or_null(^"/root/Net")
	_check(_net != null, "the Net autoload is live")
	if _net == null:
		_finish()
		return
	_net.set("cfg_file", _out.path_join("net_host.cfg"))
	_net.call("set_my_name", "เจ้าห้อง")
	_net.connect("pose", func(s: int, p: Dictionary) -> void: _poses.append([s, p]))
	_net.connect("message", func(s: int, k: int, b: Dictionary) -> void:
		if k == NetProto.CLAIM:
			_claims.append([s, int(b["k"])]))
	# 1. host on a free test pair
	var base := 30000 + (OS.get_process_id() % 4000) * 2
	var hosted := false
	for i: int in 20:
		_net.set("ports", {"game": base, "disc": base + 1})
		if int(_net.call("host")) == OK:
			hosted = true
			break
		base += 2
	_check(hosted, "hosting on test port %d" % base)
	if not hosted:
		_finish()
		return
	_check(_net.call("state") == &"hosting", "state hosting")
	_check(bool(_net.call("discovery_on")), "discovery is on")
	print("      host IPs: %s" % str(_net.call("local_ips")))
	# 2. the peer finds the room and joins as slot 1
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--audio-driver",
		"Dummy", "-s", PEER_SCRIPT, "--", "--net-port=%d" % base, "--status=" + _status, "--name=เพื่อน"])
	_pid = OS.create_process(OS.get_executable_path(), args)
	_check(_pid > 0, "the peer process started (pid %d)" % _pid)
	if _pid <= 0:
		_finish()
		return
	var found := await _wait_line("found ")
	_check(found.contains("ok=true"), "the peer found the room by discovery (%s)" % found)
	var joined := await _wait_line("joined ")
	_check(joined == "joined slot=1", "the peer joined as slot 1 (%s)" % joined)
	var ok := await _until(func() -> bool:
		var m: Array = _net.call("members")
		return m.size() == 2 and str((m[1] as Dictionary)["nm"]) == "เพื่อน")
	_check(ok, "the host's member list shows เพื่อน")
	ok = await _until(func() -> bool: return (_net.call("member", 1) as Dictionary).get("where") == &"deck")
	_check(ok, "the peer reported it is on the deck")
	# 3. poses: the peer walks 2 m and stops; the host converges on the reported spot
	var walked := await _wait_line("walked ")
	var parts := walked.split(" ")
	ok = parts.size() == 3
	_check(ok, "the peer reported its final spot (%s)" % walked)
	if ok:
		var want := Vector2(int(parts[1]), int(parts[2]))
		ok = await _until(func() -> bool:
			for i: int in range(_poses.size() - 1, -1, -1):
				var e: Array = _poses[i]
				if int(e[0]) == 1:
					var p: Dictionary = e[1]
					return Vector2(int(p["x"]), int(p["z"])).distance_to(want) <= 30.0 and int(p["sp"]) == 0
			return false)
		_check(ok, "the host's last pose of slot 1 is within 0.3 m of the peer's spot and stopped")
		var moving := _poses.filter(func(e: Array) -> bool: return int(e[0]) == 1 and int((e[1] as Dictionary)["sp"]) > 0)
		_check(moving.size() >= 3, "moving poses arrived while it walked (%d)" % moving.size())
	_net.call("send_pose", {"x": 0, "z": 300, "yaw": 0, "sp": 0, "run": false, "t": Time.get_ticks_msec()}, true)
	var seen := await _wait_line("see_host ")
	_check(seen == "see_host 0 300", "the peer sees the host's pose (%s)" % seen)
	# 4. setup: the peer claims seat 1
	var seats := [{"team": 0, "owner": 0, "fac": ""}, {"team": 0, "owner": -1, "fac": ""},
		{"team": 1, "owner": -1, "fac": ""}, {"team": 1, "owner": -1, "fac": ""}]
	_check(bool(_net.call("send", NetProto.SETUP, {"open": true, "seats": seats})), "the host opens a setup")
	_check(_net.call("room_state") == "setup", "the room is in setup")
	ok = await _until(func() -> bool: return _claims.has([1, 1]))
	_check(ok, "the peer claimed seat 1 (CLAIM from slot 1)")
	seats[1]["owner"] = 1
	_net.call("send", NetProto.SETUP, {"open": true, "seats": seats})
	var seat := await _wait_line("seat ")
	_check(seat == "seat 1 owner 1", "the peer sees itself on seat 1 (%s)" % seat)
	_net.call("send", NetProto.SETUP, {"open": false, "seats": []})
	# 6. kill the peer: the slot goes away (kept for a reconnect)
	var t_kill := Time.get_ticks_msec()
	OS.kill(_pid)
	_pid = -1
	ok = await _until(func() -> bool: return not bool((_net.call("member", 1) as Dictionary).get("here", true)), 12000)
	_check(ok, "the host marks the killed peer away within 12 s (%d ms)" % (Time.get_ticks_msec() - t_kill))
	_check((_net.call("members") as Array).size() == 2, "its slot is kept for a reconnect")
	# 7. close the room: sockets closed, cfg files untouched
	_net.call("leave")
	_check(_net.call("state") == &"off", "the room is closed")
	_check(_net.get_children().filter(func(c: Node) -> bool: return c is Timer).is_empty(), "no Timer left under Net")
	var again := ENetMultiplayerPeer.new()
	_check(again.create_server(base, 2) == OK, "binding the test game port again succeeds")
	again.close()
	var u := PacketPeerUDP.new()
	_check(u.bind(base + 1, "*") == OK, "binding the test discovery port again succeeds")
	u.close()
	_check(_machine_cfg() == _cfg_before, "this machine's net.cfg and settings.cfg are untouched")
	_finish()


## the first status line starting with prefix (waits up to STEP_CAP_MS; "" on timeout)
func _wait_line(prefix: String) -> String:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < STEP_CAP_MS:
		if FileAccess.file_exists(_status):
			for line: String in FileAccess.get_file_as_string(_status).split("\n"):
				if line.begins_with(prefix):
					return line.strip_edges()
		await process_frame
	print("      peer status so far:\n" + (FileAccess.get_file_as_string(_status) if FileAccess.file_exists(_status) else "(none)"))
	return ""


func _until(cond: Callable, cap_ms := STEP_CAP_MS) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < cap_ms:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _machine_cfg() -> Dictionary:
	var out := {}
	for f: String in ["user://net.cfg", "user://settings.cfg"]:
		out[f] = [FileAccess.file_exists(f), FileAccess.get_modified_time(f) if FileAccess.file_exists(f) else 0]
	return out


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)   # only the PID this test started
		_pid = -1
	if _net != null and _net.call("state") != &"off":
		_net.call("leave")
	print("      %.1f s" % ((Time.get_ticks_msec() - _t0) / 1000.0))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 and _passed > 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 and _passed > 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg)
