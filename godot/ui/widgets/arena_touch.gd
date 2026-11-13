class_name ArenaTouch
extends Control
## ปุ่มบนจอของอารีน่า (ARENA_SPEC §5.3): จอยเดิน (TouchStick ของห้องโถง ไม่แก้) ซ้ายล่าง, AimPad ล่องหนครึ่งขวาของจอ
## (ลากนิ้วเดียว = เล็ง 0.006 เรเดียนต่อพิกเซล) และปุ่มกลมสี่ปุ่มขวาล่าง: ยิง (กดค้าง ลากจากปุ่มก็เล็งได้) หมัด บรรจุ อาวุธ
## ตำแหน่งปุ่มวัดจากมุมขวาล่างของพื้นที่ปลอดภัย (ตัวนี้เต็มกรอบ Safe/Layer อยู่แล้ว) ทุกปุ่มอยู่ใน 290 px ของมุม
## (ปุ่มบรรจุขยับจาก (−218, −198) ของสเปกเป็น (−206, −190): จุดเดิมห่างมุม 294 px เกินเกณฑ์ 290 ของสเปกเอง)
## ปุ่มรับนิ้วเอง (InputEventScreenTouch/Drag ตาม index: กดยิงค้างพร้อมเดินด้วยจอยได้) และเมาส์จริง (ลองบนเดสก์ท็อป)
## เมาส์ที่จำลองจากนิ้ว (DEVICE_ID_EMULATION) ถูกข้าม · โหมดเดินเหลือจอยอย่างเดียว (ลากจอ = หมุนกล้องตาม)
## ภาพ: _draw เดียววาดจอยกับปุ่มทั้งหมดจากแผ่นภาพวงกลมแผ่นเดียว (1 draw call) แล้วป้ายปุ่มขนาดเดียว (1 draw call)
## ตัวปุ่มและจอยจริงโปร่งใส (modulate 0 = ไม่วาด) แต่ยังรับนิ้ว วัดผัง และเก็บข้อความตามเดิม
## ปุ่มยิงบอกสิ่งที่ทำจริง: "ยิง" ตอนถือปืน "ฟัน" ตอนถือดาบเลื่อย · ป้ายที่ยาวเกิน (เช่น "Saw Sword") แบ่งสองบรรทัด ไม่ย่อจนอ่านไม่ออก
## ปุ่มกลางจอยวาดตามนิ้วจริง (รวมในเขตตาย) ไม่กระโดดตอนนิ้วพ้นเขตตาย
## (ปุ่มกลมแบบ StyleBox วาดทีละ draw call: 13 ครั้งในมุมแย่สุดบนมือถือ เกินงบ min)
## ปุ่ม "หลบ" (พุ่งหลบ) เหนือปุ่มยิงทางซ้าย (ปุ่มอาวุธขยับขวาจาก (−84, −256) เป็น (−52, −258) ให้กรอบปุ่มไม่ทับกัน): ระหว่างพุ่ง/คูลดาวน์ปุ่มมืด วงแหวนทองขยายจากกลางจนเต็มขอบเมื่อพร้อม
## (แผ่นภาพเดิม ไม่เพิ่ม draw call; min ไม่ขยับวง แค่มืดจนพร้อม)
## งานต่อเฟรม: ไม่มี ยกเว้นวงคูลดาวน์ของปุ่มหลบ (ไม่เกิน 1 วิหลังกดหลบ ไม่มีบน min)

signal pressed_action(action: StringName, on: bool)

