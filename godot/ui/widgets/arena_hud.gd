class_name ArenaHud
extends Control
## หน้าจอการต่อสู้ของอารีน่า (ARENA_SPEC §5.5): สร้างด้วยโค้ด หน้าอารีน่าใส่ไว้เต็มกรอบ Safe/Layer ชื่อ "Hud"
## _draw() เดียววาดเป้าเล็งกลางจอ (โดนแล้วขึ้นกากบาท 0.12 วิ เป้าแดงเมื่อเล็งโดนศัตรู) แถบพลังศัตรู (บนกลาง) แถบพลังเรา
## (ซ้ายบน ใต้ปุ่มล็อบบี้) และตัวเลขความเสียหาย (8 ช่อง: hi/mid ลอยขึ้นจาง 0.8 วิ, lo/min นิ่ง 0.6 วิ)
## กระสุนที่โดนเป้าเดิมติดกันภายใน 0.3 วิ รวมเป็นตัวเลขเดียว ("36" แทน "12 12 12") สีขาวแบบปืน
## ลูก: Ammo (กระสุน/ชื่ออาวุธ/กำลังบรรจุ), Hint (คำแนะนำทางเดิน/การยิง), Hurt (ขอบจอแดงตอนโดน), Downed (ล้ม), Touch (ArenaTouch)
## ข้อความไทยทั้งหมดของหน้าจอนี้อยู่ในไฟล์นี้และ arena_touch.gd · ชื่ออาวุธ/ศัตรูมาจาก ArenaData (หรือชื่อจากแพ็ก)
## งานต่อเฟรม: _process เฉพาะตอนมีตัวเลขลอย กากบาทโดน หรือขอบแดงบน hi/mid; ที่เหลือวาดใหม่ตามสัญญาณ

const HINT_WALK := "เดินเข้าอารีน่าแล้วจะถือปืน"
const HINT_KEYS := "คลิกซ้ายยิง · คลิกขวาหรือ F ต่อย · R บรรจุกระสุน · 1 / 2 เปลี่ยนอาวุธ · Space หลบ · Esc หยุด"
const HINT_TOUCH := "ลากจอด้านขวาเพื่อเล็ง · ปุ่มยิง หมัด หลบ และอาวุธอยู่ขวาล่าง"
const RELOADING := "กำลังบรรจุกระสุน…"
const DOWNED := "คุณล้ม! กำลังลุกขึ้น…"
const HP_TEXT := "พลังชีวิต {hp}/{max}"
const HINT_SECONDS := 5.0
const HIT_MARK := 0.12
const HURT_TIME := 0.2
const ENEMY_LINGER := 1.5
const ENEMY_BAR := Vector2(480.0, 26.0)
const PLAYER_BAR := Vector2(320.0, 26.0)
const PLAYER_BAR_Y := 68.0          # ใต้ปุ่มล็อบบี้ (56) เว้น 12
const HINT_W := 560.0
const HINT_Y := 44.0
const AMMO_W := 340.0
const AMMO_H := 44.0
const CROSS := 9.0
const CROSS_GAP := 5.0
const ARENA_ACTORS := "res://scenes/arena/arena_actors.gd"
const BAR_BG := Color(0.06, 0.04, 0.03, 0.78)
const BAR_EDGE := Color(0.42, 0.29, 0.16, 0.95)
const ENEMY_FILL := Color(0.80, 0.24, 0.20)
const PLAYER_FILL := Color(0.36, 0.72, 0.44)
const CROSS_COL := Color(1.0, 0.95, 0.85, 0.95)
const CROSS_HOT := Color(1.0, 0.32, 0.26, 1.0)
const NUM_WHITE := Color(1.0, 1.0, 1.0)
const NUM_AMBER := Color(1.0, 0.74, 0.25)
const NUM_NORMAL := 26.0
const NUM_HEAVY := 34
const NUM_OUTLINE := 7
## ตัวเลขที่ออกติดกันเยื้องซ้าย/ขวา/ขึ้นสลับกัน (px) ห่างกันแนวนอน ≥ 52 หรือแนวตั้ง ≥ 34 ไม่อ่านติดกันเป็นทศนิยม
const NUM_SPREAD: Array[Vector2] = [Vector2(0, 0), Vector2(-52, -14), Vector2(52, -8), Vector2(-26, -42), Vector2(26, -36)]
## กระสุนโดนเป้าเดิมภายในกี่วิจึงรวมเข้าตัวเลขล่าสุด
const NUM_MERGE := 0.3
const CROSS_EDGE := Color(0.0, 0.0, 0.0, 0.7)

