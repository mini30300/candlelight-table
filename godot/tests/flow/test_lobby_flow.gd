extends SceneTree
## The whole new flow, headless (LOBBY_SPEC §7.2), across the three tracks: main menu → เล่นกับบอท → the lobby hall →
## hold W until the war table's station is active → E → battle setup → a 2-team bot game (kn vs or, 36", 3 rounds of
## objectives, 300 points, seed 4242) with egg figures → instant speed to the end panel → กลับล็อบบี้ → Esc back to the
## main menu, W held while leaving does not make the next game's camera drift (a second game). Input goes through
## Input.parse_input_event with keycode and physical keycode set, as a player's keyboard sends them. Uses a
## test settings file (never this machine's settings.cfg), graphics level min, Thai, egg figures. Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_lobby_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_lobby_flow.cfg"
const WALK_CAP_MS := 15000
const GAME_CAP_MS := 60000
## the hall's blockers from LOBBY_SPEC §2.1 (centre x, z, half x, half z) and its pillars (x, z, r)
## 0.3 (SHIP_LOBBY_SPEC §2.2, §12): the airlock (online) moved to the right wall and the treasure chest (round) was added
const RECTS := {"battle": [0.0, -2.0, 3.0, 2.0], "army": [-11.4, -1.0, 0.5, 2.6], "settings": [10.0, -1.0, 0.4, 0.4],
	"online": [11.95, 3.0, 0.15, 1.7], "exit": [0.0, 7.9, 1.2, 0.2]}
