extends SceneTree
## Battle setup and the battle screen with egg placeholders (LOBBY_SPEC §3, §4, §7.4), on scenes/main.tscn (the
## World/BattleTable is the table the battle draws on):
## - the setup panel at 640x360, 1280x720 and 1280x576 (logical 1280x720 / 1600x720) in Thai and English: nothing
##   overflows, no two sibling buttons overlap, every button is at least 44x44, no Thai left in English mode; a bad
##   choice disables START with a message, and 4 x 2 seats is refused with a message;
## - a 2-team bot game with eggs: every egg stands on its unit (1 cm on x/z), rings = units + objectives, team rings in
##   team colours; the HUD in both languages at the three sizes; instant speed to the end panel; กลับล็อบบี้ pops;
## - a human game: the runner waits for the human with nothing processing on min (screen, timer, table, camera rig); a
##   synthetic pick on an own squad selects it, a ground pick moves it (MOVE_STEP, an smove with the human pid);
##   %DoneButton ends the phase; %AutoButton plays on to the end panel; ดูสนาม / ผลการรบ; เล่นอีกครั้ง restarts;
## - with kits on disk, App.set_fig("kit") draws kits.
## PNGs: setup_th.png, setup_en.png (+ _<w>x<h>), battle_eggs_th.png, battle_eggs_en.png, battle_end.png,
## battle_kits.png. Uses a test settings file, never this machine's settings.cfg. Run like the other render suites:
##   TEST_OUT=<abs dir> timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_battle_screen.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const BATTLE_SETUP := "res://ui/screens/battle_setup.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_battle_screen.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1280, 576)]
const SETTLE := 6
const MIN_TARGET := 44.0
const GAME_CAP_MS := 90000

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
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
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(3)
	var menu: Node = _app().call("current")
	_check(menu != null, "main.tscn opens a first screen")
	await _check_setup()
	await _check_bot_game(menu)
	await _check_stuck_and_touch_log(menu)
	await _check_human_game(menu)
	await _check_kits(menu)
	_finish()


# ---- setup panel ----

func _open_setup() -> Node:
	var setup: Node = _app().call("push", load(BATTLE_SETUP))
	await _frames(3)
	return setup


func _check_setup() -> void:
	var setup: Node = await _open_setup()
	_check(setup != null and setup.has_method("start") and setup.get_node_or_null("%StartButton") != null, "the setup screen opens with its API")
	if setup == null or setup.get_node_or_null("%StartButton") == null:
		return
	var start := setup.get_node("%StartButton") as Button
	var errors := setup.get_node("%Errors") as Label
	_check(not start.disabled and (setup.call("errors") as PackedStringArray).is_empty(), "the defaults can start")
	var ch: Dictionary = setup.get("choice")
	_check(int(ch["teams"]) == 2 and int(ch["per_team"]) == 1 and bool(ch["seats"][0]["human"]) and not bool(ch["seats"][1]["human"]),
		"defaults: 2 x 1, seat 0 is you, seat 1 a bot")
	for sz in SIZES:
		await _resize(sz)
		for lang in ["th", "en"]:
			_app().call("set_lang", lang)
			setup.call("refresh")
			await _frames(2)
			var tag := "setup %s %dx%d" % [lang, sz.x, sz.y]
			var probs := _layout_problems(setup)
			_check(probs.is_empty(), tag + ": layout fits (no overflow, no overlap, 44 px targets)", str(probs.slice(0, 6)))
			var thai := _thai_in(setup, [])
			if lang == "en":
				_check(thai.is_empty(), tag + ": no Thai left in English mode", str(thai.slice(0, 6)))
			else:
				_check(_thai_re.search(str((setup.get_node("%StartButton") as Button).text)) != null and thai.size() > 10, tag + ": Thai on screen")
			_save("setup_%s%s.png" % [lang, _suffix(sz)])
	_app().call("set_lang", "th")
	setup.call("refresh")
	await _resize(SIZES[0])
	await _check_army_popup(setup)
	# a bad choice: 6 seats on the medium table
	setup.call("set_teams", 3)
	setup.call("set_per_team", 2)
	setup.call("set_size", "m")
	await _frames(1)
	_check((setup.call("errors") as PackedStringArray).has("small"), "3 x 2 on the medium table is an error")
	_check(start.disabled and errors.text.strip_edges() != "", "START is disabled with a message (%s)" % errors.text)
	_check(not bool(setup.call("start")), "start() refuses a bad choice")
	await _resize(SIZES[0])
	_check(_layout_problems(setup).is_empty(), "6 seat rows fit", str(_layout_problems(setup).slice(0, 6)))
	_save("setup_six_seats.png")
	setup.call("set_size", "l")
	await _frames(1)
	_check(not start.disabled, "the large table fits 6 seats")
	setup.call("set_teams", 4)
	await _frames(1)
	_check(int(setup.get("choice")["teams"]) == 3 and errors.text.strip_edges() != "", "4 x 2 seats is refused with a message (%s)" % errors.text)
	# radio: choosing you on another row turns the old one into a bot
	setup.call("set_seat", 3, "gr", true)
	var seats: Array = setup.get("choice")["seats"]
	var humans := 0
	for sd: Dictionary in seats:
		humans += 1 if bool(sd["human"]) else 0
	_check(humans == 1 and bool(seats[3]["human"]) and str(seats[3]["fac"]) == "gr", "only one seat is you (radio)")
	_app().call("pop")
	await _frames(2)