const FIRE_TEXT := "ยิง"
const SWING_TEXT := "ฟัน"
const MELEE_TEXT := "หมัด"
const RELOAD_TEXT := "บรรจุ"
## ปุ่ม: ชื่อโหนด → [action, รัศมี, dx, dy จากมุมขวาล่าง]
const BUTTONS := {
	"FireButton": [&"fire", 62.0, -106.0, -116.0],
	"MeleeButton": [&"melee", 46.0, -234.0, -60.0],
	"ReloadButton": [&"reload", 38.0, -206.0, -190.0],
	"WeaponButton": [&"weapon", 38.0, -52.0, -258.0],
	"DodgeButton": [&"dodge", 32.0, -128.0, -218.0],
}
const DODGE_DIM := Color(0.06, 0.04, 0.03, 0.75)
const STICK_SIZE := 180.0
const AIM_TOP := 64.0          # AimPad ไม่บังปุ่มบนสุดของหน้าจอ
const AIM_BOTTOM := 88.0       # และไม่บังปุ่มใช้งานกลางล่าง
const FILL := Color(0.10, 0.065, 0.04, 0.55)
const FILL_HELD := Color(0.48, 0.29, 0.11, 0.75)
const RIM := Color(0.91, 0.72, 0.38, 0.9)
const KNOB_RIM := Color(0.3, 0.18, 0.08, 0.9)
## แผ่นภาพ: วงกลมทึบ | วงแหวน ขนาด SPRITE px สีขาว (ย้อมสีตอนวาด) สร้างครั้งเดียวต่อการเปิดแอป
const SPRITE := 128
const RING_T := 3.5
const LABEL_FS := 26
const LABEL_MIN := 16          # ป้ายเล็กกว่านี้อ่านยากบนมือถือ: แบ่งสองบรรทัดแทน
const INVISIBLE := Color(1.0, 1.0, 1.0, 0.0)

static var _atlas: ImageTexture

var player: Node3D
var shoot := false

var stick: TouchStick
var aim_pad: Control
var buttons: Dictionary = {}     # ชื่อ → Button
var _held: Dictionary = {}       # ชื่อ → index นิ้ว (-2 = เมาส์)
var _fs: Dictionary = {}         # ชื่อ → ขนาดตัวอักษรของป้าย (ย่อให้พอดีวง)
var _lines: Dictionary = {}      # ชื่อ → บรรทัดของป้าย (1 หรือ 2)
var _aim_finger := -1
var _aim_mouse := false
var _dodge_ratio := 1.0          # วงคูลดาวน์ของปุ่มหลบ (1 = พร้อม)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(layout)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			release_all())
	layout()
	set_process(false)
	set_physics_process(false)


func bind(p: Node3D) -> void:
	player = p
	if stick != null and not stick.changed.is_connected(_on_stick):
		stick.changed.connect(_on_stick)
	if p != null and p.has_signal(&"dodge_changed") and not p.is_connected(&"dodge_changed", _on_dodge):
		p.connect(&"dodge_changed", _on_dodge)


## ข้อความปุ่มตามภาษา (ปุ่มอาวุธ = ชื่ออาวุธอีกอันที่จะเปลี่ยนไป)
func refresh() -> void:
	_set_text("MeleeButton", I18n.t(MELEE_TEXT))
	_set_text("ReloadButton", I18n.t(RELOAD_TEXT))
	_set_text("DodgeButton", I18n.t(str(ArenaData.DODGE["th"])))
	update_weapon()


func update_weapon() -> void:
	var other := &"gun"
	var held := &"gun"
	if player != null and player.get("weapons") != null:
		var w := player.get("weapons") as ArenaWeapons
		other = w.other()
		held = w.held()
	_set_text("WeaponButton", I18n.t(str(ArenaData.WEAPONS[String(other)]["th"])))
	_set_text("FireButton", I18n.t(SWING_TEXT if held == &"sword" else FIRE_TEXT))


## โหมดยิงโชว์ปุ่มยิง/หมัด/บรรจุ/อาวุธ และ AimPad; โหมดเดินซ่อน (เหลือจอย)
func set_shoot(on: bool) -> void:
	shoot = on
	if not on:
		_release_buttons()
	for n in buttons:
		(buttons[n] as Control).visible = on
	aim_pad.visible = on
	aim_pad.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func release_all() -> void:
	_release_buttons()
	if stick != null:
		stick.release()


## จุดศูนย์กลางของปุ่ม (พิกัด canvas) สำหรับเทส
func button_centre(n: String) -> Vector2:
	var b: Control = buttons.get(n)
	return b.get_global_rect().get_center() if b != null else Vector2.ZERO