const ROUND_TABLE := [-5.0, 4.0, 1.3]
const VAULT := [5.0, 4.0, 1.2]
const PILLARS := [[-8.5, -5.0], [8.5, -5.0], [-8.5, 0.5], [8.5, 0.5], [-8.5, 5.5], [8.5, 5.5]]
const PILLAR_R := 0.45
const CLEAR := 0.25   # the avatar's centre stays at least this far from any blocker (its capsule is 0.35)

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _t0 := 0


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)   # never write this machine's settings.cfg from a test
	app.call("set_gfx", "min")
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	_main = scene.instantiate()
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
	var app := _app()
	# 1-2. the main menu, then เล่นกับบอท opens the hall
	var menu: Node = app.call("current")
	_check(menu != null and menu.get_node_or_null("%PlayButton") != null, "main.tscn opens the main menu")
	_check(root.get_viewport().get_camera_3d() == null, "no 3D camera draws under the first main menu (%s)" % _cam_name())
	if menu == null or menu.get_node_or_null("%PlayButton") == null:
		_finish()
		return
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = app.call("current")
	_check(hall != null and hall != menu and hall.has_method("station") and hall.get("world") != null, "เล่นกับบอท opens the lobby hall (%s)" % _name(hall))
	if hall == null or not hall.has_method("station") or hall.get("world") == null:
		_finish()
		return
	var world: Node = hall.get("world")
	var avatar := world.get("avatar") as Node3D
	var table := root.get_tree().get_first_node_in_group("table_view") as Node3D
	_check(avatar != null, "the hall world has an avatar")
	_check(table == null or not table.visible, "the battle table stays hidden in the hall")
	if avatar == null:
		_finish()
		return
	_log("hall open")

	# 3. hold W until the war table's station is active
	var start := avatar.global_position
	_key(KEY_W, true)
	var t := Time.get_ticks_msec()
	while str(hall.call("station")) != "battle" and Time.get_ticks_msec() - t < WALK_CAP_MS:
		await process_frame
	_key(KEY_W, false)
	await _frames(2)
	var walked := Vector2(avatar.global_position.x - start.x, avatar.global_position.z - start.z).length()
	_check(str(hall.call("station")) == "battle", "holding W reaches the war table's station in %d ms" % (Time.get_ticks_msec() - t))
	_check(walked >= 3.0, "the avatar walked at least 3 m (%.2f m, from %s to %s)" % [walked, _xz(start), _xz(avatar.global_position)])
	var inside := _blocker_at(avatar.global_position)
	_check(inside == "", "the avatar stands in no blocker", inside)
	_log("walked")

	# 4. E uses the station: battle setup
	_key(KEY_E, true)
	await _frames(1)
	_key(KEY_E, false)
	await _frames(3)
	var setup: Node = app.call("current")
	_check(setup != null and setup.has_method("set_teams") and setup.has_method("start"), "E at the war table opens battle setup (%s)" % _name(setup))
	if setup == null or not setup.has_method("start"):
		_finish()
		return

	# 5. two bot seats, a small quick table, then START
	setup.call("set_teams", 2)
	setup.call("set_per_team", 1)
	setup.call("set_seat", 0, "kn", false)
	setup.call("set_seat", 1, "or", false)
	_set_size(setup, "s")
	setup.call("set_goal", "obj")
	setup.call("set_rounds", 3)
	setup.call("set_budget", 300)
	setup.call("set_seed", 4242)
	var errs: PackedStringArray = setup.call("errors")
	_check(errs.is_empty(), "the setup is valid", str(errs))
	var started: bool = setup.call("start")
	await _frames(3)
	var battle: Node = app.call("current")
	_check(started and battle != null and battle.has_method("begin") and battle.has_method("is_over"), "START replaces setup with the battle screen (%s)" % _name(battle))
	if battle == null or not battle.has_method("is_over"):
		_finish()
		return
	_check(int(app.call("depth")) == 3, "the battle took setup's place (depth %d)" % int(app.call("depth")))
	table = root.get_tree().get_first_node_in_group("table_view") as Node3D
	var st: Object = _state(battle.get("runner"))
	_check(table != null and st != null, "the battle has a table and a rules state")
	if table == null or st == null:
		_finish()
		return
	var c: Dictionary = table.call("counts")
	var units := int((st.get("units") as Array).size())
	_check(str(c.get("style", "")) == "egg" and int(c.get("skinned", -1)) == 0, "the figures are eggs (style %s, skinned %d)" % [str(c.get("style", "")), int(c.get("skinned", -1))])
	_check(int(c.get("figures", -1)) == units and units > 0, "one egg per unit (%d figures, %d units)" % [int(c.get("figures", -1)), units])
	_check(table.visible, "the battle shows the table")
	_log("battle started")

	# 6. instant speed to the end
	battle.call("set_speed", "instant")
	t = Time.get_ticks_msec()
	while not bool(battle.call("is_over")) and Time.get_ticks_msec() - t < GAME_CAP_MS:
		await process_frame
	_check(bool(battle.call("is_over")), "the bot game reaches the end in %d ms" % (Time.get_ticks_msec() - t))
	await _frames(2)
	var end_panel := battle.get_node_or_null("%EndPanel") as CanvasItem
	var end_title := battle.get_node_or_null("%EndTitle") as Label
	_check(end_panel != null and end_panel.visible, "the end panel shows")
	_check(end_title != null and end_title.text.strip_edges() != "", "the end title says who won (%s)" % (end_title.text if end_title != null else "?"))
	_log("game over")

	# 7. กลับล็อบบี้ while W is still held (keycode + physical, like a real keyboard): the table camera pans on W
	var lobby_button := battle.get_node_or_null("%LobbyButton") as Button
	_check(lobby_button != null, "the end panel has a back-to-lobby button")
	if lobby_button == null:
		_finish()
		return
	var table_rig: Node3D = table.get("camera_rig")
	_key(KEY_W, true)
	await _frames(2)
	_check(table_rig.is_processing(), "W held over the battle pans the table camera")
	lobby_button.pressed.emit()
	await _frames(3)
	_key(KEY_W, false)
	await _frames(2)
	_check(not table_rig.is_processing(), "leaving the battle forgets the held W (the table camera stops panning)")
	_check(app.call("current") == hall and (hall as CanvasItem).visible, "กลับล็อบบี้ returns to the hall")
	_check((world as Node3D).visible and world.process_mode != Node.PROCESS_MODE_DISABLED, "the hall world is active again")
	var rig: Object = world.get("camera_rig")
	var cam: Camera3D = rig.get("camera") if rig != null else null
	_check(cam != null and cam.current, "the hall camera is current again")
	_check(not table.visible, "the battle table is hidden again")

	# 7b. a second game from the war table: its camera stays put with no key held (review of 12 Nov)
	_key(KEY_E, true)
	await _frames(1)
	_key(KEY_E, false)
	await _frames(3)
	setup = app.call("current")
	var ch2: Dictionary = setup.get("choice") if setup != null and setup.has_method("start") else {}
	_check(not ch2.is_empty() and str(ch2["size"]) == "s" and int(ch2["budget"]) == 300 and int(ch2["rounds"]) == 3
		and str(ch2["seats"][0]["fac"]) == "kn" and str(ch2["seats"][1]["fac"]) == "or" and not bool(ch2["seats"][0]["human"]),
		"setup opens again with the last game's choices (%s)" % str(ch2.get("seats", [])))
	if setup != null and setup.has_method("start"):
		setup.call("set_teams", 2)
		setup.call("set_per_team", 1)
		setup.call("set_seat", 0, "kn", false)
		setup.call("set_seat", 1, "or", false)
		_set_size(setup, "s")
		setup.call("set_seed", 4243)
		setup.call("start")
		await _frames(3)
	battle = app.call("current")
	_check(battle != null and battle.has_method("is_over") and table.visible, "E at the war table starts a second game (%s)" % _name(battle))
	if battle == null or not battle.has_method("is_over"):
		_finish()
		return
	await _frames(2)
	var aim0: Vector3 = table_rig.get("target")
	await _frames(30)
	var aim1: Vector3 = table_rig.get("target")
	_check(aim0.distance_to(aim1) < 0.001, "the second game's camera does not drift (%.3f m in 30 frames)" % aim0.distance_to(aim1))
	battle.call("set_speed", "instant")
	t = Time.get_ticks_msec()
	while not bool(battle.call("is_over")) and Time.get_ticks_msec() - t < GAME_CAP_MS:
		await process_frame
	await _frames(2)
	lobby_button = battle.get_node_or_null("%LobbyButton") as Button
	if lobby_button != null:
		lobby_button.pressed.emit()
	await _frames(3)
	_check(app.call("current") == hall, "the second game also returns to the hall")

	# 8. Esc goes back to the main menu
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(app.call("current") == menu and int(app.call("depth")) == 1, "Esc in the hall returns to the main menu")
	_check((menu as CanvasItem).visible, "the main menu is visible")
	_check(root.get_viewport().get_camera_3d() == null, "no 3D camera draws under the main menu after the hall (%s)" % _cam_name())
	_finish()


