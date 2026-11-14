class_name PlanetCard
extends PanelContainer
## การ์ดดาว (CAMPAIGN_SPEC §1.5): ชื่อดาว สภาพดาว ผู้รุกราน (ฝ่าย · ลักษณะพิเศษ) ป้ายดาวเด่น เวลาจนสุ่มใหม่
## แถวละหนึ่งเหตุการณ์: ไอคอน ชื่อภารกิจ เป้าหมาย รางวัลประมาณ (CampaignRules.estimate_coins) "ผ่านแล้ว"
## แตะแถว = event_chosen(idx) · ‹ แผนที่ = closed · จอกว้างอยู่ขวา จอแคบเป็นแผ่นล่าง (GalaxyScreen จัดตำแหน่ง)
## ข้อความหัวการ์ดเป็นก้อนเดียว แถวเหตุการณ์ทั้งหมดวาดในโหนดเดียว (เมช + ตัวอักษร): draw call น้อยแม้มี 3 เหตุการณ์
## ไม่มีงานต่อเฟรม (เวลาจนสุ่มใหม่ GalaxyScreen ส่งมาทุก 30 วิ)

signal event_chosen(idx: int)
signal closed

const BACK_TEXT := "‹ แผนที่"
const BIOME := "สภาพดาว: {biome}"
const INVADERS := "ผู้รุกราน: {faction} · {modifier}"
const FEATURED := "ดาวเด่นสัปดาห์นี้ · เหรียญ ×1.5"
const RESET := "รีเซ็ตใน {d} วัน {h} ชม."
const EVENTS := "เหตุการณ์บนดาวนี้"
const REWARD := "รางวัลประมาณ {n} เหรียญ"
const CLEARED := "ผ่านแล้ว"

var week := 0
var planet_id := ""
var difficulty := "normal"

var _back: Button
## ชื่อดาว สภาพดาว ผู้รุกราน (สีฝ่าย) ดาวเด่น เวลาจนสุ่มใหม่ หัวข้อเหตุการณ์: ข้อความเดียว
var _info: RichTextLabel
var _list: EventList
var _scroll: ScrollContainer
var _left_s := 0


## ไอคอนเหตุการณ์ (วาดเอง ไม่มีไฟล์ภาพ): purge = เป้าเล็ง, defend = โล่, rescue = คน, destroy_camp = เสาพิธี
class Icon:
	extends Control
	var type := ""
	var col := Color("e8b860")

	func _init(t := "", c := Color("e8b860")) -> void:
		type = t
		col = c
		custom_minimum_size = Vector2(48, 48)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pen := GalaxyMap.Pen.new()
		PlanetCard.icon_into(pen, type, Rect2(Vector2.ZERO, size), col)
		if size.x > 1.0:
			pen.draw(self)


## รายการเหตุการณ์: พื้นแถว + ไอคอนทุกแถวเป็นสามเหลี่ยมชุดเดียว ตัวอักษรวาดต่อในโหนดเดียวกัน · แตะแถว = chosen(idx)
class EventList:
	extends Control
	signal chosen(idx: int)
	const PAD := 10.0
	const ICON := 52.0
	const GAP := 8.0
	const MIN_H := 84.0
	## [{idx, type, title, goal, reward, done}]
	var rows: Array[Dictionary] = []
	var _paras: Array = []          # ต่อแถว: [TextParagraph ชื่อ, เป้าหมาย, รางวัล]
	var _tops: PackedFloat32Array = []
	var _heights: PackedFloat32Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(_reflow)

	func set_rows(r: Array[Dictionary]) -> void:
		rows = r
		_reflow()

	func row_rect(i: int) -> Rect2:
		return Rect2(0.0, _tops[i], size.x, _heights[i])

	func _para(text: String, font: Font, fsize: int, width: float) -> TextParagraph:
		var p := TextParagraph.new()
		p.add_string(text, font, fsize)
		p.width = maxf(width, 40.0)
		p.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		return p

	func _reflow() -> void:
		var font := get_theme_default_font()
		var tw := size.x - PAD * 3.0 - ICON
		_paras.clear()
		_tops.clear()
		_heights.clear()
		var y := 0.0
		for r in rows:
			var ps := [_para(str(r["title"]), CandleStyle.BOLD, 22, tw), _para(str(r["goal"]), font, 18, tw),
				_para(str(r["reward"]), font, 18, tw)]
			var h := PAD * 2.0
			for p: TextParagraph in ps:
				h += p.get_size().y
			h = maxf(h, MIN_H)
			_paras.append(ps)
			_tops.append(y)
			_heights.append(h)
			y += h + GAP
		custom_minimum_size.y = maxf(y - GAP, 0.0)
		queue_redraw()

	func _draw() -> void:
		if rows.is_empty() or size.x < 2.0 or _tops.size() != rows.size():
			return
		var pen := GalaxyMap.Pen.new()
		var bg := Color(0.2, 0.135, 0.085, 0.95)
		for i in rows.size():
			var r := row_rect(i)
			var done := bool(rows[i]["done"])
			var edge := Color("4f8a55") if done else CandleStyle.GOLD
			var tr := r.position + Vector2(r.size.x, 0)
			var bl := r.position + Vector2(0, r.size.y)
			pen.tri(r.position, tr, r.end, bg)
			pen.tri(r.position, r.end, bl, bg)
			pen.line(r.position, tr, 2.0, edge)
			pen.line(bl, r.end, 2.0, edge)
			pen.line(r.position, bl, 2.0, edge)
			pen.line(tr, r.end, 2.0, edge)
			PlanetCard.icon_into(pen, str(rows[i]["type"]), Rect2(r.position + Vector2(PAD, (r.size.y - ICON) * 0.5), Vector2(ICON, ICON)),
				GalaxyMap.CHECK if done else CandleStyle.GOLD)
		pen.draw(self)
		# ตัวหนาทุกแถวก่อน แล้วตัวธรรมดาทุกแถว: แบบอักษรเดียวกันต่อเนื่อง = รวมเป็น draw call เดียว
		var cols := [CandleStyle.TEXT, CandleStyle.MUTED, GalaxyMap.GOLD]
		for pass_bold in [true, false]:
			for i in rows.size():
				var r := row_rect(i)
				var ps: Array = _paras[i]
				var th := 0.0
				for p: TextParagraph in ps:
					th += p.get_size().y
				var y := r.position.y + (r.size.y - th) * 0.5
				for k in ps.size():
					var p: TextParagraph = ps[k]
					if (k == 0) == pass_bold:
						var c: Color = cols[k]
						if k == 2 and bool(rows[i]["done"]):
							c = GalaxyMap.CHECK
						p.draw(get_canvas_item(), Vector2(PAD * 2.0 + ICON, y), c)
					y += p.get_size().y


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				for i in rows.size():
					if i < _tops.size() and row_rect(i).has_point(mb.position):
						chosen.emit(int(rows[i]["idx"]))
						accept_event()
						return


