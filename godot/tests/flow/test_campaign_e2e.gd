extends SceneTree
## The whole public campaign with every real screen (integration of tracks A–C, CAMPAIGN_SPEC §1.1), headless, min,
## Thai, egg figure, touch off, test settings and campaign save files, test clock = week 2967:
## main menu → เล่นกับบอท → the deck; E at the campaign table → the real difficulty screen; → then E (keys) chooses
## hard → the real galaxy; a planet with a purge event → its card → the brief → ออกรบ (min: a cut) → the real mission
## screen (where = arena, battle music); the world is fast-forwarded (MissionWorld.simulate, test_god) until every wave
## is down → finished → the real report (win, the score of CampaignRules.score, coins saved once, where = deck, deck
## music); เล่นอีกครั้ง → the same mission again (same seed); pause → leave → confirm → the report says withdrew, the
## wallet is unchanged; กลับยาน → the deck with the avatar still at the table and nothing of the campaign left on top.
## Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_campaign_e2e.gd

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_campaign_e2e.cfg"
const SAVE := "user://test_campaign_e2e.json"
const NOW := 1794657600      # Sat 14 Nov 2026 12:00 UTC = week 2967

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var CF: Script


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


## ดาวที่มีเหตุการณ์ purge ในสัปดาห์นี้ (เลือกดาวที่มีเหตุการณ์น้อยสุด): [planet id, event idx]
func _purge_planet(week: int) -> Array:
	var best: Array = []
	var best_n := 99
	for p: Dictionary in CampaignGalaxy.week(week)["planets"]:
		var evs: Array = p["events"]
		for i in evs.size():
			if str(evs[i]["type"]) == "purge" and evs.size() < best_n:
				best = [str(p["id"]), i]
				best_n = evs.size()
	return best