func _cam_name() -> String:
	var cam := root.get_viewport().get_camera_3d()
	return "none" if cam == null else str(cam.get_path())


## The table size: LOBBY_SPEC §3 names the setter set_size, which collides with Control.set_size(Vector2), so the setup
## screen may define it under another name; use whichever its script defines, else the public choice dict + refresh().
func _set_size(setup: Node, key: String) -> void:
	var defined := {}
	for m in setup.get_script().get_script_method_list():
		defined[str(m["name"])] = true
	for n in ["set_size", "set_table_size", "set_field_size", "set_board_size", "set_size_key"]:
		if defined.has(n):
			setup.call(n, key)
			return
	var ch: Dictionary = setup.get("choice")
	ch["size"] = key
	setup.call("refresh")


## The rules state behind the battle screen's runner (MatchRunner keeps it on its Battle).
func _state(runner: Object) -> Object:
	if runner == null:
		return null
	for prop in runner.get_property_list():
		if str(prop["name"]) == "st":
			return runner.get("st")
	var b: Object = runner.get("b") if "b" in runner else null
	return b.get("st") if b != null else null


## The name of the blocker the point lies in (with the avatar's clearance), or "".
func _blocker_at(p: Vector3) -> String:
	if absf(p.x) > 12.0 - CLEAR or absf(p.z) > 8.0 - CLEAR:
		return "outside the hall %s" % _xz(p)
	for id in RECTS:
		var r: Array = RECTS[id]
		var dx := maxf(absf(p.x - float(r[0])) - float(r[2]), 0.0)
		var dz := maxf(absf(p.z - float(r[1])) - float(r[3]), 0.0)
		if Vector2(dx, dz).length() < CLEAR:
			return "%s at %s" % [id, _xz(p)]
	if Vector2(p.x - ROUND_TABLE[0], p.z - ROUND_TABLE[1]).length() < ROUND_TABLE[2] + CLEAR:
		return "adventure table at " + _xz(p)
	if Vector2(p.x - VAULT[0], p.z - VAULT[1]).length() < VAULT[2] + CLEAR:
		return "treasure chest at " + _xz(p)
	for q in PILLARS:
		if Vector2(p.x - float(q[0]), p.z - float(q[1])).length() < PILLAR_R + CLEAR:
			return "pillar %s at %s" % [str(q), _xz(p)]
	return ""


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


func _app() -> Node:
	return root.get_node(^"App")


func _name(n: Node) -> String:
	return "none" if n == null else String(n.name)


static func _xz(p: Vector3) -> String:
	return "(%.2f, %.2f)" % [p.x, p.z]


func _log(step: String) -> void:
	print("info  %s at %d ms" % [step, Time.get_ticks_msec() - _t0])


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
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