## The army dropdown (review of 12 Nov): its popup wears the candle theme, every row is at least 44 px tall (the 16
## rows scroll when they outgrow the screen) and the open popup stays on screen; picking a row sets the seat's army.
func _check_army_popup(setup: Node) -> void:
	var army := setup.find_child("Army0", true, false) as OptionButton
	_check(army != null, "seat 0 has an army dropdown")
	if army == null:
		return
	var pm := army.get_popup()
	var row := pm.get_theme_font(&"font").get_height(pm.get_theme_font_size(&"font_size")) + pm.get_theme_constant(&"v_separation")
	_check(row >= MIN_TARGET, "army popup rows are at least %d px tall (%.1f px, %d rows)" % [int(MIN_TARGET), row, pm.item_count])
	_check(pm.has_theme_stylebox_override(&"panel") and pm.has_theme_stylebox_override(&"hover"), "the army popup wears the candle theme")
	army.show_popup()
	await _frames(3)
	var vis := root.get_visible_rect()
	var r := Rect2(Vector2(pm.position), Vector2(pm.size))
	_check(pm.visible and vis.grow(1.0).encloses(r), "the open army popup stays on screen (%s in %s)" % [str(r), str(vis)])
	_save("setup_army_popup.png")
	pm.hide()
	await _frames(1)
	var before := str(setup.get("choice")["seats"][0]["fac"])
	army.select(2)
	army.item_selected.emit(2)
	await _frames(1)
	var fac := str(setup.get("choice")["seats"][0]["fac"])
	_check(fac == GameData.factions()[1], "picking the second army in the popup sets seat 0 (%s -> %s)" % [before, fac])


func _new_game(facs: Array, human: int, seed_v: int) -> Node:
	var setup: Node = await _open_setup()
	setup.call("set_teams", facs.size())
	setup.call("set_per_team", 1)
	for k in facs.size():
		setup.call("set_seat", k, str(facs[k]), k == human)
	setup.call("set_size", "s")
	setup.call("set_goal", "obj")
	setup.call("set_rounds", 3)
	setup.call("set_budget", 300)
	setup.call("set_seed", seed_v)
	var depth := int(_app().call("depth"))
	var ok: bool = setup.call("start")
	await _frames(3)
	var battle: Node = _app().call("current")
	_check(ok and battle != null and battle.has_method("begin") and int(_app().call("depth")) == depth,
		"START replaces setup with the battle screen (depth %d)" % int(_app().call("depth")))
	return battle


# ---- a bot game with eggs ----

