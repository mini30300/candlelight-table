extends SceneTree
## The play-with-friends screen behind the docking airlock (NET_SPEC §7.2, §12.4 DECK), driven through a duck-typed fake
## Net (tests/unit/fixtures/fake_net.gd) that stands in for the autoload at /root/Net for the whole run (the real one is
## renamed aside and put back), so no socket opens. Every state at 640x360, 1280x720 and 1280x576, Thai and English:
## the empty list (searching, then the 4 s line), two found rows with one greyed mismatch (its reason shown, tapping it
## never joins), connecting (cancel leaves), the hosting card with two IPs and discovery off (close asks first; back
## closes the question), the joined card with six members and 20-character names (host / you tags, where lines, the
## army pick cycles), the setup seat list with six seats (sit on a bot seat, leave my own seat) and every refused / lost
## key. Layout rules of LOBBY_SPEC §7.1 (inside the canvas, inside the parent, scroll content only horizontally,
## buttons >= 44 px, no sibling buttons overlapping); in English no Thai except the players' names. IP field: only a
## dotted IPv4 with an optional port joins. Opening the screen starts the join list (find(true)), back pops it and stops
## the list. Saves lobby_find_th.png, lobby_find_en.png, lobby_room_th.png, lobby_seats_en.png and lobby_refused.png.
## Review fixes: the IP row sits right under the name row (above the room list, so the phone keyboard does not cover it)
## with a URL keyboard; the 4 s line points up to it; a device without Wi-Fi (has_lan false) is told no_lan instead of
## "no rooms yet"; the host card shows the IP large with a copy button that puts the first IP on the clipboard.
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_lobby.gd

const SCENE := "res://scenes/main.tscn"
const LOBBY := "res://ui/screens/lobby.tscn"
const FAKE_NET := "res://tests/unit/fixtures/fake_net.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_lobby.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1280, 576)]
const SETTLE := 6
const MIN_TARGET := 44.0
const NAMES: PackedStringArray = ["เจ้าห้องใจดีมากๆนะครับ", "เพื่อนคนที่สองชื่อยาวมาก", "Third friend long nm", "เพื่อนสี่", "Friend five", "หก"]
const KEYS: PackedStringArray = ["not_lan", "wrong_game", "wrong_net", "wrong_app", "wrong_rules", "full", "closing", "port_busy",
	"no_lan", "bad_ip", "timeout", "host_left", "bad_message", "reconnect_failed"]

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _fake: Node
var _real_net: Node
var _machine_cfg := ""


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_machine_cfg = _machine_files()
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "min")
	app.call("set_touch", "off")
	# the fake Net takes the autoload's place for the whole run (the real one keeps its object, renamed aside)
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
	await _frames(4)
	var app := _app()
	var depth0 := int(app.call("depth"))
	var lobby: Node = app.call("push", load(LOBBY))
	await _frames(3)
	_check(lobby != null and lobby.has_method("view") and lobby.get("net") == _fake, "the lobby screen opens and reads Net from /root/Net (the fake)")
	_check(_fake.calls_of("find") == [["find", true]], "opening the screen starts the join list once (find(true))", str(_fake.calls_of("find")))
	_check(str(lobby.call("view")) == "find", "offline it shows the find state")
	var name_edit := lobby.get_node("%NameEdit") as LineEdit
	_check(RegEx.create_from_string("^ผู้เล่น [1-9][0-9][0-9]$").search(name_edit.text) != null and str(_fake.get("nm")) == name_edit.text,
		"an empty name gets the default ผู้เล่น NNN, saved through set_my_name (%s)" % name_edit.text)
	_check(name_edit.max_length == 20, "the name field takes 20 characters")
	await _check_ip(lobby)
	for sz in SIZES:
		await _resize(sz)
		for lang in ["th", "en"]:
			app.call("set_lang", lang)
			await _states(lobby, "%s %dx%d" % [lang, sz.x, sz.y], lang, sz == SIZES[0])
	app.call("set_lang", "th")
	await _resize(SIZES[0])
	await _check_flows(lobby)
	await _check_refused(lobby)
	# back pops the screen and closes the join list
	_set_offline()
	lobby.call("refresh")
	await _frames(2)
	(lobby.get_node("%BackButton") as Button).pressed.emit()
	await _frames(3)
	_check(int(app.call("depth")) == depth0, "the back button pops the lobby screen (depth %d)" % int(app.call("depth")))
	var finds: Array = _fake.calls_of("find")
	_check(not finds.is_empty() and finds[finds.size() - 1] == ["find", false], "leaving the screen stops the join list (find(false))", str(finds))
	_check(_machine_files() == _machine_cfg, "this machine's settings.cfg and net.cfg were not touched")
	_finish()


