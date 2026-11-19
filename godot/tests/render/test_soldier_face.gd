extends SceneTree
## The soldier's face (ใหม่ 0.14 item 2: scenes/arena/soldier_face.gd on SoldierFigure) under xvfb, a close-up of every
## body (base, m2, m3, f1, f2). Checks, per body:
##  - closed lids hide the eye whites (an eye close-up): on hi the bright, unsaturated pixels of the eye band with the lids
##    closed are fewer than 35 % of those with the eyes open; lo paints its lids too (its blurred eyes have no white to
##    count: at least 8 % of the eye band (both eyes and the skin around) changes when the lids close, the mouth band
##    does not);
##  - an open mouth darkens: the dark pixels of the mouth band grow when the jaw opens (hi: viseme A and the shout mood
##    against the closed mouth) and when lo paints its mouth open;
##  - the dead face keeps its eyes closed or open by the figure's seed (both kinds are drawn);
## The bubbles: the dressing room greets with the soldier in a speech bubble (the Thai line; switching to English
## while it shows turns it English; the next figure greets in English; gone after the mouth stops) and not on min; the "normal" hero card says its first line on hi (the
## mouth moving) and has no bubble on lo.
## And once: min draws no face (two min figures of the same seed stepped 4 s, one told a line and a mood: the same
## picture, no face writes, the material's face_on off).
## A face sheet per body for the look judge: row 1 neutral, blink and the 9 other moods; row 2 the 8 visemes; rows 3-4 a
## talking strip of a Thai and an English line (10 frames each); row 5 lo (neutral, blink, A, E, O, U, shout, dead).
## PNGs (TEST_OUT, default tests/out): soldier_face_<body>.png. Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_soldier_face.gd

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const BODIES: PackedStringArray = ["", "m2", "m3", "f1", "f2"]
const CELL := Vector2i(160, 160)
const COLS := 11
const ROWS := 5
const LINE_TH := "สวัสดี! พร้อมออกรบแล้ว"
const LINE_EN := "Hello! Ready for battle."
const TALK_FRAMES := 10
const DT := 1.0 / 30.0
const WHITES_KEEP := 0.35
const SETTINGS_FILE := "user://test_soldier_face_settings.cfg"
const DRESSING := "res://ui/screens/dressing_screen.tscn"
const HERO := "res://scenes/campaign/hero_normal.gd"

var _out_dir := DEFAULT_OUT_DIR
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var S: GDScript


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	S = load(SCRIPT)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(2)
	for b in BODIES:
		await _body(b)
	await _min_static()
	await _bubbles()
	_finish()


## ฉากเล็กของหน้า: [viewport, ตัว, กล้อง, จุดคิ้ว, จุดปาก] · eyes = กล้องใกล้ที่แนวตา
func _stage(body: String, lv: String, seed := 3, eyes := false) -> Array:
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.08, 0.08, 0.09)
	vp.add_child(we)
	var fig: Node3D = S.new()
	vp.add_child(fig)
	fig.call("set_manual", true)
	fig.call("setup", {"role": &"player", "level": lv, "seed": seed, "body": body})
	fig.call("step", DT)
	var sk: Skeleton3D = fig.call("skeleton")
	var brow := (_bone(sk, "head_browL") + _bone(sk, "head_browR")) * 0.5
	var lip := (_bone(sk, "head_lipL") + _bone(sk, "head_lipR")) * 0.5
	var c := (brow + lip) * 0.5 + Vector3(0.0, -0.004, 0.0)
	if eyes:
		c = brow.lerp(lip, 0.3)
	var cam := Camera3D.new()
	cam.fov = 24.0
	vp.add_child(cam)
	cam.current = true
	var eye := c + (Vector3(0.0, 0.004, 0.25) if eyes else Vector3(0.0, 0.01, 0.42))
	cam.transform = Transform3D(Basis.looking_at(c - eye, Vector3.UP), eye)
	return [vp, fig, cam, brow, lip]


func _bone(sk: Skeleton3D, name: String) -> Vector3:
	var i := sk.find_bone(name)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


func _shot(st: Array) -> Image:
	await _frames(2)
	await RenderingServer.frame_post_draw
	return (st[0] as SubViewport).get_texture().get_image()


