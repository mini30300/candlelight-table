extends SceneTree
## Galaxy screen under xvfb (CAMPAIGN_SPEC §1.5, §4, §7 track A): week 2967 at every graphics level on desktop
## (1280×720), phone landscape (1600×720, touch) and phone portrait (720×1600, touch) in Thai and English. Checks the
## draw-call / primitive budget of §4 with the map alone and with the planet card open, that nothing redraws or processes
## after 10 idle frames (the map draws only on input, resize or data), that min and lo use the small baked texture, that
## a tap on a planet opens its card (right panel on wide screens, bottom sheet on narrow), that the brief fits, and no
## overflow past the screen edge. PNGs to $TEST_OUT (default godot/tests/out). Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_campaign_galaxy.gd

const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_campaign_galaxy.cfg"
const SAVE := "user://test_campaign_galaxy.json"
const GALAXY := "res://ui/screens/galaxy_screen.tscn"
const NOW := 1794657600      # Sat 14 Nov 2026 12:00 UTC = week 2967
const DESK := Vector2i(1280, 720)
const PHONE := Vector2i(1600, 720)
const TALL := Vector2i(720, 1600)
## §4: draw calls / primitives per level
const BUDGET := {"hi": [40, 60000], "mid": [30, 40000], "lo": [20, 20000], "min": [15, 10000]}

var _out_dir := DEFAULT_OUT_DIR
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var thai_re := RegEx.create_from_string("[฀-๿]")


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_touch", "off")
	CampaignWeek.test_now = NOW
	CampaignSave.path = SAVE
	CampaignSave.reset()
	# one cleared event so the check mark shows in the pictures
	var spec := CampaignGalaxy.mission_spec(2967, "p05", 0, "hard")
	CampaignSave.record(spec, {"win": true, "total": 2000, "coins": 75, "grade": "B"})


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _open(level: String, sz: Vector2i, touch: bool) -> Node:
	_app().call("set_gfx", level)
	_app().call("set_touch", "on" if touch else "off")
	root.size = sz
	var gs: Node = (load(GALAXY) as PackedScene).instantiate()
	root.add_child(gs)
	gs.call("open", {"difficulty": "hard", "week": 2967})
	await _frames(4)
	return gs


func _close(gs: Node) -> void:
	gs.queue_free()
	await _frames(2)


