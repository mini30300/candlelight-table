extends SceneTree
## Shared walk for the dressing room (PACK_SPEC §9.6), run headless by test_dressing_flow.gd and under xvfb by
## tests/render/test_dressing.gd (RENDER = true: TH/EN screenshots on desktop and phone, draw calls, min idle).
## Neutral fixture room tests/fixtures/pack_rooms_dressing/dress_room (test_room with a "dressing" station "wardrobe"),
## online flag on, no network. Figures: the real app/figures.gd when it exists, else (or with DRESS_STUB=1) the stub
## tests/unit/fixtures/figures_stub.gd. Main menu → เล่นกับบอท → the deck → the room at the wardrobe; E opens the
## dressing screen with one button per Figures.list() entry and one swatch per scheme; picking a paintable figure shows it
## in the preview, a scheme reaches it through H10 apply_scheme; a figure that keeps its own colours disables the swatches
## and says so; saving slot 2 stores {figure, scheme} and names it; loading it brings the pair back; English leaves no Thai;
## "ใช้ตัวนี้" selects, closes and the room's avatar is the new figure with the scheme; a reload keeps the selection and the
## slot; ‹ กลับ closes without a change; on min nothing under the dressing screen processes after 10 frames.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_dressing.cfg"
const STUB_FILE := "user://test_dressing_stub.cfg"
const FIX := "res://tests/fixtures/pack_rooms_dressing"
const STUB := "res://tests/unit/fixtures/figures_stub.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const PHONE := Vector2i(1600, 720)
## หน้าแต่งตัวโหลดตอนรัน (สคริปต์ -s คอมไพล์ก่อนมี autoload App)
const DS_PATH := "res://ui/screens/dressing_screen.gd"
const FIGURES := "res://app/figures.gd"

var RENDER := false
var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _stub := false
var _api: Object
var DS: Script
var _t0 := 0


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STUB_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("load_settings")
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "off")
	DS = load(DS_PATH)
	_stub = OS.get_environment("DRESS_STUB") == "1" or not ResourceLoader.exists(FIGURES)
	_api = _new_api()
	DS.set("api", _api if _stub else null)
	PackRooms.reset()
	PackRooms.test_root = FIX
	Features.set_flag(&"online", true)
	_main = (load(SCENE) as PackedScene).instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_t0 = Time.get_ticks_msec()
		_run()
	elif not _done and Time.get_ticks_msec() - _t0 > 240000:
		_check(false, "the walk finished within 240 s (a script error stops it)")
		_finish()
	return _done


func _new_api() -> Object:
	if _stub:
		var s: Object = (load(STUB) as GDScript).new()
		s.set("path", STUB_FILE)
		return s
	return load(FIGURES)


