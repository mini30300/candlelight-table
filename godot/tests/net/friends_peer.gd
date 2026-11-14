extends SceneTree
## The friend's device in tests/flow/test_friends_flow.gd (NET_SPEC §12.3 with the real UI): a second app process on the
## same machine running main.tscn. Not a test by itself (run.sh only globs tests/flow/test_*.gd). Started as
##   <godot> [--headless] --path <project> --audio-driver Dummy -s tests/net/friends_peer.gd -- --net-port=<P>
##     --status=<file> --cmd=<file> --name=<nm> [--fake-app=<APP_VER>] [--rejoin] [--gfx=min] [--media=<dir>]
## Like a player: main menu → ออนไลน์ → the airlock screen; types its name, waits for the host's row (discovery, probe
## 127.0.0.1) and taps เข้าร่วม; back to the deck. When the host opens the setup it walks to the war table and taps
## นั่งที่นี่ on seat 1; on every battle it turns on ให้บอทเล่นแทน at instant speed and reports the end. --fake-app sends
## another APP_VER in its hello (Net.hello_extra): the join is refused and it reports the reason in Thai and English.
## --rejoin keeps the net cfg of the friend that was killed (same nid, so the host gives it the same slot) and plays the
## running game it is put back into.
## Status lines appended to <file> (the flow test reads them):
##   lobby · found <ok> · joined slot=<n> · room members=<n> · deck <x_cm> <z_cm> · walked <x_cm> <z_cm> ·
##   look host=<x_cm>,<z_cm> steps=<n> friends=<n> you3d=<bool> tags=<a|b> · toast <text> · claimed <k> · seat <k> mine ·
##   battle seat=<k> gen=<g> · over gen=<g> seq=<n> dg=<hex> checks=<n> desync=<n> sync=<s> log=<sha> again=<bool> wait=<bool> ·
##   desync <seq> · refused <key> · reason_th <text> · reason_en <text> · shot <name> · lost <key>
## Commands read from <file> (one per line, appended by the flow test): walk <keys> <ms> (keys like W or W+D) · look ·
##   shot <name> · lang <th|en> · quit. A test settings file and net cfg file (never this machine's), touch off, eggs.
## The flow test kills this process by its PID; it also quits by itself after LIFE_MS.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_friends_peer.cfg"
const LIFE_MS := 280000
const STEP_CAP_MS := 30000
const KEYS := {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "SHIFT": KEY_SHIFT}

var _status := ""
var _cmd := ""
var _name := "peer"
var _fake_app := ""
var _media := ""
var _gfx := "min"
var _rejoin := false          # --rejoin: keep the net cfg (same nid → same slot) and go straight back into the game
var _main: Node
var _net: Node
var _t0 := 0
var _started := false
var _cmd_done := 0
var _cmd_at := 0
var _busy := false            # a command coroutine is running
var _joined := false
var _claiming := false
var _claimed := false
var _gen := -1                # last battle gen seen
var _over_gen := -1           # last gen reported over
var _desync_seen := false
var _host_last := Vector3.INF
var _host_steps := 0          # frames where the host's egg moved a small step (since the last look)


func _initialize() -> void:
	# round B: แอปสาธารณะเล่นกับเพื่อนได้ (ไม่มีสวิตช์ online ไม่มีห้องเสริม) — เทสไม่เปิดสวิตช์
	Engine.max_fps = 60
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--status="):
			_status = a.trim_prefix("--status=")
		elif a.begins_with("--cmd="):
			_cmd = a.trim_prefix("--cmd=")
		elif a.begins_with("--name="):
			_name = a.trim_prefix("--name=")
		elif a.begins_with("--fake-app="):
			_fake_app = a.trim_prefix("--fake-app=")
		elif a.begins_with("--media="):
			_media = a.trim_prefix("--media=")
		elif a.begins_with("--gfx="):
			_gfx = a.trim_prefix("--gfx=")
		elif a == "--rejoin":
			_rejoin = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := root.get_node(^"App")
	app.set("settings_file", SETTINGS_FILE)   # never this machine's settings.cfg
	app.call("set_gfx", _gfx)
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	_net = root.get_node_or_null(^"Net")
	if _net != null:
		var cfg := _status.get_base_dir().path_join("net_%s.cfg" % ("old" if _fake_app != "" else "friend"))
		if not _rejoin:
			DirAccess.remove_absolute(cfg)
		_net.set("cfg_file", cfg)
		_net.set("probe", PackedStringArray(["127.0.0.1"]))
		if _fake_app != "":
			_net.set("hello_extra", {"app": _fake_app})
	_main = (load(SCENE) as PackedScene).instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_t0 = Time.get_ticks_msec()
		if _net == null:
			_say("no_net")
			quit(1)
			return true
		_net.connect("refused", func(k: String, _a: Dictionary) -> void: _say("refused " + k))
		_net.connect("lost", func(k: String) -> void: _say("lost " + k))
		_run()
	if Time.get_ticks_msec() - _t0 > LIFE_MS:
		_say("timeout")
		quit(2)
		return true
	if _joined:
		_watch()
	if not _busy and Time.get_ticks_msec() - _cmd_at >= 100:
		_cmd_at = Time.get_ticks_msec()
		_poll_cmd()
	return false


