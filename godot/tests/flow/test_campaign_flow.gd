extends SceneTree
## The campaign flow end to end, headless (CAMPAIGN_SPEC §1.1–§1.3, §7 track A): main menu → เล่นกับบอท → the deck;
## at the campaign table's front ring E opens the difficulty screen (the real one, through its choose()); hard → the
## galaxy of week 2967 (test clock); tapping planet p00 on the map opens its card, the first event opens the brief,
## ออกรบ (min: no fade tween) launches a stand-in mission (tests/fixtures/campaign_flow/stub_mission) that finishes with
## a scripted result → the report shows the score of CampaignRules.score and the wallet, coins are saved once; Esc →
## the galaxy (its coins line updated, the planet marked cleared), Esc twice more → the deck with the avatar still at
## the projector. Then the fixture pack room (tests/fixtures/pack_rooms_campaign): the third card and the dropship
## station both open the same flow, Esc on the difficulty screen and leaving from the galaxy land back in the room.
## English mode: the galaxy's texts are English. Graphics level min, test settings and campaign save files. Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_campaign_flow.gd

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_campaign_flow.cfg"
const SAVE := "user://test_campaign_flow.json"
const STUB_MISSION := "res://tests/fixtures/campaign_flow/stub_mission.tscn"
const CAMP_ROOMS := "res://tests/fixtures/pack_rooms_campaign"
const NOW := 1794657600      # Sat 14 Nov 2026 12:00 UTC = week 2967

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var thai_re := RegEx.create_from_string("[฀-๿]")
## CampaignFlow and the screens use the App autoload: load them at run time (not as globals at compile time)
var CF: Script
const DIFF_SCENE := "res://ui/screens/difficulty_screen.tscn"


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_gfx", "min")
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	CampaignWeek.test_now = NOW
	CampaignSave.path = SAVE
	CampaignSave.reset()
	var scene: PackedScene = load(SCENE)
	_main = scene.instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _result() -> Dictionary:
	return {"v": 1, "outcome": "win", "time_s": 185.0, "kills": {"rusher": 12, "gunner": 5, "brute": 2, "boss": 1, "structure": 0},
		"shots": 60, "hits": 39, "damage_taken": 90, "downs": 0, "secondary_done": []}