func _run() -> void:
	await _frames(2)
	OS.low_processor_usage_mode = false
	for level in ["hi", "mid", "lo", "min"]:
		var gs: Node = await _open(level, DESK, false)
		var mp: Variant = gs.call("map")
		var b: Array = BUDGET[level]
		var m := await _measure()
		_check(m[0] <= int(b[0]) and m[1] <= int(b[1]), "%s map: %d draw calls / %d primitives (budget %d / %d)" % [level, m[0], m[1], b[0], b[1]])
		var tex: Texture2D = GalaxyMap.texture_for(level)
		_check(tex.get_width() == int(GalaxyMap.TEX_SIZE[level]), "%s bakes a %d px galaxy" % [level, tex.get_width()])
		var d0: int = mp.draws()
		await _frames(10)
		_check(mp.draws() == d0, "%s: the map does not redraw while idle (%d -> %d)" % [level, d0, mp.draws()])
		var busy := _idle_problems(gs)
		_check(busy.is_empty(), "%s: nothing processes on the galaxy screen" % level, ", ".join(busy))
		if level == "hi":
			await _save("galaxy_map_th.png")
		mp.tap(mp.screen_pos(5))
		await _frames(3)
		_check(bool(gs.call("card_open")) and str(gs.get("planet_id")) == "p05", "%s: a tap on p05 opens its card (%s at %s, map %s)" % [level, str(gs.get("planet_id")), str(mp.screen_pos(5)), str(mp.get_global_rect())])
		var card: Control = gs.call("card")
		_check(card.get_global_rect().position.x > DESK.x * 0.5 and card.get_global_rect().end.x <= DESK.x + 0.5,
			"%s desktop: the card is a right-hand panel inside the screen" % level)
		var m2 := await _measure()
		_check(m2[0] <= int(b[0]) and m2[1] <= int(b[1]), "%s with the card: %d draw calls / %d primitives (budget %d / %d)" % [level, m2[0], m2[1], b[0], b[1]])
		if level == "hi":
			await _save("galaxy_card_th.png")
			gs.call("open_brief", 0)
			await _frames(3)
			await _save("galaxy_brief_th.png")
			var lb: Control = gs.call("brief").call("launch_button")
			_check(lb.is_visible_in_tree() and lb.get_global_rect().end.y <= DESK.y + 0.5, "the ออกรบ button is on screen")
		if level == "min":
			gs.call("open_brief", 0)
			var mb := await _measure()
			_check(mb[0] <= int(b[0]) and mb[1] <= int(b[1]), "min with the brief: %d draw calls / %d primitives (budget %d / %d)" % [mb[0], mb[1], b[0], b[1]])
			gs.call("close_brief")
			await _frames(2)
		if level == "min":
			for pl: Dictionary in CampaignGalaxy.week(2967)["planets"]:
				if (pl["events"] as Array).size() == 3:
					gs.call("select_planet", str(pl["id"]))
					var m3 := await _measure()
					_check(m3[0] <= int(b[0]) and m3[1] <= int(b[1]), "min with a 3-event card (%s): %d / %d" % [str(pl["id"]), m3[0], m3[1]])
					break
			var d1: int = mp.draws()
			await _frames(10)
			_check(mp.draws() == d1 and _idle_problems(gs).is_empty(), "min with the card: idle after 10 frames")
			await _save("galaxy_card_min.png")
		await _close(gs)
	# English, desktop, brief
	_app().call("set_lang", "en")
	var ge: Node = await _open("hi", DESK, false)
	ge.call("select_planet", "p05")
	await _frames(2)
	var thai := _thai_in(ge)
	_check(thai.is_empty(), "English: no Thai with the card open", ", ".join(thai))
	await _save("galaxy_card_en.png")
	ge.call("open_brief", 0)
	await _frames(2)
	thai = _thai_in(ge)
	_check(thai.is_empty(), "English: no Thai in the brief", ", ".join(thai))
	var over := _overflow(ge, DESK)
	_check(over.is_empty(), "English desktop: nothing past the screen edge", ", ".join(over))
	await _save("galaxy_brief_en.png")
	await _close(ge)
	# phone landscape (touch) and portrait
	for lang in ["th", "en"]:
		_app().call("set_lang", lang)
		var gp: Node = await _open("mid", PHONE, true)
		gp.call("select_planet", "p12")
		await _frames(3)
		over = _overflow(gp, PHONE)
		_check(over.is_empty(), "%s phone landscape: nothing past the screen edge" % lang, ", ".join(over))
		_check(not bool(gp.call("narrow")), "phone landscape keeps the side panel")
		await _save("galaxy_phone_%s.png" % lang)
		await _close(gp)
		var gt: Node = await _open("lo", TALL, true)
		var mt: Variant = gt.call("map")
		mt.tap(mt.screen_pos(12))
		await _frames(3)
		var card: Control = gt.call("card")
		var vt: Vector2 = gt.get_viewport_rect().size
		_check(bool(gt.call("narrow")) and bool(gt.call("card_open")) and card.get_global_rect().position.y > vt.y * 0.3
			and card.get_global_rect().end.y <= vt.y + 0.5, "%s portrait: a tap opens the card as a bottom sheet (%s in %s)" % [lang, str(card.get_global_rect()), str(vt)])
		_check(mt.get_global_rect().end.y <= card.get_global_rect().position.y + 0.5, "%s portrait: the map sits above the sheet" % lang)
		over = _overflow(gt, TALL)
		_check(over.is_empty(), "%s portrait: nothing past the screen edge" % lang, ", ".join(over))
		var m3 := await _measure()
		_check(m3[0] <= int(BUDGET["lo"][0]) and m3[1] <= int(BUDGET["lo"][1]), "%s portrait lo: %d / %d within the lo budget" % [lang, m3[0], m3[1]])
		await _save("galaxy_tall_card_%s.png" % lang)
		gt.call("open_brief", 0)
		await _frames(3)
		var lb: Control = gt.call("brief").call("launch_button")
		_check(lb.is_visible_in_tree() and lb.get_global_rect().end.y <= vt.y + 0.5 and lb.size.y >= 44.0, "%s portrait: ออกรบ is on screen and touch-sized" % lang)
		await _save("galaxy_tall_brief_%s.png" % lang)
		# zoom and pan by input
		var z0: float = mt.zoom
		mt.set_zoom(2.0, mt.size * 0.5)
		await _frames(2)
		_check(is_equal_approx(float(mt.zoom), 2.0) and float(mt.zoom) > z0, "%s: zoom 2x" % lang)
		mt.set_zoom(9.0)
		_check(is_equal_approx(float(mt.zoom), GalaxyMap.ZOOM_MAX), "%s: zoom stops at 3x" % lang)
		await _close(gt)
	root.size = DESK
	_finish()


func _measure() -> Array:
	for _i in 4:
		await process_frame
	var d := 0
	var p := 0
	for _i in 4:
		await process_frame
		d = maxi(d, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return [d, p]


func _idle_problems(n0: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [n0]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		stack.append_array(n.get_children())
	return out


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in node.find_children("*", "", true, false):
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
			out.append(String(c.name) + ": " + t.left(50))
	return out


## Labels and buttons whose box leaves the screen sideways (vertical scroll areas are fine)
func _overflow(node: Node, _sz: Vector2i) -> PackedStringArray:
	var out := PackedStringArray()
	var sz := (node as Control).get_viewport_rect().size
	for c in node.find_children("*", "", true, false):
		if not (c is Label or c is Button or c is RichTextLabel) or not (c as Control).is_visible_in_tree():
			continue
		var r := (c as Control).get_global_rect()
		if r.position.x < -0.5 or r.end.x > sz.x + 0.5:
			out.append("%s %s" % [String(c.name), str(r)])
	return out


func _save(name: String) -> void:
	await _frames(1)
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var err := img.save_png(_out_dir + "/" + name)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(_out_dir + "/" + name))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
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