var world: Node3D
var player: Node3D
var enemy: Node3D
var touch_mode := false
var level := "mid"

var ammo_label: Label
var hint: Label
var hurt: Control
var downed: Control
var downed_label: Label
var touch: ArenaTouch

var _mode: StringName = &"walk"
var _hp := 100
var _hp_max := 100
var _enemy_hp := 0
var _enemy_max := 1
var _enemy_show := false
var _enemy_dead := false
var _enemy_name := {}
var _aim_hot := false
var _hit_mark := 0.0
var _hurt := 0.0
var _numbers: Array[Dictionary] = []    # {"point": Vector3, "amount", "style", "t", "off": Vector2, "kind", "target"}
var _num_seq := 0
var _shot_hint_shown := false
var _hint_done := false
var _hint_timer: SceneTreeTimer
var _paused := false
var _reloading := false
var _last_ammo := 0
var _rects := {}


func _ready() -> void:
	name = "Hud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	set_process(false)
	set_physics_process(false)


## ต่อเข้ากับโลก ผู้เล่น และศัตรู (สัญญาณเท่านั้น)
func bind(w: Node3D) -> void:
	world = w
	player = w.get("player")
	enemy = w.get("enemy")
	if player != null:
		_connect(player, &"mode_changed", _on_mode)
		_connect(player, &"hp_changed", _on_hp)
		_connect(player, &"ammo_changed", _on_ammo)
		_connect(player, &"reload_changed", _on_reload)
		_connect(player, &"weapon_changed", _on_weapon)
		_connect(player, &"hit_landed", _on_hit_landed)
		_connect(player, &"hurt", _on_hurt)
		_connect(player, &"downed", _on_downed)
		_connect(player, &"revived", _on_revived)
		_connect(player, &"aim_changed", _on_aim)
		_mode = player.call("mode")
		_hp = int(player.call("hp"))
		_hp_max = int(player.call("hp_max")) if player.has_method("hp_max") else int(ArenaData.PLAYER["hp"])
		touch.bind(player)
	if enemy != null:
		_connect(enemy, &"hp_changed", _on_enemy_hp)
		_connect(enemy, &"died", _on_enemy_died)
		_enemy_hp = int(enemy.call("hp")) if enemy.has_method("hp") else 0
		_enemy_max = maxi(int(enemy.call("hp_max")) if enemy.has_method("hp_max") else int(ArenaData.BEAST["hp"]), 1)
		_enemy_dead = enemy.has_method("is_alive") and not bool(enemy.call("is_alive"))
	if w.has_signal(&"reset_done"):
		_connect(w, &"reset_done", _on_reset)
	_enemy_name = _pack_name()
	_on_mode(_mode)


## ข้อความตามภาษา โชว์/ซ่อนปุ่มบนจอ (หน้าอารีน่าเรียกทุกครั้งที่โชว์)
func refresh(touch_on: bool) -> void:
	touch_mode = touch_on
	var app := get_node_or_null(^"/root/App")
	if app != null:
		level = str(app.get("gfx"))
	if player != null and player.has_method("set_touch"):
		player.call("set_touch", touch_on)
	touch.visible = touch_on and not _paused
	touch.refresh()
	downed_label.text = I18n.t(DOWNED)
	_update_ammo()
	_update_hint()
	_layout()
	queue_redraw()


