extends SceneTree
## The army picker screen (ui/screens/army.tscn, R1-V4) inside scenes/main.tscn: the GPU-check screen's army button
## opens it through App.push and its back button returns. For every army, in Thai and in English: the roster lists
## that army's datasheets in TYPES order and never a hidden unit, and in English no visible Label/Button text keeps
## Thai (the language button's "ไทย" is the one deliberate exception, as on the old page). The +/- buttons move the
## points total, the random army is fixed by its seed and fits the budget, the preview turntable shows the selected
## unit's kit and spins (not on min, where nothing runs per frame), touch targets are >= 44 px and nothing sticks out
## sideways. Saves tests/out/army_<fac>_th.png for three armies and army_en.png (a window other than 1280x720 adds
## _<w>x<h> to the names, e.g. the phone run at 2400x1080). Run like the other render suites:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_army_screen.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SHOTS: PackedStringArray = ["gr", "kn", "th"]
## a unit worth looking at for each screenshot (falls back to the first card)
const SHOWCASE := {"gr": "cyclops", "kn": "kcapt", "th": "eleph", "nr": "odin"}
const EN_ARMY := "nr"
const BUDGETS: PackedInt32Array = [200, 500, 1000, 2000]
const SETTLE := 6
const MIN_TARGET := 44.0

var _out_dir := DEFAULT_OUT_DIR
var _suffix := ""
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
	var win := DisplayServer.window_get_size()
	if win != Vector2i(1280, 720):
		_suffix = "_%dx%d" % [win.x, win.y]
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	_main = scene.instantiate()
	_main.set("first_run_guess", false)   # never write this machine's settings.cfg from a test
	_app().call("set_lang", "th")
	root.add_child(_main)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")
	print("window %s, level %s" % [str(win), str(_app().get("gfx"))])


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(4)
	var gpu: Node = _app().call("current")
	_check(gpu != null and gpu.has_signal("army_requested"), "the first screen is the GPU check with an army button")
	if gpu == null:
		_finish()
		return
	var army_button: Button = gpu.get_node("%ArmyButton")
	_check(_thai_re.search(army_button.text) != null, "Thai mode: the army button is Thai (%s)" % army_button.text)
	_check(army_button.size.y >= MIN_TARGET, "the army button is a touch target (%.0f px)" % army_button.size.y)
	army_button.pressed.emit()
	await _frames(2)
	var screen: Node = _app().call("current")
	_check(screen != null and screen.has_method("listed_units"), "the army button opens the army screen via App.push")
	if screen == null or not screen.has_method("listed_units"):
		_finish()
		return
	_check(not (gpu as CanvasItem).visible, "the GPU-check screen is hidden under it")
	_check((gpu.get_node("%Timer") as Timer).paused, "the hidden GPU-check screen stops its counter timer")
	_check(int(screen.get("random_seed")) >= 1, "the random seed starts at a positive number (%d)" % int(screen.get("random_seed")))
	var table := _main.get_node_or_null(^"World/BattleTable") as Node3D
	_check(table != null and not table.visible, "the 3D table is hidden while the opaque army screen is open")
	_check(str(screen.get("roster").get("fac")) == "mod", "the default army is the soldiers (the page's facOf)")
	_check(int(screen.get("roster").get("budget")) == 1000, "the default budget is 1000")

	_check_every_army(screen)
	_check_points(screen)
	_check_random(screen)
	await _check_shots(screen)
	await _check_turntable(screen)
	_check_targets_and_layout(screen)

	screen.get_node("%BackButton").pressed.emit()
	await _frames(2)
	_check(_app().call("current") == gpu, "the back button returns to the GPU-check screen")
	_check((gpu as CanvasItem).visible, "the GPU-check screen is shown again")
	_check(not (gpu.get_node("%Timer") as Timer).paused, "its counter timer runs again")
	_check(table == null or table.visible, "the 3D table is shown again")
	_check(_thai_re.search(str(gpu.get_node("%Title").get("text"))) != null, "the GPU-check screen redraws in Thai after the round trip")
	_finish()


