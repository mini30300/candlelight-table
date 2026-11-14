extends SceneTree
## Report screen under xvfb (CAMPAIGN_SPEC §1.7, §4, §7 track A): a win with every score line and a fail, Thai and
## English, desktop (1280×720), phone landscape (1600×720) and portrait (720×1600). Checks the numbers shown against
## CampaignRules.score, the budget of §4 per level, the count-up tween on hi/mid only (lo/min show the final numbers at
## once, no Tween), nothing processes once the numbers stand, and nothing past the screen edge. PNGs to $TEST_OUT. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_campaign_report.gd

const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_campaign_report.cfg"
const REPORT := "res://ui/screens/report_screen.tscn"
const DESK := Vector2i(1280, 720)
const PHONE := Vector2i(1600, 720)
const TALL := Vector2i(720, 1600)
const BUDGET := {"hi": [30, 20000], "mid": [30, 20000], "lo": [25, 15000], "min": [20, 10000]}

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


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _spec() -> Dictionary:
	# p04 of week 2967 has three events: one primary and two secondaries; at very hard
	return CampaignGalaxy.mission_spec(2967, "p04", 0, "veryhard")


func _win() -> Dictionary:
	return {"v": 1, "outcome": "win", "time_s": 201.4, "kills": {"rusher": 22, "gunner": 9, "brute": 4, "boss": 1, "structure": 3},
		"shots": 80, "hits": 52, "damage_taken": 140, "downs": 1, "secondary_done": [true, false],
		"hostages_saved": 1, "hostages_total": 1}


func _fail() -> Dictionary:
	return {"v": 1, "outcome": "fail", "time_s": 95.0, "kills": {"rusher": 6, "gunner": 1}, "shots": 30, "hits": 9,
		"damage_taken": 700, "downs": 2, "secondary_done": [false, false]}


func _open(level: String, sz: Vector2i, result: Dictionary, featured := false, repeat := false) -> Node:
	_app().call("set_gfx", level)
	root.size = sz
	var spec := _spec()
	spec["featured"] = featured
	var sc := CampaignRules.score(spec, result, {"repeat": repeat})
	sc["repeat"] = repeat
	var rs: Node = (load(REPORT) as PackedScene).instantiate()
	root.add_child(rs)
	rs.call("open", {"spec": spec, "result": result, "score": sc, "coins": 500 + int(sc["coins"])})
	await _frames(3)
	return rs


func _run() -> void:
	await _frames(2)
	OS.low_processor_usage_mode = false
	for level in ["hi", "mid", "lo", "min"]:
		var rs: Node = await _open(level, DESK, _win(), level == "hi", level == "mid")
		var tween_on: bool = level == "hi" or level == "mid"
		_check(bool(rs.call("counting")) == tween_on, "%s: the count-up tween %s" % [level, "runs" if tween_on else "is not used"])
		if tween_on:
			var t0 := Time.get_ticks_msec()
			while bool(rs.call("counting")) and Time.get_ticks_msec() - t0 < 1500:
				await process_frame
		_check(not bool(rs.call("counting")), "%s: the numbers stand after at most 1.2 s" % level)
		var spec := _spec()
		spec["featured"] = level == "hi"
		var sc := CampaignRules.score(spec, _win(), {"repeat": level == "mid"})
		var shown: Dictionary = rs.call("shown")
		_check(str(shown["total"]).contains(str(sc["total"])) and str(shown["raw"]).contains(str(sc["raw"])), "%s: raw %d and total %d" % [level, int(sc["raw"]), int(sc["total"])])
		_check(str(shown["earned"]).contains("+%d" % int(sc["coins"])) and str(shown["wallet"]).contains(str(500 + int(sc["coins"]))), "%s: +%d coins, wallet %d" % [level, int(sc["coins"]), 500 + int(sc["coins"])])
		_check(str(shown["grade"]) == str(sc["grade"]), "%s: grade %s" % [level, str(sc["grade"])])
		_check((shown["lines"] as Array).size() == (sc["lines"] as Array).size(), "%s: one row per score line (%d)" % [level, (sc["lines"] as Array).size()])
		if level == "hi":
			_check(str(shown["notes"]).contains("×1.5"), "the featured bonus is noted")
		if level == "mid":
			_check(str(shown["notes"]).contains("25 %"), "the repeat clear is noted")
		var m := await _measure()
		var b: Array = BUDGET[level]
		_check(m[0] <= int(b[0]) and m[1] <= int(b[1]), "%s report: %d draw calls / %d primitives (budget %d / %d)" % [level, m[0], m[1], b[0], b[1]])
		var busy := _idle_problems(rs)
		_check(busy.is_empty(), "%s: nothing processes once the numbers stand" % level, ", ".join(busy))
		var over := _overflow(rs)
		_check(over.is_empty(), "%s desktop: nothing past the screen edge" % level, ", ".join(over))
		if level == "hi":
			await _save("report_win_th.png")
		rs.queue_free()
		await _frames(2)
	# fail in English, desktop and phones
	_app().call("set_lang", "en")
	for sz: Vector2i in [DESK, PHONE, TALL]:
		var rf: Node = await _open("lo", sz, _fail())
		var shown: Dictionary = rf.call("shown")
		_check(str(shown["grade"]) == "-" and str(shown["title"]) == "Mission result: failed", "fail %s: grade - and the failed title" % str(sz))
		var thai := _thai_in(rf)
		for tile: Array in shown["tiles"]:
			if thai_re.search(str(tile[0])) != null:
				thai.append("tile " + str(tile[0]))
		for line: Array in shown["lines"]:
			if thai_re.search(str(line[0])) != null:
				thai.append("line " + str(line[0]))
		for k in ["raw", "mult", "earned", "wallet", "total"]:
			if thai_re.search(str(shown[k])) != null:
				thai.append(str(shown[k]))
		_check(thai.is_empty(), "English %s: no Thai on the report" % str(sz), ", ".join(thai))
		var over := _overflow(rf)
		_check(over.is_empty(), "English %s: nothing past the screen edge" % str(sz), ", ".join(over))
		for btn: Button in rf.call("buttons"):
			_check(btn.size.y >= 44.0 and btn.get_global_rect().end.x <= rf.get_viewport_rect().size.x + 0.5, "%s: %s is touch-sized and on screen" % [str(sz), btn.name])
		await _save("report_fail_en_%dx%d.png" % [sz.x, sz.y])
		rf.queue_free()
		await _frames(2)
	_app().call("set_lang", "th")
	var rp: Node = await _open("mid", TALL, _win(), true)
	rp.call("finish_count")
	await _frames(2)
	_check(bool(rp.call("narrow")), "portrait: score and reward stack")
	await _save("report_win_th_tall.png")
	rp.queue_free()
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
		if t != "" and thai_re.search(t) != null:
			out.append(String(c.name) + ": " + t.left(50))
	return out


func _overflow(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var sz := (node as Control).get_viewport_rect().size
	for c in node.find_children("*", "", true, false):
		if not (c is Label or c is Button) or not (c as Control).is_visible_in_tree():
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