func set_paused(on: bool) -> void:
	_paused = on
	touch.visible = touch_mode and not on
	if on:
		touch.release_all()
	if player != null:
		player.call("press", &"fire", false)


## คำแนะนำการยิงครั้งแรกจบแล้ว (ครบ 5 วิหรือยิงนัดแรก)
func hint_done() -> bool:
	return _hint_done


func numbers_alive() -> int:
	return _numbers.size()


## กรอบที่วาดเอง (พิกัด canvas) สำหรับเทสผัง: Crosshair, EnemyBar, PlayerBar (แถบศัตรูซ่อน = กรอบว่าง)
func drawn_rects() -> Dictionary:
	var xf := get_global_transform()
	var out := {}
	for k in _rects:
		var r: Rect2 = _rects[k]
		out[k] = Rect2(xf * r.position, r.size) if r.has_area() else Rect2()
	if not _enemy_visible():
		out["EnemyBar"] = Rect2()
	return out


func crosshair_hot() -> bool:
	return _aim_hot


func enemy_bar_visible() -> bool:
	return _enemy_visible()


# ---- วาด ----

func _draw() -> void:
	var font := CandleStyle.BOLD
	var cr: Rect2 = _rects.get("Crosshair", Rect2())
	var c := cr.get_center()
	var col := CROSS_HOT if _aim_hot else CROSS_COL
	# วาดเรียงตามพื้นผิว: สี่เหลี่ยมทั้งหมดก่อน แล้วขอบตัวอักษร แล้วตัวอักษร (สลับพื้นผิวน้อยที่สุด = draw call น้อยสุด)
	if _mode == &"shoot":
		# เป้าเล็ง: ขีดสี่ด้าน + จุดกลาง มีขอบดำ 1 px (อ่านออกบนตัวศัตรูสีอ่อนตอนกะพริบขาว; สี่เหลี่ยมชุดเดียวกัน ไม่เพิ่ม draw call)
		# กากบาทโดนเป็นสี่เหลี่ยมเอียง (ไม่ใช่รูปหลายเหลี่ยม ซึ่งแยก draw call ทีละชิ้น)
		var bars := [Rect2(c.x - CROSS_GAP - CROSS, c.y - 1.0, CROSS, 2.0), Rect2(c.x + CROSS_GAP, c.y - 1.0, CROSS, 2.0),
			Rect2(c.x - 1.0, c.y - CROSS_GAP - CROSS, 2.0, CROSS), Rect2(c.x - 1.0, c.y + CROSS_GAP, 2.0, CROSS),
			Rect2(c.x - 1.5, c.y - 1.5, 3.0, 3.0)]
		for b: Rect2 in bars:
			draw_rect(b.grow(1.0), CROSS_EDGE)
		for b: Rect2 in bars:
			draw_rect(b, col)
		if _hit_mark > 0.0:
			var xc := CROSS_HOT if _aim_hot else Color.WHITE
			for i in 4:
				draw_set_transform(c, PI * 0.25 + PI * 0.5 * i)
				draw_rect(Rect2(7.0 * sqrt(2.0), -1.4, 7.0 * sqrt(2.0), 2.8), xc)
			draw_set_transform(Vector2.ZERO)
	var pr: Rect2 = _rects.get("PlayerBar", Rect2())
	_bar(pr, float(_hp) / maxf(float(_hp_max), 1.0), PLAYER_FILL)
	var er: Rect2 = _rects.get("EnemyBar", Rect2())
	var show_enemy := _enemy_visible()
	if show_enemy:
		_bar(er, float(_enemy_hp) / float(_enemy_max), ENEMY_FILL)
	# ข้อความบนแถบ: ขอบทั้งหมดก่อน แล้วตัวอักษร
	var fs := 17
	var asc := font.get_ascent(fs)
	var texts: Array = []      # [ตำแหน่ง, ข้อความ, การจัด, กว้าง]
	var ty := pr.position.y + (pr.size.y + asc - font.get_descent(fs)) * 0.5
	texts.append([Vector2(pr.position.x + 10.0, ty), _hp_text(), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 20.0])
	if show_enemy:
		var ey := er.position.y + (er.size.y + asc - font.get_descent(fs)) * 0.5
		texts.append([Vector2(er.position.x + 10.0, ey), _enemy_label(), HORIZONTAL_ALIGNMENT_LEFT, er.size.x * 0.6])
		texts.append([Vector2(er.position.x + 10.0, ey), "%d/%d" % [_enemy_hp, _enemy_max], HORIZONTAL_ALIGNMENT_RIGHT, er.size.x - 20.0])
	for t in texts:
		draw_string_outline(font, t[0], t[1], t[2], t[3], fs, 4, Color(0, 0, 0, 0.8))
	for t in texts:
		draw_string(font, t[0], t[1], t[2], t[3], fs, CandleStyle.TEXT)
	# ตัวเลขความเสียหาย: ขนาดตัวอักษรเดียว (ตัวเลขธรรมดาย่อด้วย transform) ขอบทั้งหมดก่อน แล้วตัวเลข
	var cam := _camera()
	if cam == null or _numbers.is_empty():
		return
	var inv := get_global_transform().affine_inverse()
	var nums: Array = []       # [จุดบนจอ, ข้อความ, สเกล, สี, ความทึบ]
	for n in _numbers:
		var t := float(n["t"])
		var heavy: bool = n["style"] == &"heavy"
		var p: Vector3 = n["point"]
		var a := 1.0
		if _smooth():
			var k := clampf(t / float(ArenaData.NUMBERS["life"]), 0.0, 1.0)
			p += Vector3(0.0, float(ArenaData.NUMBERS["rise"]) * k, 0.0)
			a = 1.0 - k * k
		if cam.is_position_behind(p):
			continue
		nums.append([inv * cam.unproject_position(p) + (n.get("off", Vector2.ZERO) as Vector2), str(int(n["amount"])), 1.0 if heavy else NUM_NORMAL / NUM_HEAVY,
			NUM_AMBER if heavy else NUM_WHITE, a])
	for e in nums:
		_number(font, e, true)
	for e in nums:
		_number(font, e, false)
	draw_set_transform(Vector2.ZERO)