func _run() -> void:
	print("      Figures: " + ("stub (tests/unit/fixtures/figures_stub.gd)" if _stub else "app/figures.gd"))
	_check(PackRooms.ACTIONS.has("dressing"), "dressing is a station action")
	var rooms := PackRooms.list(FIX)
	_check(rooms.size() == 1 and str(rooms[0]["id"]) == "dress_room", "the fixture room with a dressing station validates")
	_check(PackRooms.list("res://packs/rooms_absent").is_empty(), "no pack rooms: nothing new (public app)")
	await _frames(3)
	var menu: Node = _app().call("current")
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	var room: Node = hall.call("_open_room", "wardrobe") if hall != null and hall.has_method("_open_room") else null
	await _frames(20)
	_check(room != null and _app().call("current") == room, "the deck opens the fixture room at the wardrobe")
	if room == null:
		_finish()
		return
	_check(str(room.call("station")) == "wardrobe", "the wardrobe is in reach", str(room.call("station")))
	var prompt: Button = room.get_node("%UseButton")
	_check(prompt.visible and prompt.text.begins_with("ตู้แต่งตัว"), "its prompt names it", prompt.text)
	var rw: Node3D = room.get("world")
	var avatar: Node3D = rw.get("avatar")
	var before: Variant = avatar.get("figure")
	var before_id := (before as Node3D).get_instance_id() if before != null else 0
	await _press(KEY_E)
	var ds: Node = _app().call("current")
	_check(ds is Control and ds.get_script() == DS, "E at the wardrobe opens the dressing screen")
	if not (ds is Control and ds.get_script() == DS):
		_finish()
		return
	await _frames(3)
	await _check_screen(ds)
	var target := str(ds.get("figure_id"))
	var scheme := str(ds.get("scheme_id"))
	ds.use_selection()
	await _frames(4)
	_check(_app().call("current") == room and room.is_visible_in_tree(), "ใช้ตัวนี้ closes the screen back to the room")
	var sel: Dictionary = _api.call("selected")
	_check(str(sel.get("figure")) == target and str(sel.get("scheme")) == scheme, "Figures.select got the pair",
		"%s / %s vs %s / %s" % [sel.get("figure"), sel.get("scheme"), target, scheme])
	var now: Variant = avatar.get("figure")
	var now_id := (now as Node3D).get_instance_id() if now != null else 0
	_check(now != null and now_id != before_id and (now as Node3D).get_parent() == avatar, "the room's avatar is the new figure",
		"%d → %d" % [before_id, now_id])
	_check(not (avatar.get_node("Egg") as Node3D).visible, "the egg is hidden")
	var want := _scheme_colour(scheme)
	if now != null and now.get("scheme") is Array:
		var got: Array = now.get("scheme")
		_check(got.size() == 2 and got[0] == want, "the avatar wears the chosen scheme (H10)", str(got))
	if RENDER:
		await _frames(3)
		_save("dressing_room_after_th.png")
	# โหลดใหม่: การเลือกและช่องบันทึกยังอยู่
	_app().call("load_settings")
	var again := _new_api()
	var sel2: Dictionary = again.call("selected")
	var slots: Array = again.call("slots")
	_check(str(sel2.get("figure")) == target and str(sel2.get("scheme")) == scheme, "the selection persists after a reload",
		str(sel2))
	_check(slots.size() == 3 and slots[1] is Dictionary and str((slots[1] as Dictionary).get("figure", "")) == target,
		"slot 2 persists after a reload", str(slots))
	await _check_back_and_min(room, avatar)
	await _check_not_ready(room)
	_finish()