func _run() -> void:
	CF = load("res://app/campaign_flow.gd")
	CF.set("test_scenes", {"mission": STUB_MISSION})
	await _frames(3)
	var menu: Node = _app().call("current")
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	_check(hall != null and hall.has_method("open_campaign"), "เล่นกับบอท opens the deck")
	var world: Node3D = hall.get("world")
	var f: Vector2 = HallLayout.STATIONS["campaign"]["front"]
	world.call("place_avatar", Vector3(f.x, 0.0, f.y), 0.0)
	await _physics(4)
	_check(str(hall.call("station")) == "campaign", "the front ring of the campaign table is its station")
	var use: Button = hall.get_node("%UseButton")
	_check(use.visible and use.text.contains("โต๊ะแคมเปญ"), "the prompt names the campaign table: " + use.text)
	await _press(KEY_E)
	var ds: Node = _app().call("current")
	_check(_is_diff(ds) and int(_app().call("depth")) == 3, "E opens the difficulty screen over the deck (depth 3)")
	_check(str(CF.get("from")) == "deck" and int(CF.get("base_depth")) == 2, "the flow remembers the deck (base depth 2)")
	ds.call("choose", &"hard")
	await _frames(3)
	var gs: Variant = _app().call("current")
	_check(_is_galaxy(gs) and int(_app().call("depth")) == 3, "hard opens the galaxy in place of the difficulty screen")
	_check(gs.week == 2967 and gs.difficulty == "hard", "the galaxy is week 2967 at hard")
	_check(gs.countdown_text().contains("1 วัน 12 ชม."), "the countdown says 1 day 12 h to the Monday reroll: " + gs.countdown_text())
	var mp: Variant = gs.map()
	_check(mp.size.x > 100.0 and mp.size.y > 100.0, "the map fills the screen (%s)" % str(mp.size))
	mp.tap(mp.screen_pos(0))
	await _frames(2)
	_check(gs.card_open() and gs.planet_id == "p00", "tapping p00 on the map opens its card")
	var card: Variant = gs.card()
	var pw := CampaignGalaxy.planet_week(2967, "p00")
	_check(card.rows().size() == (pw["events"] as Array).size(), "one row per event (%d)" % card.rows().size())
	# a tap on the first row, through the list's own hit test (headless viewports pick no hovered control)
	var rr: Rect2 = card.row_global_rect(0)
	var lst: Control = card.get("_list")
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = rr.get_center() - lst.get_global_rect().position
		lst.call("_gui_input", mb)
		await _frames(1)
	await _frames(2)
	_check(gs.brief_open() and not gs.card_open(), "tapping the first event row opens the brief (%s)" % str(rr))
	var spec: Dictionary = gs.current_spec()
	_check(gs.brief().side_lines().size() == maxi((spec["secondary"] as Array).size(), 1), "the brief lists the side objectives")
	# review fix: the brief states the rules that end or prolong a mission (time limit, pickup, revives)
	var br = gs.brief()
	var keep: Dictionary = br.spec
	for ty in ["purge", "defend", "rescue", "destroy_camp"]:
		for df in ["normal", "catastrophe"]:
			var sp := keep.duplicate(true)
			sp["primary"] = {"type": ty, "idx": 0}
			sp["difficulty"] = df
			br.show_spec(sp)
			var tx: String = br.text()
			var want := PackedStringArray()
			if ty == "rescue":
				want.append(str(root.get_node(^"I18n").call("t", br.LIMIT)).format({"m": 10}))
			if ty == "defend":
				want.append(str(root.get_node(^"I18n").call("t", br.HOLD)).format({"m": 3}))
			if ty == "destroy_camp":
				want.append(str(root.get_node(^"I18n").call("t", br.EXTRACT)))
			var rv := int(CampaignRules.difficulty(df)["revives"])
			want.append(str(root.get_node(^"I18n").call("t", "ล้มแล้วจบ" if rv == 0 else "ลุกได้ {n} ครั้ง")).format({"n": rv}))
			var miss := Array(want).filter(func(w: String) -> bool: return not tx.contains(w))
			_check(miss.is_empty(), "brief %s %s states its rules" % [ty, df], ", ".join(miss))
	br.show_spec(keep)
	gs.brief().launch_button().pressed.emit()
	gs.brief().launch_button().pressed.emit()
	await _frames(3)
	var ms: Node = _app().call("current")
	_check(ms != null and ms.get("spec") == spec and int(_app().call("depth")) == 4, "ออกรบ launches the mission with the brief's spec (depth 4)")
	_check(int(ms.get("started")) == 1, "a double press starts one mission")
	var res := _result()
	res["secondary_done"] = []
	for i in (spec["secondary"] as Array).size():
		res["secondary_done"].append(i == 0)
	ms.call("finish", res)
	await _frames(3)
	var rs: Variant = _app().call("current")
	var sc := CampaignRules.score(spec, res)
	_check(rs != null and rs.has_method("shown") and int(_app().call("depth")) == 4, "the report replaces the mission")
	var shown: Dictionary = rs.shown()
	_check(str(shown["total"]).contains(str(sc["total"])) and str(shown["grade"]) == str(sc["grade"]),
		"the report shows score %d grade %s (%s)" % [int(sc["total"]), str(sc["grade"]), str(shown["total"])])
	_check(str(shown["earned"]).contains(str(sc["coins"])) and str(shown["wallet"]).contains(str(CampaignSave.coins())),
		"it shows the coins earned and the wallet (%s / %s)" % [str(shown["earned"]), str(shown["wallet"])])
	_check(CampaignSave.coins() == int(sc["coins"]), "the coins are saved once (%d)" % CampaignSave.coins())
	var tiles: Array = shown["tiles"]
	_check(tiles.size() == 6 and str(tiles[0][1]) == "20" and str(tiles[1][1]) == "65 %" and str(tiles[2][1]) == "3:05",
		"stats: 20 kills, 65 %% accuracy, 3:05 (%s)" % str(tiles))
	_check(FileAccess.file_exists(SAVE), "the campaign save is written to user://")
	await _press(KEY_ESCAPE)
	_check(_app().call("current") == gs and int(_app().call("depth")) == 3, "Esc on the report goes back to the galaxy")
	_check(str(gs.coins_text()).contains(str(CampaignSave.coins())), "the galaxy's coins line shows the wallet: " + str(gs.coins_text()))
	var cleared := false
	for p: Dictionary in mp.planets:
		if str(p["id"]) == "p00":
			cleared = bool(p["cleared"])
	_check(cleared, "p00 is marked cleared on the map")
	_check(gs.card_open() and not gs.brief_open(), "back from the report the planet's card shows, not the old brief")
	_check(bool(card.rows()[0]["done"]) and str(card.rows()[0]["reward"]).contains("ผ่านแล้ว"), "and its event row says cleared", str(card.rows()[0]))
	await _press(KEY_ESCAPE)
	_check(not gs.card_open(), "Esc closes the card")
	await _press(KEY_ESCAPE)
	await _frames(3)
	_check(_app().call("current") == hall and int(_app().call("depth")) == 2, "Esc on the map leaves the campaign to the deck")
	var av := world.get("avatar") as Node3D
	_check(Vector2(av.global_position.x, av.global_position.z).distance_to(f) < 0.3 and str(hall.call("station")) == "campaign",
		"the avatar still stands at the projector's ring")
	# English
	_app().call("set_lang", "en")
	await _press(KEY_E)
	ds = _app().call("current")
	ds.call("choose", &"normal")
	await _frames(3)
	gs = _app().call("current")
	gs.select_planet("p20")
	gs.open_brief(0)
	await _frames(2)
	var thai := _thai_labels(gs)
	_check(thai.is_empty(), "English mode: no Thai on the galaxy, card or brief", ", ".join(thai))
	# review fix: back on the difficulty screen opened from the galaxy chip returns to the galaxy (real screens)
	var diff0 := str(gs.get("difficulty"))
	gs.change_difficulty()
	await _frames(2)
	_check(str((_app().call("current") as Node).scene_file_path).ends_with("difficulty_screen.tscn"), "the galaxy chip opens the difficulty screen")
	_app().call("back")
	await _frames(2)
	gs = _app().call("current")
	_check(str(gs.scene_file_path).ends_with("galaxy_screen.tscn") and str(gs.get("difficulty")) == diff0,
		"back returns to the galaxy at the same difficulty", str(gs))
	gs.select_planet("p20")
	gs.open_brief(0)
	await _frames(1)
	# review fix: the week rolls over while the galaxy is open -> the next countdown tick loads the new week
	var wk0 := int(gs.get("week"))
	CampaignWeek.test_now = NOW + 7 * 86400
	(gs.timer() as Timer).timeout.emit()
	await _frames(2)
	_check(int(gs.get("week")) == wk0 + 1 and not gs.card_open() and not gs.brief_open(),
		"a week rollover on an open galaxy loads the new week and closes last week's brief", str(gs.get("week")))
	_check(str(gs.get("_note_key")) == str(gs.NEW_WEEK), "and tells the player new events arrived")
	CampaignWeek.test_now = NOW
	CF.call("leave")
	await _frames(3)
	_app().call("set_lang", "th")
	_check(_app().call("current") == hall, "leave() lands on the deck")
	await _check_room(hall)
	_finish()