func _number(font: Font, e: Array, outline: bool) -> void:
	var s: String = e[1]
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, NUM_HEAVY).x
	draw_set_transform(e[0], 0.0, Vector2(e[2], e[2]))
	var a := float(e[4])
	if outline:
		draw_string_outline(font, Vector2(-w * 0.5, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, NUM_HEAVY, NUM_OUTLINE, Color(0, 0, 0, 0.75 * a))
	else:
		draw_string(font, Vector2(-w * 0.5, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, NUM_HEAVY, Color(e[3] as Color, a))


## แถบพลัง: พื้น เนื้อ และขอบ 2 px เป็นสี่เหลี่ยมทึบทั้งหมด (ขอบแบบเส้นแยก draw call)
func _bar(r: Rect2, frac: float, fill: Color) -> void:
	if not r.has_area():
		return
	draw_rect(r, BAR_BG)
	var inner := r.grow(-3.0)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(frac, 0.0, 1.0), inner.size.y)), Color(fill, 0.85))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), BAR_EDGE)
	draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), BAR_EDGE)
	draw_rect(Rect2(r.position.x, r.position.y + 2.0, 2.0, r.size.y - 4.0), BAR_EDGE)
	draw_rect(Rect2(r.end.x - 2.0, r.position.y + 2.0, 2.0, r.size.y - 4.0), BAR_EDGE)