func _check_bot_game(menu: Node) -> void:
	var battle: Node = await _new_game(["kn", "or"], -1, 4242)
	if battle == null or not battle.has_method("is_over"):
		return
	var table := root.get_tree().get_first_node_in_group("table_view") as Node3D
	var runner: Object = battle.get("runner")
	var st: BattleState = runner.get("st")
	_check(table != null and table.visible and table.process_mode != Node.PROCESS_MODE_DISABLED, "the battle shows and enables the table")
	_check((table.get("camera_rig").get("camera") as Camera3D).current, "the table camera is current")
	battle.call("set_speed", "normal")
	await _frames(2)
	_check_figures(table, st, "start")
	for sz in SIZES:
		await _resize(sz)
		for lang in ["th", "en"]:
			_app().call("set_lang", lang)
			battle.call("refresh")
			await _frames(2)
			var tag := "battle HUD %s %dx%d" % [lang, sz.x, sz.y]
			var probs := _layout_problems(battle)
			_check(probs.is_empty(), tag + ": layout fits", str(probs.slice(0, 6)))
			if lang == "en":
				var thai := _thai_in(battle, [])
				_check(thai.is_empty(), tag + ": no Thai left in English mode", str(thai.slice(0, 6)))
			if sz == SIZES[0]:
				_save("battle_eggs_%s.png" % lang)
	_app().call("set_lang", "th")
	battle.call("refresh")
	await _resize(SIZES[0])
	battle.call("set_speed", "instant")
	var t := Time.get_ticks_msec()
	while not bool(battle.call("is_over")) and Time.get_ticks_msec() - t < GAME_CAP_MS:
		await process_frame
	_check(bool(battle.call("is_over")), "the bot game reaches the end in %d ms (round %d)" % [Time.get_ticks_msec() - t, st.round_no])
	await _frames(3)
	_check_figures(table, st, "end")
	var end_panel := battle.get_node("%EndPanel") as Control
	var end_title := battle.get_node("%EndTitle") as Label
	_check(end_panel.visible and end_title.text.strip_edges() != "", "the end panel shows who won (%s)" % end_title.text)
	_check((battle.get_node("StepTimer") as Timer).is_stopped(), "the step timer stops at the end")
	_check_log_fits(battle)
	_check(_layout_problems(battle).is_empty(), "the end panel fits", str(_layout_problems(battle).slice(0, 6)))
	_save("battle_end.png")
	_app().call("set_lang", "en")
	battle.call("refresh")
	await _frames(2)
	var left := _thai_in(battle, [])
	_check(left.is_empty(), "end panel, English mode: no Thai", str(left.slice(0, 6)))
	_app().call("set_lang", "th")
	battle.call("refresh")
	(battle.get_node("%LobbyButton") as Button).pressed.emit()
	await _frames(3)
	_check(_app().call("current") == menu and (menu as CanvasItem).visible, "กลับล็อบบี้ pops back to the screen under the battle")
	_check(not table.visible and table.process_mode == Node.PROCESS_MODE_DISABLED, "the table is hidden and disabled again")
	_check(not bool(table.call("in_battle")) and int(table.call("counts")["figures"]) == 0, "the table left battle mode")


## Review of 12 Nov: a runner that reports "stuck" shows the end panel with a stuck title and กลับล็อบบี้ (never a
## state the player cannot leave); with touch controls the log uses bigger text in fewer lines.
func _check_stuck_and_touch_log(menu: Node) -> void:
	var touch0 := str(_app().get("touch"))
	_app().call("set_touch", "on")
	var battle: Node = await _new_game(["kn", "or"], -1, 4244)
	_app().call("set_touch", touch0)
	if battle == null or not battle.has_method("is_over"):
		return
	var lbl := battle.get_node("%LogText") as Label
	_check(lbl.get_theme_font_size(&"font_size") >= 18 and lbl.max_lines_visible == 6,
		"touch: the battle log uses %d px text in %d lines" % [lbl.get_theme_font_size(&"font_size"), lbl.max_lines_visible])
	var i18n := root.get_node(^"I18n")
	battle.set("_stuck", true)
	battle.call("_show_stuck")
	await _frames(2)
	var end_panel := battle.get_node("%EndPanel") as Control
	var title := battle.get_node("%EndTitle") as Label
	var lobby := battle.get_node("%LobbyButton") as Button
	_check(end_panel.visible and lobby.is_visible_in_tree() and title.text == str(i18n.call("t", "เกมติด — กดกลับล็อบบี้")),
		"a stuck game shows the end panel with its title and กลับล็อบบี้ (%s)" % title.text)
	_check((battle.get_node("StepTimer") as Timer).is_stopped(), "a stuck game stops the step timer")
	_check(not bool(battle.call("handle_back")), "Esc on a stuck game leaves without asking")
	_app().call("set_lang", "en")
	battle.call("refresh")
	await _frames(1)
	_check(_thai_re.search(title.text) == null and title.text != "", "the stuck title follows the language (%s)" % title.text)
	_app().call("set_lang", "th")
	battle.call("refresh")
	lobby.pressed.emit()
	await _frames(3)
	_check(_app().call("current") == menu, "กลับล็อบบี้ leaves the stuck game")