# ---- the states ----

func _states(lobby: Node, tag: String, lang: String, save: bool) -> void:
	# 1. empty list: searching, then after 4 s the longer line
	_set_offline()
	_fake.set("found_rows", [] as Array[Dictionary])
	lobby.call("refresh")
	await _frames(2)
	var empty := lobby.get_node("%FoundEmpty") as Label
	_check(empty.visible and empty.text == _t("กำลังค้นหาห้อง…"), tag + ": the empty list says it is looking (%s)" % empty.text)
	var timer := lobby.get_node("%EmptyTimer") as Timer
	_check(not timer.is_stopped() and absf(timer.wait_time - 4.0) < 0.01, tag + ": a 4 s timer runs while the list is empty")
	timer.timeout.emit()
	timer.stop()
	await _frames(1)
	# changed on purpose (review): the IP row moved above the list, so the line says the IP field is above
	_check(empty.text == _t("ยังไม่พบห้อง — ให้เพื่อนกดเปิดห้อง หรือใส่ IP ของเจ้าห้องด้านบน"), tag + ": after 4 s it suggests hosting or the IP (%s)" % empty.text)
	var ip_row := (lobby.get_node("%IpEdit") as Control).get_parent() as Control
	var found_panel := lobby.get_node("%FoundPanel") as Control
	var name_row := (lobby.get_node("%NameEdit") as Control).get_parent() as Control
	_check(ip_row.get_index() == name_row.get_index() + 1 and ip_row.get_index() < found_panel.get_index()
		and ip_row.get_global_rect().position.y < found_panel.get_global_rect().position.y,
		tag + ": the IP row is right under the name row, above the room list (the phone keyboard does not cover it)")
	_check((lobby.get_node("%IpEdit") as LineEdit).virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_URL, tag + ": the IP field opens a URL keyboard (digits and dots)")
	await _layout_ok(lobby, tag + " empty list")
	# no Wi-Fi on this device: the list says so (not "ask a friend to host")
	_fake.set("lan", false)
	lobby.call("refresh")
	await _frames(1)
	_check(empty.text == _t("ไม่พบ Wi-Fi — ต่อ Wi-Fi ก่อนแล้วลองใหม่"), tag + ": without Wi-Fi the empty list says no_lan (%s)" % empty.text)
	_fake.set("lan", true)
	lobby.call("refresh")
	await _frames(1)
	# 2. two rows, one greyed
	_fake.set("found_rows", _rows())
	_fake.emit_signal("found_changed")
	await _frames(2)
	var list := lobby.get_node("%FoundList") as Control
	_check(list.get_child_count() == 2 and not empty.visible, tag + ": two found rows")
	var grey := list.get_child(1)
	_check(grey.find_child("RoomWhy", true, false) != null and _t("รุ่นแอปไม่ตรงกัน: เจ้าห้อง {host} · คุณ {mine} — อัปเดตให้เป็นรุ่นเดียวกันก่อน").format({"host": "0.3", "mine": Version.APP_VER.get_slice(" ", 1)}) == (grey.find_child("RoomWhy", true, false) as Label).text,
		tag + ": the mismatched row is greyed with its reason")
	await _layout_ok(lobby, tag + " found rows")
	if save and lang == "th":
		_save("lobby_find_th.png")
	elif save:
		_save("lobby_find_en.png")
	# 3. connecting
	_fake.set("st", &"connecting")
	_fake.emit_signal("state_changed", &"connecting")
	await _frames(2)
	_check(str(lobby.call("view")) == "connecting" and (lobby.get_node("%ConnectBox") as Control).visible
		and (lobby.get_node("%ConnectLabel") as Label).text == _t("กำลังเชื่อมต่อ…"), tag + ": connecting shows กำลังเชื่อมต่อ… and cancel")
	await _layout_ok(lobby, tag + " connecting")
	# 4. hosting, two IPs, discovery off
	_set_host()
	await _frames(2)
	var ips := lobby.get_node("%HostIps") as Label
	_check(str(lobby.call("view")) == "room" and ips.visible and ips.text.contains("192.168.1.20") and ips.text.contains("10.0.0.7"), tag + ": the host card lists both IPs (%s)" % ips.text)
	_check((lobby.get_node("%DiscOff") as Label).visible and (lobby.get_node("%HostHelp") as Label).visible, tag + ": discovery off is said on the host card, with the help line")
	var copy := lobby.get_node("%CopyIpButton") as Button
	_check(copy.visible and not copy.disabled and copy.text == _t("คัดลอก IP") and ips.get_theme_font_size(&"font_size") >= 28,
		tag + ": the IP is large (%d px) with a copy button" % ips.get_theme_font_size(&"font_size"))
	copy.pressed.emit()
	_check(DisplayServer.clipboard_get() == "192.168.1.20" and copy.text == _t("คัดลอกแล้ว"), tag + ": copy puts the first IP on the clipboard (%s)" % DisplayServer.clipboard_get())
	lobby.call("refresh")
	_check(not (lobby.get_node("%PickButton") as Control).visible and (lobby.get_node("%LeaveButton") as Button).text == _t("ปิดห้อง"),
		tag + ": the host has no army pick and a close-room button")
	await _layout_ok(lobby, tag + " hosting")
	# 5. joined, six members with long names
	_set_joined(1, "deck")
	await _frames(2)
	var members := lobby.get_node("%MemberList") as Control
	_check(members.get_child_count() == 6, tag + ": six member rows")
	var host_row := (members.get_child(0).find_child("MemberName", true, false) as Label).text
	var me_row := (members.get_child(1).find_child("MemberName", true, false) as Label).text
	_check(host_row == NAMES[0] + " " + _t("(เจ้าห้อง)") and me_row == NAMES[1] + " " + _t("(คุณ)"), tag + ": host and you tags (%s / %s)" % [host_row, me_row])
	_check((members.get_child(3).find_child("MemberWhere", true, false) as Label).text == _t("กำลังจัดกองทัพ"), tag + ": a where line per member")
	_check((members.get_child(4).find_child("MemberWhere", true, false) as Label).text == _t("การเชื่อมต่อหลุด — กำลังต่อใหม่…"), tag + ": a reconnecting member says so")
	var pick := lobby.get_node("%PickButton") as Button
	_check(pick.visible and pick.text == _t("กองทัพที่อยากใช้: {army}").format({"army": _t("ให้เจ้าห้องเลือก")}), tag + ": the army pick starts at let the host choose (%s)" % pick.text)
	_check((lobby.get_node("%LeaveButton") as Button).text == _t("ออกจากห้อง") and (lobby.get_node("%RoomTitle") as Label).text == _t("ห้องของ {name}").format({"name": NAMES[0]}),
		tag + ": a member leaves the room; the card names the host's room")
	await _layout_ok(lobby, tag + " joined")
	if save and lang == "th":
		_save("lobby_room_th.png")
	# 6. the setup seat list
	_set_joined(1, "setup")
	await _frames(2)
	var seats := lobby.get_node("%SeatList") as Control
	_check(seats.visible and seats.get_child_count() == 6 and (lobby.get_node("%SeatsTitle") as Label).text == _t("ที่นั่ง"), tag + ": six seat rows under ที่นั่ง")
	var sits := 0
	var stands := 0
	for r in seats.get_children():
		if r.find_child("SitButton", true, false) != null:
			sits += 1
		if r.find_child("StandButton", true, false) != null:
			stands += 1
	_check(sits == 2 and stands == 1, tag + ": sit here on the two bot seats, leave on my own (%d / %d)" % [sits, stands])
	var bot_text := (seats.get_child(2).find_child("SeatText", true, false) as Label).text
	var fac2 := GameData.factions()[2]
	var want := _t("ทีม {n} · {owner} · {army}").format({"n": 2, "owner": _t("บอท"), "army": _t(str(GameData.faction(fac2).get("nm", fac2)))})
	_check(bot_text == want, tag + ": a bot seat row reads %s" % want, bot_text)
	var mine := (seats.get_child(1).find_child("SeatText", true, false) as Label).text
	_check(mine == _t("ทีม {n} · {owner} · {army}").format({"n": 2, "owner": _t("(คุณ)"), "army": _t("สุ่ม")}), tag + ": my seat row (%s)" % mine)
	await _layout_ok(lobby, tag + " seats")
	if save and lang == "en":
		_save("lobby_seats_en.png")
	# every refused key in this size and language
	_set_offline()
	lobby.call("refresh")
	for key in KEYS:
		_fake.emit_signal("refused", key, _args(key))
		await _frames(1)
		var reason := str(lobby.call("reason_text"))
		_check(reason == _reason(key), tag + ": refused %s shows its reason" % key, reason)
	await _frames(1)
	await _layout_ok(lobby, tag + " refused (last key)")