# ------------------------------------------------------------------------------------------------ the player's steps

func _run() -> void:
	_busy = true
	await _frames(3)
	var app := _app()
	var menu: Node = app.call("current")
	var online := menu.get_node_or_null("%OnlineButton") as Button if menu != null else null
	if online == null:
		_say("no_menu")
		quit(1)
		return
	online.pressed.emit()
	await _frames(3)
	var lobby: Node = app.call("current")
	if lobby == null or not lobby.has_method("join_row"):
		_say("no_lobby")
		quit(1)
		return
	_say("lobby depth=%d" % int(app.call("depth")))
	var name_edit := lobby.get_node("%NameEdit") as LineEdit
	name_edit.text = _name
	name_edit.text_submitted.emit(_name)
	# the host's row (discovery), then เข้าร่วม
	var row: Node = null
	var t := Time.get_ticks_msec()
	while row == null and Time.get_ticks_msec() - t < STEP_CAP_MS:
		for c: Node in lobby.get_node("%FoundList").get_children():
			if str(c.name).begins_with("Room_") and c.get_node_or_null("JoinButton") != null:
				row = c
		await process_frame
	if row == null:
		_say("found none")
		quit(1)
		return
	var rows: Array = _net.call("found")
	_say("found ok=%s rows=%d name=%s" % [str(bool((rows[0] as Dictionary).get("ok", false))) if not rows.is_empty() else "?",
		rows.size(), _room_name(row)])
	if _media != "" and _fake_app == "":
		await _shot("lobby_find_th")
	(row.get_node("JoinButton") as Button).pressed.emit()
	if _fake_app != "":
		await _refused(lobby)
		return
	t = Time.get_ticks_msec()
	while _net.call("state") != &"joined" and Time.get_ticks_msec() - t < STEP_CAP_MS:
		await process_frame
	if _net.call("state") != &"joined":
		_say("join failed state=%s reason=%s" % [str(_net.call("state")), str(lobby.call("reason_text"))])
		quit(1)
		return
	_say("joined slot=%d" % int(_net.call("my_slot")))
	if _rejoin:
		# the host puts a returning player straight back into the running game (RESYNC): no deck steps, no claim
		_claimed = true
		_joined = true
		_busy = false
		return
	t = Time.get_ticks_msec()
	while (lobby.get_node("%MemberList").get_child_count() < 2 or str(lobby.call("view")) != "room") and Time.get_ticks_msec() - t < 5000:
		await process_frame
	_say("room members=%d view=%s" % [lobby.get_node("%MemberList").get_child_count(), str(lobby.call("view"))])
	# กลับดาดฟ้า (still in the room)
	(lobby.get_node("%BackButton") as Button).pressed.emit()
	await _frames(3)
	var hall := _hall()
	if hall == null or app.call("current") != hall:
		_say("no_deck")
		quit(1)
		return
	var p: Vector3 = _avatar().global_position
	_say("deck %d %d" % [roundi(p.x * 100.0), roundi(p.z * 100.0)])
	_joined = true
	_busy = false


