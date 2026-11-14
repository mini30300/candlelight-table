class_name HeroStage
extends SubViewportContainer
## เวทีของฉากโชว์บนการ์ดความยาก (CAMPAIGN_SPEC §3.4): SubViewport โลกของตัวเอง + ฉากจาก CampaignHeroes (ชุดเสริมก่อน)
## สด (live) = วาดทุกเฟรมตอนเห็น (lo: ไม่เกิน 30 fps ด้วย Timer 33 ms สลับ UPDATE_ONCE) · ฉากที่ไม่ขยับ (animated() = false) วาดครั้งเดียว
## นิ่ง = สร้างฉาก รอท่าลง 2 เฟรม วาดครั้งเดียว คัดลอกเป็น ImageTexture แล้วทิ้งฉากและ viewport (ไม่มีงานต่อเฟรมหลังจากนั้น)
## min: นิ่งเสมอ · ความละเอียด 3 มิติ hi 1 / mid .75 / lo .5 / min .5 ของขนาดการ์ด (scaling_3d_scale)
## ฉากชุดเสริมที่ setup แล้วไม่มีกล้องของตัวเอง (เขียนพัง ไม่ครบ) → ทิ้งแล้วใช้ฉากในตัวแทน หน้าจอไม่ล่ม

signal still_ready

const SCALE := {"hi": 1.0, "mid": 0.75, "lo": 0.5, "min": 0.5}
const WARM := 2               # เฟรมรอท่าลงกระดูกก่อนถ่ายภาพนิ่ง
const SHOOT_WAIT := 4         # รอ frame_post_draw ไม่มา (headless) ก็เก็บเท่าที่ได้
const LO_FRAME := 0.033
const REDO_ASPECT := 0.15     # การ์ดเปลี่ยนสัดส่วนเกินนี้ วาดภาพนิ่งใหม่

enum Phase { IDLE, WARM, SHOOT }

var level := "mid"
var id := ""
var live := false
## ฉากล่าสุดมาจากฉากในตัวเพราะฉากชุดเสริมใช้ไม่ได้
var fell_back := false

var _ctx: Dictionary = {}
var _vp: SubViewport
var _hero: Node3D
var _still: TextureRect
var _blank: ColorRect
var _poster: Texture2D
var _poster_size := Vector2.ZERO
var _phase := Phase.IDLE
var _wait := 0
var _timer: Timer
var _hide_still_next := false
var _pending := false          # ภาพนิ่งที่ยังไม่ได้วาดเพราะการ์ดซ่อนอยู่ (วาดเมื่อโผล่)


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_blank = ColorRect.new()
	_blank.name = "Blank"
	_blank.color = Color(0.03, 0.025, 0.035)
	_blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blank)
	_still = TextureRect.new()
	_still.name = "Still"
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_still)
	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility)
	set_process(false)


## ตั้งฉากของ id: เริ่มเป็นภาพนิ่ง (set_live(true) ทีหลังเพื่อเล่น) · ctx = {"level", "sel", ...}
func show_hero(p_id: String, ctx: Dictionary) -> void:
	id = p_id
	_ctx = ctx.duplicate()
	level = str(ctx.get("level", "mid"))
	if not SCALE.has(level):
		level = "mid"
	live = false
	_poster = null
	_poster_size = Vector2.ZERO
	_stop_timer()
	_drop_hero()
	_render_still()


## เล่นสด / กลับเป็นภาพนิ่ง (min: นิ่งเสมอ)
func set_live(on: bool) -> void:
	if level == "min":
		on = false
	if on == live:
		return
	live = on
	if on:
		_start_live()
	else:
		_stop_timer()
		_drop_hero()
		_render_still()


## ภาพนิ่งล่าสุด (ไม่มี = ภาพของ viewport ที่เล่นอยู่ หรือ null)
func snapshot() -> Texture2D:
	if _poster != null:
		return _poster
	return _vp.get_texture() if _vp != null else null


func hero() -> Node3D:
	return _hero


func viewport() -> SubViewport:
	return _vp


## กำลังสร้างภาพนิ่งอยู่ไหม
func busy() -> bool:
	return _phase != Phase.IDLE


## ภาพนิ่งรอวาดตอนการ์ดโผล่
func pending() -> bool:
	return _pending


## สำหรับเทส: {"live", "draws_hint" (เมชที่มองเห็นในฉาก + overlay), "level", "still", "viewport", "update", "scale"}
func counts() -> Dictionary:
	var draws := 0
	if _hero != null:
		for mi in HeroKit.meshes(_hero):
			if mi.is_visible_in_tree() and mi.mesh != null:
				var n := mi.mesh.get_surface_count()
				draws += n * (2 if mi.material_overlay != null else 1)
	return {"live": live and _hero != null, "draws_hint": draws, "level": level, "still": _poster != null,
		"viewport": _vp != null, "update": _vp.render_target_update_mode if _vp != null else -1,
		"scale": float(SCALE[level])}


# ---- ภายใน ----

func _start_live() -> void:
	_phase = Phase.IDLE
	_make_hero()
	if _hero == null:
		return
	_hero.call("set_active", true)
	var moving := not _hero.has_method("animated") or bool(_hero.call("animated"))
	if not moving:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif level == "lo":
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_timer = Timer.new()
		_timer.name = "LoFrame"
		_timer.wait_time = LO_FRAME
		_timer.timeout.connect(_lo_frame)
		add_child(_timer)
		_timer.start()
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# ภาพนิ่งยังบังไว้จนเฟรมแรกของฉากสดวาดเสร็จ (ไม่กะพริบ)
	_hide_still_next = true
	set_process(true)