## Joining, cancelling, hosting, closing (with the question), the pick and the seat claims through the buttons.
func _check_flows(lobby: Node) -> void:
	_set_offline()
	_fake.set("found_rows", _rows())
	lobby.call("refresh")
	await _frames(2)
	var list := lobby.get_node("%FoundList") as Control
	_fake.set("calls", [])
	(list.get_child(1).find_child("JoinButton", true, false) as Button).pressed.emit()
	await _frames(1)
	_check(_fake.calls_of("join").is_empty() and str(lobby.call("reason_text")).begins_with("รุ่นแอปไม่ตรงกัน"), "tapping the greyed row shows its reason and never joins")
	(list.get_child(0).find_child("JoinButton", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(_fake.calls_of("join") == [["join", "192.168.1.30", 24680]] and str(lobby.call("view")) == "connecting", "tapping เข้าร่วม joins that host's ip and port", str(_fake.calls_of("join")))
	(lobby.get_node("%CancelButton") as Button).pressed.emit()
	await _frames(2)
	_check(_fake.calls_of("leave").size() == 1 and str(lobby.call("view")) == "find", "cancel leaves and returns to the list")
	(lobby.get_node("%HostButton") as Button).pressed.emit()
	await _frames(2)
	_check(_fake.calls_of("host").size() == 1 and str(lobby.call("view")) == "room" and bool(_fake.call("is_host")), "เปิดห้อง hosts a room and shows the room card")
	var confirm := lobby.get_node("%Confirm") as Control
	(lobby.get_node("%LeaveButton") as Button).pressed.emit()
	await _frames(1)
	_check(confirm.visible and _fake.calls_of("leave").size() == 1, "ปิดห้อง asks first (ปิดห้อง? เพื่อนทุกคนจะหลุดจากห้อง)")
	_check((lobby.get_node("%ConfirmText") as Label).text == "ปิดห้อง? เพื่อนทุกคนจะหลุดจากห้อง", "the question's text")
	await _layout_ok(lobby, "the close-room question")
	_check(bool(lobby.call("handle_back")) and not confirm.visible, "back closes the question first")
	(lobby.get_node("%LeaveButton") as Button).pressed.emit()
	await _frames(1)
	(lobby.get_node("%ConfirmYes") as Button).pressed.emit()
	await _frames(2)
	_check(_fake.calls_of("leave").size() == 2 and str(lobby.call("view")) == "find" and not confirm.visible, "yes closes the room (leave) and returns to the list")
	# a member: pick and claims
	_set_joined(1, "setup")
	await _frames(2)
	_fake.set("calls", [])
	(lobby.get_node("%PickButton") as Button).pressed.emit()
	await _frames(1)
	var first := GameData.factions()[0]
	_check(_fake.calls_of("set_pick") == [["set_pick", first]], "the army pick cycles to the first army (%s)" % first, str(_fake.calls_of("set_pick")))
	var pick := lobby.get_node("%PickButton") as Button
	_check(pick.text.contains(_t(str(GameData.faction(first).get("nm", first)))), "and names it (%s)" % pick.text)
	var seats := lobby.get_node("%SeatList") as Control
	(seats.get_child(2).find_child("SitButton", true, false) as Button).pressed.emit()
	(seats.get_child(1).find_child("StandButton", true, false) as Button).pressed.emit()
	await _frames(1)
	_check(_fake.calls_of("claim") == [["claim", 2], ["claim", -1]], "นั่งที่นี่ claims seat 2, ลุกจากที่นั่ง claims -1", str(_fake.calls_of("claim")))
	# a SETUP message refreshes the seats (the host changed a seat)
	var s: Array[Dictionary] = _fake.get("seats")
	s[4]["owner"] = 2
	_fake.emit_signal("message", 0, NetProto.SETUP, {"open": true, "seats": s})
	await _frames(1)
	var sits := 0
	for r in seats.get_children():
		if r.find_child("SitButton", true, false) != null:
			sits += 1
	_check(sits == 1, "a SETUP from the host updates the seat rows (one bot seat left)")
	# lost while in the room: back to the list with the reason
	_fake.set("st", &"finding")
	_fake.set("slot", -1)
	_fake.emit_signal("state_changed", &"finding")
	_fake.emit_signal("lost", "host_left")
	await _frames(2)
	_check(str(lobby.call("view")) == "find" and str(lobby.call("reason_text")) == "เจ้าห้องปิดห้องแล้ว", "the host leaving: back to the list with เจ้าห้องปิดห้องแล้ว")


## The IP field: only a dotted IPv4 address with an optional :port joins; anything else says IP ไม่ถูกต้อง.
func _check_ip(lobby: Node) -> void:
	var ip := lobby.get_node("%IpEdit") as LineEdit
	_check(ip.placeholder_text == "ใส่ IP ของเจ้าห้อง", "the IP field's placeholder")
	for bad in ["999.1.1.1", "a.b.c.d", "example.com", "192.168.1.5:0", "192.168.1.5:70000", ""]:
		_fake.set("calls", [])
		ip.text = bad
		lobby.call("join_ip")
		await _frames(1)
		_check(_fake.calls_of("join").is_empty() and str(lobby.call("reason_text")) == "IP ไม่ถูกต้อง", "IP '%s' is refused with IP ไม่ถูกต้อง" % bad)
	_fake.set("calls", [])
	ip.text = " 192.168.1.5:24680 "
	lobby.call("join_ip")
	await _frames(1)
	_check(_fake.calls_of("join") == [["join", "192.168.1.5", 24680]] and str(lobby.call("reason_text")) == "", "192.168.1.5:24680 joins that address and port", str(_fake.calls_of("join")))
	_set_offline()
	ip.text = "10.0.0.9"
	lobby.call("join_ip")
	await _frames(1)
	var j: Array = _fake.calls_of("join")
	_check(j.size() == 2 and j[1] == ["join", "10.0.0.9", 0], "a bare IP joins the default port (0)", str(j))
	_set_offline()
	ip.text = ""
	lobby.call("refresh")


func _check_refused(lobby: Node) -> void:
	_set_offline()
	lobby.call("refresh")
	_fake.emit_signal("refused", "wrong_app", {"host": "ใหม่ 0.6", "mine": Version.APP_VER})
	await _frames(2)
	_check((lobby.get_node("%Reason") as Label).visible, "a refusal shows its reason in the list area")
	_save("lobby_refused.png")


# ---- fake Net set-ups ----

func _rows() -> Array[Dictionary]:
	return [{"t": "a1b2c3d4", "ip": "192.168.1.30", "port": 24680, "nm": NAMES[0], "n": 2, "max": 6, "st": "deck", "app": Version.APP_VER,
			"rules": Version.RULES_V, "ok": true, "why": "", "args": {}},
		{"t": "e5f6a7b8", "ip": "192.168.1.31", "port": 24680, "nm": NAMES[2], "n": 1, "max": 6, "st": "deck", "app": "ใหม่ 0.3",
			"rules": Version.RULES_V, "ok": false, "why": "wrong_app", "args": {"host": "ใหม่ 0.3", "mine": Version.APP_VER}}]


func _set_offline() -> void:
	_fake.set("host_flag", false)
	_fake.set("slot", -1)
	_fake.set("member_list", [] as Array[Dictionary])
	_fake.set("room_st", "deck")
	_fake.set("st", &"finding")
	_fake.emit_signal("state_changed", &"finding")


func _set_host() -> void:
	_fake.set("host_flag", true)
	_fake.set("slot", 0)
	_fake.set("ips", PackedStringArray(["192.168.1.20", "10.0.0.7"]))
	_fake.set("disc", false)
	_fake.set("member_list", [{"slot": 0, "nm": NAMES[0], "where": "deck", "pick": "", "here": true},
		{"slot": 1, "nm": NAMES[1], "where": "deck", "pick": "", "here": true}] as Array[Dictionary])
	_fake.set("st", &"hosting")
	_fake.emit_signal("state_changed", &"hosting")


func _set_joined(me: int, room: String) -> void:
	var wheres := ["deck", "deck", "setup", "army", "arena", "menu"]
	var list: Array[Dictionary] = []
	for i in 6:
		list.append({"slot": i, "nm": NAMES[i], "where": wheres[i], "pick": "", "here": i != 4})
	_fake.set("host_flag", false)
	_fake.set("slot", me)
	_fake.set("member_list", list)
	_fake.set("room_st", room)
	var facs := GameData.factions()
	_fake.set("seats", [{"team": 0, "owner": 0, "fac": facs[0]}, {"team": 1, "owner": me, "fac": ""}, {"team": 1, "owner": -1, "fac": facs[2]},
		{"team": 2, "owner": 2, "fac": facs[3]}, {"team": 2, "owner": -1, "fac": ""}, {"team": 3, "owner": 3, "fac": facs[5]}] as Array[Dictionary])
	_fake.set("st", &"joined")
	_fake.emit_signal("state_changed", &"joined")
	_fake.emit_signal("members_changed")


func _args(key: String) -> Dictionary:
	match key:
		"wrong_app":
			return {"host": "ใหม่ 0.6", "mine": Version.APP_VER}
		"wrong_rules", "wrong_net":
			return {"host": 11, "mine": Version.RULES_V}
		"full":
			return {"n": 6, "max": 6}
		"port_busy":
			return {"port": 24680}
	return {}


## OnlineText is loaded at run time: a class that uses the I18n autoload cannot compile before the autoloads exist
func _reason(key: String) -> String:
	return str((load("res://ui/online_text.gd") as GDScript).call("reason", key, _args(key)))


func _t(th: String) -> String:
	return str(root.get_node(^"I18n").call("t", th))


# ---- shared checks ----

## Layout rules (LOBBY_SPEC §7.1); content inside the ScrollContainer is checked horizontally only (it scrolls), and the
## English check ignores the players' names (never translated).
func _layout_ok(lobby: Node, tag: String) -> void:
	var lay := _layout_problems(lobby)
	_check(lay.is_empty(), tag + ": nothing sticks out, no buttons overlap, targets >= 44 px", ", ".join(lay))
	if bool(root.get_node(^"I18n").get("english")):
		var thai := _thai_in(lobby)
		_check(thai.is_empty(), tag + ": no Thai on screen in English except player names", ", ".join(thai))


func _layout_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var vis := root.get_visible_rect()
	_walk(screen, func(c: Control) -> void:
		var r := c.get_global_rect()
		var sc := _scroll_of(c, screen)
		if sc != null:
			var sr := sc.get_global_rect()
			if r.position.x < sr.position.x - 1.0 or r.end.x > sr.end.x + 1.0:
				out.append("%s wider than the scroll area %s in %s" % [c.name, str(r), str(sr)])
		elif r.position.x < vis.position.x - 1.0 or r.position.y < vis.position.y - 1.0 or r.end.x > vis.end.x + 1.0 or r.end.y > vis.end.y + 1.0:
			out.append("%s outside the canvas %s" % [c.name, str(r)])
		var p := c.get_parent() as Control
		if p != null and not p is ScrollContainer and c != screen:
			var pr := p.get_global_rect()
			if r.position.x < pr.position.x - 1.0 or r.position.y < pr.position.y - 1.0 or r.end.x > pr.end.x + 1.0 or r.end.y > pr.end.y + 1.0:
				out.append("%s outside its parent %s: %s in %s" % [c.name, p.name, str(r), str(pr)])
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			out.append("%s smaller than 44x44 %s" % [c.name, str(r.size)])
		if c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and (c as Label).get_minimum_size().x > r.size.x + 1.0:
			out.append("%s text wider than its box" % c.name)
		var buttons: Array[Control] = []
		for s in c.get_children():
			if s is Button and (s as Control).is_visible_in_tree():
				buttons.append(s)
		for i in buttons.size():
			for j in range(i + 1, buttons.size()):
				if buttons[i].get_global_rect().intersection(buttons[j].get_global_rect()).get_area() > 1.0:
					out.append("%s overlaps %s" % [buttons[i].name, buttons[j].name]))
	return out


func _scroll_of(c: Node, stop: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and p != stop:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	_scan(node, out)
	return out


func _scan(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	var texts := PackedStringArray()
	if node is Label or node is Button:
		texts.append(str(node.get("text")))
	if node is LineEdit and node.name != &"NameEdit":
		texts.append((node as LineEdit).placeholder_text)
		texts.append((node as LineEdit).text)
	for t in texts:
		var rest := t
		for n in NAMES:
			rest = rest.replace(n, "")
		rest = rest.replace(str(_fake.get("nm")), "")
		if _thai_re.search(rest) != null:
			out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, out)


func _machine_files() -> String:
	var out := ""
	for p in ["user://settings.cfg", "user://net.cfg"]:
		out += "%s %d:%s|" % [p, FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else p + " none|"
	return out


func _resize(sz: Vector2i) -> void:
	root.size = sz
	await _frames(SETTLE)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	if _fake != null:
		_fake.name = "FakeNet"
		_fake.queue_free()
	if _real_net != null:
		_real_net.name = "Net"
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
