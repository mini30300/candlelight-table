extends SceneTree
## Play with friends end to end with the real UI on two app processes (NET_SPEC §12.3, integration): this process is the
## host, tests/net/friends_peer.gd is the friend (a second Godot process running main.tscn). Steps:
##  1. main menu → ออนไลน์ → the deck + the airlock screen (depth 3); name เจ้าห้อง; เปิดห้อง → hosting, discovery on
##  2. กลับดาดฟ้า; the friend starts, finds the room by discovery (probe 127.0.0.1), taps เข้าร่วม → slot 1; the host's
##     deck says "เพื่อน เข้าห้องแล้ว" and draws the friend's egg at its spawn spot
##  3. the friend walks 2 m: the host's egg converges within 0.3 m, its name tag and the host's own tag are drawn by
##     FriendTags, the 3D "you" sign hides; the host walks from the spawn row to the war table: the friend sees it
##     moved and standing within 0.3 m of where it stopped; everyone still → the friends stop processing
##  4. E at the war table → online setup: 3 teams × 1 (host · bot · bot), the host frees seat 1; the friend gets the deck
##     note, walks to the war table (round B: no pack room) and taps นั่งที่นี่ on seat 1 (CLAIM) → the host's row 1 shows เพื่อน
##  5. เริ่มรบ: both screens open (1 human per process + 1 bot), both turn on ให้บอทเล่นแทน at instant speed and play
##     to the end: the friend's final seq, digest and act log equal the host's, checks ≥ seq / 8, no desync anywhere,
##     every action of seat 1 carries pid n1 (seat 0 n0, the bot ""); the host has เล่นอีกครั้ง, the friend waits
##  6. เล่นอีกครั้ง (gen 2): after ≥ 20 acts the host kills the friend's process (only that PID): within 10 s the host
##     shows "บอทเล่นแทน เพื่อน (หลุดจากห้อง)" and plays seat 1 with pid n1 to the end
##  6b. เล่นอีกครั้ง while the friend is away: the host plays seat 1 from the start; the friend reopens its app (same nid),
##     joins and is put straight back into the running game (RESYNC), plays on and ends with the host's digest and act
##     log; then it leaves the room on purpose
##  7. a friend on another app version (hello with APP_VER "ใหม่ 0.4") is refused: its airlock screen gives the reason
##     in Thai and in English; nobody joins
##  8. main menu → ออนไลน์ → ปิดห้อง → offline; the test ports bind again; this machine's cfg files untouched
## Headless by default (CI). With FRIENDS_MEDIA=<dir> under xvfb (not headless) both processes render and the run also
## writes deck_two.png, lobby_room_th/en.png, battle_two.png and friends_deck.mp4 (ffmpeg) into <dir>; the friend's
## apps add lobby_find_th.png, lobby_seats_th.png and lobby_refused_th/en.png. Run:
##   TEST_OUT=<dir> timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_friends_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_friends_flow.cfg"
const PEER := "tests/net/friends_peer.gd"
const STEP_CAP_MS := 30000
const GAME_CAP_MS := 150000
const OLD_APP := "ใหม่ 0.4"
const FRIEND := "เพื่อน"
const HOST_NM := "เจ้าห้อง"

var _out := ""
var _media := ""
var _status := ""
var _status_old := ""
var _status_back := ""
var _cmd_back := ""
var _pid_back := -1
var _cmd := ""
var _pid := -1
var _pid_old := -1
var _net: Node
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _t0 := 0
var _port := 0
var _cfg_before := {}