func _check_screen(ds: Node) -> void:
	var list: Array = _api.call("list")
	var schemes: Array = _api.call("schemes")
	_check(ds.char_buttons().size() == list.size() and list.size() >= 2, "one button per character", "%d / %d" % [ds.char_buttons().size(), list.size()])
	_check(ds.swatch_buttons().size() == schemes.size() and schemes.size() >= 2, "one swatch per scheme")
	_check(ds.slot_buttons().size() == 3 and ds.save_buttons().size() == 3, "three slots with save buttons")
	_check(ds.get_node("Safe").get_child(0).get_child(0).get_child(1).get("text") == "ห้องแต่งตัว", "the Thai title")
	# ตัวที่ทาสีได้ (ไม่ใช่ตัวที่เลือกอยู่) และตัวที่ใช้สีของตัวเอง
	var cur := str(ds.get("figure_id"))
	var paint := ""
	var fixed := ""
	for e: Dictionary in list:
		if bool(e.get("schemes", false)) and paint == "" and str(e["id"]) != cur:
			paint = str(e["id"])
		if not bool(e.get("schemes", false)) and str(e.get("kind", "")) != "egg" and fixed == "":
			fixed = str(e["id"])
	_check(paint != "", "a paintable character to pick")
	if paint == "":
		return
	if fixed != "":
		ds.pick_figure(fixed)
		await _frames(2)
		_check(ds.swatch_buttons().all(func(b: Button) -> bool: return b.disabled), "a figure with its own colours disables the swatches")
		_check(_visible_text(ds, "ตัวนี้ใช้สีของตัวเอง"), "and says so")
	_press_button(_char_button(ds, paint))
	await _frames(2)
	_check(ds.figure_id == paint and ds.preview_figure() != null and ds.preview_figure().is_inside_tree(), "picking a character shows it in the preview")
	_check(ds.swatch_buttons().all(func(b: Button) -> bool: return not b.disabled), "its swatches are enabled")
	var sch := str(schemes[1]["id"])
	_press_button(ds.swatch_buttons()[1])
	await _frames(2)
	_check(ds.scheme_id == sch and ds.swatch_buttons()[1].button_pressed, "tapping a swatch picks the scheme", ds.scheme_id)
	var pf: Node3D = ds.preview_figure()
	var sc: Variant = pf.call("scheme") if pf.has_method("scheme") else pf.get("scheme")
	if sc is Array:
		var got: Array = sc
		_check(got.size() == 2 and got[0] == schemes[1]["primary"] and got[1] == schemes[1]["secondary"], "the preview wears it (H10)", str(got))
	# สีเดิม (Figures รอบ C): ปุ่มแรก สร้างตัวอย่างใหม่โดยไม่ทาสี แล้วกลับไปชุดสีที่เลือก
	if bool(schemes[0].get("original", false)):
		_press_button(ds.swatch_buttons()[0])
		await _frames(2)
		var pf0: Node3D = ds.preview_figure()
		var sc0: Variant = pf0.call("scheme") if pf0.has_method("scheme") else pf0.get("scheme")
		_check(ds.scheme_id == str(schemes[0]["id"]) and pf0 != pf and (not sc0 is Array or (sc0 as Array).is_empty()),
			"the original swatch rebuilds the preview unpainted")
		_check(ds.swatch_buttons()[0].text == "เดิม", "the original swatch is labelled", ds.swatch_buttons()[0].text)
		_press_button(ds.swatch_buttons()[1])
		await _frames(2)
	_press_button(ds.save_buttons()[1])
	await _frames(2)
	var slots: Array = _api.call("slots")
	_check(slots[1] is Dictionary and str(slots[1].get("figure", "")) == paint and str(slots[1].get("scheme", "")) == sch, "saving slot 2 stores the pair", str(slots))
	var nm := PackRooms.text(list[list.map(func(e: Dictionary) -> String: return str(e["id"])).find(paint)]["name"])
	_check(ds.slot_buttons()[1].text.begins_with("ช่อง 2: " + nm) and not ds.slot_buttons()[1].disabled, "slot 2 shows its name", ds.slot_buttons()[1].text)
	_check(_visible_text(ds, "บันทึกช่อง 2 แล้ว"), "a saved note")
	_check(ds.slot_buttons()[0].disabled and ds.slot_buttons()[0].text == "ช่อง 1: ว่าง", "an empty slot says so and does nothing", ds.slot_buttons()[0].text)
	# เลือกตัวอื่นแล้วโหลดช่อง 2 กลับมา
	var other := str(list[0]["id"]) if str(list[0]["id"]) != paint else str(list[1]["id"])
	ds.pick_figure(other)
	await _frames(2)
	_press_button(ds.slot_buttons()[1])
	await _frames(2)
	_check(ds.figure_id == paint and ds.scheme_id == sch, "loading slot 2 brings the pair back")
	if RENDER:
		await _frames(4)
		_save("dressing_th.png")
	_app().call("set_lang", "en")
	ds.refresh()
	await _frames(2)
	var thai := _thai_in(ds)
	_check(thai.is_empty(), "English mode: no Thai on the dressing screen", ", ".join(thai))
	var vh0: float = ds.get_viewport_rect().size.y
	_check(not RENDER or (ds.use_button().get_global_rect().end.y <= vh0 + 1.0 and ds.save_buttons()[2].get_global_rect().end.y <= vh0 + 1.0),
		"desktop: ใช้ตัวนี้ and the last slot are on screen")
	_check(ds.use_button().text == "Use this", "Use this", ds.use_button().text)
	if RENDER:
		_save("dressing_en.png")
		_app().call("set_touch", "on")
		var size0 := root.size
		root.size = PHONE
		ds.set("touch_mode", true)
		ds.call("_layout")
		await _frames(4)
		var vh: float = ds.get_viewport_rect().size.y
		_check(ds.use_button().get_global_rect().end.y <= vh + 1.0 and ds.save_buttons()[2].get_global_rect().end.y <= vh + 1.0
			and ds.use_button().size.y >= 63.0, "phone: ใช้ตัวนี้ and the last slot are on screen with touch-size buttons")
		_save("dressing_phone_en.png")
		_app().call("set_lang", "th")
		ds.refresh()
		await _frames(2)
		_save("dressing_phone_th.png")
		root.size = size0
		ds.set("touch_mode", false)
		_app().call("set_touch", "off")
		ds.call("_layout")
		await _frames(2)
	_app().call("set_lang", "th")
	ds.refresh()