## The fixture pack room: the card and the dropship both open the campaign; back lands in the room
func _check_room(hall: Node) -> void:
	Features.set_flag(&"online", true)
	hall.set("rooms_root", CAMP_ROOMS)
	hall.call("refresh")
	var room: Node = hall.call("enter_room", true)
	await _frames(3)
	_check(room != null and str(room.call("room_id")) == "camp_room" and int(_app().call("depth")) == 3, "the airlock opens the campaign room (depth 3)")
	if room == null:
		return
	room.call("open_cards", "cards_box")
	await _frames(2)
	var cards: Array = room.call("card_buttons")
	_check(cards.size() == 3, "the mode table has three cards")
	(cards[2] as Button).pressed.emit()
	await _frames(3)
	var ds: Node = _app().call("current")
	_check(_is_diff(ds) and int(_app().call("depth")) == 4 and str(CF.get("from")) == "room", "the campaign card opens the difficulty screen from the room")
	await _press(KEY_ESCAPE)
	_check(_app().call("current") == room and int(_app().call("depth")) == 3, "Esc on the difficulty screen goes back to the room")
	var lw: Node3D = room.get("world")
	lw.call("place_avatar", Vector3(4.4, 0.0, 1.0), -PI * 0.5)
	await _physics(4)
	_check(str(room.call("station")) == "dropship", "the dropship's front ring is its station")
	await _press(KEY_E)
	ds = _app().call("current")
	_check(_is_diff(ds) and int(CF.get("base_depth")) == 3, "E at the dropship opens the same flow (base depth 3)")
	ds.call("choose", &"veryhard")
	await _frames(3)
	var gs: Variant = _app().call("current")
	_check(_is_galaxy(gs) and gs.difficulty == "veryhard", "veryhard opens the galaxy")
	gs.leave()
	await _frames(3)
	_check(_app().call("current") == room and str(room.call("station")) == "dropship", "leaving lands in the room at the dropship")
	while int(_app().call("depth")) > 1:
		_app().call("pop")
		await _frames(2)
	Features.reset()


func _row_text(n: Node) -> String:
	var t := ""
	for c in n.find_children("*", "", true, false):
		if c is Label:
			t += (c as Label).text + " | "
		elif c is RichTextLabel:
			t += (c as RichTextLabel).get_parsed_text() + " | "
	return t


func _is_diff(n: Variant) -> bool:
	return n is Node and (n as Node).scene_file_path == DIFF_SCENE


func _is_galaxy(n: Variant) -> bool:
	return n is Node and (n as Node).scene_file_path == "res://ui/screens/galaxy_screen.tscn"


func _thai_labels(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in n.find_children("*", "", true, false):
		if not (c is CanvasItem) or not (c as CanvasItem).is_visible_in_tree():
			continue
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is Button:
			t = (c as Button).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).get_parsed_text()
		if t != "" and thai_re.search(t) != null:
			out.append(t)
	return out


func _press(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(3)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	CampaignSave.path = CampaignSave.PATH
	CampaignWeek.test_now = -1
	if CF != null:
		CF.set("test_scenes", {})
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