func _initialize() -> void:
	# round B: แอปสาธารณะเล่นกับเพื่อนได้ (ไม่มีสวิตช์ online ไม่มีห้องเสริม) — เทสไม่เปิดสวิตช์
	Engine.max_fps = 60
	_out = OS.get_environment("TEST_OUT")
	if _out == "":
		_out = ProjectSettings.globalize_path("res://tests/out")
	DirAccess.make_dir_recursive_absolute(_out)
	_media = OS.get_environment("FRIENDS_MEDIA")
	if _media != "" and DisplayServer.get_name() == "headless":
		_media = ""
	if _media != "":
		DirAccess.make_dir_recursive_absolute(_media)
	_status = _out.path_join("friends_peer_status.txt")
	_status_old = _out.path_join("friends_old_status.txt")
	_cmd = _out.path_join("friends_peer_cmd.txt")
	_status_back = _out.path_join("friends_back_status.txt")
	_cmd_back = _out.path_join("friends_back_cmd.txt")
	for f: String in [_status, _status_old, _cmd, _status_back, _cmd_back, _out.path_join("friends_old_cmd.txt"),
			_out.path_join("net_host.cfg")]:
		DirAccess.remove_absolute(f)
	_cfg_before = _machine_cfg()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := root.get_node(^"App")
	app.set("settings_file", SETTINGS_FILE)   # never this machine's settings.cfg
	app.call("set_gfx", "mid" if _media != "" else "min")
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	_net = root.get_node_or_null(^"Net")
	if _net != null:
		_net.set("cfg_file", _out.path_join("net_host.cfg"))
	_main = (load(SCENE) as PackedScene).instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	await _frames(3)
	_check(_net != null, "the Net autoload is live")
	if _net == null:
		_finish()
		return
	var app := _app()
	# 1. main menu → ออนไลน์ → the deck and the airlock screen; เปิดห้อง
	var menu: Node = app.call("current")
	var online := menu.get_node_or_null("%OnlineButton") as Button if menu != null else null
	_check(online != null and online.visible, "the main menu has the Online button")
	if online == null:
		_finish()
		return
	online.pressed.emit()
	await _frames(3)
	var lobby: Node = app.call("current")
	_check(lobby != null and lobby.has_method("host_room") and int(app.call("depth")) == 3,
		"ออนไลน์ opens the deck and the airlock screen on top (depth %d)" % int(app.call("depth")))
	if lobby == null or not lobby.has_method("host_room"):
		_finish()
		return
	var name_edit := lobby.get_node("%NameEdit") as LineEdit
	name_edit.text = HOST_NM
	name_edit.text_submitted.emit(HOST_NM)
	var base := 30000 + (OS.get_process_id() % 4000) * 2
	for i: int in 20:
		_net.set("ports", {"game": base, "disc": base + 1})
		(lobby.get_node("%HostButton") as Button).pressed.emit()
		await _frames(1)
		if _net.call("state") == &"hosting":
			break
		base += 2
	_port = base
	_check(_net.call("state") == &"hosting", "เปิดห้อง → hosting on test port %d" % base)
	if _net.call("state") != &"hosting":
		_finish()
		return
	await _frames(2)
	_check(str(lobby.call("view")) == "room" and (lobby.get_node("%HostIps") as CanvasItem).visible,
		"the room card shows this device's IPs (%s)" % (lobby.get_node("%HostIps") as Label).text)
	_check(not (lobby.get_node("%DiscOff") as CanvasItem).visible and bool(_net.call("discovery_on")), "discovery is on")
	_check(str(_net.call("my_name")) == HOST_NM, "the host's name is %s" % HOST_NM)
	(lobby.get_node("%BackButton") as Button).pressed.emit()
	await _frames(3)
	var hall: Node = app.call("current")
	_check(hall != null and hall.has_method("open_online") and int(app.call("depth")) == 2, "กลับดาดฟ้า returns to the deck, still hosting")
	if hall == null or not hall.has_method("open_online"):
		_finish()
		return
	var world: Node = hall.get("world")
	var friends: Node = world.get("friends")
	var tags: Node = hall.get_node("%FriendTags")
	_check(str(tags.call("status_text")).contains(HOST_NM), "the deck's status line names the room (%s)" % str(tags.call("status_text")))

	# 2. the friend finds the room and joins as slot 1
	var notes := PackedStringArray()
	var note_watch := func() -> void:
		var sp := hall.get_node("%SoonPanel") as CanvasItem
		var txt := (hall.get_node("%SoonLabel") as Label).text
		if sp.visible and (notes.is_empty() or notes[notes.size() - 1] != txt):
			notes.append(txt)
	process_frame.connect(note_watch)
	_pid = _spawn_peer(_status, FRIEND, "", _cmd)
	_check(_pid > 0, "the friend's app started (pid %d)" % _pid)
	if _pid <= 0:
		_finish()
		return
	var line := await _wait_line(_status, "found ")
	_check(line.contains("ok=true") and line.contains(HOST_NM), "the friend's airlock screen lists the host's room (%s)" % line)
	line = await _wait_line(_status, "joined ")
	_check(line == "joined slot=1", "the friend joined as slot 1 (%s)" % line)
	var ok := await _until(func() -> bool: return notes.has(FRIEND + " เข้าห้องแล้ว"), 5000)
	process_frame.disconnect(note_watch)
	_check(ok, "the host's deck says \"%s เข้าห้องแล้ว\" (%s)" % [FRIEND, "|".join(notes)])
	ok = await _until(func() -> bool:
		var m: Array = _net.call("members")
		return m.size() == 2 and str((m[1] as Dictionary)["nm"]) == FRIEND)
	_check(ok, "the host's member list shows %s" % FRIEND)
	line = await _wait_line(_status, "room ")
	_check(line.begins_with("room members=2"), "the friend's room card lists both players (%s)" % line)
	line = await _wait_line(_status, "deck ")
	var spawn1: Vector3 = HallFriends.spawn_for(1)
	_check(_xz_cm(line, 1).distance_to(Vector2(spawn1.x, spawn1.z) * 100.0) <= 5.0,
		"the friend stands at its slot's spawn spot on the deck (%s)" % line)
	ok = await _until(func() -> bool:
		return bool(friends.call("has_friend", 1)) and _v2(friends.call("friend_pos", 1)).distance_to(Vector2(spawn1.x, spawn1.z)) <= 0.3)
	_check(ok, "the host draws the friend's egg at its spawn spot (%s)" % str(friends.call("friend_pos", 1)))
	if _media != "":
		await _media_lobby(hall)

	# 3. the friend walks 2 m forward and stops; the host's egg follows
	var max_proc := [false]
	var watch := func() -> void:
		if bool((friends.call("counts") as Dictionary).get("processing", false)):
			max_proc[0] = true
	process_frame.connect(watch)
	_send("walk W 700")
	line = await _wait_line(_status, "walked ")
	var spot := _xz_cm(line, 1) / 100.0
	_check(spot.distance_to(Vector2(spawn1.x, spawn1.z)) >= 1.5, "the friend walked about 2 m (%s)" % line)
	ok = await _until(func() -> bool: return _v2(friends.call("friend_pos", 1)).distance_to(spot) <= 0.3, 5000)
	_check(ok, "the host's egg of the friend converges within 0.3 m of where it stopped (%.2f m)" % _v2(friends.call("friend_pos", 1)).distance_to(spot))
	process_frame.disconnect(watch)
	_check(bool(max_proc[0]), "the friend's egg moved on the host's deck while it walked (interpolated)")
	# the host steps back to its spawn row facing the war table (the friend ahead on the right)
	world.call("place_avatar", HallFriends.spawn_for(0), PI)
	(world.get("camera_rig") as Object).call("set_view", HallLayout.SPAWN_YAW, -0.45, 6.5)
	await _frames(5)
	var drawn := _tag_texts(tags)
	_check(drawn.has(FRIEND) and drawn.has("คุณ"), "FriendTags draws the friend's name and the host's own tag (%s)" % "|".join(drawn))
	_check(not bool(world.call("you_tag_visible")), "the 3D you sign is hidden while a friend is on the deck")
	if _media != "":
		await _media_deck(hall)
	# the host walks to the war table; the friend sees it walk (interpolated steps) and stop
	var spawn0: Vector3 = HallFriends.spawn_for(0)
	var looks := 0
	ok = false
	for i: int in 20:
		_send("look")
		line = await _wait_line(_status, "look ", looks)
		looks += 1
		if _look_host(line).distance_to(_v2((world.get("avatar") as Node3D).global_position)) <= 0.05:
			ok = true
			break
		await _frames(6)
	_check(ok, "the friend sees the host at its spawn spot before the walk (%s)" % line)
	var avatar := world.get("avatar") as Node3D
	_key(KEY_W, true)
	var t := Time.get_ticks_msec()
	while str(hall.call("station")) != "battle" and Time.get_ticks_msec() - t < 15000:
		await process_frame
	_key(KEY_W, false)
	_check(str(hall.call("station")) == "battle", "the host walked to the war table in %d ms" % (Time.get_ticks_msec() - t))
	ok = await _until(func() -> bool: return float(avatar.call("speed")) <= 0.01, 3000)
	await _frames(30)
	var hp := _v2(avatar.global_position)
	_send("look")
	line = await _wait_line(_status, "look ", looks)
	looks += 1
	var seen := _look_host(line)
	_check(seen.distance_to(hp) <= 0.3, "the friend sees the host's egg where it stopped (%.2f m off; %s)" % [seen.distance_to(hp), line])
	_check(seen.distance_to(Vector2(spawn0.x, spawn0.z)) >= 2.0 and _field(line, "steps").to_int() >= 10,
		"the friend saw the host walk %.1f m in %s small steps (interpolated, no jump)" % [seen.distance_to(Vector2(spawn0.x, spawn0.z)), _field(line, "steps")])
	_check(line.substr(maxi(0, line.find("tags="))).contains(HOST_NM) and _field(line, "you3d") == "false",
		"the friend's FriendTags draws %s and hides its 3D you sign" % HOST_NM)
	ok = await _until(func() -> bool: return not bool((friends.call("counts") as Dictionary).get("processing", true)), 3000)
	await _frames(10)
	_check(ok and not bool((friends.call("counts") as Dictionary).get("processing", true)), "everyone still: the friends stop processing on the host")

	# 4. E at the war table → the online setup; the friend claims seat 1 from the airlock
	_key(KEY_E, true)
	await _frames(1)
	_key(KEY_E, false)
	await _frames(3)
	var setup: Node = app.call("current")
	_check(setup != null and setup.has_method("set_seat_owner") and bool(setup.get("online")), "E at the war table opens the setup in online mode (%s)" % _name(setup))
	if setup == null or not setup.has_method("set_seat_owner") or not bool(setup.get("online")):
		_finish()
		return
	_check((_net.call("member", 0) as Dictionary).get("where") == &"setup" and _net.call("room_state") == "setup", "the room is in setup")
	setup.call("set_teams", 3)
	setup.call("set_per_team", 1)
	for k: int in 3:
		setup.call("set_seat", k, ["kn", "or", "gr"][k], false)
	setup.call("set_seat_owner", 1, -1)
	_set_choice(setup, "size", "m")
	setup.call("set_goal", "obj")
	setup.call("set_rounds", 3)
	setup.call("set_budget", 300)
	setup.call("set_seed", 4242)
	line = await _wait_line(_status, "toast ")
	_check(line.contains("เลือกที่นั่งได้ที่โต๊ะรบ"), "the friend's deck says the host is setting up, pick a seat at the war table (%s)" % line)
	line = await _wait_line(_status, "table ")
	_check(line == "table station=battle lobby=true", "the friend's war table opens host/join with the seats (%s)" % line)
	line = await _wait_line(_status, "seat 1 ")
	_check(line == "seat 1 mine", "the friend's claim of seat 1 came back as its own (%s)" % line)
	var choice: Dictionary = setup.get("choice")
	_check(int((choice["seats"][1] as Dictionary).get("owner", -9)) == 1, "the host's seat 1 belongs to slot 1 after CLAIM")
	var who1 := setup.find_child("Who1", true, false) as Button
	_check(who1 != null and who1.text == FRIEND, "the host's row 1 shows %s (%s)" % [FRIEND, who1.text if who1 != null else "?"])
	var errs: PackedStringArray = setup.call("errors")
	_check(errs.is_empty(), "the online setup is valid", str(errs))

	# 5. เริ่มรบ: both play with ให้บอทเล่นแทน at instant speed to the end
	_check(bool(setup.call("start")), "เริ่มรบ starts the online game")
	await _frames(3)
	var battle: Node = app.call("current")
	_check(battle != null and battle.has_method("is_waiting_remote") and int(app.call("depth")) == 3, "the host's battle screen took the setup's place (%s)" % _name(battle))
	if battle == null or not battle.has_method("is_waiting_remote"):
		_finish()
		return
	var runner: Object = battle.get("runner")
	_check(runner != null and runner.has_method("online") and bool(runner.call("is_net_host")) and int(runner.get("human")) == 0, "the host plays seat 0 with a host runner")
	line = await _wait_line(_status, "battle ")
	_check(line == "battle seat=1 gen=1", "the friend's battle screen opened on seat 1 (%s)" % line)
	(battle.get_node("%AutoButton") as Button).button_pressed = true
	battle.call("set_speed", "fast" if _media != "" else "instant")
	if _media != "":
		await _media_battle(battle)
		battle.call("set_speed", "instant")
	t = Time.get_ticks_msec()
	ok = await _until(func() -> bool: return bool(battle.call("is_over")), GAME_CAP_MS)
	_check(ok, "game 1 reaches the end on the host in %d ms (%d acts)" % [Time.get_ticks_msec() - t, (runner.call("acts") as Array).size()])
	line = await _wait_line(_status, "over gen=1", 0, 20000)
	var b: Object = runner.get("b")
	var seq := int((b.get("actlog") as Object).call("last_seq"))
	var dg := str(b.call("digest"))
	var acts: Array = runner.call("acts")
	var log_sha := JSON.stringify(acts, "", true).sha256_text().left(16)
	_check(_field(line, "seq").to_int() == seq and _field(line, "dg") == dg, "the friend ends at the host's seq %d and digest %s (%s)" % [seq, dg, line])
	_check(_field(line, "log") == log_sha, "the friend's act log equals the host's (sha %s)" % log_sha)
	_check(_field(line, "checks").to_int() >= seq / 8 and _field(line, "desync") == "0" and _field(line, "sync") == "ok",
		"every digest check on the friend matched (%s checks for %d acts, desync %s)" % [_field(line, "checks"), seq, _field(line, "desync")])
	_check(not _peer_said(_status, "desync"), "no DESYNC on the friend")
	_check(str(runner.call("sync_state")) == "ok" and not _log_has("desync"), "no desync on the host")
	_check_pids(acts, runner.get("st"), "game 1")
	_check(_field(line, "again") == "false" and _field(line, "wait") == "true", "the friend's end panel waits for the host (no เล่นอีกครั้ง)")
	_check((battle.get_node("%AgainButton") as CanvasItem).visible, "the host's end panel has เล่นอีกครั้ง")

	# 6. เล่นอีกครั้ง; the friend's app dies mid-game → the host plays seat 1 to the end
	battle.call("set_speed", "normal")
	(battle.get_node("%AgainButton") as Button).pressed.emit()
	await _frames(2)
	runner = battle.get("runner")
	(battle.get_node("%AutoButton") as Button).button_pressed = true
	line = await _wait_line(_status, "battle seat=1 gen=2")
	_check(line == "battle seat=1 gen=2", "เล่นอีกครั้ง starts game 2 on both (%s)" % line)
	ok = await _until(func() -> bool: return (runner.call("acts") as Array).size() >= 20 or bool(runner.call("is_over")), GAME_CAP_MS)
	var at_kill := (runner.call("acts") as Array).size()
	_check(ok and not bool(runner.call("is_over")), "game 2 runs (%d acts) when the friend's app is killed" % at_kill)
	var t_kill := Time.get_ticks_msec()
	OS.kill(_pid)       # only the PID this test started
	_pid = -1
	var toast := battle.get("_toast_text") as Label
	var gone_at := [-1]          # (lambdas capture ints by value)
	ok = await _until(func() -> bool:
		if toast.text == "บอทเล่นแทน %s (หลุดจากห้อง)" % FRIEND and (battle.get_node("%Toast") as CanvasItem).visible:
			gone_at[0] = int(((runner.get("b") as Object).get("actlog") as Object).call("last_seq"))
			return true
		return false, 10000)
	_check(ok, "within 10 s the host shows \"บอทเล่นแทน %s (หลุดจากห้อง)\" (%d ms)" % [FRIEND, Time.get_ticks_msec() - t_kill])
	_check((runner.call("gone_seats") as PackedInt32Array).has(1), "seat 1 is played by the host")
	battle.call("set_speed", "instant")
	t = Time.get_ticks_msec()
	ok = await _until(func() -> bool: return bool(battle.call("is_over")), GAME_CAP_MS)
	_check(ok, "game 2 reaches the end without the friend in %d ms" % (Time.get_ticks_msec() - t))
	acts = runner.call("acts")
	var gone_seq := int(gone_at[0])
	var later := acts.filter(func(a: Dictionary) -> bool: return int(a.get("seq", 0)) > gone_seq and str(a.get("pid", "")) == "n1")
	_check(gone_seq > 0 and not later.is_empty(), "seat 1's acts after the drop (seq > %d) carry pid n1 (%d acts)" % [gone_seq, later.size()])
	_check_pids(acts, runner.get("st"), "game 2")
	_check(str(runner.call("sync_state")) == "ok" and not _log_has("desync"), "no desync on the host in game 2")

	# 6b. เล่นอีกครั้ง while the friend is away: its seat starts as played by the host; the friend reopens the app (same
	#     net cfg → same nid → same slot), joins from the airlock and is put straight back into the running game (RESYNC)
	battle.call("set_speed", "normal")
	(battle.get_node("%AgainButton") as Button).pressed.emit()
	var t_again := Time.get_ticks_msec()
	await _frames(2)
	runner = battle.get("runner")
	(battle.get_node("%AutoButton") as Button).button_pressed = true
	_check((runner.call("gone_seats") as PackedInt32Array).has(1), "game 3 starts with the away friend's seat played by the host")
	_pid_back = _spawn_peer(_status_back, FRIEND, "", _cmd_back, true)
	_check(_pid_back > 0, "the friend reopens its app (pid %d)" % _pid_back)
	line = await _wait_line(_status_back, "joined ")
	_check(line == "joined slot=1", "the friend rejoins with the same slot (%s)" % line)
	var back_at := [-1]
	ok = await _until(func() -> bool:
		if toast.text == "%s กลับมาแล้ว" % FRIEND and (battle.get_node("%Toast") as CanvasItem).visible:
			back_at[0] = int(((runner.get("b") as Object).get("actlog") as Object).call("last_seq"))
			return true
		return false, 10000)
	var back_seq := int(back_at[0])
	_check(ok, "the host shows \"%s กลับมาแล้ว\" and gives seat 1 back (at seq %d, %d ms into the game)" % [FRIEND, back_seq,
		Time.get_ticks_msec() - t_again])
	line = await _wait_line(_status_back, "battle ")
	_check(line == "battle seat=1 gen=3", "the friend's app opens the running game on seat 1 (%s)" % line)
	_check(not (runner.call("gone_seats") as PackedInt32Array).has(1), "seat 1 is the friend's again")
	battle.call("set_speed", "instant")
	ok = await _until(func() -> bool: return bool(battle.call("is_over")), GAME_CAP_MS)
	_check(ok, "game 3 reaches the end with the friend back")
	line = await _wait_line(_status_back, "over gen=3", 0, 20000)
	b = runner.get("b")
	seq = int((b.get("actlog") as Object).call("last_seq"))
	acts = runner.call("acts")
	_check(_field(line, "seq").to_int() == seq and _field(line, "dg") == str(b.call("digest")) and _field(line, "desync") == "0"
		and _field(line, "log") == JSON.stringify(acts, "", true).sha256_text().left(16),
		"the rejoined friend ends at the host's seq %d, digest and act log, no desync (%s)" % [seq, line])
	later = acts.filter(func(a: Dictionary) -> bool: return int(a.get("seq", 0)) > back_seq and str(a.get("pid", "")) == "n1")
	_check(not later.is_empty(), "the friend played seat 1 again after it came back (%d acts with pid n1)" % later.size())
	_check_pids(acts, runner.get("st"), "game 3")
	_send_to(_cmd_back, "quit")
	ok = await _until(func() -> bool: return not OS.is_process_running(_pid_back) and (_net.call("members") as Array).size() == 1, 15000)
	_check(ok, "the friend leaves the room on purpose (BYE): the host's room has 1 member")
	_pid_back = -1
	(battle.get_node("%LobbyButton") as Button).pressed.emit()
	await _frames(3)
	_check(app.call("current") == hall and (hall as CanvasItem).visible, "กลับล็อบบี้ returns the host to the deck")
	ok = await _until(func() -> bool: return int(friends.call("friend_count")) == 0, 3000)
	_check(ok, "the dropped friend is not drawn on the deck")

	# 7. another app version is refused with the reason in Thai and English
	_pid_old = _spawn_peer(_status_old, "เพื่อนรุ่นเก่า", OLD_APP, _out.path_join("friends_old_cmd.txt"))
	_check(_pid_old > 0, "an app on version %s started (pid %d)" % [OLD_APP.split(" ")[1], _pid_old])
	var want_th := "รุ่นแอปไม่ตรงกัน: เจ้าห้อง %s · คุณ %s — อัปเดตให้เป็นรุ่นเดียวกันก่อน" % [_ver(Version.APP_VER), _ver(OLD_APP)]
	var want_en := "App versions differ: host %s · you %s — update both to the same version first" % [_ver(Version.APP_VER), _ver(OLD_APP)]
	line = await _wait_line(_status_old, "refused ")
	_check(line == "refused wrong_app", "the join is refused with wrong_app (%s)" % line)
	line = await _wait_line(_status_old, "reason_th ")
	_check(line == "reason_th " + want_th, "its airlock screen gives the reason in Thai (%s)" % line)
	line = await _wait_line(_status_old, "reason_en ")
	_check(line == "reason_en " + want_en, "and in English (%s)" % line)
	line = await _wait_line(_status_old, "view ")
	_check(line.begins_with("view find state=finding"), "it is back on the room list, not in the room (%s)" % line)
	ok = await _until(func() -> bool: return not OS.is_process_running(_pid_old), 10000)
	_check(ok, "the old app quit by itself")
	_pid_old = -1
	_check((_net.call("members") as Array).filter(func(m: Dictionary) -> bool: return str(m["nm"]) == "เพื่อนรุ่นเก่า").is_empty(),
		"nobody on another version joined the room")

	# 8. round B: main menu → ออนไลน์ (no airlock station without a pack room) → ปิดห้อง → offline; cfg files untouched
	_check(not bool((hall.get("world") as Node).call("station_enabled", "online")), "no pack room: the airlock is no station")
	app.call("pop")
	await _frames(3)
	var menu8: Node = app.call("current")
	(menu8.get_node("%OnlineButton") as Button).pressed.emit()
	await _frames(3)
	lobby = app.call("current")
	_check(lobby != null and lobby.has_method("leave_room") and str(lobby.call("view")) == "room", "main menu → ออนไลน์ opens the room card")
	if lobby != null and lobby.has_method("leave_room"):
		(lobby.get_node("%LeaveButton") as Button).pressed.emit()
		await _frames(1)
		_check((lobby.get_node("%Confirm") as CanvasItem).visible, "ปิดห้อง asks first")
		(lobby.get_node("%ConfirmYes") as Button).pressed.emit()
		await _frames(2)
		_check(_net.call("state") != &"hosting" and not bool(_net.call("is_online")), "the room is closed (state %s)" % str(_net.call("state")))
		_check(str(lobby.call("view")) == "find", "the airlock screen is back on the room list")
		(lobby.get_node("%BackButton") as Button).pressed.emit()
		await _frames(3)
	_check(_net.call("state") == &"off", "leaving the airlock screen stops looking for rooms (state %s)" % str(_net.call("state")))
	var again := ENetMultiplayerPeer.new()
	_check(again.create_server(_port, 2) == OK, "binding the test game port again succeeds")
	again.close()
	var u := PacketPeerUDP.new()
	_check(u.bind(_port + 1, "*") == OK, "binding the test discovery port again succeeds")
	u.close()
	_check(_machine_cfg() == _cfg_before, "this machine's net.cfg and settings.cfg are untouched")
	_finish()