## wrong version: the refusal on the airlock screen in Thai, then in English, then quit
func _refused(lobby: Node) -> void:
	var t := Time.get_ticks_msec()
	while str(lobby.call("reason_text")) == "" and Time.get_ticks_msec() - t < STEP_CAP_MS:
		await process_frame
	await _frames(2)
	_say("reason_th " + str(lobby.call("reason_text")))
	if _media != "":
		await _shot("lobby_refused_th")
	_say("view %s state=%s members=%d" % [str(lobby.call("view")), str(_net.call("state")), (_net.call("members") as Array).size()])
	_app().call("set_lang", "en")
	lobby.call("refresh")
	await _frames(2)
	_say("reason_en " + str(lobby.call("reason_text")))
	if _media != "":
		await _shot("lobby_refused_en")
	_app().call("set_lang", "th")
	_finish(0)


## every frame once in the room: claim a seat when the host opens the setup, play each battle, report its end
func _watch() -> void:
	var hall := _hall()
	if hall != null and hall.get("world") != null:
		var fr: Node = hall.get("world").get("friends")
		if fr != null and bool(fr.call("has_friend", 0)):
			var hp: Vector3 = fr.call("friend_pos", 0)
			var d := hp.distance_to(_host_last) if _host_last != Vector3.INF else 0.0
			if d > 0.0005 and d < 0.5:
				_host_steps += 1
			_host_last = hp
	if not _claiming and not _claimed and not _busy and _net.call("room_state") == "setup" and not (_net.call("setup_seats") as Array).is_empty():
		_claiming = true
		_claim()
	var top: Node = _app().call("current")
	if top == null or not top.has_method("is_waiting_remote"):
		return
	var r: Object = top.get("runner")
	if r == null or not r.has_method("online"):
		return
	var lk: Object = r.get("lockstep")
	var g := int(lk.get("gen")) if lk != null else -1
	if g != _gen:
		_gen = g
		_desync_seen = false
		_say("battle seat=%d gen=%d" % [int(r.get("human")), g])
		var auto := top.get_node_or_null("%AutoButton") as Button
		if auto != null and auto.visible:
			auto.button_pressed = true      # ให้บอทเล่นแทน (sends this seat's acts as requests)
		top.call("set_speed", "instant")
	if r.call("sync_state") != &"ok" and not _desync_seen:
		_desync_seen = true
		_say("desync seq=%d state=%s" % [int((r.get("b") as Object).get("actlog").call("last_seq")), str(r.call("sync_state"))])
	if bool(r.call("is_over")) and _over_gen != g:
		_over_gen = g
		var b: Object = r.get("b")
		var log: Object = b.get("actlog")
		var acts: Array = log.call("acts")
		var again := top.get_node_or_null("%AgainButton") as CanvasItem
		var wait := top.get_node_or_null("%WaitAgain") as CanvasItem
		_say("over gen=%d seq=%d dg=%s checks=%d desync=%d sync=%s log=%s again=%s wait=%s" % [g, int(log.call("last_seq")),
			str(b.call("digest")), int(r.call("checks")), int(lk.get("desync_n")), str(r.call("sync_state")),
			JSON.stringify(acts, "", true).sha256_text().left(16), str(again != null and again.visible),
			str(wait != null and wait.visible)])


## the host opened the setup: the deck note, walk to the war table (round B: no pack room, so the friend picks a seat
## there), นั่งที่นี่ on seat 1, wait until it is mine
func _claim() -> void:
	_busy = true
	var hall := _hall()
	var t := Time.get_ticks_msec()
	var note := ""
	while Time.get_ticks_msec() - t < 3000 and hall != null:
		var sp := hall.get_node_or_null("%SoonPanel") as CanvasItem
		if sp != null and sp.visible:
			note = (hall.get_node("%SoonLabel") as Label).text
			break
		await process_frame
	_say("toast " + note)
	if hall != null and _app().call("current") == hall:
		var f: Vector2 = HallLayout.STATIONS["battle"]["front"]
		(hall.get("world") as Node).call("place_avatar", Vector3(f.x, 0.0, f.y), PI)
		await _frames(4)
		var at := str(hall.call("station"))
		hall.call("use_station")
		await _frames(3)
		_say("table station=%s lobby=%s" % [at, str(_app().call("current") != hall and (_app().call("current") as Node).has_method("claim"))])
	var lobby: Node = _app().call("current")
	if lobby == null or not lobby.has_method("claim"):
		_say("claim no_lobby")
		_busy = false
		return
	var sit: Button = null
	t = Time.get_ticks_msec()
	while sit == null and Time.get_ticks_msec() - t < STEP_CAP_MS:
		var row := lobby.get_node("%SeatList").get_node_or_null("Seat_1")
		if row != null and row.get_node_or_null("SitButton") != null:
			sit = row.get_node("SitButton")
		await process_frame
	if sit == null:
		_say("claim no_seat")
		_busy = false
		return
	if _media != "":
		await _shot("lobby_seats_th")
	sit.pressed.emit()
	_say("claimed 1")
	t = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < STEP_CAP_MS:
		var row := lobby.get_node("%SeatList").get_node_or_null("Seat_1") if is_instance_valid(lobby) else null
		if row != null and row.get_node_or_null("StandButton") != null:
			_say("seat 1 mine")
			break
		await process_frame
	_claimed = true
	_busy = false