## every egg stands on its unit, rings = units + objectives, team rings in team colours
## The battle log: a line wider than the log panel (an attack with many dice) must end in an ellipsis, never be cut off
## at the panel's edge (it was cut mid-number on 12 Nov).
func _check_log_fits(battle: Node) -> void:
	var lbl := battle.get_node("%LogText") as Label
	var font := lbl.get_theme_font(&"font")
	var fsize := lbl.get_theme_font_size(&"font_size")
	var wide := 0
	for line in lbl.text.split("\n"):
		if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > lbl.size.x:
			wide += 1
	_check(lbl.text.strip_edges() != "", "the battle log has lines")
	_check(lbl.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"log lines wider than the panel end in an ellipsis (%d of %d lines are wider now)" % [wide, lbl.text.split("\n").size()])


func _check_figures(table: Node3D, st: BattleState, tag: String) -> void:
	var c: Dictionary = table.call("counts")
	_check(str(c.get("style", "")) == "egg" and int(c["skinned"]) == 0, "%s: egg figures, none skinned (%s, %d)" % [tag, str(c.get("style", "")), int(c["skinned"])])
	_check(int(c["figures"]) == st.units.size() and st.units.size() > 0, "%s: one egg per unit (%d / %d)" % [tag, int(c["figures"]), st.units.size()])
	_check(int(c["kits"]) <= 7, "%s: at most 7 egg MultiMeshes (%d)" % [tag, int(c["kits"])])
	var figs: Array = table.get("figures").get("figures")
	var off := []
	var bad_ring := []
	var rings: Node = table.get("rings")
	var mm: MultiMesh = rings.get("multimesh")
	for i in figs.size():
		var uid := str(table.call("fig_unit", i))
		var u := st.unit(uid)
		var f: Object = figs[i]
		var p: Vector3 = f.get("pos")
		if u == null or absf(p.x - u.x / 1000.0) > 0.01 or absf(p.z - u.z / 1000.0) > 0.01:
			off.append("%d %s" % [i, uid])
			continue
		var want: Color = table.call("team_colour", u.side)
		var got := mm.get_instance_color(i)
		if absf(got.r - want.r) > 0.02 or absf(got.g - want.g) > 0.02 or absf(got.b - want.b) > 0.02:
			bad_ring.append("%d %s %s != %s" % [i, uid, str(got), str(want)])
	_check(off.is_empty(), "%s: every egg stands on its unit within 1 cm" % tag, str(off.slice(0, 6)))
	_check(bad_ring.is_empty(), "%s: every team ring has its team colour" % tag, str(bad_ring.slice(0, 6)))
	var want_rings := st.units.size() + st.objs.size()
	var sel := (table.get("_sel_rings") as PackedInt32Array).size() + (1 if int(table.get("_dest_ring")) >= 0 else 0)
	_check(int(c["rings"]) - sel == want_rings, "%s: rings = units + objectives (%d = %d + %d)" % [tag, int(c["rings"]) - sel, st.units.size(), st.objs.size()])


# ---- a human game ----