# ------------------------------------------------------------------------------------------------ checks

## every action on a squad carries its seat's pid: seat 0 n0, seat 1 n1, the bot seat ""; only these pids appear
func _check_pids(acts: Array, st: Object, what: String) -> void:
	var bad := PackedStringArray()
	var pids := {}
	for a: Dictionary in acts:
		var pid := str(a.get("pid", ""))
		pids[pid] = int(pids.get(pid, 0)) + 1
		if not Lockstep.ACTION_CODES.has(str(a.get("a", ""))) or not a.has("u"):
			continue
		var s: Object = st.call("squad", str(a["u"]))
		if s == null:
			continue
		var want: String = ["n0", "n1", ""][int(s.get("pl"))]
		if pid != want and bad.size() < 5:
			bad.append("seq %d %s %s pid %s" % [int(a.get("seq", 0)), str(a["a"]), str(a["u"]), pid])
	_check(bad.is_empty(), "%s: every action on a seat's squad carries that seat's pid" % what, ", ".join(bad))
	var keys: Array = pids.keys()
	keys.sort()
	_check(keys == ["", "n0", "n1"], "%s: acts carry pids \"\" (bot), n0 (host) and n1 (friend) only (%s)" % [what, str(pids)])


func _log_has(word: String) -> bool:
	var lg := root.get_node_or_null(^"Log")
	if lg == null:
		return false
	for l: String in lg.call("lines"):
		if l.begins_with("E ") and l.contains(word):
			return true
	return false


