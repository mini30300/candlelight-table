extends SceneTree
## The second process of tests/flow/test_lan_flow.gd (NET_SPEC §12.3): a friend on the same machine. Not a test by
## itself (run.sh only globs tests/flow/test_*.gd). Started by the flow test with
##   <godot> --headless --path <project> --audio-driver Dummy -s tests/net/lan_peer.gd -- --net-port=<P> --status=<file> --name=<nm>
## It uses the live Net autoload (which reads --net-port itself), a test cfg file next to the status file (never this
## machine's user://net.cfg), probe 127.0.0.1, and appends one status line per event to <file>:
##   finding · found <ip> <port> ok=<bool> · joined slot=<n> · walked <x_cm> <z_cm> · see_host <x_cm> <z_cm> ·
##   setup <n seats> · claimed <k> · seat <k> owner <slot> · refused <key> · lost <key>
## The flow test kills this process by its PID; it also quits by itself after 120 s.

const LIFE_MS := 120000
const WALK_MS := 1000
const STEP_MS := 100

var _status := ""
var _name := "peer"
var _net: Node
var _t0 := 0
var _started := false
var _joined_at := -1
var _walk_done := false
var _claimed := false
var _seen_host := false
var _last_seat_owner := -99
var _last_step := -1


func _initialize() -> void:
	Engine.max_fps = 60
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--status="):
			_status = a.trim_prefix("--status=")
		elif a.begins_with("--name="):
			_name = a.trim_prefix("--name=")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_start()
	if Time.get_ticks_msec() - _t0 > LIFE_MS:
		_say("timeout")
		return true
	_step()
	return false


func _start() -> void:
	_t0 = Time.get_ticks_msec()
	_net = root.get_node_or_null(^"/root/Net")
	if _net == null:
		_say("no_net")
		quit(1)
		return
	_net.set("cfg_file", _status.get_base_dir().path_join("net_peer.cfg"))
	_net.set("probe", PackedStringArray(["127.0.0.1"]))
	_net.call("set_my_name", _name)
	_net.connect("refused", func(k: String, _a: Dictionary) -> void: _say("refused " + k))
	_net.connect("lost", func(k: String) -> void: _say("lost " + k))
	_net.connect("pose", _on_pose)
	_net.connect("message", _on_message)
	_net.call("find", true)
	_say("finding")


func _step() -> void:
	if _net == null:
		return
	var st: StringName = _net.call("state")
	if st == &"finding":
		var rows: Array = _net.call("found")
		for r: Dictionary in rows:
			_say("found %s %d ok=%s" % [r["ip"], int(r["port"]), str(r["ok"])])
			if bool(r["ok"]):
				_net.call("join", str(r["ip"]), int(r["port"]))
				return
	elif st == &"joined":
		if _joined_at < 0:
			_joined_at = Time.get_ticks_msec()
			_net.call("set_where", &"deck")
			_say("joined slot=%d" % int(_net.call("my_slot")))
		_walk()


## walk 2 m forward (−z) from the slot's spawn spot in one second: POSE every 100 ms, then POSE_STOP
func _walk() -> void:
	if _walk_done:
		return
	var t := Time.get_ticks_msec() - _joined_at
	var x := 90 * (int(_net.call("my_slot")) - 2) - 45
	var z0 := 500
	var f := clampf(float(t) / WALK_MS, 0.0, 1.0)
	var z := z0 - int(200 * f)
	if f >= 1.0:
		_net.call("send_pose", {"x": x, "z": z, "yaw": 0, "sp": 0, "run": false, "t": Time.get_ticks_msec()}, true)
		_walk_done = true
		_say("walked %d %d" % [x, z])
	elif t / STEP_MS != _last_step:
		_last_step = t / STEP_MS
		_net.call("send_pose", {"x": x, "z": z, "yaw": 0, "sp": 200, "run": false, "t": Time.get_ticks_msec()}, false)


func _on_pose(slot: int, p: Dictionary) -> void:
	if slot == 0 and not _seen_host and int(p.get("sp", 1)) == 0:
		_seen_host = true
		_say("see_host %d %d" % [int(p["x"]), int(p["z"])])


func _on_message(_from: int, kind: int, body: Dictionary) -> void:
	if kind != NetProto.SETUP or not bool(body.get("open", false)):
		return
	var seats: Array = body["seats"]
	_say("setup %d" % seats.size())
	var me := int(_net.call("my_slot"))
	for k: int in seats.size():
		var owner := int((seats[k] as Dictionary)["owner"])
		if owner == me and owner != _last_seat_owner:
			_last_seat_owner = owner
			_say("seat %d owner %d" % [k, owner])
	if not _claimed and seats.size() > 1 and int((seats[1] as Dictionary)["owner"]) == -1:
		_claimed = true
		_net.call("claim", 1)
		_say("claimed 1")


func _say(line: String) -> void:
	print("peer: " + line)
	if _status == "":
		return
	var f := FileAccess.open(_status, FileAccess.READ_WRITE if FileAccess.file_exists(_status) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()