func _check_human_game(menu: Node) -> void:
	var battle: Node = await _new_game(["kn", "or"], 0, 11)
	if battle == null or not battle.has_method("is_over"):
		return
	var table := root.get_tree().get_first_node_in_group("table_view") as Node3D
	var runner: Object = battle.get("runner")
	var st: BattleState = runner.get("st")
	battle.call("set_speed", "fast")
	var t := Time.get_ticks_msec()
	while not bool(battle.call("is_waiting")) and Time.get_ticks_msec() - t < 20000:
		await process_frame
	_check(bool(battle.call("is_waiting")) and st.phase == BattleState.PH_MOVE, "the screen waits for the human in the move phase")
	await _frames(10)
	# min level: nothing processes while waiting
	var idle := _idle_problems(battle)
	idle.append_array(_idle_problems(table))
	_check(idle.is_empty(), "min: nothing processes while waiting for the human (screen, timer, table, camera rig)", str(idle))
	_check(not (battle.get_node("%DoneButton") as Button).disabled, "%DoneButton is enabled on the human's turn")
	# a synthetic pick on an own squad selects it
	var mine: Array = runner.call("selectable")
	_check(mine.size() >= 1, "the human has selectable squads (%d)" % mine.size())
	if mine.is_empty():
		return
	# the last selectable squad that is not locked in melee (the screen auto-selects the first one)
	var s: BattleState.Squad = mine[mine.size() - 1]
	for q: BattleState.Squad in mine:
		if not BtSquads.is_engaged(st, q):
			s = q
	var fi := int(table.call("unit_fig", s.models[0].id))
	var fpos: Vector3 = (table.get("figures").get("figures") as Array)[fi].get("pos")
	table.emit_signal("picked", fi, fpos)
	await _frames(2)
	_check(battle.call("selected") == s, "a pick on an own squad selects it")
	_check((table.get("_sel_rings") as PackedInt32Array).size() == s.models.size(), "SELECT rings under its models (%d)" % s.models.size())
	_check((battle.get_node("%SquadCard") as Control).visible, "the squad card shows")
	# a ground pick moves it (2" toward the centre, or sideways when that spot is taken)
	var c := BtSquads.center(s)
	var toward := -1 if c[1] > 0 else 1
	var n0: int = (runner.call("acts") as Array).size()
	var said := []
	for d: Vector2i in [Vector2i(0, toward * 2000), Vector2i(2000, 0), Vector2i(-2000, 0), Vector2i(0, toward * 3500)]:
		table.emit_signal("picked", -1, Vector3((c[0] + d.x) / 1000.0, 0.0, (c[1] + d.y) / 1000.0))
		await _frames(2)
		if (runner.call("acts") as Array).size() > n0:
			break
		said.append((battle.get_node("%Toast").get_child(0) as Label).text)
	var acts: Array = runner.call("acts")
	var moved := acts.size() > n0 and str(acts[n0].get("a", "")) == "smove" and str(acts[n0].get("pid", "")) == "L0"
	_check(moved, "a ground pick moves the squad (an smove with pid L0)", str(acts.slice(n0, n0 + 2)) + " refusals " + str(said))
	var cc := BtSquads.center(s)
	_check(absi(cc[1] - c[1]) + absi(cc[0] - c[0]) > 500, "the squad stands somewhere new (%s -> %s)" % [str(c), str(cc)])
	var fi2 := int(table.call("unit_fig", s.models[0].id))
	var fpos2: Vector3 = (table.get("figures").get("figures") as Array)[fi2].get("pos")
	_check(absf(fpos2.z - s.models[0].z / 1000.0) < 0.01 and absf(fpos2.x - s.models[0].x / 1000.0) < 0.01, "its egg followed (MOVE_STEP drawn)")
	_save("battle_human_th.png")
	# %DoneButton ends the phase
	var ph := st.phase
	(battle.get_node("%DoneButton") as Button).pressed.emit()
	await _frames(3)
	_check(st.phase != ph or st.turn != 0, "%DoneButton ends the move phase (phase now " + st.phase_name() + ")")
	# ดูสนาม is checked at the end; now let the bot play for the human
	var auto := battle.get_node("%AutoButton") as Button
	auto.button_pressed = true
	battle.call("set_speed", "instant")
	t = Time.get_ticks_msec()
	while not bool(battle.call("is_over")) and Time.get_ticks_msec() - t < GAME_CAP_MS:
		await process_frame
	_check(bool(battle.call("is_over")), "%%AutoButton plays on to the end in %d ms" % (Time.get_ticks_msec() - t))
	await _frames(2)
	var end_panel := battle.get_node("%EndPanel") as Control
	var title := (battle.get_node("%EndTitle") as Label).text
	_check(end_panel.visible and (title == "คุณชนะ!" or title == "คุณแพ้" or title == "เสมอ"), "the end panel speaks to the human (%s)" % title)
	(battle.get_node("%LookButton") as Button).pressed.emit()
	await _frames(1)
	var result := battle.get_node("%ResultButton") as Control
	_check(not end_panel.visible and result.visible, "ดูสนาม hides the panel and shows ผลการรบ")
	(result as Button).pressed.emit()
	await _frames(1)
	_check(end_panel.visible and not result.visible, "ผลการรบ brings the panel back")
	var old_runner: Object = battle.get("runner")
	(battle.get_node("%AgainButton") as Button).pressed.emit()
	await _frames(3)
	var new_runner: Object = battle.get("runner")
	_check(new_runner != old_runner and not bool(battle.call("is_over")) and not end_panel.visible, "เล่นอีกครั้ง restarts with the same plan")
	_check(int((new_runner.get("st") as BattleState).seed) != int(st.seed), "เล่นอีกครั้ง uses a new seed")
	# Back during play opens the leave confirm; Back again closes it
	_check(bool(battle.call("handle_back")) and (battle.get_node("%LeaveConfirm") as Control).visible, "Back opens the leave confirm")
	_check(bool(battle.call("handle_back")) and not (battle.get_node("%LeaveConfirm") as Control).visible, "Back again closes it")
	battle.call("handle_back")
	(battle.get_node("%LeaveYes") as Button).pressed.emit()
	await _frames(3)
	_check(_app().call("current") == menu, "ออกจากการรบ leaves to the screen below")
	_check(not table.visible, "the table is hidden after leaving")