func _check_back_and_min(room: Node, avatar: Node3D) -> void:
	_app().call("set_gfx", "min")
	room.call("refresh")
	var keep: Variant = avatar.get("figure")
	room.call("use_station")
	await _frames(2)
	var ds: Node = _app().call("current")
	_check(ds is Control and ds.get_script() == DS, "the wardrobe opens the screen again")
	if not (ds is Control and ds.get_script() == DS):
		return
	await _frames(10)
	var busy := _idle_problems(ds)
	_check(busy.is_empty(), "min: nothing under the dressing screen processes after 10 frames", ", ".join(busy))
	var vp: SubViewport = ds.preview_viewport()
	_check(vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "min: the preview does not redraw every frame")
	if RENDER:
		# ทั้งเฟรมเป็นปุ่ม 2 มิติเกือบหมด (รายงานไว้) · ภาพตัวอย่างต้องอยู่ในงบตัวละครของ PACK_SPEC §3.5 + แท่น 1 ครั้ง
		var m := await _measure()
		var pv := await _measure_preview(ds)
		print("info  dressing screen min: frame draw calls %d, primitives %d; preview %d / %d" % [m[0], m[1], pv[0], pv[1]])
		_check(pv[0] <= 4 and pv[1] <= 8000, "min: the preview fits the figure budget (3 draws / 7k + the plinth)", str(pv))
		_app().call("set_gfx", "hi")
		ds.set("level", "hi")
		ds.call("_show_figure")
		var m2 := await _measure()
		var pv2 := await _measure_preview(ds)
		print("info  dressing screen hi: frame draw calls %d, primitives %d; preview %d / %d" % [m2[0], m2[1], pv2[0], pv2[1]])
		_check(pv2[0] <= 5 and pv2[1] <= 31000, "hi: the preview fits the figure budget (4 draws / 30k + the plinth)", str(pv2))
		_save("dressing_hi.png")
		ds.set("level", "min")
		ds.call("_show_figure")
		_app().call("set_gfx", "min")
	ds.pick_figure(str((_api.call("list") as Array)[0]["id"]))
	await _press(KEY_ESCAPE)
	await _frames(2)
	_check(_app().call("current") == room, "Esc closes the dressing screen")
	_check(avatar.get("figure") == keep, "closing without ใช้ตัวนี้ leaves the avatar as it was")
	_app().call("set_gfx", "mid")
	room.call("refresh")


func _check_not_ready(room: Node) -> void:
	DS.set("api", null)
	DS.set("path", "res://tests/absent_figures.gd")
	var shown: Variant = room.call("open_dressing")
	await _frames(2)
	_check(shown == null and _app().call("current") == room and room.get_node("%SoonPanel").visible
		and (room.get_node("%SoonLabel") as Label).text == "ห้องแต่งตัว — ยังไม่พร้อม", "no Figures file: a not-ready note, no screen")
	DS.set("api", _api if _stub else null)
	DS.set("path", FIGURES)
	room.call("close_soon")


func _scheme_colour(id: String) -> Color:
	for s: Dictionary in _api.call("schemes"):
		if str(s["id"]) == id:
			return s["primary"]
	return Color.BLACK


func _char_button(ds: Node, id: String) -> Button:
	for b in ds.char_buttons():
		if str(b.get_meta(&"id")) == id:
			return b
	return null


func _press_button(b: Button) -> void:
	if b == null:
		_check(false, "button exists")
		return
	if b.toggle_mode:
		b.button_pressed = true
	b.pressed.emit()


func _visible_text(node: Node, text: String) -> bool:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return false
	if (node is Label or node is Button) and str(node.get("text")) == text:
		return true
	for c in node.get_children():
		if _visible_text(c, text):
			return true
	return false


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


## ภาพตัวอย่างอย่างเดียว: ขอวาดหนึ่งครั้งแล้วอ่านของ SubViewport
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
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing() and (n as AnimationPlayer).speed_scale != 0.0 \
				and n.can_process():
			out.append(String(n.name) + " plays")
		stack.append_array(n.get_children())
	return out


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return out
	var texts := PackedStringArray()
	if node is Label or node is Button:
		texts.append(str(node.get("text")))
		texts.append(str(node.get("tooltip_text")))
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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var err := img.save_png(_out_dir + "/" + name)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(_out_dir + "/" + name))


func _finish() -> void:
	DS.set("api", null)
	DS.set("path", FIGURES)
	PackRooms.reset()
	Features.reset()
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STUB_FILE))
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