# ------------------------------------------------------------------------------------------------ media (FRIENDS_MEDIA)

## the host's airlock screen in a room with the friend, Thai and English
func _media_lobby(hall: Node) -> void:
	var lobby: Node = hall.call("open_online")
	await _frames(4)
	await _shot("lobby_room_th")
	_app().call("set_lang", "en")
	lobby.call("refresh")
	await _frames(3)
	await _shot("lobby_room_en")
	_app().call("set_lang", "th")
	(lobby.get_node("%BackButton") as Button).pressed.emit()
	await _frames(4)


## ~10 s of both avatars walking (the host's view, ffmpeg), then both windows on the deck side by side (the walk has
## put the first-walk hint away, so no name tag hides behind it)
func _media_deck(hall: Node) -> void:
	var frames := _media.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames)
	for f: String in DirAccess.get_files_at(frames):
		DirAccess.remove_absolute(frames.path_join(f))
	var plan := [["W", 1300], ["", 400], ["D", 1300], ["", 400], ["S", 1300], ["", 400], ["A", 1300], ["", 400],
		["W", 700], ["", 1800]]
	var n := 0
	var t0 := Time.get_ticks_msec()
	for p: Array in plan:
		var keys := str(p[0])
		if keys != "":
			_send("walk %s %d" % [keys, int(p[1])])
			_key(_code(keys), true)
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < int(p[1]):
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_jpg(frames.path_join("f%04d.jpg" % n), 0.9)
			n += 1
		if keys != "":
			_key(_code(keys), false)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var fps := maxf(1.0, n / secs)
	var mp4 := _media.path_join("friends_deck.mp4")
	var o: Array = []
	var rc := OS.execute("ffmpeg", ["-y", "-loglevel", "error", "-framerate", "%.2f" % fps, "-i", frames.path_join("f%04d.jpg"),
		"-vf", "scale=1280:-2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", mp4], o, true)
	print("      video: %d frames in %.1f s (%.1f fps) → %s (ffmpeg %d)" % [n, secs, fps, mp4, rc])
	_check(rc == 0 and FileAccess.file_exists(mp4), "friends_deck.mp4 written (%.1f s)" % secs)
	# back to the spawn row: both windows side by side
	var world: Node = hall.get("world")
	await _wait_line(_status, "walked ", 5, 10000)
	world.call("place_avatar", HallFriends.spawn_for(0), PI)
	(world.get("camera_rig") as Object).call("set_view", HallLayout.SPAWN_YAW, -0.45, 6.5)
	await _frames(30)
	_send("shot deck_peer")
	await _shot("deck_host")
	await _wait_line(_status, "shot deck_peer", 0, 10000)
	_side_by_side("deck_host", "deck_peer", "deck_two")