## Every army in Thai and English: the listed units, no hidden unit, no Thai left in English mode.
func _check_every_army(screen: Node) -> void:
	var hidden_seen := 0
	for t: Dictionary in GameData.types():
		if GameData.is_hidden(str(t["k"])):
			hidden_seen += 1
	_check(hidden_seen > 0, "the data carries hidden units for the filter to keep out (%d)" % hidden_seen)
	var bad_hidden := PackedStringArray()
	var bad_order := PackedStringArray()
	var thai_left := PackedStringArray()
	var no_thai := PackedStringArray()
	var total := 0
	for fac in GameData.factions():
		screen.call("set_language", false, false)
		screen.call("select_army", fac)
		var listed: PackedStringArray = screen.call("listed_units")
		var expected := PackedStringArray()
		for t: Dictionary in GameData.types():
			var k := str(t["k"])
			if (str(t["fac"]) == fac or str(t["fac"]) == "*") and not GameData.is_hidden(k):
				expected.append(k)
		if listed != expected:
			bad_order.append("%s: %d listed, %d expected" % [fac, listed.size(), expected.size()])
		for k in listed:
			if GameData.is_hidden(k):
				bad_hidden.append(fac + ":" + k)
		bad_hidden.append_array(_hidden_names_on(screen))
		total += listed.size()
		if _thai_in(screen, []).is_empty():
			no_thai.append(fac)
		var pressed: Button = screen.get_node("%ArmyList").get_node("Army_" + fac)
		if not pressed.button_pressed:
			bad_order.append(fac + ": its army button is not pressed")
		screen.call("set_language", true, false)
		var left := _thai_in(screen, ["LangButton"])
		if not left.is_empty():
			thai_left.append(fac + ": " + ", ".join(left.slice(0, 4)))
		if (screen.get_node("%LangButton") as Button).text != "ไทย":
			thai_left.append(fac + ": the language button does not offer ไทย")
		bad_hidden.append_array(_hidden_names_on(screen))
	screen.call("set_language", false, false)
	_check(bad_order.is_empty(), "every army lists its datasheets in TYPES order (%d cards over 15 armies)" % total, str(bad_order))
	_check(bad_hidden.is_empty(), "no hidden unit is listed or named in any army, Thai or English", str(bad_hidden))
	_check(no_thai.is_empty(), "Thai mode shows Thai for every army", str(no_thai))
	_check(thai_left.is_empty(), "English mode: no Thai left on screen for any army", "\n".join(thai_left))


## +/- on a card moves the points total and the labels; the budget steps through BUDGETS.
func _check_points(screen: Node) -> void:
	screen.call("set_language", false, false)
	screen.call("select_army", "mod")
	var roster: Object = screen.get("roster")
	roster.call("clear")
	screen.call("refresh")
	var listed: PackedStringArray = screen.call("listed_units")
	var k := listed[0]
	var pts := int(GameData.ty(k)["pts"])
	var card: Control = screen.call("card", k)
	var plus: Button = card.find_child("Plus", true, false)
	var minus: Button = card.find_child("Minus", true, false)
	var count: Label = card.find_child("Count", true, false)
	_check(minus.disabled and not plus.disabled, "an empty squad: minus is off, plus is on")
	plus.pressed.emit()
	_check(int(screen.call("points")) == pts, "plus adds one squad's points (%d)" % pts)
	plus.pressed.emit()
	_check(int(screen.call("points")) == 2 * pts and count.text == "2", "plus again: two squads (%s)" % count.text)
	var label := str(screen.get_node("%PointsLabel").get("text"))
	_check(label.contains(DatasheetText.fmt_pts(2 * pts)) and label.contains("1,000"), "the points label shows the total against the budget: " + label)
	_check(str(screen.get_node("%StatusLabel").get("text")).begins_with("พร้อม"), "status: ready")
	minus.pressed.emit()
	_check(int(screen.call("points")) == pts and count.text == "1", "minus takes one squad off")
	var other: String = listed[1]
	var other_pts := int(GameData.ty(other)["pts"])
	(screen.call("card", other) as Control).find_child("Plus", true, false).pressed.emit()
	_check(int(screen.call("points")) == pts + other_pts, "two different units add up (%d)" % (pts + other_pts))
	screen.get_node("%BudgetPlus").pressed.emit()
	_check(int(roster.get("budget")) == 1050, "the budget steps up to the next BUDGETS entry (1050)")
	screen.get_node("%BudgetMinus").pressed.emit()
	screen.get_node("%BudgetMinus").pressed.emit()
	_check(int(roster.get("budget")) == 950, "and down (950)")
	_check(str(screen.get_node("%BudgetLabel").get("text")).contains("950"), "the budget label follows")
	roster.call("set_budget", 200)
	var big := ""
	for u in listed:
		if int(GameData.ty(u)["pts"]) > 200:
			big = u
			break
	if big != "":
		screen.call("add_unit", big, 1)
		_check(str(screen.get_node("%StatusLabel").get("text")).begins_with("เกินงบ"), "over budget: the status says so")
	roster.call("clear")
	roster.call("set_budget", 1000)
	screen.call("refresh")
	_check(int(screen.call("points")) == 0 and str(screen.get_node("%StatusLabel").get("text")) == "ต้องมีหน่วยอย่างน้อยหนึ่งตัว", "an empty list asks for a unit")


