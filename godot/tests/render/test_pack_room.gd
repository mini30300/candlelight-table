extends SceneTree
## Pack room behind the docking airlock (PACK_SPEC §9) with the neutral fixture room (tests/fixtures/pack_rooms), the
## online flag on and a fake Net: main menu → เล่นกับบอท → the deck. The airlock's sign and prompt use the room's
## door_sign / title (Thai, then English); walking into the airlock fades and pushes PackRoomScreen at the spawn; E at
## soon_box shows its text; cards_box opens the two-card panel, the soon card shows its text, the online card opens the
## lobby and popping it shows the room again where the avatar stood; the room script got setup once with the context,
## station_near / station_used with the ids, set_active(false) while covered and true after; walking into the door
## goes back to the deck at AIRLOCK_RETURN facing -x with no station in reach; Esc does the same and closes the cards
## and the panel first; English mode leaves no Thai on the room screen; budgets on all four levels, desktop and phone
## (room_budget.gd); min: nothing under the room processes after 10 idle frames, lo: the anim part stays still;
## friends: a pose in the band (+30 m) draws the friend in the room at x - 30 and not on the deck, a deck pose the
## other way round; my poses from the room are in the band, at most one per 100 ms plus one stop pose; leaving sends a
## deck pose; the host's SETUP-open note in the room names the cards station; a second visit is a new screen that
## draws a friend already in the room (seed_poses), a member who leaves loses the room pose and a reused slot starts on
## the deck; a screen pushed during the leave fade (a friend starting a battle) leaves no black room behind: popping it
## lands on the deck; a room whose script blocks the spawn is refused: the lobby opens, then the ROOM_FAILED note. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_pack_room.gd
## Exit code 1 on any failure; the last line is PASS or FAIL. PNGs in $TEST_OUT (default godot/tests/out).

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_pack_room.cfg"
const FIX := "res://tests/fixtures/pack_rooms"
const REFUSED := "res://tests/fixtures/pack_rooms_refused"
const FAKE_NET := "res://tests/unit/fixtures/fake_net.gd"
const BUDGET_SCRIPT := "res://tests/render/room_budget.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const FRIENDS: PackedStringArray = ["เจ้าห้อง", "เพื่อนหนึ่ง", "Friend Two"]

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _fake: Node
var _real_net: Node


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	PackRooms.reset()
	PackRooms.test_root = FIX
	Features.set_flag(&"online", true)
	_real_net = root.get_node_or_null(^"Net")
	if _real_net != null:
		_real_net.name = "NetReal"
	_fake = (load(FAKE_NET) as GDScript).new()
	_fake.name = "Net"
	root.add_child(_fake)
	_main = (load(SCENE) as PackedScene).instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(3)
	var menu: Node = _app().call("current")
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	_check(hall != null and hall.has_method("door_room"), "เล่นกับบอท opens the deck")
	if hall == null or not hall.has_method("door_room"):
		_finish()
		return
	_check(str(hall.get("rooms_root")) == FIX and str(hall.call("door_room").get("id", "")) == "test_room",
		"the deck's airlock has the fixture room")
	await _check_deck_door(hall)
	var room := await _walk_in(hall)
	if room == null:
		_finish()
		return
	await _check_stations(room)
	await _check_script_calls(room)
	await _check_english(room)
	await _check_levels(room)
	await _check_friends(hall, room)
	var first_id := room.get_instance_id()
	await _check_leave(hall, room)
	await _check_second_visit(hall, first_id)
	await _check_esc(hall)
	await _check_refused(hall)
	_finish()