# ------------------------------------------------------------------------------------------------ commands

func _poll_cmd() -> void:
	if _cmd == "" or not FileAccess.file_exists(_cmd):
		return
	var lines := FileAccess.get_file_as_string(_cmd).split("\n", false)
	if lines.size() <= _cmd_done:
		return
	var line := lines[_cmd_done].strip_edges()
	_cmd_done += 1
	_do(line)


func _do(line: String) -> void:
	_busy = true
	var w := line.split(" ", false)
	match w[0] if not w.is_empty() else "":
		"walk":
			await _walk(w[1], int(w[2]))
		"look":
			_look()
		"shot":
			await _shot(w[1])
		"lang":
			_app().call("set_lang", w[1])
			var top: Node = _app().call("current")
			if top != null and top.has_method("refresh"):
				top.call("refresh")
			await _frames(2)
			_say("lang " + w[1])
		"quit":
			_finish(0)
	_busy = false


## hold keys for ms (like a keyboard), then wait until the avatar stops and report where it stands
func _walk(keys: String, ms: int) -> void:
	var codes: Array[Key] = []
	for k: String in keys.split("+"):
		if KEYS.has(k):
			codes.append(KEYS[k])
	for c: Key in codes:
		_key(c, true)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame
	for c: Key in codes:
		_key(c, false)
	var av := _avatar()
	t = Time.get_ticks_msec()
	while av != null and float(av.call("speed")) > 0.01 and Time.get_ticks_msec() - t < 3000:
		await process_frame
	await _frames(20)       # the stop pose leaves 0.25 s after the last move
	var p: Vector3 = av.global_position if av != null else Vector3.ZERO
	_say("walked %d %d" % [roundi(p.x * 100.0), roundi(p.z * 100.0)])


func _look() -> void:
	var hall := _hall()
	if hall == null:
		_say("look none")
		return
	var world: Node = hall.get("world")
	var fr: Node = world.get("friends")
	var hp: Vector3 = fr.call("friend_pos", 0) if bool(fr.call("has_friend", 0)) else Vector3.INF
	var names := PackedStringArray()
	var tags: Node = hall.get_node_or_null("%FriendTags")
	if tags != null:
		for d: Dictionary in tags.call("drawn"):
			names.append(str(d.get("text", "")))
	_say("look host=%s steps=%d friends=%d you3d=%s tags=%s" % [
		"none" if hp == Vector3.INF else "%d,%d" % [roundi(hp.x * 100.0), roundi(hp.z * 100.0)], _host_steps,
		int(fr.call("friend_count")), str(bool(world.call("you_tag_visible"))), "|".join(names)])
	_host_steps = 0


func _shot(nm: String) -> void:
	if _media == "" or DisplayServer.get_name() == "headless":
		_say("shot %s skipped" % nm)
		return
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_media.path_join(nm + ".png"))
	_say("shot " + nm)


# ------------------------------------------------------------------------------------------------ helpers

func _app() -> Node:
	return root.get_node(^"App")


func _hall() -> Node:
	var root_node: Node = _app().call("screen_root")
	for c: Node in root_node.get_children():
		if c.has_method("open_online") and c.get("world") != null:
			return c
	return null


func _avatar() -> Node3D:
	var hall := _hall()
	return (hall.get("world").get("avatar") as Node3D) if hall != null else null


func _room_name(row: Node) -> String:
	var l := row.find_child("RoomName", true, false) as Label
	return l.text if l != null else "?"


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _finish(code: int) -> void:
	if _net != null and _net.call("state") != &"off":
		_net.call("leave")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_say("bye")
	quit(code)


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