# ---- kit mode ----

func _check_kits(menu: Node) -> void:
	if KitLibrary.list_kits().is_empty():
		print("note  no kits on disk: kit mode not checked (eggs stand in)")
		return
	_app().call("set_fig", "kit")
	var battle: Node = await _new_game(["kn", "or"], -1, 77)
	if battle == null or not battle.has_method("is_over"):
		_app().call("set_fig", "egg")
		return
	battle.call("set_speed", "normal")
	await _frames(4)
	var table := root.get_tree().get_first_node_in_group("table_view") as Node3D
	var c: Dictionary = table.call("counts")
	var st: BattleState = battle.get("runner").get("st")
	_check(str(c.get("style", "")) == "kit" and int(c["figures"]) == st.units.size(), "App.fig kit draws kits (style %s, %d figures)" % [str(c.get("style", "")), int(c["figures"])])
	_save("battle_kits.png")
	battle.call("handle_back")
	(battle.get_node("%LeaveYes") as Button).pressed.emit()
	await _frames(3)
	_check(_app().call("current") == menu, "leaving the kit game returns")
	_app().call("set_fig", "egg")


# ---- helpers ----

## Nodes that would run every frame: _process / _physics_process on, or a running Timer.
func _idle_problems(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			out.append(String(n.name) + " processes")
		if n is Timer and not (n as Timer).is_stopped() and not (n as Timer).one_shot:
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


## LOBBY_SPEC §7.1 for every visible Control under the screen.
func _layout_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var vis := root.get_visible_rect()
	_walk(screen, func(c: Control) -> void:
		var r := c.get_global_rect()
		if r.position.x < vis.position.x - 1.0 or r.position.y < vis.position.y - 1.0 or r.end.x > vis.end.x + 1.0 or r.end.y > vis.end.y + 1.0:
			out.append("%s outside the canvas %s" % [c.name, str(r)])
		var p := c.get_parent() as Control
		if p != null and not p is ScrollContainer:
			var pr := p.get_global_rect()
			if r.position.x < pr.position.x - 1.0 or r.position.y < pr.position.y - 1.0 or r.end.x > pr.end.x + 1.0 or r.end.y > pr.end.y + 1.0:
				out.append("%s outside its parent %s: %s in %s" % [c.name, p.name, str(r), str(pr)])
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			out.append("%s smaller than 44x44 %s" % [c.name, str(r.size)])
		var buttons: Array[Control] = []
		for s in c.get_children():
			if s is Button and (s as Control).is_visible_in_tree():
				buttons.append(s)
		for i in buttons.size():
			for j in range(i + 1, buttons.size()):
				if buttons[i].get_global_rect().intersection(buttons[j].get_global_rect()).get_area() > 1.0:
					out.append("%s overlaps %s" % [buttons[i].name, buttons[j].name]))
	return out


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


func _thai_in(node: Node, exempt: Array) -> PackedStringArray:
	var out := PackedStringArray()
	_scan(node, exempt, out)
	return out


func _scan(node: Node, exempt: Array, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if not exempt.has(String(node.name)):
		var texts := PackedStringArray()
		if node is Label or node is Button:
			texts.append(str(node.get("text")))
		if node is OptionButton:
			for i in (node as OptionButton).item_count:
				texts.append((node as OptionButton).get_item_text(i))
		if node is Label3D:
			texts.append((node as Label3D).text)
		for t in texts:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, exempt, out)


func _resize(sz: Vector2i) -> void:
	root.size = sz
	await _frames(SETTLE)


func _suffix(sz: Vector2i) -> String:
	return "" if sz == SIZES[0] else "_%dx%d" % [sz.x, sz.y]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(file: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + file
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))
	_check(_mean_luma(img) > 0.02, file + " is not black")


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
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


static func _mean_luma(img: Image) -> float:
	var sum := 0.0
	var n := 0
	var size := img.get_size()
	var x := 7
	while x < size.x:
		var y := 5
		while y < size.y:
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
			y += 29
		x += 31
	return sum / maxi(n, 1)