func _ready() -> void:
	CandleStyle.panel(self)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	col.add_child(top)
	_info = rich(20)
	_info.name = "Info"
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_size_override(&"bold_font_size", 30)
	top.add_child(_info)
	# ปุ่มปิดแบบตัวอักษรอย่างเดียว (ไม่มีกรอบ: draw call น้อย) ยังกดง่าย 52 px
	_back = Button.new()
	_back.name = "CloseCard"
	_back.flat = true
	_back.custom_minimum_size = Vector2(120, 52)
	_back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_override(&"font", CandleStyle.BOLD)
	_back.add_theme_font_size_override(&"font_size", 22)
	for k in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		_back.add_theme_color_override(k, CandleStyle.GOLD)
	_back.pressed.connect(func() -> void: closed.emit())
	top.add_child(_back)
	_scroll = ScrollContainer.new()
	_scroll.name = "EventScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_list = EventList.new()
	_list.name = "Events"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.chosen.connect(choose)
	_scroll.add_child(_list)


## ข้อความหลายสีในก้อนเดียว (bbcode) ความสูงตามเนื้อหา ไม่รับการแตะ
static func rich(size_px: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override(&"normal_font_size", size_px)
	r.add_theme_font_size_override(&"bold_font_size", size_px + 2)
	r.add_theme_font_override(&"bold_font", CandleStyle.BOLD)
	r.add_theme_color_override(&"default_color", CandleStyle.TEXT)
	return r


static func esc(t: String) -> String:
	return t.replace("[", "[lb]")


static func colour(t: String, c: Color) -> String:
	return "[color=#%s]%s[/color]" % [c.to_html(false), esc(t)]


## โชว์ดาว id ของสัปดาห์ w ที่ความยาก diff · left_s = วินาทีจนสุ่มใหม่
func show_planet(w: int, id: String, diff: String, left_s: int) -> void:
	week = w
	planet_id = id
	difficulty = diff
	_left_s = left_s
	refresh()


func set_left(left_s: int) -> void:
	_left_s = left_s
	_fill_info()


## ข้อความหัวการ์ด (เทส)
func info_text() -> String:
	return _info.get_parsed_text()


## อ่านภาษาใหม่และข้อมูลใหม่ (เหตุการณ์ที่ผ่านแล้ว) แล้ววาดทั้งการ์ด
func refresh() -> void:
	if _info == null:
		return
	var pw := CampaignGalaxy.planet_week(week, planet_id)
	if pw.is_empty():
		return
	_back.text = I18n.t(BACK_TEXT)
	_fill_info()
	var list: Array[Dictionary] = []
	for e: Dictionary in pw["events"]:
		var idx := int(e["idx"])
		var t := str(e["type"])
		var spec := CampaignGalaxy.mission_spec(week, planet_id, idx, difficulty)
		var done := CampaignSave.is_repeat(spec)
		list.append({"idx": idx, "type": t, "done": done, "title": I18n.t(MissionTypes.name_th(t)),
			"goal": I18n.t(MissionTypes.goal_th(t)),
			"reward": I18n.t(REWARD).format({"n": reward(idx)}) + ("  ·  " + I18n.t(CLEARED) if done else "")})
	_list.set_rows(list)


func _fill_info() -> void:
	var p := CampaignGalaxy.planet(planet_id)
	var pw := CampaignGalaxy.planet_week(week, planet_id)
	if p.is_empty() or pw.is_empty() or _info == null:
		return
	var f := CampaignGalaxy.faction(str(pw["faction"]))
	var fc := Color(str(f.get("col", "888888"))).lightened(0.3)
	var lines := PackedStringArray()
	lines.append("[b]" + colour(I18n.t(str(p["th"])), CandleStyle.GOLD) + "[/b]")
	lines.append(esc(I18n.t(BIOME).format({"biome": I18n.t(str(CampaignGalaxy.BIOMES[str(p["biome"])]))})))
	lines.append(colour(I18n.t(INVADERS).format({"faction": I18n.t(str(f.get("th", ""))),
		"modifier": I18n.t(str(CampaignGalaxy.modifier(str(pw["modifier"])).get("th", "")))}), fc))
	if bool(pw["featured"]):
		lines.append(colour(I18n.t(FEATURED), GalaxyMap.GOLD))
	lines.append(colour(I18n.t(RESET).format(CampaignWeek.split(_left_s)), CandleStyle.MUTED))
	lines.append(colour(I18n.t(EVENTS), CandleStyle.GOLD))
	_info.text = "\n".join(lines)


## แถวเหตุการณ์ที่โชว์อยู่ (เทส): [{idx, type, title, goal, reward, done}]
func rows() -> Array[Dictionary]:
	return _list.rows


## กรอบของแถว i ในพิกัดจอ (เทส: แตะจริง)
func row_global_rect(i: int) -> Rect2:
	var r := _list.row_rect(i)
	return Rect2(_list.get_global_rect().position + r.position, r.size)


## เลือกเหตุการณ์ idx (แตะแถว / เทส)
func choose(idx: int) -> void:
	var pw := CampaignGalaxy.planet_week(week, planet_id)
	if pw.is_empty() or idx < 0 or idx >= (pw["events"] as Array).size():
		return
	event_chosen.emit(idx)


## เหรียญโดยประมาณของเหตุการณ์ idx ที่ความยากนี้ (รวมดาวเด่น/เล่นซ้ำ)
func reward(idx: int) -> int:
	var spec := CampaignGalaxy.mission_spec(week, planet_id, idx, difficulty)
	return CampaignRules.estimate_coins(spec, CampaignSave.is_repeat(spec))


## ไอคอนเหตุการณ์ใส่ลงใน pen (สามเหลี่ยมชุดเดียว) ในกรอบ r (ใช้ทั้งการ์ดและบรีฟ)
static func icon_into(pen: GalaxyMap.Pen, type: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var red := Color("d8746a")
	pen.circle(c, s, Color(0.06, 0.04, 0.03, 0.9), 24)
	pen.ring(c, s - 1.5, 1.5, Color(col, 0.6), 24)
	var w := maxf(s * 0.11, 2.0)
	match type:
		"purge":
			pen.ring(c, s * 0.55, w, col, 20)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				pen.line(c + d * s * 0.3, c + d * s * 0.8, w, col)
			pen.circle(c, w * 0.8, col, 8)
		"defend":
			var pts := PackedVector2Array([c + Vector2(0, -s * 0.65), c + Vector2(s * 0.52, -s * 0.42),
				c + Vector2(s * 0.45, s * 0.15), c + Vector2(0, s * 0.68), c + Vector2(-s * 0.45, s * 0.15),
				c + Vector2(-s * 0.52, -s * 0.42)])
			pen.poly(pts, Color(col, 0.45))
			for i in pts.size():
				pen.line(pts[i], pts[(i + 1) % pts.size()], w, col)
		"rescue":
			pen.circle(c + Vector2(0, -s * 0.38), s * 0.2, col, 12)
			pen.poly(PackedVector2Array([c + Vector2(-s * 0.32, s * 0.55), c + Vector2(-s * 0.22, -s * 0.1),
				c + Vector2(s * 0.22, -s * 0.1), c + Vector2(s * 0.32, s * 0.55)]), col)
			pen.ring(c + Vector2(0, s * 0.05), s * 0.62, w * 0.8, Color(col, 0.7), 10, PI * 0.15, PI * 0.85)
		"destroy_camp":
			pen.poly(PackedVector2Array([c + Vector2(-s * 0.16, s * 0.6), c + Vector2(-s * 0.1, -s * 0.35),
				c + Vector2(0, -s * 0.55), c + Vector2(s * 0.1, -s * 0.35), c + Vector2(s * 0.16, s * 0.6)]), col)
			pen.line(c + Vector2(-s * 0.55, -s * 0.5), c + Vector2(s * 0.55, s * 0.5), w * 1.2, red)
			pen.line(c + Vector2(s * 0.55, -s * 0.5), c + Vector2(-s * 0.55, s * 0.5), w * 1.2, red)
		_:
			pen.circle(c, s * 0.3, col, 12)