## both battle screens side by side, a few seconds into game 1
func _media_battle(battle: Node) -> void:
	var runner: Object = battle.get("runner")
	await _until(func() -> bool: return (runner.call("acts") as Array).size() >= 40 or bool(battle.call("is_over")), 60000)
	battle.call("set_speed", "normal")
	await _frames(30)
	_send("shot battle_peer")
	await _shot("battle_host")
	await _wait_line(_status, "shot battle_peer", 0, 10000)
	_side_by_side("battle_host", "battle_peer", "battle_two")


func _shot(nm: String) -> void:
	if _media == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_media.path_join(nm + ".png"))
	print("      media: " + _media.path_join(nm + ".png"))


func _side_by_side(a: String, b: String, out: String) -> void:
	var ia := Image.load_from_file(_media.path_join(a + ".png"))
	var ib := Image.load_from_file(_media.path_join(b + ".png"))
	if ia == null or ib == null:
		_check(false, "%s.png composed" % out)
		return
	for im: Image in [ia, ib]:
		im.convert(Image.FORMAT_RGB8)
		im.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	var img := Image.create(1920 + 8, 540, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.07))
	img.blit_rect(ia, Rect2i(0, 0, 960, 540), Vector2i(0, 0))
	img.blit_rect(ib, Rect2i(0, 0, 960, 540), Vector2i(968, 0))
	img.save_png(_media.path_join(out + ".png"))
	_check(true, "%s.png written (host left, friend right)" % out)