func _check_deck_door(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	_check(str(world.call("sign_text", "online")) == "ประตูเทียบยาน · ห้องทดสอบ", "the airlock sign is the room's door_sign (Thai)",
		str(world.call("sign_text", "online")))
	var f: Vector2 = HallLayout.STATIONS["online"]["front"]
	world.call("place_avatar", Vector3(f.x, 0.0, f.y), PI * 0.5)
	await _frames(2)
	var use: Button = hall.get_node("%UseButton")
	_check(use.visible and use.text.begins_with("ห้องทดสอบ"), "the airlock prompt uses the room title", use.text)
	_app().call("set_lang", "en")
	hall.call("refresh")
	await _frames(2)
	_check(str(world.call("sign_text", "online")) == "Docking Airlock · Test room" and use.text.begins_with("Test room"),
		"English: the door_sign and title in English", "%s / %s" % [world.call("sign_text", "online"), use.text])
	_app().call("set_lang", "th")
	hall.call("refresh")
	_save("pack_room_deck_door.png")


func _walk_in(hall: Node) -> Node:
	var world: Node3D = hall.get("world")
	var f: Vector2 = HallLayout.STATIONS["online"]["front"]
	world.call("place_avatar", Vector3(f.x, 0.0, f.y), PI * 0.5)
	(world.get("camera_rig") as Node3D).call("set_view", -PI * 0.5, -0.35, 5.5)
	await _frames(2)
	world.call("set_stick", Vector2(0.0, 0.84))
	var room: Node = null
	for i in 240:
		await physics_frame
		var cur: Node = _app().call("current")
		if cur != null and cur.has_method("room_id"):
			room = cur
			break
	world.call("set_stick", Vector2.ZERO)
	_check(room != null, "walking into the airlock pushes the pack room screen")
	if room == null:
		return null
	_check(str(room.call("room_id")) == "test_room" and _app().call("current") == room, "App.current() is the test room")
	await _frames_until(func() -> bool: return not bool(room.call("fading")), 60)
	var rw: Node3D = room.get("world")
	var av := rw.get("avatar") as Node3D
	_check(av.global_position.distance_to(Vector3(0.0, 0.0, 6.0)) < 0.05, "the avatar stands at the room's spawn", str(av.global_position))
	_check(not (hall as CanvasItem).visible and not (world as Node3D).visible, "the deck is hidden under the room")
	_save("pack_room_entered.png")
	return room


func _check_stations(room: Node) -> void:
	var rw: Node3D = room.get("world")
	var soon: Label = room.get_node("%SoonLabel")
	await _stand(room, "soon_box")
	_check(str(room.call("station")) == "soon_box", "soon_box in reach at its front")
	await _press(KEY_E)
	_check(room.get_node("%SoonPanel").visible and soon.text == "กล่องนี้ — เร็วๆ นี้", "E at soon_box shows its Thai text", soon.text)
	_app().call("set_lang", "en")
	room.call("refresh")
	_check(soon.text == "This box — coming soon", "and English", soon.text)
	_app().call("set_lang", "th")
	room.call("refresh")
	room.call("close_soon")
	await _stand(room, "cards_box")
	await _press(KEY_E)
	var cards: Array = room.call("card_buttons")
	_check(room.get_node("%CardsPanel").visible and cards.size() == 2, "E at cards_box opens the panel with two cards")
	_save("pack_room_cards.png")
	if cards.size() == 2:
		(cards[0] as Button).pressed.emit()
		await _frames(2)
		_check(not room.get_node("%CardsPanel").visible and soon.text == "โหมดทดสอบ — เร็วๆ นี้", "the soon card shows its text", soon.text)
		room.call("open_cards", "cards_box")
		await _frames(2)
		var at := (rw.get("avatar") as Node3D).global_position
		(room.call("card_buttons")[1] as Button).pressed.emit()
		await _frames(3)
		var lobby: Node = _app().call("current")
		_check(lobby != room and lobby != null and lobby.scene_file_path == "res://ui/screens/lobby.tscn", "the online card opens the lobby")
		_app().call("pop")
		await _frames(3)
		_check(_app().call("current") == room and (rw as Node3D).visible, "popping the lobby shows the room again")
		_check((rw.get("avatar") as Node3D).global_position.distance_to(at) < 0.05, "the avatar stands where it was")


func _check_script_calls(room: Node) -> void:
	var rw: Node3D = room.get("world")
	var sn: Node = rw.get("script_node")
	var calls: Dictionary = sn.get("calls")
	var setup: Array = calls.get("setup", [])
	_check(setup.size() == 1, "setup was called once", str(setup.size()))
	if setup.size() == 1:
		var ctx: Dictionary = setup[0][0]
		_check(ctx.has("data") and str(ctx.get("dir", "")) == FIX + "/test_room" and ["hi", "mid", "lo", "min"].has(str(ctx.get("level")))
			and ctx.get("english") is bool and ctx.get("team_colour") is Color, "with the context keys", str(ctx.keys()))
	var near := []
	for a: Array in calls.get("station_near", []):
		near.append(a[0])
	_check(near.has("soon_box") and near.has("cards_box"), "station_near with the ids", str(near))
	var used := []
	for a: Array in calls.get("station_used", []):
		used.append(a[0])
	_check(used.has("soon_box") and used.has("cards_box"), "station_used with the ids", str(used))
	var act := []
	for a: Array in calls.get("set_active", []):
		act.append(a[0])
	var i := act.find(false)
	_check(i >= 0 and act.slice(i).has(true) and act.back() == true, "set_active(false) while covered, true after", str(act))


func _check_english(room: Node) -> void:
	_app().call("set_lang", "en")
	room.call("refresh")
	await _stand(room, "cards_box")
	room.call("open_cards", "cards_box")
	await _frames(3)
	var thai := _thai_in(room)
	_check(thai.is_empty(), "English mode: no Thai on the room screen (cards open)", ", ".join(thai))
	_save("pack_room_cards_en.png")
	room.call("close_cards")
	_app().call("set_lang", "th")
	room.call("refresh")


func _check_levels(room: Node) -> void:
	var res: Dictionary = await (load(BUDGET_SCRIPT) as Script).call("measure", self, room, ProjectSettings.globalize_path(_out_dir))
	for l: String in res["lines"]:
		print("      " + l)
	_check(bool(res["ok"]), "budgets on hi/mid/lo/min, desktop and phone, within the deck's limits")
	var rw: Node3D = room.get("world")
	var sn: Node = rw.get("script_node")
	for level in ["min", "lo"]:
		_app().call("set_gfx", level)
		room.call("refresh")
		var part := sn.get("anim_part") as Node3D
		var y0 := part.position.y
		await _frames(10)
		var busy := _idle_problems(rw)
		busy.append_array(_idle_problems(room))
		_check(busy.is_empty(), "%s: nothing under the room processes after 10 idle frames" % level, ", ".join(busy))
		_check(absf(part.position.y - y0) < 0.0001, "%s: the anim part stays still" % level)
	_app().call("set_gfx", "mid")
	room.call("refresh")
	await _frames(10)
	_check((sn as Node).is_processing(), "mid: the anim part runs")


func _check_friends(hall: Node, room: Node) -> void:
	var rw: Node3D = room.get("world")
	var rf: HallFriends = rw.get("friends")
	var df: HallFriends = (hall.get("world") as Node3D).get("friends")
	_fake.set("host_flag", true)
	_fake.set("slot", 0)
	var list: Array[Dictionary] = []
	for i in 3:
		list.append({"slot": i, "nm": FRIENDS[i], "where": "deck", "pick": "", "here": true})
	_fake.set("member_list", list)
	_fake.set("st", &"hosting")
	_fake.emit_signal("state_changed", &"hosting")
	_fake.emit_signal("members_changed")
	await _frames(2)
	_check(rf.friend_count() == 0, "no pose yet: the friends count as on the deck, not in the room")
	# เจ้าห้องเปิดหน้าตั้งเกม: เพื่อนในห้องเห็นข้อความพร้อมชื่อโต๊ะการ์ด (ครั้งเดียวต่อการเปิด) · เจ้าห้องเองไม่เห็น
	var soon: Label = room.get_node("%SoonLabel")
	room.call("close_soon")
	_fake.emit_signal("message", 0, NetProto.SETUP, {"open": true})
	await _frames(1)
	_check(not room.get_node("%SoonPanel").visible, "the host gets no SETUP-open note")
	_fake.emit_signal("message", 0, NetProto.SETUP, {"open": false})
	_fake.set("host_flag", false)
	_fake.set("slot", 1)
	_fake.emit_signal("message", 0, NetProto.SETUP, {"open": true})
	await _frames(1)
	_check(room.get_node("%SoonPanel").visible and soon.text == "เจ้าห้องกำลังตั้งเกม — เลือกที่นั่งได้ที่โต๊ะเลือกโหมด",
		"a guest in the room gets the SETUP-open note naming the cards station", soon.text)
	room.call("close_soon")
	_fake.emit_signal("message", 0, NetProto.SETUP, {"open": true})
	await _frames(1)
	_check(not room.get_node("%SoonPanel").visible, "once per opening")
	_fake.emit_signal("message", 0, NetProto.SETUP, {"open": false})
	_fake.set("host_flag", true)
	_fake.set("slot", 0)
	_fake.emit_signal("members_changed")
	await _frames(1)
	_fake.emit_signal("pose", 1, {"x": roundi(PackRooms.to_band(2.0) * 100.0), "z": 300, "yaw": 0, "sp": 0, "run": false, "t": 0})
	await _frames(2)
	_check(rf.has_friend(1) and rf.friend_pos(1).distance_to(Vector3(2.0, 0.0, 3.0)) < 0.05, "a pose in the band draws the friend in the room at x - 30",
		str(rf.friend_pos(1)) if rf.has_friend(1) else "absent")
	_check(not df.has_friend(1), "and not on the deck")
	_fake.emit_signal("pose", 2, {"x": 100, "z": 200, "yaw": 0, "sp": 0, "run": false, "t": 0})
	await _frames(2)
	_check(not rf.has_friend(2) and df.has_friend(2), "a deck pose draws the friend on the deck and not in the room")
	_fake.emit_signal("pose", 1, {"x": -200, "z": 0, "yaw": 0, "sp": 0, "run": false, "t": 0})
	await _frames(2)
	_check(not rf.has_friend(1) and df.has_friend(1), "the friend walking back to the deck moves there")
	# ท่าของเราเองจากห้อง
	_fake.set("calls", [])
	var rig: Node3D = rw.get("camera_rig")
	(rw.get("avatar") as Node3D).call("place", Vector3(0.0, 0.0, 2.0), PI)
	rig.call("set_view", 0.0, -0.45, 6.5)
	rw.call("set_stick", Vector2(0.0, 0.84))
	await _physics(30)
	rw.call("set_stick", Vector2.ZERO)
	await _frames_until(func() -> bool: return _stops() >= 1, 120)
	var poses := _sent()
	var in_band := true
	for p: Array in poses:
		in_band = in_band and PackRooms.in_band(p[1])
	var moving := poses.filter(func(p: Array) -> bool: return not bool(p[2]))
	var gaps_ok := true
	for i in range(1, moving.size()):
		gaps_ok = gaps_ok and int(moving[i][1]["t"]) - int(moving[i - 1][1]["t"]) >= 100
	_check(not poses.is_empty() and in_band, "my poses from the room are in the band (%d sent)" % poses.size())
	_check(gaps_ok and _stops() == 1, "at most one per 100 ms while walking, then one stop pose", "%d moving, %d stop" % [moving.size(), _stops()])


func _check_leave(hall: Node, room: Node) -> void:
	_fake.set("calls", [])
	var rw: Node3D = room.get("world")
	var f := Vector3(0.0, 0.0, 6.6)
	rw.call("place_avatar", f, 0.0)
	(rw.get("camera_rig") as Node3D).call("set_view", PI, -0.45, 6.5)
	await _frames(2)
	rw.call("set_stick", Vector2(0.0, 0.84))
	await _frames_until(func() -> bool: return _app().call("current") == hall, 240)
	if is_instance_valid(rw):
		rw.call("set_stick", Vector2.ZERO)
	_check(_app().call("current") == hall, "walking into the door goes back to the deck")
	await _frames_until(func() -> bool: return not bool(hall.call("fading")), 60)
	var world: Node3D = hall.get("world")
	var av := world.get("avatar") as Node3D
	_check(Vector2(av.global_position.x, av.global_position.z).distance_to(Vector2(HallLayout.AIRLOCK_RETURN.x, HallLayout.AIRLOCK_RETURN.z)) < 0.05,
		"back at AIRLOCK_RETURN", str(av.global_position))
	_check(absf(wrapf(float(av.get("face")) + PI * 0.5, -PI, PI)) < 0.01 and str(hall.call("station")) == "", "facing -x, no station in reach")
	var sent := _sent()
	_check(not sent.is_empty() and not PackRooms.in_band(sent.back()[1]), "leaving the room sends a deck pose")
	_save("pack_room_back_on_deck.png")
	_fake.set("st", &"off")
	_fake.set("member_list", [] as Array[Dictionary])
	_fake.emit_signal("state_changed", &"off")
	_fake.emit_signal("members_changed")
	await _frames(2)


func _check_esc(hall: Node) -> void:
	var room: Node = hall.call("enter_room", true)
	_check(room != null and room.has_method("room_id") and str(room.call("station")) == "cards_box", "enter_room(true) stands in front of cards_box")
	if room == null:
		return
	await _frames_until(func() -> bool: return not bool(room.call("fading")), 60)
	room.call("open_cards", "cards_box")
	room.call("show_note", "{name} เข้าห้องแล้ว", {"name": "x"})
	room.get_node("%SoonPanel").show()
	_check(bool(room.call("handle_back")) and not room.get_node("%CardsPanel").visible and room.get_node("%SoonPanel").visible,
		"back closes the cards first")
	_check(bool(room.call("handle_back")) and not room.get_node("%SoonPanel").visible and _app().call("current") == room,
		"then the panel, still in the room")
	await _press(KEY_ESCAPE)
	await _frames_until(func() -> bool: return _app().call("current") == hall, 60)
	_check(_app().call("current") == hall, "Esc in the room goes back to the deck (never the main menu)")
	await _frames_until(func() -> bool: return not bool(hall.call("fading")), 60)
	var av := (hall.get("world") as Node3D).get("avatar") as Node3D
	_check(Vector2(av.global_position.x, av.global_position.z).distance_to(Vector2(HallLayout.AIRLOCK_RETURN.x, HallLayout.AIRLOCK_RETURN.z)) < 0.05,
		"and stands at AIRLOCK_RETURN")


func _check_second_visit(hall: Node, first_id: int) -> void:
	_fake.set("host_flag", true)
	_fake.set("slot", 0)
	var list: Array[Dictionary] = []
	for i in 3:
		list.append({"slot": i, "nm": FRIENDS[i], "where": "deck", "pick": "", "here": true})
	_fake.set("member_list", list)
	_fake.set("st", &"hosting")
	_fake.emit_signal("state_changed", &"hosting")
	_fake.emit_signal("members_changed")
	await _frames(2)
	# เพื่อนหนึ่งเดินเข้าห้องก่อนเรา (ท่าในแถบห้องขณะเราอยู่บนดาดฟ้า)
	_fake.emit_signal("pose", 1, {"x": roundi(PackRooms.to_band(-2.0) * 100.0), "z": 100, "yaw": 0, "sp": 0, "run": false, "t": 0})
	await _frames(2)
	var df: HallFriends = (hall.get("world") as Node3D).get("friends")
	_check((hall.call("band_poses") as Dictionary).has(1) and not df.has_friend(1), "a friend in the room is remembered, not drawn on the deck")
	var room: Node = hall.call("enter_room", true)
	_check(room != null and room.get_instance_id() != first_id and room.has_method("room_id"), "a second visit opens a new room screen")
	if room == null or not room.has_method("room_id"):
		return
	_check(instance_from_id(first_id) == null, "the first room screen is gone")
	await _frames_until(func() -> bool: return not bool(room.call("fading")), 60)
	var rw: Node3D = room.get("world")
	var rf: HallFriends = rw.get("friends")
	_check(rf.has_friend(1) and rf.friend_pos(1).distance_to(Vector3(-2.0, 0.0, 1.0)) < 0.05, "seed_poses: the friend already in the room is drawn there",
		str(rf.friend_pos(1)) if rf.has_friend(1) else "absent")
	var calls: Dictionary = (rw.get("script_node") as Node).get("calls")
	_check((calls.get("setup", []) as Array).size() == 1, "the new room's script got setup once")
	# เพื่อนออก: ลืมท่าในห้อง · คนใหม่ได้ช่องเดิม: เริ่มที่ดาดฟ้า ไม่โผล่ในห้อง
	_fake.set("member_list", list.filter(func(m: Dictionary) -> bool: return int(m["slot"]) != 1))
	_fake.emit_signal("members_changed")
	await _frames(2)
	_check(not rf.has_friend(1) and not (room.get("_in") as Dictionary).has(1) and not (hall.call("band_poses") as Dictionary).has(1),
		"a member who leaves loses the room pose (room and deck)")
	_fake.set("member_list", list.map(func(m: Dictionary) -> Dictionary:
		return {"slot": 1, "nm": "Newcomer", "where": "deck", "pick": "", "here": true} if int(m["slot"]) == 1 else m))
	_fake.emit_signal("members_changed")
	await _frames(2)
	_check(not rf.has_friend(1), "a reused slot starts on the deck, not in the room")
	# หน้าอื่นถูกเปิดทับระหว่างจอมืดตอนออก (เช่นเพื่อนเริ่มรบ): ปิดหน้านั้นแล้วต้องกลับดาดฟ้า ไม่ค้างจอดำในห้อง
	room.call("leave")
	var dummy := PackedScene.new()
	var ctl := Control.new()
	ctl.name = "CoverScreen"
	dummy.pack(ctl)
	ctl.free()
	var cover: Node = _app().call("push", dummy)
	await _frames_until(func() -> bool: return not bool(room.get("_fading")), 90)
	await _frames(2)
	_check(_app().call("current") == cover and is_instance_valid(room) and room.is_inside_tree(), "the cover stays on top after the fade")
	_app().call("pop")
	await _frames_until(func() -> bool: return _app().call("current") == hall, 30)
	_check(_app().call("current") == hall and bool(hall.get("active")), "popping the cover lands on the deck (no black room left)")
	await _frames_until(func() -> bool: return not bool(hall.call("fading")), 60)
	var av := (hall.get("world") as Node3D).get("avatar") as Node3D
	_check(Vector2(av.global_position.x, av.global_position.z).distance_to(Vector2(HallLayout.AIRLOCK_RETURN.x, HallLayout.AIRLOCK_RETURN.z)) < 0.05
		and not (hall.get_node("%Fade") as CanvasItem).visible, "at AIRLOCK_RETURN with the fade gone", str(av.global_position))
	_fake.set("st", &"off")
	_fake.set("member_list", [] as Array[Dictionary])
	_fake.emit_signal("state_changed", &"off")
	_fake.emit_signal("members_changed")
	await _frames(2)


func _check_refused(hall: Node) -> void:
	hall.set("rooms_root", REFUSED)
	_check(str(hall.call("door_room").get("id", "")) == "blocked_room", "the refused fixture is listed (room.json is valid)")
	var depth := int(_app().call("depth"))
	var got: Node = hall.call("enter_room", true)
	await _frames(2)
	var lobby: Node = _app().call("current")
	_check(got != null and got == lobby and lobby.scene_file_path == "res://ui/screens/lobby.tscn" and int(_app().call("depth")) == depth + 1,
		"a room whose script blocks the spawn is refused: the lobby opens instead")
	_app().call("pop")
	await _frames(3)
	var soon: Label = hall.get_node("%SoonLabel")
	_check(_app().call("current") == hall and hall.get_node("%SoonPanel").visible and soon.text == "เปิดห้องไม่ได้ — เปิดหน้าเล่นกับเพื่อนแทน",
		"back on the deck: the ROOM_FAILED note", soon.text)
	_check(not (hall.get_node("%Fade") as CanvasItem).visible, "and no fade left")
	hall.set("rooms_root", FIX)


# ---- ตัวช่วย ----

func _stand(room: Node, id: String) -> void:
	var rw: Node3D = room.get("world")
	var lay: RoomLayout = rw.get("layout")
	var f: Vector2 = lay.stations[id]["front"]
	rw.call("place_avatar", Vector3(f.x, 0.0, f.y), PI)
	await _frames(2)


func _sent() -> Array:
	return (_fake.get("calls") as Array).filter(func(c: Array) -> bool: return str(c[0]) == "send_pose")


func _stops() -> int:
	return _sent().filter(func(c: Array) -> bool: return bool(c[2])).size()


func _idle_problems(n0: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [n0]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return out
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return out
	var texts := PackedStringArray()
	if node is Label or node is Button:
		texts.append(str(node.get("text")))
	if node is Label3D:
		texts.append((node as Label3D).text)
	for t in texts:
		if _thai_re.search(t) != null:
			out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		out.append_array(_thai_in(c))
	return out


func _press(code: Key) -> void:
	for p in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = p
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await _frames(2)


func _frames_until(cond: Callable, n: int) -> void:
	for i in n:
		if cond.call():
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var err := img.save_png(_out_dir + "/" + name)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(_out_dir + "/" + name))


func _finish() -> void:
	if _fake != null:
		_fake.name = "FakeNet"
		_fake.queue_free()
	if _real_net != null:
		_real_net.name = "Net"
	PackRooms.reset()
	Features.reset()
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
