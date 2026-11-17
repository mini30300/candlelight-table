extends SceneTree
## Dressing room with many palettes (PACK_SPEC §10.1, H11): the fixture pack tests/fixtures/figure_pack_palettes lists a
## figure with 24 palettes (plus broken ones the registry skips), an H10-only figure with 2 and a fixed-colour figure.
## The dressing screen shows the 9 presets + the figure's palettes as a scrolling grid of named cards that fits desktop,
## phone landscape and phone portrait; the selected palette is pressed; picking one paints the preview through H11; the
## last card scrolls into view and can be picked; a slot keeps a pack palette and names it; English shows no Thai; another
## figure gets its own list (H10 fallback figure: presets + 2; fixed-colour figure: presets, disabled); ใช้ตัวนี้ selects
## the pair. On min nothing under the screen processes after 10 frames, the preview never redraws every frame and fits the
## figure budget; hi too. Saves dressing_palettes_<case>.png. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_dressing_palettes.gd
## TEST_OUT (an absolute folder) replaces tests/out. Exit code 1 on any failure; the last line is PASS or FAIL.

const DS_PATH := "res://ui/screens/dressing_screen.tscn"
const PAL_LIST := "res://tests/fixtures/figure_pack_palettes/figures.json"
const SETTINGS_FILE := "user://test_dressing_palettes.cfg"
const STORE := "user://test_dressing_palettes_fig.cfg"
const DEFAULT_OUT_DIR := "res://tests/out"
const N_PACK := 24

var _out_dir := DEFAULT_OUT_DIR
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _t0 := 0


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	for f in [SETTINGS_FILE, STORE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "hi")
	app.call("set_touch", "off")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_t0 = Time.get_ticks_msec()
		_run()
	elif not _done and Time.get_ticks_msec() - _t0 > 240000:
		_check(false, "the walk finished within 240 s (a script error stops it)")
		_finish()
	return _done


func _run() -> void:
	var fig: Script = load("res://app/figures.gd")
	fig.set("store_path", STORE)
	fig.set("pack_list", PAL_LIST)
	fig.call("select", "palettes", "p05")
	root.size = Vector2i(1280, 720)
	var ds := await _open()
	var pals: Array = fig.call("palettes", "palettes")
	_check(pals.size() == 9 + N_PACK, "the registry gives the presets + %d pack palettes" % N_PACK, str(pals.size()))
	_check(ds.swatch_buttons().size() == pals.size(), "one card per palette (%d)" % pals.size(), str(ds.swatch_buttons().size()))
	_check(str(ds.get("scheme_id")) == "p05" and _card(ds, "p05").button_pressed, "the saved palette is selected and pressed")
	_check(_card(ds, "p05").text == "ขาวแดงชาด" and _card(ds, "original").text == "เดิม", "cards are named (Thai)",
		"%s / %s" % [_card(ds, "p05").text, _card(ds, "original").text])
	await _layout_checks(ds, "desktop", 4)
	# เลือกชุด: ภาพตัวอย่างได้ทั้งชุดผ่าน H11
	_press(_card(ds, "p01"))
	await _frames(2)
	var want: Dictionary = fig.call("palette", "p01", "palettes")["colours"]
	var pf: Node3D = ds.preview_figure()
	_check(str(ds.get("scheme_id")) == "p01" and pf != null and pf.get("palette") == want, "picking a card paints the preview through H11")
	# การ์ดสุดท้าย: เลื่อนให้เห็นแล้วกดได้
	var last: Button = ds.swatch_buttons()[-1]
	var sc: ScrollContainer = ds.get("_swatch_scroll")
	sc.ensure_control_visible(last)
	await _frames(3)
	_check(sc.get_global_rect().grow(1.0).encloses(last.get_global_rect()), "the last card scrolls into view")
	_press(last)
	await _frames(2)
	_check(str(ds.get("scheme_id")) == "p23", "and can be picked", str(ds.get("scheme_id")))
	await _save("dressing_palettes_desktop_th.png")
	ds.save_slot(0)
	await _frames(2)
	var sl: Array = fig.call("slots")
	_check(sl[0] is Dictionary and str(sl[0].get("scheme", "")) == "p23", "a slot keeps the pack palette", str(sl))
	_check(ds.slot_buttons()[0].text.ends_with("· น้ำตาลทอง"), "the slot names the palette", ds.slot_buttons()[0].text)
	sc.scroll_vertical = 0
	_press(_card(ds, "p01"))
	await _frames(2)
	_app().call("set_lang", "en")
	ds.refresh()
	await _frames(2)
	var thai := PackedStringArray()
	for b: Button in ds.swatch_buttons():
		if _thai_re.search(b.text + b.tooltip_text) != null:
			thai.append(b.name)
	_check(thai.is_empty() and _card(ds, "p01").text == "Vermilion & Black", "English: every card name is English", ", ".join(thai))
	await _save("dressing_palettes_desktop_en.png")
	# มือถือแนวนอนและแนวตั้ง (ปุ่มขนาดนิ้ว)
	_app().call("set_touch", "on")
	_app().call("set_lang", "th")
	ds = await _reopen(ds)
	for c in [["phone_land", Vector2i(1600, 720), 4], ["phone_tall", Vector2i(720, 1520), 3]]:
		root.size = c[1]
		ds.call("_layout")
		await _frames(4)
		await _layout_checks(ds, c[0], c[2])
		_check(_card(ds, "p01").size.y >= 103.0, "%s: touch-size cards" % c[0], str(_card(ds, "p01").size))
		await _save("dressing_palettes_%s_th.png" % c[0])
	root.size = Vector2i(1280, 720)
	_app().call("set_touch", "off")
	# ตัวอื่น: H10 อย่างเดียว ได้ชุดสำเร็จรูป + 2 ; ตัวสีตายตัว: ชุดสำเร็จรูป ปิดหมด
	ds = await _reopen(ds)
	ds.pick_figure("h10_only")
	await _frames(2)
	_check(ds.swatch_buttons().size() == 9 + 2 and str(ds.get("scheme_id")) == "original", "another figure gets its own list (presets + 2) and falls back to the original",
		"%d %s" % [ds.swatch_buttons().size(), ds.get("scheme_id")])
	_press(_card(ds, "q_teal"))
	await _frames(2)
	var t: Dictionary = fig.call("palette", "q_teal", "h10_only")
	_check(ds.preview_figure().get("scheme") == [t["primary"], t["secondary"]], "an H10-only figure wears a pack palette as primary/secondary")
	ds.pick_figure("fixed")
	await _frames(2)
	_check(ds.swatch_buttons().size() == 9 and ds.swatch_buttons().all(func(b: Button) -> bool: return b.disabled),
		"a fixed-colour figure shows the presets disabled")
	ds.pick_figure("h10_only")
	await _frames(1)
	_press(_card(ds, "q_teal"))
	await _frames(1)
	ds.use_selection()
	await _frames(3)
	_check(fig.call("selected") == {"figure": "h10_only", "scheme": "q_teal"}, "ใช้ตัวนี้ selects the pair", str(fig.call("selected")))
	# min และ hi: ไม่มีงานต่อเฟรม ภาพตัวอย่างอยู่ในงบ
	fig.call("select", "palettes", "p02")
	for l in ["min", "hi"]:
		_app().call("set_gfx", l)
		ds = await _open()
		await _frames(10)
		if l == "min":
			var busy := _idle_problems(ds)
			_check(busy.is_empty(), "min: nothing under the dressing screen processes after 10 frames", ", ".join(busy))
			_check((ds.preview_viewport() as SubViewport).render_target_update_mode != SubViewport.UPDATE_ALWAYS, "min: the preview does not redraw every frame")
		var m := await _measure()
		var pv := await _measure_preview(ds)
		print("info  dressing palettes %s: frame draw calls %d, primitives %d; preview %d / %d" % [l, m[0], m[1], pv[0], pv[1]])
		_check(pv[0] <= 5 and pv[1] <= 31000, "%s: the preview fits the figure budget" % l, str(pv))
		await _save("dressing_palettes_%s.png" % l)
		ds.close()
		await _frames(2)
	_finish()