func _process(delta: float) -> void:
	var alive := false
	if _hit_mark > 0.0:
		_hit_mark = maxf(_hit_mark - delta, 0.0)
		alive = alive or _hit_mark > 0.0
	if _hurt > 0.0:
		_hurt = maxf(_hurt - delta, 0.0)
		hurt.modulate.a = _hurt / HURT_TIME if _smooth() else 1.0
		if _hurt <= 0.0:
			hurt.visible = false
		alive = alive or _hurt > 0.0
	if not _numbers.is_empty():
		var life := float(ArenaData.NUMBERS["life"] if _smooth() else ArenaData.NUMBERS["still"])
		var keep: Array[Dictionary] = []
		for n in _numbers:
			n["t"] = float(n["t"]) + delta
			if float(n["t"]) < life:
				keep.append(n)
		_numbers = keep
		alive = alive or not _numbers.is_empty()
	queue_redraw()
	if not alive:
		set_process(false)


# ---- สัญญาณ ----

func _on_mode(m: StringName) -> void:
	_mode = m
	if m == &"shoot" and not _shot_hint_shown:
		_shot_hint_shown = true
		_hint_timer = get_tree().create_timer(HINT_SECONDS) if is_inside_tree() else null
		if _hint_timer != null:
			_hint_timer.timeout.connect(_finish_hint)
	touch.set_shoot(m == &"shoot")
	touch.update_weapon()
	_update_hint()
	_update_ammo()
	queue_redraw()


func _on_hp(hp: int, hp_max: int) -> void:
	_hp = hp
	_hp_max = maxi(hp_max, 1)
	queue_redraw()


## กระสุนลด = ยิงนัดแรกแล้ว: ปิดคำแนะนำการยิง
func _on_ammo(in_mag: int, _mag: int) -> void:
	if in_mag < _last_ammo and _mode == &"shoot" and _shot_hint_shown:
		_finish_hint()
	_last_ammo = in_mag
	_update_ammo()


func _on_reload(on: bool, _seconds: float) -> void:
	_reloading = on
	_update_ammo()


func _on_weapon(_id: StringName) -> void:
	touch.update_weapon()
	_update_ammo()


func _on_hit_landed(info: Dictionary) -> void:
	_hit_mark = HIT_MARK
	var amount := int(info.get("amount", 0))
	var kind := StringName(str(info.get("kind", "")))
	var target := StringName(str(info.get("target", "")))
	if amount > 0:
		var last: Dictionary = _numbers.back() if not _numbers.is_empty() else {}
		if kind == &"gun" and last.get("kind") == &"gun" and last.get("target") == target and float(last["t"]) < NUM_MERGE:
			# ยิงรัวโดนเป้าเดิม: บวกเข้าตัวเลขล่าสุด เริ่มนับอายุใหม่ ย้ายไปจุดที่โดนล่าสุด (คงสีขาวแบบปืน)
			last["amount"] = int(last["amount"]) + amount
			last["t"] = 0.0
			last["point"] = info.get("point", last["point"])
		else:
			if _numbers.size() >= int(ArenaData.NUMBERS["pool"]):
				_numbers.pop_front()
			_numbers.append({"point": info.get("point", Vector3.ZERO), "amount": amount, "kind": kind, "target": target,
				"style": ArenaCombat.number_style(amount) if kind != &"gun" else &"normal", "t": 0.0,
				"off": NUM_SPREAD[_num_seq % NUM_SPREAD.size()]})
			_num_seq += 1
	set_process(true)
	queue_redraw()


func _on_hurt(_info: Dictionary) -> void:
	_hurt = HURT_TIME
	hurt.visible = true
	hurt.modulate.a = 1.0
	set_process(true)


func _on_downed() -> void:
	downed.visible = true


func _on_revived() -> void:
	downed.visible = false


func _on_aim(on: bool) -> void:
	_aim_hot = on
	queue_redraw()


func _on_enemy_hp(hp: int, hp_max: int) -> void:
	_enemy_hp = hp
	_enemy_max = maxi(hp_max, 1)
	if hp > 0:
		_enemy_dead = false
		_enemy_show = false
	queue_redraw()