func _run() -> void:
	CF = load("res://app/campaign_flow.gd")
	CF.set("test_scenes", {})
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
	_check(str(hall.call("station")) == "campaign", "the avatar stands at the campaign table")
	await _press(KEY_E)
	var ds: Node = _app().call("current")
	_check(ds != null and ds.get_script() != null and ds.get_script().resource_path == CF.DIFFICULTY.replace(".tscn", ".gd")
		and int(_app().call("depth")) == 3, "E opens the real difficulty screen over the deck")
	_check(ds.has_method("stages") and (ds.call("stages") as Array).size() == 4, "it shows four hero cards")
	await _press(KEY_RIGHT)
	_check(str(ds.call("selected")) == "hard", "→ selects hard (%s)" % str(ds.call("selected")))
	await _press(KEY_E)
	await _frames(3)
	var gs: Variant = _app().call("current")
	_check(_kind(gs) == "galaxy" and int(_app().call("depth")) == 3, "E chooses hard: the real galaxy replaces the difficulty screen")
	if _kind(gs) != "galaxy":
		_finish()
		return
	_check(gs.week == 2967 and gs.difficulty == "hard" and CampaignSave.last_difficulty() == "hard",
		"the galaxy is week 2967 at hard, and hard is remembered")
	var pick := _purge_planet(2967)
	_check(pick.size() == 2, "week 2967 has a purge event (%s)" % str(pick))
	if pick.size() != 2:
		_finish()
		return
	gs.select_planet(pick[0])
	await _frames(2)
	_check(gs.card_open() and gs.planet_id == pick[0], "planet %s: its card opens" % pick[0])
	gs.open_brief(pick[1])
	await _frames(2)
	var spec: Dictionary = gs.current_spec()
	_check(gs.brief_open() and str(spec["primary"]["type"]) == "purge" and str(spec["difficulty"]) == "hard",
		"the brief shows the purge mission at hard")
	gs.brief().launch_button().pressed.emit()
	var ms: Variant = null
	for i in 30:
		await process_frame
		ms = _app().call("current")
		if _kind(ms) == "mission":
			break
	_check(_kind(ms) == "mission" and ms.has_method("world") and int(_app().call("depth")) == 4, "ออกรบ opens the real mission screen (depth 4)")
	if _kind(ms) != "mission":
		_finish()
		return
	await _play_to_win(ms, spec)
	var rs: Variant = await _wait_report()
	_check(rs != null and int(_app().call("depth")) == 4, "the real report replaces the mission (depth 4)")
	if rs == null:
		_finish()
		return
	var shown: Dictionary = rs.shown()
	var score: Dictionary = rs.get("score")
	_check(bool(score.get("win", false)) and str(shown["title"]) == _t("ผลภารกิจ: สำเร็จ"), "the report says success (%s)" % str(shown["title"]))
	_check(int(score["coins"]) > 0 and CampaignSave.coins() == int(score["coins"]),
		"the coins are saved once (%d, wallet %d)" % [int(score["coins"]), CampaignSave.coins()])
	_check(CampaignSave.is_repeat(spec), "the event is recorded as cleared")
	_check(_where() == "deck" or _where() == "", "friends see the deck again (%s)" % _where())
	var music := root.get_node_or_null(^"Music")
	if music != null and "mood" in music:
		_check(str(music.get("mood")) == "deck", "the deck music is back")
	var wallet := CampaignSave.coins()
	# เล่นอีกครั้ง → ภารกิจเดิม (seed เดิม) แล้วออกกลางคัน
	(rs.buttons()[0] as Button).pressed.emit()
	await _frames(3)
	ms = _app().call("current")
	_check(_kind(ms) == "mission" and int(_app().call("depth")) == 4 and ms.get("spec") == spec,
		"เล่นอีกครั้ง starts the same mission again (same seed %s)" % str(spec["seed"]))
	if _kind(ms) != "mission":
		_finish()
		return
	for i in 400:
		if ms.call("playing"):
			break
		await process_frame
	_app().call("back")
	await _frames(2)
	_check(ms.call("paused"), "Esc pauses the mission")
	ms.quit_button.pressed.emit()
	await _frames(1)
	ms.confirm_yes.pressed.emit()
	rs = await _wait_report()
	_check(rs != null and str(rs.shown()["title"]) == _t("ผลภารกิจ: ถอนตัว"), "leaving the mission shows the report: withdrew")
	_check(CampaignSave.coins() == wallet, "withdrawing earns nothing (wallet %d)" % CampaignSave.coins())
	if rs == null:
		_finish()
		return
	# กลับยาน
	(rs.buttons()[2] as Button).pressed.emit()
	await _frames(3)
	_check(_app().call("current") == hall and int(_app().call("depth")) == 2, "กลับยาน lands on the deck (depth 2)")
	_check(not CF.call("running") and int(CF.get("base_depth")) == -1, "the campaign flow is closed")
	var av := world.get("avatar") as Node3D
	_check(Vector2(av.global_position.x, av.global_position.z).distance_to(f) < 0.3, "the avatar still stands at the table")
	_check(_where() == "deck" or _where() == "", "friends see the deck (%s)" % _where())
	_finish()


func _play_to_win(ms: Node, spec: Dictionary) -> void:
	for i in 400:
		if ms.call("playing"):
			break
		await process_frame
	_check(ms.call("playing"), "the mission plays after its intro banner")
	_check(_where() == "arena", "friends see 'arena' during the mission (%s)" % _where())
	var w = ms.world()
	w.test_god = true
	for i in 300:
		if w.is_ended():
			break
		for e in w.enemies():
			var t: Dictionary = w.hit_target(e)
			if not t.is_empty():
				(t["node"] as Object).call("take_hit", {"amount": 99999, "kind": &"gun", "dir": Vector3.FORWARD, "knockback": 0.0, "stagger": false})
				w.obj.shot()
				w.obj.hit()
		w.simulate(0.5)
		await process_frame
	_check(w.is_ended() and str(w.result()["outcome"]) == "win", "every wave of %s is down: won" % str(spec["planet"]))


func _wait_report() -> Variant:
	for i in 600:
		var c: Variant = _app().call("current")
		if _kind(c) == "report":
			await _frames(2)
			return c
		await process_frame
	return null


## ชนิดหน้าแคมเปญที่ CampaignFlow ติดป้ายไว้ ("" = ไม่ใช่)
func _kind(n: Variant) -> String:
	if not n is Node or not (n as Node).has_meta(&"campaign_screen"):
		return ""
	return str((n as Node).get_meta(&"campaign_screen"))


func _where() -> String:
	var net := root.get_node_or_null(^"Net")
	return str(net.get("_where")) if net != null else ""


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


func _t(s: String) -> String:
	return str(root.get_node(^"I18n").call("t", s))


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := _app()
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	CampaignSave.path = CampaignSave.PATH
	CampaignWeek.test_now = -1
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
