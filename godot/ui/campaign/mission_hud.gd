class_name MissionHud
extends Control
## หน้าจอเป้าหมายของภารกิจ (CAMPAIGN_SPEC §1.6, track C): แผงเป้าหมายมุมขวาบน (ชื่อภารกิจ เป้าหมายหลัก เวลา ฐาน ตัวประกัน
## เป้าหมายรอง สิทธิ์ลุก) แถบพลังหัวหน้าศัตรู (บนกลาง) แถบปล่อยตัวประกัน ป้ายใหญ่กลางจอ (เริ่ม/จบภารกิจ) · สร้างด้วยโค้ด
## หน้าภารกิจใส่ไว้เต็มกรอบ Safe/Layer ต่อจาก ArenaHud (กระสุน เป้าเล็ง พลังชีวิต ตัวเลขความเสียหาย ปุ่มบนจอ)
## ข้อความไทยทั้งหมดของแผงนี้อยู่ในไฟล์นี้ (คำแปลใน ui/i18n/campaign_mission.json) · งานต่อเฟรม: ไม่มี (อัปเดตตามสัญญาณ)

const PRIMARY_HEAD := "เป้าหมายหลัก"
const SECONDARY_HEAD := "เป้าหมายรอง"
const LINE_PURGE := "สังหารศัตรู {n}/{total}"
const LINE_DEFEND := "รักษาฐานไว้อีก {t}"
const LINE_BASE := "ฐาน {pct}%"
const LINE_RESCUE := "ตัวประกันถึงจุดรับ {n}/{total}"
const LINE_FOLLOW := "กำลังตามคุณ {n} คน"
const LINE_CAMP := "เสาพิธีกรรมที่ทำลาย {n}/{total}"
const LINE_EXTRACT := "ไปที่จุดรับเพื่อถอนตัว"
const LINE_TIME := "เวลาเหลือ {t}"
const SEC_PURGE := "สังหารศัตรู {n}/{total}"
const SEC_DEFEND_OFF := "ยึดสัญญาณ: กด E ในวงสีฟ้า"
const SEC_DEFEND := "ยึดสัญญาณ {n}/{total} วิ"
const SEC_RESCUE := "พาตัวประกันในกรงไปจุดรับ"
const SEC_CAMP := "ทำลายเสาพิธีกรรมนอกค่าย"
const REVIVES := "ลุกได้อีก {n} ครั้ง"
const REVIVES_NONE := "ล้มอีกครั้ง = ภารกิจล้มเหลว"
const BOSS := "หัวหน้าศัตรู"
const FREEING := "กำลังปล่อยตัวประกัน…"
const DONE_MARK := "✓ "
const TODO_MARK := "• "
const PANEL_W := 330.0
const PANEL_W_PHONE := 290.0
const BOSS_BAR := Vector2(440.0, 22.0)
const FREE_BAR := Vector2(320.0, 18.0)

var world: Node3D
var spec: Dictionary = {}
var touch_mode := false
var panel: PanelContainer
var box: VBoxContainer
var title_label: Label
var lines: Array[Label] = []
var boss_box: Control
var boss_label: Label
var boss_fill: ColorRect
var free_box: Control
var free_label: Label
var free_fill: ColorRect
var banner: Label
var banner_sub: Label
var _state: Dictionary = {}
var _boss: Node3D


func _ready() -> void:
	name = "MissionHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	_layout()
	set_process(false)
	set_physics_process(false)


## ต่อเข้ากับโลกภารกิจ (สัญญาณเท่านั้น)
func bind(w: Node3D, s: Dictionary) -> void:
	world = w
	spec = s
	if w.has_signal(&"objective_changed"):
		w.connect(&"objective_changed", _on_objectives)
	if w.has_signal(&"event"):
		w.connect(&"event", _on_event)
	if w.has_method(&"objective_state"):
		_state = w.call(&"objective_state")
	refresh(touch_mode)


func refresh(touch_on: bool) -> void:
	touch_mode = touch_on
	var t := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	title_label.text = I18n.t(MissionTypes.name_th(t))
	boss_label.text = I18n.t(BOSS)
	free_label.text = I18n.t(FREEING)
	_render()
	_layout()


## ป้ายใหญ่กลางจอ (ข้อความแปลแล้ว) · "" = ซ่อน
func show_banner(title: String, sub: String = "") -> void:
	banner.text = title
	banner_sub.text = sub
	banner.visible = title != ""
	banner_sub.visible = sub != "" and title != ""
	_layout()