## กรอบพิกเซลของแถบตา (ใต้คิ้ว) และแถบปาก (รอบแนวปาก) จากจุดกระดูก
func _eye_rect(st: Array) -> Rect2i:
	var cam: Camera3D = st[2]
	var b: Vector3 = st[3]
	var lip: Vector3 = st[4]
	var h := b.y - lip.y
	var a := cam.unproject_position(b + Vector3(-0.055, -0.08 * h, 0.0))
	var z := cam.unproject_position(b + Vector3(0.055, -0.5 * h, 0.0))
	return Rect2i(Vector2i(a), Vector2i(z - a)).abs()


func _mouth_rect(st: Array) -> Rect2i:
	var cam: Camera3D = st[2]
	var lip: Vector3 = st[4]
	var b: Vector3 = st[3]
	var h := b.y - lip.y
	var a := cam.unproject_position(lip + Vector3(-0.03, 0.08 * h, 0.0))
	var z := cam.unproject_position(lip + Vector3(0.03, -0.3 * h, 0.0))
	return Rect2i(Vector2i(a), Vector2i(z - a)).abs()


func _count(img: Image, r: Rect2i, white: bool) -> int:
	var n := 0
	var rr := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			var c := img.get_pixel(x, y)
			var hi := maxf(c.r, maxf(c.g, c.b))
			var lo := minf(c.r, minf(c.g, c.b))
			if white:
				if c.get_luminance() > 0.55 and hi - lo < 0.2 * hi:
					n += 1
			elif c.get_luminance() < 0.09:
				n += 1
	return n


func _body(body: String) -> void:
	var tag := "base" if body == "" else body
	var sheet := Image.create(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	var st := _stage(body, "hi")
	var fig: Node3D = st[1]
	var face: SoldierFace = fig.call("face")
	_check(face != null and face.active(), "%s hi: the face is on" % tag)
	if face == null:
		(st[0] as Node).queue_free()
		return
	# แถว 1: ปกติ กะพริบ แล้วอารมณ์อื่น 9 แบบ
	var col := 0
	face.show_pose(&"neutral")
	var open := await _shot(st)
	sheet.blit_rect(open, Rect2i(Vector2i.ZERO, CELL), Vector2i(0, 0))
	face.show_pose(&"neutral", "", 1.0)
	var shut := await _shot(st)
	sheet.blit_rect(shut, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x, 0))
	await _eyes(body, "hi")
	await _eyes(body, "lo")
	col = 2
	var shout := Image.new()
	for m: String in SoldierFace.MOODS:
		if m == "neutral":
			continue
		face.show_pose(StringName(m))
		var img := await _shot(st)
		if m == "shout":
			shout = img
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, 0))
		col += 1
	# แถว 2: รูปปาก 8 แบบ
	var mr := _mouth_rect(st)
	var d_closed := _count(open, mr, false)
	col = 0
	var d_a := 0
	for code: String in FaceSpeech.CODES:
		face.show_pose(&"neutral", code)
		var img := await _shot(st)
		if code == "A":
			d_a = _count(img, mr, false)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, CELL.y))
		col += 1
	var d_shout := _count(shout, mr, false)
	print("%s hi mouth band %s: dark closed %d, A %d, shout %d" % [tag, str(mr), d_closed, d_a, d_shout])
	_check(d_a >= d_closed + 15 and d_shout >= d_a, "%s hi: an open jaw darkens the mouth (closed %d, A %d, shout %d)"
		% [tag, d_closed, d_a, d_shout])
	# แถว 3-4: พูดไทย / อังกฤษ
	for r in 2:
		face.show_pose(&"neutral")
		var dur := float(fig.call("say", LINE_TH if r == 0 else LINE_EN, "th" if r == 0 else "en"))
		_check(dur > 1.0, "%s: says the %s line (%.2f s)" % [tag, "Thai" if r == 0 else "English", dur])
		var steps := maxi(int(dur / DT / TALK_FRAMES), 1)
		for i in TALK_FRAMES:
			for k in steps:
				fig.call("step", DT)
			var img := await _shot(st)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, (2 + r) * CELL.y))
		fig.call("say", "")
	(st[0] as Node).queue_free()
	# แถว 5: lo ทาสีเปลือกตาและปาก
	var lo := _stage(body, "lo")
	var lface: SoldierFace = (lo[1] as Node).call("face")
	lface.show_pose(&"neutral")
	var lo_open := await _shot(lo)
	lface.show_pose(&"neutral", "", 1.0)
	var lo_shut := await _shot(lo)
	var cells := [lo_open, lo_shut]
	var lmr := _mouth_rect(lo)
	var ld0 := _count(lo_open, lmr, false)
	var ld1 := 0
	for code: String in ["A", "E", "O", "U"]:
		lface.show_pose(&"neutral", code)
		var img := await _shot(lo)
		if code == "A":
			ld1 = _count(img, lmr, false)
		cells.append(img)
	lface.show_pose(&"shout")
	cells.append(await _shot(lo))
	_check(ld1 >= ld0 + 8, "%s lo: the painted mouth opens dark (%d -> %d)" % [tag, ld0, ld1])
	(lo[1] as Node).call("play", &"die", 1.0)
	cells.append(await _shot(lo))
	var dead_state: Vector4 = lface.state()
	var want := 0.0 if lface.dead_open() else 1.0
	_check(is_equal_approx(dead_state.x, want), "%s lo: dead eyes %s by the seed (lid %.2f)" % [tag,
		"open" if lface.dead_open() else "closed", dead_state.x])
	for i in cells.size():
		sheet.blit_rect(cells[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 4 * CELL.y))
	(lo[0] as Node).queue_free()
	await _frames(1)
	_save_img(sheet, "soldier_face_%s.png" % tag)