func layout() -> void:
	if aim_pad == null:
		return
	var w := size.x
	var h := size.y
	stick.position = Vector2(0.0, h - STICK_SIZE)
	stick.size = Vector2(STICK_SIZE, STICK_SIZE)
	aim_pad.position = Vector2(w * 0.5, AIM_TOP)
	aim_pad.size = Vector2(w * 0.5, maxf(h - AIM_TOP - AIM_BOTTOM, 0.0))
	for n in BUTTONS:
		var cfg: Array = BUTTONS[n]
		var r := float(cfg[1])
		var b: Button = buttons[n]
		b.size = Vector2(r, r) * 2.0
		b.position = Vector2(w + float(cfg[2]) - r, h + float(cfg[3]) - r)
	update_weapon()
	queue_redraw()


# ---- ภายใน ----

func _build() -> void:
	stick = TouchStick.new()
	stick.name = "Stick"
	stick.modulate = INVISIBLE
	# จอยขอวาดใหม่ทุกครั้งที่ปุ่มกลางขยับ (แม้ในเขตตาย): วาดตามไปด้วย
	stick.draw.connect(queue_redraw)
	add_child(stick)
	aim_pad = Control.new()
	aim_pad.name = "AimPad"
	aim_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	aim_pad.focus_mode = Control.FOCUS_NONE
	aim_pad.gui_input.connect(_on_aim_input)
	add_child(aim_pad)
	for n in BUTTONS:
		var cfg: Array = BUTTONS[n]
		var r := float(cfg[1])
		var b := Button.new()
		b.name = n
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = INVISIBLE
		b.custom_minimum_size = Vector2(r, r) * 2.0
		b.clip_text = false
		b.add_theme_font_override(&"font", CandleStyle.BOLD)
		b.add_theme_font_size_override(&"font_size", 26 if n == "FireButton" else 20)
		b.add_theme_color_override(&"font_color", CandleStyle.TEXT)
		b.add_theme_color_override(&"font_pressed_color", CandleStyle.GOLD)
		b.add_theme_color_override(&"font_hover_color", CandleStyle.TEXT)
		for st in [&"normal", &"hover", &"focus", &"disabled"]:
			b.add_theme_stylebox_override(st, _round(r, FILL))
		b.add_theme_stylebox_override(&"pressed", _round(r, FILL_HELD))
		b.add_theme_stylebox_override(&"hover_pressed", _round(r, FILL_HELD))
		b.gui_input.connect(_on_button_input.bind(n))
		add_child(b)
		buttons[n] = b
	set_shoot(false)


static func _round(r: float, fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = RIM
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(r))
	sb.anti_aliasing = false
	sb.set_content_margin_all(4.0)
	return sb


## ข้อความปุ่ม: ย่อตัวอักษรจนพอดีวงกลม · ต้องเล็กกว่า LABEL_MIN และมีช่องว่าง = แบ่งสองบรรทัด
func _set_text(n: String, text: String) -> void:
	var b: Button = buttons.get(n)
	if b == null:
		return
	b.text = text
	var r := float(BUTTONS[n][1])
	var room := r * 2.0 - 12.0
	var top := 26 if n == "FireButton" else 20
	var lines := PackedStringArray([text])
	var fs := _fit(lines, top, room)
	if fs < LABEL_MIN and text.contains(" "):
		var cut := _middle_space(text)
		var two := PackedStringArray([text.left(cut), text.substr(cut + 1)])
		var fs2 := _fit(two, top, room)
		if fs2 > fs:
			lines = two
			fs = fs2
	b.add_theme_font_size_override(&"font_size", fs)
	_fs[n] = fs
	_lines[n] = lines
	queue_redraw()