func banner_text() -> String:
	return banner.text if banner.visible else ""


## ข้อความทุกบรรทัดในแผงตอนนี้ (เทส)
func panel_lines() -> PackedStringArray:
	var out := PackedStringArray([title_label.text])
	for l in lines:
		if l.visible:
			out.append(l.text)
	return out


func boss_visible() -> bool:
	return boss_box.visible


func free_visible() -> bool:
	return free_box.visible


## สถานะเป้าหมายเป็นบรรทัดข้อความ (ฟังก์ชันล้วน แปลภาษาแล้ว)
static func objective_lines(st: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if st.is_empty():
		return out
	var p: Dictionary = st.get("primary", {})
	var ptype := str(p.get("type", ""))
	out.append({"text": I18n.t(PRIMARY_HEAD), "head": true, "done": false})
	var done := str(st.get("outcome", "")) == "win"
	match ptype:
		"purge":
			out.append({"text": I18n.t(LINE_PURGE).format({"n": int(p.get("progress", 0)), "total": int(p.get("total", 0))}), "done": done})
		"defend":
			out.append({"text": I18n.t(LINE_DEFEND).format({"t": clock(float(st.get("timer_s", 0.0)))}), "done": done})
			out.append({"text": I18n.t(LINE_BASE).format({"pct": int(st.get("base_pct", 0))}), "done": false, "warn": int(st.get("base_pct", 100)) < 35})
		"rescue":
			out.append({"text": I18n.t(LINE_RESCUE).format({"n": int(p.get("progress", 0)), "total": int(p.get("total", 0))}), "done": done})
			var follow := int((st.get("hostages", {}) as Dictionary).get("freed", 0))
			if follow > 0:
				out.append({"text": I18n.t(LINE_FOLLOW).format({"n": follow}), "done": false})
			out.append({"text": I18n.t(LINE_TIME).format({"t": clock(float(st.get("timer_s", 0.0)))}), "done": false,
				"warn": float(st.get("timer_s", 999.0)) < 60.0})
		"destroy_camp":
			out.append({"text": I18n.t(LINE_CAMP).format({"n": int(p.get("progress", 0)), "total": int(p.get("total", 0))}),
				"done": bool(p.get("extract", false)) or done})
			if bool(p.get("extract", false)):
				out.append({"text": I18n.t(LINE_EXTRACT), "done": done, "warn": not done})
	var sec: Array = st.get("secondary", [])
	if not sec.is_empty():
		out.append({"text": I18n.t(SECONDARY_HEAD), "head": true, "done": false})
		for s: Dictionary in sec:
			var txt := ""
			match str(s.get("type", "")):
				"purge":
					txt = I18n.t(SEC_PURGE).format({"n": int(s.get("progress", 0)), "total": int(s.get("total", 0))})
				"defend":
					if bool(s.get("on", false)) or bool(s.get("done", false)):
						txt = I18n.t(SEC_DEFEND).format({"n": int(s.get("progress", 0)), "total": int(s.get("total", 0))})
					else:
						txt = I18n.t(SEC_DEFEND_OFF)
				"rescue":
					txt = I18n.t(SEC_RESCUE)
				"destroy_camp":
					txt = I18n.t(SEC_CAMP)
			out.append({"text": txt, "done": bool(s.get("done", false))})
	var rv := int(st.get("revives", 0))
	out.append({"text": I18n.t(REVIVES).format({"n": rv}) if rv > 0 else I18n.t(REVIVES_NONE), "done": false, "small": true,
		"warn": rv <= 0})
	return out


## วินาที → "m:ss"
static func clock(s: float) -> String:
	var t := maxi(int(ceil(s)), 0)
	return "%d:%02d" % [t / 60, t % 60]


# ---- สัญญาณ ----

func _on_objectives(st: Dictionary) -> void:
	_state = st
	_render()
	var f := float(st.get("freeing", -1.0))
	free_box.visible = f >= 0.0
	if f >= 0.0:
		free_fill.size.x = (FREE_BAR.x - 4.0) * f


func _on_event(kind: StringName, _info: Dictionary) -> void:
	if kind == &"boss" and world != null and world.has_method(&"boss"):
		_bind_boss(world.call(&"boss"))


func _bind_boss(b: Node3D) -> void:
	_boss = b
	boss_box.visible = b != null
	if b == null:
		return
	if b.has_signal(&"hp_changed") and not b.is_connected(&"hp_changed", _on_boss_hp):
		b.connect(&"hp_changed", _on_boss_hp)
	_on_boss_hp(int(b.call(&"hp")), int(b.call(&"hp_max")))


func _on_boss_hp(hp: int, hp_max: int) -> void:
	boss_fill.size.x = (BOSS_BAR.x - 4.0) * clampf(float(hp) / maxf(float(hp_max), 1.0), 0.0, 1.0)
	if hp <= 0:
		boss_box.visible = false


# ---- ภายใน ----

func _render() -> void:
	var ls := objective_lines(_state)
	while lines.size() < ls.size():
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CandleStyle.text(l, 18)
		box.add_child(l)
		lines.append(l)
	for i in lines.size():
		var l := lines[i]
		if i >= ls.size():
			l.visible = false
			continue
		var d: Dictionary = ls[i]
		l.visible = true
		var head := bool(d.get("head", false))
		l.text = str(d["text"]) if head else (DONE_MARK if bool(d.get("done", false)) else TODO_MARK) + str(d["text"])
		var col := CandleStyle.TEXT
		if head:
			col = CandleStyle.GOLD
		elif bool(d.get("done", false)):
			col = Color(0.5, 0.88, 0.55)
		elif bool(d.get("warn", false)):
			col = Color(1.0, 0.55, 0.42)
		l.add_theme_color_override(&"font_color", col)
		l.add_theme_font_size_override(&"font_size", 15 if head or bool(d.get("small", false)) else 18)


func _build() -> void:
	panel = PanelContainer.new()
	panel.name = "ObjectivePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.72)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	panel.add_theme_stylebox_override(&"panel", sb)
	add_child(panel)
	box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	panel.add_child(box)
	title_label = Label.new()
	title_label.name = "MissionTitle"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.title(title_label, 20)
	box.add_child(title_label)
	boss_box = _bar_box("BossBar", BOSS_BAR, Color(0.80, 0.24, 0.20))
	boss_label = boss_box.get_node("Label")
	boss_fill = boss_box.get_node("Fill")
	boss_box.visible = false
	free_box = _bar_box("FreeBar", FREE_BAR, Color(1.0, 0.78, 0.34))
	free_label = free_box.get_node("Label")
	free_fill = free_box.get_node("Fill")
	free_box.visible = false
	banner = Label.new()
	banner.name = "Banner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.title(banner, 44)
	banner.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override(&"outline_size", 10)
	banner.visible = false
	add_child(banner)
	banner_sub = Label.new()
	banner_sub.name = "BannerSub"
	banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.text(banner_sub, 24)
	banner_sub.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	banner_sub.add_theme_constant_override(&"outline_size", 7)
	banner_sub.visible = false
	add_child(banner_sub)


## แถบพลัง: พื้นเข้ม + เนื้อสี + ป้ายชื่อ (ColorRect สามชิ้น ไม่มี shader)
func _bar_box(nm: String, sz: Vector2, col: Color) -> Control:
	var c := Control.new()
	c.name = nm
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = sz
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.06, 0.04, 0.03, 0.8)
	bg.size = sz
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(col, 0.9)
	fill.position = Vector2(2.0, 2.0)
	fill.size = Vector2(sz.x - 4.0, sz.y - 4.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(fill)
	var l := Label.new()
	l.name = "Label"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(0.0, -26.0)
	l.size = Vector2(sz.x, 24.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CandleStyle.text(l, 17)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 5)
	c.add_child(l)
	add_child(c)
	return c


func _layout() -> void:
	if panel == null:
		return
	var w := size.x
	var h := size.y
	var pw := PANEL_W_PHONE if touch_mode or w < 900.0 else PANEL_W
	panel.custom_minimum_size = Vector2(pw, 0.0)
	panel.size = Vector2(pw, 0.0)
	panel.reset_size()
	panel.position = Vector2(w - pw, 64.0)
	boss_box.position = Vector2((w - BOSS_BAR.x) * 0.5, 34.0)
	free_box.position = Vector2((w - FREE_BAR.x) * 0.5, h * 0.62)
	var bw := minf(w - 40.0, 900.0)
	banner.size = Vector2(bw, 0.0)
	banner.reset_size()
	banner.size.x = bw
	banner.position = Vector2((w - bw) * 0.5, h * 0.3)
	banner_sub.size = Vector2(bw, 0.0)
	banner_sub.reset_size()
	banner_sub.size.x = bw
	banner_sub.position = Vector2((w - bw) * 0.5, banner.position.y + banner.size.y + 6.0)