## The random army: fixed by its seed, fits the budget, only this army's listed units; the button moves the seed on.
func _check_random(screen: Node) -> void:
	var bad := PackedStringArray()
	var same := 0
	var runs := 0
	for fac in GameData.factions():
		screen.call("select_army", fac)
		var roster: Object = screen.get("roster")
		var allowed: PackedStringArray = screen.call("listed_units")
		for b in BUDGETS:
			roster.call("set_budget", b)
			var a: PackedInt32Array = screen.call("random_army", 11)
			var pts := int(screen.call("points"))
			var again: PackedInt32Array = screen.call("random_army", 11)
			var other: PackedInt32Array = screen.call("random_army", 12)
			runs += 1
			if a != again:
				bad.append("%s/%d: seed 11 gave two lists" % [fac, b])
			if a == other:
				same += 1
			if pts > b:
				bad.append("%s/%d: %d points over the budget" % [fac, b, pts])
			var cheapest := 1 << 30
			for k in GameData.pool(fac):
				if allowed.has(k):
					cheapest = mini(cheapest, int(GameData.ty(k)["pts"]))
			var squads := 0
			for i in a.size():
				if a[i] == 0:
					continue
				squads += a[i]
				var k := GameData.key_at(i)
				if GameData.is_hidden(k) or not allowed.has(k):
					bad.append("%s/%d: picked %s" % [fac, b, k])
			if squads == 0 and cheapest <= b:
				bad.append("%s/%d: nothing picked" % [fac, b])
			if pts + cheapest <= b and squads < ArmyRoster.RANDOM_PICKS:
				bad.append("%s/%d: stopped with room for the cheapest unit (%d of %d)" % [fac, b, pts, b])
	_check(bad.is_empty(), "random army: same seed same list, within budget, only listed units, budget filled (%d runs)" % runs, str(bad))
	_check(same < runs / 2, "random army: another seed gives another list (%d of %d equal)" % [same, runs])
	screen.call("select_army", "gr")
	var roster2: Object = screen.get("roster")
	roster2.call("set_budget", 1000)
	var seed0 := int(screen.get("random_seed"))
	screen.get_node("%RandomButton").pressed.emit()
	screen.get_node("%RandomButton").pressed.emit()
	_check(int(screen.get("random_seed")) == seed0 + 2, "the random button uses the next seed each press")
	_check(int(screen.call("points")) <= 1000 and int(screen.call("points")) > 0, "the random button fills the army within the budget (%d)" % int(screen.call("points")))
	var shown := true
	for k in screen.call("listed_units"):
		var c: Control = screen.call("card", k)
		if (c.find_child("Count", true, false) as Label).text != str(int(roster2.call("count_of", k))):
			shown = false
	_check(shown, "every card shows its squad count after a random army")


## Screenshots: three armies in Thai and one in English, each with a random army and a showcase unit on the turntable.
func _check_shots(screen: Node) -> void:
	for fac in SHOTS:
		screen.call("set_language", false, false)
		await _shot_army(screen, fac, "army_%s_th%s.png" % [fac, _suffix])
	screen.call("set_language", true, false)
	await _shot_army(screen, EN_ARMY, "army_en%s.png" % _suffix)
	var left := _thai_in(screen, ["LangButton"])
	_check(left.is_empty(), "army_en: no Thai on screen", str(left))
	screen.call("set_language", false, false)