## ตายแล้วยังโชว์แถบศัตรูอีกครู่ (ระหว่างท่าล้ม) แล้วซ่อน
func _on_enemy_died() -> void:
	_enemy_dead = true
	_enemy_show = true
	if is_inside_tree():
		get_tree().create_timer(ENEMY_LINGER).timeout.connect(func() -> void:
			_enemy_show = false
			queue_redraw())
	queue_redraw()


func _on_reset() -> void:
	if enemy != null and enemy.has_method("hp"):
		_enemy_hp = int(enemy.call("hp"))
		_enemy_dead = false
		_enemy_show = false
	queue_redraw()


# ---- ภายใน ----

func _build() -> void:
	# ขอบจอแดง: Control เปล่า (ไม่วาดสี่เหลี่ยมใสเต็มจอ) วาดขอบสี่ด้านด้วย draw_primitive ที่รวบเป็น draw call เดียว
	hurt = Control.new()
	hurt.name = "Hurt"
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.visible = false
	hurt.draw.connect(_draw_hurt)
	add_child(hurt)
	ammo_label = Label.new()
	ammo_label.name = "Ammo"
	ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_label.add_theme_font_override(&"font", CandleStyle.BOLD)
	ammo_label.add_theme_font_size_override(&"font_size", 24)
	ammo_label.add_theme_color_override(&"font_color", CandleStyle.TEXT)
	ammo_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	ammo_label.add_theme_constant_override(&"outline_size", 5)
	ammo_label.clip_text = true
	add_child(ammo_label)
	hint = Label.new()
	hint.name = "Hint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.text(hint, 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.78)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8.0)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	hint.add_theme_stylebox_override(&"normal", sb)
	add_child(hint)
	downed = ColorRect.new()
	downed.name = "Downed"
	(downed as ColorRect).color = Color(0.0, 0.0, 0.0, 0.45)
	downed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed.set_anchors_preset(Control.PRESET_FULL_RECT)
	downed.visible = false
	add_child(downed)
	downed_label = Label.new()
	downed_label.name = "DownedLabel"
	downed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	CandleStyle.title(downed_label, 40)
	downed_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	downed_label.add_theme_constant_override(&"outline_size", 8)
	downed_label.text = DOWNED
	downed.add_child(downed_label)
	touch = ArenaTouch.new()
	touch.name = "Touch"
	touch.visible = false
	add_child(touch)


func _layout() -> void:
	if ammo_label == null:
		return
	var w := size.x
	var h := size.y
	# เป้าเล็งตรงกลางจอจริง (กรอบนี้อาจไม่อยู่กลางจอถ้าขอบปลอดภัยสองข้างไม่เท่ากัน)
	var centre := get_global_transform().affine_inverse() * (get_viewport_rect().size * 0.5) if is_inside_tree() else size * 0.5
	var cs := (CROSS + CROSS_GAP) * 2.0 + 4.0
	_rects["Crosshair"] = Rect2(centre - Vector2(cs, cs) * 0.5, Vector2(cs, cs))
	_rects["EnemyBar"] = Rect2(Vector2((w - ENEMY_BAR.x) * 0.5, 6.0), ENEMY_BAR)
	_rects["PlayerBar"] = Rect2(Vector2(0.0, PLAYER_BAR_Y), PLAYER_BAR)
	hint.position = Vector2((w - HINT_W) * 0.5, HINT_Y)
	hint.size = Vector2(HINT_W, 0.0)
	hint.reset_size()
	hint.size.x = HINT_W
	if touch_mode:
		var wb: Array = ArenaTouch.BUTTONS["WeaponButton"]
		var top := h + float(wb[3]) - float(wb[1]) - 8.0
		ammo_label.position = Vector2(w - AMMO_W, top - AMMO_H)
	else:
		ammo_label.position = Vector2(w - AMMO_W, h - AMMO_H)
	ammo_label.size = Vector2(AMMO_W, AMMO_H)
	queue_redraw()