## ตาใกล้ ๆ: เปิด → ปิด · hi นับตาขาว · lo นับพิกเซลที่เปลี่ยนในแถบตา (แถบปากต้องไม่เปลี่ยน)
func _eyes(body: String, lv: String) -> void:
	var tag := "%s %s" % ["base" if body == "" else body, lv]
	var st := _stage(body, lv, 3, true)
	var face: SoldierFace = (st[1] as Node).call("face")
	face.show_pose(&"neutral")
	var open := await _shot(st)
	face.show_pose(&"neutral", "", 1.0)
	var shut := await _shot(st)
	var er := _eye_rect(st)
	if lv == "hi":
		var w0 := _count(open, er, true)
		var w1 := _count(shut, er, true)
		print("%s eye band %s: whites open %d closed %d" % [tag, str(er), w0, w1])
		_check(w0 >= 6 and float(w1) < WHITES_KEEP * float(w0), "%s: closed lids hide the eye whites (%d -> %d)" % [tag, w0, w1])
	else:
		var ch := _changed(open, shut, er)
		var mouth := _changed(open, shut, _mouth_rect(st))
		var area := maxi(er.get_area(), 1)
		print("%s eye band %s: %d of %d pixels change, mouth band %d" % [tag, str(er), ch, area, mouth])
		_check(float(ch) >= 0.08 * float(area) and mouth == 0, "%s: painted lids cover the eyes (%d of %d change, mouth %d)"
			% [tag, ch, area, mouth])
	(st[0] as Node).queue_free()
	await _frames(1)


func _changed(a: Image, b: Image, r: Rect2i) -> int:
	var n := 0
	var rr := r.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06:
				n += 1
	return n


## min: ไม่มีหน้า · สองตัว seed เดียวกันเดินท่า 4 วิ ตัวหนึ่งพูด + ตั้งอารมณ์: ภาพเหมือนกัน · face_on ปิด · ไม่เขียนเลย
func _min_static() -> void:
	var st := _stage("", "min")
	var twin := _stage("", "min")
	var fig: Node3D = st[1]
	fig.call("say", LINE_TH, "th")
	fig.call("set_mood", &"shout")
	for i in 120:
		fig.call("step", DT)
		(twin[1] as Node).call("step", DT)
	var a := await _shot(st)
	var b := await _shot(twin)
	var diff := 0
	for y in a.get_height():
		for x in a.get_width():
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				diff += 1
	var mat := (fig.call("body") as MeshInstance3D).material_override as ShaderMaterial
	var face: SoldierFace = fig.call("face")
	_check(diff == 0, "min: a line and a mood change nothing on screen (%d pixels differ)" % diff)
	_check(mat != null and not bool(mat.get_shader_parameter("face_on")), "min: the material draws no face")
	_check(face != null and face.writes() == 0, "min: no face writes (%d)" % (face.writes() if face != null else -1))
	(st[0] as Node).queue_free()
	(twin[0] as Node).queue_free()
	await _frames(1)