func _open() -> Node:
	var ds: Node = _app().call("push", load(DS_PATH))
	await _frames(6)
	return ds


func _reopen(ds: Node) -> Node:
	ds.close()
	await _frames(2)
	return await _open()


func _layout_checks(ds: Node, tag: String, min_cols: int) -> void:
	var vs: Vector2 = ds.get_viewport_rect().size
	var sc: ScrollContainer = ds.get("_swatch_scroll")
	var grid: GridContainer = ds.get("_swatches")
	var r := sc.get_global_rect()
	_check(r.position.x >= -1.0 and r.end.x <= vs.x + 1.0 and r.position.y >= -1.0 and r.end.y <= vs.y + 1.0 and r.size.y >= 90.0,
		"%s: the palette grid is on screen" % tag, str(r))
	_check(grid.columns >= min_cols, "%s: at least %d columns" % [tag, min_cols], str(grid.columns))
	_check(grid.size.y > r.size.y + 10.0, "%s: the grid scrolls (more cards than fit)" % tag, "%s / %s" % [grid.size.y, r.size.y])
	_check(ds.use_button().get_global_rect().end.y <= vs.y + 1.0 and ds.save_buttons()[2].get_global_rect().end.y <= vs.y + 1.0,
		"%s: ใช้ตัวนี้ and the last slot are on screen" % tag)
	var cut := 0
	for b: Button in ds.swatch_buttons():
		if b.get_global_rect().end.x > r.end.x + 1.0:
			cut += 1
	_check(cut == 0, "%s: no card sticks out sideways" % tag, str(cut))


func _card(ds: Node, id: String) -> Button:
	for b: Button in ds.swatch_buttons():
		if str(b.get_meta(&"id")) == id:
			return b
	return null


func _press(b: Button) -> void:
	if b == null:
		_check(false, "card exists")
		return
	b.button_pressed = true
	b.pressed.emit()


func _measure() -> Array:
	for _i in 4:
		await process_frame
	var d := 0
	var p := 0
	for _i in 3:
		await process_frame
		d = maxi(d, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return [d, p]


func _measure_preview(ds: Node) -> Array:
	var v: SubViewport = ds.preview_viewport()
	v.render_target_update_mode = SubViewport.UPDATE_ONCE
	for _i in 3:
		await process_frame
	var rid := v.get_viewport_rid()
	return [RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)]


func _idle_problems(n0: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [n0]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing() and (n as AnimationPlayer).speed_scale != 0.0 and n.can_process():
			out.append(String(n.name) + " plays")
		stack.append_array(n.get_children())
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var err := img.save_png(_out_dir + "/" + name)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(_out_dir + "/" + name))


func _finish() -> void:
	var fig: Script = load("res://app/figures.gd")
	fig.set("store_path", "")
	fig.set("pack_list", "res://packs/figures.json")
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	for f in [SETTINGS_FILE, STORE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
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