## ขนาดตัวอักษรใหญ่สุด (ไม่เกิน top ไม่ต่ำกว่า 11) ที่ทุกบรรทัดกว้างไม่เกิน room
static func _fit(lines: PackedStringArray, top: int, room: float) -> int:
	var fs := top
	while fs > 11:
		var w := 0.0
		for l in lines:
			w = maxf(w, CandleStyle.BOLD.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if w <= room:
			break
		fs -= 1
	return fs


## ช่องว่างที่ใกล้กลางข้อความที่สุด
static func _middle_space(text: String) -> int:
	var best := -1
	for i in text.length():
		if text[i] == " " and (best < 0 or absf(i - text.length() * 0.5) < absf(best - text.length() * 0.5)):
			best = i
	return best


## ขนาดตัวอักษรและบรรทัดของป้าย (เทส)
func label_layout(n: String) -> Dictionary:
	return {"fs": int(_fs.get(n, LABEL_FS)), "lines": _lines.get(n, PackedStringArray())}


func _on_button_input(event: InputEvent, n: String) -> void:
	var action: StringName = BUTTONS[n][0]
	var b: Button = buttons[n]
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _held.has(n):
			_held[n] = t.index
			b.toggle_mode = true
			b.set_pressed_no_signal(true)
			_emit(action, true)
			queue_redraw()
		elif not t.pressed and int(_held.get(n, -99)) == t.index:
			_release_button(n)
		b.accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if n == "FireButton" and int(_held.get(n, -99)) == d.index and player != null:
			player.call("aim_drag", d.relative)
		b.accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION or mb.button_index != MOUSE_BUTTON_LEFT:
			b.accept_event()
			return
		if mb.pressed and not _held.has(n):
			_held[n] = -2
			b.toggle_mode = true
			b.set_pressed_no_signal(true)
			_emit(action, true)
			queue_redraw()
		elif not mb.pressed and int(_held.get(n, -99)) == -2:
			_release_button(n)
		b.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.device != InputEvent.DEVICE_ID_EMULATION and n == "FireButton" and int(_held.get(n, -99)) == -2 and player != null:
			player.call("aim_drag", mm.relative)
		b.accept_event()


func _release_button(n: String) -> void:
	if not _held.has(n):
		return
	_held.erase(n)
	var b: Button = buttons[n]
	b.set_pressed_no_signal(false)
	b.toggle_mode = false
	_emit(BUTTONS[n][0], false)
	queue_redraw()


func _release_buttons() -> void:
	for n in _held.keys():
		_release_button(n)
	_aim_finger = -1
	_aim_mouse = false


func _emit(action: StringName, on: bool) -> void:
	if player != null:
		player.call("press", action, on)
	pressed_action.emit(action, on)
	if action == &"weapon" and on:
		update_weapon.call_deferred()


func _on_aim_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _aim_finger < 0:
			_aim_finger = t.index
		elif not t.pressed and t.index == _aim_finger:
			_aim_finger = -1
		aim_pad.accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _aim_finger and player != null:
			player.call("aim_drag", d.relative)
		aim_pad.accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.device != InputEvent.DEVICE_ID_EMULATION and mb.button_index == MOUSE_BUTTON_LEFT:
			_aim_mouse = mb.pressed
		aim_pad.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.device != InputEvent.DEVICE_ID_EMULATION and _aim_mouse and player != null:
			player.call("aim_drag", mm.relative)
		aim_pad.accept_event()


func _on_stick(v: Vector2) -> void:
	if player != null:
		player.call("set_stick", v)


## พุ่ง/คูลดาวน์/พร้อม: วาดใหม่ตามเหตุการณ์ · hi/mid/lo ขยับวงทุกเฟรมจนพร้อม (min ไม่)
func _on_dodge(state: StringName) -> void:
	_dodge_ratio = 1.0 if state == &"ready" else _ratio()
	set_process(state != &"ready" and App.gfx != "min")
	queue_redraw()


func _ratio() -> float:
	if player != null and player.has_method(&"dodge_ready_ratio"):
		return clampf(float(player.call(&"dodge_ready_ratio")), 0.0, 1.0)
	return 1.0


## วงคูลดาวน์ปุ่มหลบ (0..1) สำหรับเทส
func dodge_ratio() -> float:
	return _dodge_ratio


func _process(_delta: float) -> void:
	_dodge_ratio = _ratio()
	queue_redraw()
	if _dodge_ratio >= 1.0:
		set_process(false)


# ---- ภาพ (วาดรวบครั้งเดียว) ----

## จอย (ฐาน ขอบ วงวิ่ง ปุ่มกลาง) แล้วปุ่มกลม (พื้น ขอบ) จากแผ่นภาพเดียว แล้วป้ายปุ่มทั้งหมดขนาดเดียว (ย่อด้วย transform)
func _draw() -> void:
	var tex := atlas()
	if stick != null and stick.visible:
		var c := stick.position + stick.size * 0.5
		var knob: Vector2 = stick.get("_knob") if stick.get("_knob") is Vector2 else Vector2(stick.value.x, -stick.value.y) * TouchStick.BASE_R
		_sprite(tex, false, c, TouchStick.BASE_R, TouchStick.FILL)
		_sprite(tex, true, c, TouchStick.BASE_R, TouchStick.RIM)
		_sprite(tex, true, c, TouchStick.BASE_R * TouchStick.RUN, Color(TouchStick.RIM, 0.3))
		_sprite(tex, false, c + knob, TouchStick.KNOB_R, TouchStick.KNOB)
		_sprite(tex, true, c + knob, TouchStick.KNOB_R, KNOB_RIM)
	if not shoot:
		return
	for n in BUTTONS:
		var b: Button = buttons[n]
		var r := float(BUTTONS[n][1])
		var c := b.position + b.size * 0.5
		if n == "DodgeButton" and _dodge_ratio < 1.0:
			_sprite(tex, false, c, r, DODGE_DIM)
			_sprite(tex, true, c, r, Color(RIM, 0.35))
			if App.gfx != "min":
				_sprite(tex, true, c, maxf(r * _dodge_ratio, 2.0), CandleStyle.GOLD)
			continue
		_sprite(tex, false, c, r, FILL_HELD if b.button_pressed else FILL)
		_sprite(tex, true, c, r, RIM)
	var font := CandleStyle.BOLD
	var base_y := (font.get_ascent(LABEL_FS) - font.get_descent(LABEL_FS)) * 0.5
	var line_h := font.get_height(LABEL_FS) * 0.92
	for n in BUTTONS:
		var b: Button = buttons[n]
		if b.text == "":
			continue
		var k := float(_fs.get(n, LABEL_FS)) / LABEL_FS
		var lines: PackedStringArray = _lines.get(n, PackedStringArray([b.text]))
		draw_set_transform(b.position + b.size * 0.5, 0.0, Vector2(k, k))
		for i in lines.size():
			var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS).x
			var y := base_y + (i - (lines.size() - 1) * 0.5) * line_h
			draw_string(font, Vector2(-w * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FS,
				CandleStyle.GOLD if b.button_pressed else CandleStyle.TEXT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sprite(tex: Texture2D, ring: bool, c: Vector2, r: float, col: Color) -> void:
	draw_texture_rect_region(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0),
		Rect2(SPRITE if ring else 0, 0, SPRITE, SPRITE), col)


## แผ่นภาพวงกลมทึบกับวงแหวน (ขาว ขอบนุ่ม 1 px) สร้างครั้งแรกที่ใช้ คำนวณมุมเดียวแล้วสะท้อนสี่มุม
static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var n := SPRITE
	var w := n * 2
	var data := PackedByteArray()
	data.resize(w * n * 2)
	data.fill(255)
	var r := n * 0.5 - 0.5
	var half := n / 2
	for y in half:
		for x in half:
			var dx := r - x
			var dy := r - y
			var d := sqrt(dx * dx + dy * dy)
			var disc := clampf(r - d + 0.5, 0.0, 1.0)
			var ring := disc * clampf(d - (r - RING_T) + 0.5, 0.0, 1.0)
			var a := int(disc * 255.0)
			var b := int(ring * 255.0)
			var top := y * w * 2 + 1
			var bottom := (n - 1 - y) * w * 2 + 1
			for i in [top + x * 2, top + (n - 1 - x) * 2, bottom + x * 2, bottom + (n - 1 - x) * 2]:
				data[i] = a
				data[i + n * 2] = b
	_atlas = ImageTexture.create_from_image(Image.create_from_data(w, n, false, Image.FORMAT_LA8, data))
	return _atlas