func _update_ammo() -> void:
	if ammo_label == null:
		return
	var id: StringName = player.call("weapon") if player != null else &"none"
	ammo_label.visible = _mode == &"shoot" and id != &"none"
	if not ammo_label.visible:
		return
	if id == &"gun" and _reloading:
		ammo_label.text = I18n.t(RELOADING)
	elif id == &"gun":
		var a: Vector2i = player.call("ammo")
		ammo_label.text = "%d / %d · %s" % [a.x, a.y, I18n.t(str(ArenaData.WEAPONS["gun"]["th"]))]
	else:
		ammo_label.text = I18n.t(str(ArenaData.WEAPONS[String(id)]["th"]))


func _update_hint() -> void:
	if hint == null:
		return
	if _mode == &"walk":
		hint.text = I18n.t(HINT_WALK)
		hint.visible = not _shot_hint_shown
	else:
		hint.text = I18n.t(HINT_TOUCH if touch_mode else HINT_KEYS)
		hint.visible = not _hint_done
	hint.modulate.a = 1.0
	hint.size = Vector2(HINT_W, 0.0)
	hint.reset_size()
	hint.size.x = HINT_W


## จบคำแนะนำการยิง: hi/mid จางหาย 0.4 วิ, lo/min หายทันที
func _finish_hint() -> void:
	if _hint_done:
		return
	_hint_done = true
	if _mode != &"shoot":
		return
	if _smooth() and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(hint, ^"modulate:a", 0.0, 0.4)
		tw.tween_callback(hint.hide)
	else:
		hint.hide()


func _draw_hurt() -> void:
	var w := hurt.size.x
	var h := hurt.size.y
	var e := minf(w, h) * 0.16
	var red := Color(0.85, 0.08, 0.05, 0.55)
	var clear := Color(0.85, 0.08, 0.05, 0.0)
	var quads := [
		[Vector2(0, 0), Vector2(w, 0), Vector2(w - e, e), Vector2(e, e)],
		[Vector2(w, h), Vector2(0, h), Vector2(e, h - e), Vector2(w - e, h - e)],
		[Vector2(0, h), Vector2(0, 0), Vector2(e, e), Vector2(e, h - e)],
		[Vector2(w, 0), Vector2(w, h), Vector2(w - e, h - e), Vector2(w - e, e)],
	]
	for q in quads:
		hurt.draw_primitive(PackedVector2Array(q), PackedColorArray([red, red, clear, clear]), PackedVector2Array())


func _enemy_visible() -> bool:
	if _mode != &"shoot" or enemy == null:
		return false
	return not _enemy_dead or _enemy_show


func _enemy_label() -> String:
	if not _enemy_name.is_empty():
		return str(_enemy_name.get("en" if I18n.english else "th", ""))
	return I18n.t(str(ArenaData.BEAST["th"]))


func _hp_text() -> String:
	return I18n.t(HP_TEXT).format({"hp": _hp, "max": _hp_max})


## ชื่อศัตรูจากแพ็กส่วนตัว (ถ้ามี) ผ่าน ArenaActors.enemy_name
func _pack_name() -> Dictionary:
	if not ResourceLoader.exists(ARENA_ACTORS):
		return {}
	var s := load(ARENA_ACTORS) as Script
	if s == null or not s.has_method("enemy_name"):
		return {}
	var d: Variant = s.call("enemy_name")
	return d if d is Dictionary else {}


func _camera() -> Camera3D:
	if player != null and player.has_method("camera"):
		return player.call("camera")
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _smooth() -> bool:
	return level == "hi" or level == "mid"


func _connect(o: Object, sig: StringName, c: Callable) -> void:
	if o.has_signal(sig) and not o.is_connected(sig, c):
		o.connect(sig, c)