func _shot_army(screen: Node, fac: String, file: String) -> void:
	screen.call("select_army", fac)
	var roster: Object = screen.get("roster")
	roster.call("set_budget", 1000)
	screen.call("random_army", 5)
	var want := str(SHOWCASE.get(fac, ""))
	if not (screen.call("listed_units") as PackedStringArray).has(want):
		want = (screen.call("listed_units") as PackedStringArray)[0]
	screen.call("select_unit", want)
	await _frames(SETTLE)
	var preview: Node = screen.get_node("%Preview")
	_check(str(preview.get("kit")) == want and bool(preview.call("has_figure")), "%s: the turntable shows the selected unit's kit (%s)" % [fac, want])
	print("info  %s: %d cards, frame draw calls %d, primitives %d (table hidden, turntable on)" % [fac,
		(screen.call("listed_units") as PackedStringArray).size(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_save(file)


## The turntable spins slowly off min; on min it stands still and nothing runs per frame.
func _check_turntable(screen: Node) -> void:
	var preview: Node = screen.get_node("%Preview")
	screen.call("apply_level", "mid")
	await _frames(2)
	var a := float(preview.call("turn"))
	await _frames(5)
	var b := float(preview.call("turn"))
	_check(absf(b - a) > 0.0001 and absf(b - a) < 0.5, "off min the figure turns slowly (%.4f rad in 5 frames)" % absf(b - a))
	_check(preview.is_processing(), "off min the turntable processes frames")
	screen.call("apply_level", "min")
	await _frames(2)
	a = float(preview.call("turn"))
	await _frames(5)
	b = float(preview.call("turn"))
	_check(absf(b - a) < 0.00001, "on min the figure stands still")
	_check(not preview.is_processing() and not screen.is_processing(), "on min neither the screen nor the turntable runs per frame")
	var vp: SubViewport = preview.call("viewport")
	_check(vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "on min the preview is not redrawn every frame")
	_check(vp.own_world_3d, "the preview has its own 3D world (the table is not drawn in it)")
	screen.call("apply_level", str(_app().get("gfx")))


## Every visible button is a touch target; nothing on the screen sticks out of the window sideways.
func _check_targets_and_layout(screen: Node) -> void:
	var small := PackedStringArray()
	var outside := PackedStringArray()
	var vis := root.get_visible_rect().size
	_walk(screen, func(c: Control) -> void:
		var r := c.get_global_rect()
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			small.append("%s %s" % [c.name, str(r.size)])
		if r.position.x < -1.0 or r.end.x > vis.x + 1.0:
			outside.append("%s %s" % [c.name, str(r)]))
	_check(small.is_empty(), "every button is at least 44x44", str(small.slice(0, 8)))
	_check(outside.is_empty(), "nothing sticks out of the %dx%d canvas sideways" % [int(vis.x), int(vis.y)], str(outside.slice(0, 8)))
	# the weapon table keeps its own width (numbers next to the names) and stays inside its card on wide canvases
	var wide := PackedStringArray()
	for k in screen.call("listed_units"):
		var card: Control = screen.call("card", k)
		for g in card.find_children("*", "GridContainer", true, false):
			var grid := g as GridContainer
			if grid.size.x > grid.get_combined_minimum_size().x + 1.0 or grid.get_global_rect().end.x > card.get_global_rect().end.x + 1.0:
				wide.append("%s %.0f/%.0f" % [k, grid.size.x, grid.get_combined_minimum_size().x])
	_check(wide.is_empty(), "every weapon table keeps its own width inside its card", str(wide.slice(0, 8)))
	for n in ["TopBar", "PreviewPanel"]:
		var c := screen.find_child(n, true, false) as Control
		var r := c.get_global_rect()
		_check(r.position.y >= 0.0 and r.end.y <= vis.y + 1.0, n + " fits the canvas vertically " + str(r))


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


## Unit-name labels (card names and the preview's name) that carry a hidden unit's name, Thai or English: must stay empty.
func _hidden_names_on(screen: Node) -> PackedStringArray:
	var names := PackedStringArray()
	for t: Dictionary in GameData.types():
		var k := str(t["k"])
		if GameData.is_hidden(k):
			names.append(str(t["nm"]))
			var en := str(root.get_node(^"I18n").call("lookup", str(t["nm"])))
			if en != "":
				names.append(en)
	var out := PackedStringArray()
	_walk(screen, func(c: Control) -> void:
		if c is Label and (String(c.name) == "Name" or String(c.name) == "UnitName"):
			if names.has((c as Label).text.strip_edges()):
				out.append(String(c.name)))
	return out


## Every visible text of the screen that still contains Thai: "NodeName: text"
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
		if node is LineEdit:
			texts.append((node as LineEdit).placeholder_text)
		if node is Control and (node as Control).tooltip_text != "":
			texts.append((node as Control).tooltip_text)
		for t in texts:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, exempt, out)


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
	_check(_mean_luma(img) > 0.02, name + " is not black")


func _finish() -> void:
	_app().call("set_lang", "th")
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