## กรอบคำพูด: ห้องแต่งตัว (ไทย → อังกฤษ → หายเมื่อปากหยุด · min ไม่มี) และการ์ดฮีโร่ "ธรรมดา" (hi พูด · lo ไม่มี)
func _bubbles() -> void:
	var app := root.get_node(^"App")
	var i18n := root.get_node(^"I18n")
	var keep_file := str(app.get("settings_file"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	var ds: Node = (load(DRESSING) as PackedScene).instantiate()
	root.add_child(ds)
	await _frames(2)
	ds.call("pick_figure", "soldier")
	await _frames(2)
	var bubble: SpeechBubble = ds.call("speech_bubble")
	var fig: Node3D = ds.call("preview_figure")
	var face: SoldierFace = fig.call("face") if fig != null and fig.has_method("face") else null
	var th := str(bubble.shown()) if bubble != null else ""
	_check(th != "" and th == str(i18n.call("t", SpeechBubble.line("greet", 0))) and face != null and face.speaking(),
		"dressing room: the soldier greets in a bubble, the mouth moving (%s)" % th)
	app.call("set_lang", "en")
	ds.call("refresh")
	var swapped := str(bubble.shown()) if bubble != null else ""
	_check(swapped == str(i18n.call("lookup", SpeechBubble.line("greet", 0))),
		"dressing room: switching to English while it talks turns the bubble English (%s)" % swapped)
	ds.call("pick_figure", "soldier_m2")
	await _frames(2)
	var en := str(bubble.shown()) if bubble != null else ""
	_check(en != "" and RegEx.create_from_string("[฀-๿]").search(en) == null and en == str(i18n.call("lookup", SpeechBubble.line("greet", 1))),
		"dressing room in English: the bubble speaks English (%s)" % en)
	var gone := false
	for i in 600:
		await process_frame
		if not bubble.visible:
			gone = true
			break
	_check(gone, "dressing room: the bubble goes once the mouth stops")
	ds.queue_free()
	await _frames(1)
	app.call("set_lang", "th")
	app.call("set_gfx", "min")
	var dm: Node = (load(DRESSING) as PackedScene).instantiate()
	root.add_child(dm)
	await _frames(2)
	dm.call("pick_figure", "soldier")
	await _frames(1)
	_check(not (dm.call("speech_bubble") as SpeechBubble).visible, "dressing room on min: no bubble")
	dm.queue_free()
	await _frames(1)
	for lv in ["hi", "lo"]:
		var vp := SubViewport.new()
		vp.size = Vector2i(640, 360)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var h: Node3D = (load(HERO) as GDScript).new()
		vp.add_child(h)
		h.call("setup", {"level": lv, "sel": {"figure": "soldier", "scheme": ""}, "aspect": 16.0 / 9.0})
		var hb: SpeechBubble = h.call("speech_bubble")
		var hf: Node3D = h.get("figure")
		if lv == "hi":
			var hface: SoldierFace = hf.call("face") if hf.has_method("face") else null
			_check(hb != null and hb.shown() == str(i18n.call("t", SpeechBubble.line("hero", 0))) and hface != null and hface.speaking(),
				"hero card hi: says its first line in a bubble (%s)" % (hb.shown() if hb != null else "none"))
			await _frames(2)
			await RenderingServer.frame_post_draw
			_save_img(vp.get_texture().get_image(), "soldier_face_hero_hi.png")
		else:
			_check(hb == null, "hero card lo: no bubble (drawn once, no clock)")
		vp.queue_free()
		await _frames(1)
	app.call("set_gfx", "mid")
	app.set("settings_file", keep_file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save_img(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
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