# ------------------------------------------------------------------------------------------------ helpers

func _spawn_peer(status: String, nm: String, fake_app: String, cmd: String, rejoin := false) -> int:
	var args := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		args.append("--headless")
	else:
		args.append_array(["--rendering-driver", "opengl3", "--resolution", "1280x720"])
	args.append_array(["--path", ProjectSettings.globalize_path("res://"), "--audio-driver", "Dummy", "-s", PEER, "--",
		"--net-port=%d" % _port, "--status=" + status, "--cmd=" + cmd, "--name=" + nm,
		"--gfx=" + ("mid" if _media != "" else "min")])
	if fake_app != "":
		args.append("--fake-app=" + fake_app)
	if rejoin:
		args.append("--rejoin")
	if _media != "":
		args.append("--media=" + _media)
	return OS.create_process(OS.get_executable_path(), args)


func _send(cmd: String) -> void:
	_send_to(_cmd, cmd)


func _send_to(file: String, cmd: String) -> void:
	var f := FileAccess.open(file, FileAccess.READ_WRITE if FileAccess.file_exists(file) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(cmd)
	f.close()


## the n-th (0 = first) status line starting with prefix; waits up to cap_ms ("" on timeout)
func _wait_line(file: String, prefix: String, nth := 0, cap_ms := STEP_CAP_MS) -> String:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < cap_ms:
		if FileAccess.file_exists(file):
			var hits := 0
			for l: String in FileAccess.get_file_as_string(file).split("\n"):
				if l.begins_with(prefix):
					if hits == nth:
						return l.strip_edges()
					hits += 1
		await process_frame
	print("      waited for \"%s\" #%d; status so far:\n%s" % [prefix, nth, FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else "(none)"])
	return ""


func _peer_said(file: String, prefix: String) -> bool:
	if not FileAccess.file_exists(file):
		return false
	for l: String in FileAccess.get_file_as_string(file).split("\n"):
		if l.begins_with(prefix):
			return true
	return false


## "key=value" from a status line
static func _field(line: String, key: String) -> String:
	for w: String in line.split(" "):
		if w.begins_with(key + "="):
			return w.trim_prefix(key + "=")
	return ""


## the n-th and n+1-th words of a line as centimetres
static func _xz_cm(line: String, n: int) -> Vector2:
	var w := line.split(" ")
	if w.size() < n + 2:
		return Vector2.INF
	return Vector2(w[n].to_int(), w[n + 1].to_int())


static func _look_host(line: String) -> Vector2:
	var v := _field(line, "host").split(",")
	if v.size() != 2:
		return Vector2.INF
	return Vector2(v[0].to_int(), v[1].to_int()) / 100.0


static func _v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _ver(app_ver: String) -> String:
	var w := app_ver.split(" ")
	return w[w.size() - 1]


func _tag_texts(tags: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for d: Dictionary in tags.call("drawn"):
		out.append(str(d.get("text", "")))
	return out


## a choice field the setup screen has no setter for (size: Control.set_size is taken), then refresh
func _set_choice(setup: Node, key: String, value: Variant) -> void:
	var ch: Dictionary = setup.get("choice")
	ch[key] = value
	setup.call("refresh")


func _code(keys: String) -> Key:
	return {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D}.get(keys, KEY_W)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _until(cond: Callable, cap_ms := STEP_CAP_MS) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < cap_ms:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _name(n: Node) -> String:
	return "none" if n == null else String(n.name)


func _machine_cfg() -> Dictionary:
	var out := {}
	for f: String in ["user://net.cfg", "user://settings.cfg"]:
		out[f] = [FileAccess.file_exists(f), FileAccess.get_modified_time(f) if FileAccess.file_exists(f) else 0]
	return out


func _finish() -> void:
	for pid: int in [_pid, _pid_old, _pid_back]:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)   # only the PIDs this test started
	_pid = -1
	_pid_old = -1
	_pid_back = -1
	if _net != null and _net.call("state") != &"off":
		_net.call("leave")
	if _net != null:
		_net.call("find", false)
	var app := _app()
	app.call("set_lang", "th")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("      %.1f s" % ((Time.get_ticks_msec() - _t0) / 1000.0))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 and _passed > 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 and _passed > 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