func _lo_frame() -> void:
	if _vp != null and is_visible_in_tree():
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _stop_timer() -> void:
	if _timer != null:
		_timer.stop()
		_timer.queue_free()
		_timer = null


func _render_still() -> void:
	_pending = false
	if live:
		return
	if _poster != null and _same_shape(_poster_size, size):
		_show_still()
		return
	if not is_visible_in_tree():
		_pending = true
		_show_still()
		return
	_make_hero()
	if _hero == null:
		_show_still()
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_phase = Phase.WARM
	_wait = WARM
	set_process(true)


func _process(_delta: float) -> void:
	if _hide_still_next:
		_hide_still_next = false
		_still.visible = false
		_blank.visible = false
	match _phase:
		Phase.WARM:
			if not is_visible_in_tree():
				# ซ่อนระหว่างรอ: ไว้วาดตอนโผล่
				_phase = Phase.IDLE
				_drop_hero()
				_drop_vp()
				_pending = true
				set_process(false)
				still_ready.emit()
				return
			if size.x < 2.0 or size.y < 2.0:
				return
			_wait -= 1
			if _wait <= 0:
				_phase = Phase.SHOOT
				_wait = SHOOT_WAIT
				_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
				RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)
		Phase.SHOOT:
			_wait -= 1
			if _wait <= 0:
				_grab()
	if _phase == Phase.IDLE and not _hide_still_next:
		set_process(false)


func _grab() -> void:
	if _phase != Phase.SHOOT:
		return
	if RenderingServer.frame_post_draw.is_connected(_grab):
		RenderingServer.frame_post_draw.disconnect(_grab)
	_phase = Phase.IDLE
	var img: Image = _vp.get_texture().get_image() if _vp != null else null
	if img != null and not img.is_empty():
		_poster = ImageTexture.create_from_image(img)
	else:
		_poster = null
	_poster_size = size
	_drop_hero()
	_drop_vp()
	_show_still()
	set_process(false)
	still_ready.emit()


func _show_still() -> void:
	_still.texture = _poster
	_still.visible = true
	_blank.visible = _poster == null
	_fit()


func _make_hero() -> void:
	_drop_hero()
	_ensure_vp()
	fell_back = false
	var c := _ctx.duplicate()
	c["level"] = level
	c["aspect"] = _aspect()
	if not c.has("sel"):
		c["sel"] = Figures.selected()
	var h := CampaignHeroes.make(id)
	if h == null:
		return
	_vp.add_child(h)
	h.call("setup", c)
	if not _owns_camera(h):
		push_warning("campaign hero: %s set up no camera of its own; using the built-in scene" % _script_path(h))
		_vp.remove_child(h)
		h.free()
		fell_back = true
		h = CampaignHeroes.make_builtin(id)
		if h == null:
			return
		_vp.add_child(h)
		h.call("setup", c)
	_hero = h


func _owns_camera(h: Node3D) -> bool:
	var cam := _vp.get_camera_3d()
	return cam != null and h.is_ancestor_of(cam)


func _drop_hero() -> void:
	if _hero == null:
		return
	if is_instance_valid(_hero):
		if _hero.has_method("set_active"):
			_hero.call("set_active", false)
		if _hero.get_parent() != null:
			_hero.get_parent().remove_child(_hero)
		_hero.queue_free()
	_hero = null


func _ensure_vp() -> void:
	if _vp != null:
		_vp.scaling_3d_scale = float(SCALE[level])
		return
	_vp = SubViewport.new()
	_vp.name = "View"
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.handle_input_locally = false
	_vp.audio_listener_enable_3d = false
	_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_vp.scaling_3d_scale = float(SCALE[level])
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if size.x >= 2.0 and size.y >= 2.0:
		_vp.size = Vector2i(size)
	add_child(_vp)
	move_child(_vp, 0)


func _drop_vp() -> void:
	if _vp == null:
		return
	remove_child(_vp)
	_vp.queue_free()
	_vp = null


func _aspect() -> float:
	return size.x / size.y if size.x >= 2.0 and size.y >= 2.0 else 16.0 / 9.0


func _fit() -> void:
	for c: Control in [_still, _blank]:
		c.position = Vector2.ZERO
		c.size = size


func _on_resized() -> void:
	_fit()
	if size.x < 2.0 or size.y < 2.0:
		return
	if _hero != null and _hero.has_method("set_aspect"):
		_hero.call("set_aspect", _aspect())
		if _vp != null and live and _vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# ภาพนิ่งที่สัดส่วนต่างไปมาก: วาดใหม่ (ครั้งเดียว)
	if not live and _phase == Phase.IDLE and _poster != null and not _same_shape(_poster_size, size) and id != "":
		_render_still.call_deferred()


func _on_visibility() -> void:
	if _pending and not live and _phase == Phase.IDLE and is_visible_in_tree():
		_render_still.call_deferred()
		return
	if _hero == null or not live:
		return
	var on := is_visible_in_tree()
	_hero.call("set_active", on)
	if _timer != null:
		_timer.paused = not on


static func _same_shape(a: Vector2, b: Vector2) -> bool:
	if a.x < 2.0 or a.y < 2.0 or b.x < 2.0 or b.y < 2.0:
		return a == b
	return absf(a.x / a.y - b.x / b.y) / (b.x / b.y) <= REDO_ASPECT and absf(a.y - b.y) / b.y <= 0.5


static func _script_path(n: Object) -> String:
	var s: Script = n.get_script()
	return s.resource_path if s != null else str(n)
