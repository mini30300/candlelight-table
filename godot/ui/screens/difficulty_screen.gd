class_name DifficultyScreen
extends Control
## หน้าเลือกความยาก (CAMPAIGN_SPEC §1.4, §3, track B เป็นเจ้าของ): การ์ด 4 ใบ ธรรมดา / ยาก / ยากมาก / ภัยพิบัติ
## แต่ละใบมีฉากโชว์ (HeroStage + CampaignHeroes) ชื่อ คำอธิบาย สิ่งที่เปลี่ยน ตัวคูณคะแนน และจำนวนครั้งที่ลุกได้
## (CampaignRules.difficulty / mult_text) · เลือกแล้ว: ส่ง chosen(id) ครั้งเดียว — หน้านี้ไม่ปิดตัวเอง CampaignFlow เปลี่ยนหน้าเอง
## ‹ กลับ / Esc = App ถอยกลับ (handle_back คืน false)
## จอกว้าง (≥ 1100 และไม่ใช่แนวตั้ง): 4 ใบเรียงแถว · จอแคบ/แนวตั้ง: ใบเดียวเต็มจอ + แท็บ 4 ปุ่ม + ปุ่ม ‹ › + ปัดซ้าย/ขวา
## (ขนาดเป็นหน่วย canvas: ยืดแบบ expand ฐาน 1280×720 กว้างไม่ต่ำกว่า 1280 จึงแคบเฉพาะหน้าต่างแนวตั้ง)
## แตะ/คลิกการ์ด = เลือก (ฉากของใบนั้นเล่นสด) แตะซ้ำหรือปุ่ม "เลือก" (มีเฉพาะใบที่ชี้อยู่) = ยืนยัน · ←/→ (A/D) เลื่อน · E / Enter ยืนยัน
## ฉากสดได้ทีละใบ (ใบที่เลือก) ใบอื่นเป็นภาพนิ่งที่วาดครั้งเดียว ทีละใบ · min: ภาพนิ่งทั้ง 4 ใบ ไม่มีงานต่อเฟรมหลังวาดเสร็จ

signal chosen(difficulty: StringName)

const SCENE := "res://ui/screens/difficulty_screen.tscn"
const TITLE := "เลือกความยาก"
const SUBTITLE := "ความยากเปลี่ยนจำนวนศัตรู ความแรง และคะแนน"
const BACK_TEXT := "‹ กลับ"
const CHOOSE := "เลือก"
const SCORE := "คะแนน {x}"
const REVIVES := "ลุกได้ {n} ครั้ง"
const REVIVE_ONE := "ลุกได้ 1 ครั้ง"
const NO_REVIVE := "ล้มแล้วจบ"
const STATS := "ศัตรู {count} · ทน {hp} · แรง {dmg} · เร็ว {speed}"
const STATS_BASE := "ศัตรูค่าปกติ ไม่มีตัวคูณ"
const HINT_KEYS := "← → เลือกการ์ด · E / Enter ยืนยัน"
const HINT_TOUCH := "แตะการ์ดเพื่อดูฉาก แตะซ้ำหรือกดปุ่มเลือกเพื่อยืนยัน"
const WIDE := 1100.0
const SWIPE := 70.0
const ACCENT := {"normal": Color("d2cbbf"), "hard": Color("5b95e8"), "veryhard": Color("c4d0de"),
	"catastrophe": Color("e4483c")}
const CARD_BG := Color(0.075, 0.058, 0.05, 0.96)
## ตัวอักษรในการ์ดมีสองแบบเท่านั้น (ชื่อ+คะแนน ตัวหนา, ที่เหลือตัวธรรมดา) วาดรวมกันได้ทีละชุด: min ไม่เกิน 30 draw calls
const NAME_SIZE := 24
const TEXT_SIZE := 16

var ctx: Dictionary = {}
var level := "mid"
var touch_mode := false
var narrow := false

var _sel: StringName = &"normal"
var _done := false
var _started := false
var _cards: Dictionary = {}          # id → {panel, stage, name, mult, blurb, stats, revives, button, on, off}
var _queue: Array[String] = []
var _press_id := ""
var _press_at := Vector2.ZERO

var _margin: MarginContainer
var _back: Button
var _title: Label
var _sub: Label
var _tabs: HBoxContainer
var _prev: Button
var _next: Button
var _row: HBoxContainer
var _hint: Label


func _ready() -> void:
	level = App.gfx
	touch_mode = App.touch_active()
	_build()
	refresh()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_start.call_deferred()


## เรียกหลัง App.push ทันที: ctx = {"last": ความยากที่เลือกครั้งก่อน ("" = ยังไม่เคย), "from": "deck" | "room"}
func open(c: Dictionary) -> void:
	ctx = c
	var last := str(c.get("last", ""))
	_sel = StringName(last) if CampaignGalaxy.DIFFICULTIES.has(last) else &"normal"
	_paint_selection()


## เลือกความยาก = ยืนยัน (ปุ่มการ์ด / แตะซ้ำ / Enter / เทส) · ส่ง chosen ครั้งเดียวต่อเฟรม
func choose(id: StringName) -> void:
	if _done or not CampaignGalaxy.DIFFICULTIES.has(String(id)):
		return
	_done = true
	_set_unlocked.call_deferred()
	if id != _sel:
		select(id)
	chosen.emit(id)


## ชี้การ์ด id: ไฮไลต์ ฉากของใบนั้นเล่นสด ใบเดิมกลับเป็นภาพนิ่ง
func select(id: StringName) -> void:
	if not CampaignGalaxy.DIFFICULTIES.has(String(id)):
		return
	var old := _sel
	_sel = id
	_paint_selection()
	if not _started:
		return
	if old != id and _cards.has(String(old)):
		(_cards[String(old)]["stage"] as HeroStage).set_live(false)
	_go_live(String(id))
	# ภาพนิ่งที่ถูกยกเลิกกลางทาง (ใบนั้นกลายเป็นใบสด) ไม่ส่ง still_ready: เดินคิวต่อเอง
	_next_still.call_deferred()


func selected() -> StringName:
	return _sel


## เวทีทั้ง 4 ใบตามลำดับ normal, hard, veryhard, catastrophe (เทส)
func stages() -> Array:
	var out := []
	for id in CampaignGalaxy.DIFFICULTIES:
		out.append(_cards[id]["stage"])
	return out


## การ์ดของ id (เทส): {panel, stage, name, mult, blurb, stats, revives, button}
func card(id: String) -> Dictionary:
	return _cards.get(id, {})


func tab_buttons() -> Array:
	return _tabs.get_children()


func handle_back() -> bool:
	return false


## อ่านภาษาใหม่แล้ววาดข้อความทั้งหมด
func refresh() -> void:
	_back.text = I18n.t(BACK_TEXT)
	_title.text = I18n.t(TITLE)
	_sub.text = I18n.t(SUBTITLE)
	_hint.text = I18n.t(HINT_TOUCH if touch_mode else HINT_KEYS)
	for id in CampaignGalaxy.DIFFICULTIES:
		var d := CampaignRules.difficulty(id)
		var c: Dictionary = _cards[id]
		(c["name"] as Label).text = I18n.t(str(d["th"]))
		(c["mult"] as Label).text = I18n.t(SCORE).format({"x": CampaignRules.mult_text(id)})
		(c["blurb"] as Label).text = I18n.t(str(d["blurb"]))
		(c["stats"] as Label).text = stats_text(id)
		(c["revives"] as Label).text = revives_text(int(d["revives"]))
		(c["button"] as Button).text = I18n.t(CHOOSE)
	for b: Button in _tabs.get_children():
		b.text = I18n.t(str(CampaignRules.difficulty(str(b.get_meta(&"id")))["th"]))
	_even_cards.call_deferred()


## กล่องข้อความทุกใบสูงเท่าใบที่สูงสุด (ข้อความยาวไม่เท่ากันในแต่ละภาษา)
func _even_cards() -> void:
	if not is_inside_tree():
		return
	var tallest := 0.0
	for id in CampaignGalaxy.DIFFICULTIES:
		var info: Control = _cards[id]["info"]
		info.custom_minimum_size.y = 0.0
	for id in CampaignGalaxy.DIFFICULTIES:
		var info: Control = _cards[id]["info"]
		tallest = maxf(tallest, info.get_combined_minimum_size().y)
	for id in CampaignGalaxy.DIFFICULTIES:
		(_cards[id]["info"] as Control).custom_minimum_size.y = tallest


## "ศัตรู ×1.4 · ทน ×1.3 · แรง ×1.3 · เร็ว ×1.1" (ค่าปกติทั้งหมด = ข้อความสั้น)
static func stats_text(id: String) -> String:
	var d := CampaignRules.difficulty(id)
	var keys := ["count_pct", "hp_pct", "dmg_pct", "speed_pct"]
	if keys.all(func(k: String) -> bool: return int(d[k]) == 100):
		return I18n.t(STATS_BASE)
	return I18n.t(STATS).format({"count": pct_text(int(d["count_pct"])), "hp": pct_text(int(d["hp_pct"])),
		"dmg": pct_text(int(d["dmg_pct"])), "speed": pct_text(int(d["speed_pct"]))})


## ร้อยละ → "×1.4" / "×2"
static func pct_text(p: int) -> String:
	if p % 100 == 0:
		return "×%d" % (p / 100)
	if p % 10 == 0:
		return "×%d.%d" % [p / 100, (p % 100) / 10]
	return "×%d.%02d" % [p / 100, p % 100]


static func revives_text(n: int) -> String:
	if n <= 0:
		return I18n.t(NO_REVIVE)
	if n == 1:
		return I18n.t(REVIVE_ONE)
	return I18n.t(REVIVES).format({"n": n})


# ---- สร้างหน้า ----

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = CandleStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_margin = MarginContainer.new()
	_margin.name = "Safe"
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	_margin.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 16)
	col.add_child(top)
	_back = Button.new()
	_back.name = "BackButton"
	_back.custom_minimum_size = Vector2(140.0, 56.0)
	_back.focus_mode = Control.FOCUS_NONE
	CandleStyle.button(_back)
	_back.pressed.connect(_on_back)
	top.add_child(_back)
	var heads := VBoxContainer.new()
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_theme_constant_override(&"separation", 0)
	top.add_child(heads)
	_title = Label.new()
	_title.name = "Title"
	CandleStyle.title(_title, 32)
	heads.add_child(_title)
	_sub = Label.new()
	_sub.name = "Subtitle"
	CandleStyle.text(_sub, 17, true)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heads.add_child(_sub)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override(&"separation", 8)
	col.add_child(_tabs)
	var tab_list: Array = []
	for id in CampaignGalaxy.DIFFICULTIES:
		var tb := Button.new()
		tb.name = "Tab_" + id
		tb.set_meta(&"id", id)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.focus_mode = Control.FOCUS_NONE
		tb.clip_text = true
		CandleStyle.button(tb)
		tb.add_theme_font_size_override(&"font_size", 18)
		tb.pressed.connect(select.bind(StringName(id)))
		_tabs.add_child(tb)
		tab_list.append(tb)
	CandleStyle.toggle_group(tab_list)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 8)
	col.add_child(body)
	_prev = _arrow("‹", -1)
	body.add_child(_prev)
	_row = HBoxContainer.new()
	_row.name = "Cards"
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_theme_constant_override(&"separation", 12)
	body.add_child(_row)
	_next = _arrow("›", 1)
	body.add_child(_next)
	for id in CampaignGalaxy.DIFFICULTIES:
		_cards[id] = _build_card(id)
	_hint = Label.new()
	_hint.name = "Hint"
	CandleStyle.text(_hint, 16, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)


func _arrow(text: String, dir: int) -> Button:
	var b := Button.new()
	b.name = "Prev" if dir < 0 else "Next"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56.0, 56.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	CandleStyle.button(b)
	b.add_theme_font_size_override(&"font_size", 32)
	b.pressed.connect(_step.bind(dir))
	return b


func _build_card(id: String) -> Dictionary:
	var accent: Color = ACCENT[id]
	var panel := PanelContainer.new()
	panel.name = "Card_" + id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_card_input.bind(id))
	var off := _card_box(CandleStyle.EDGE, 1, Color(0, 0, 0, 0))
	var on := _card_box(accent, 3, Color(accent, 0.35))
	panel.add_theme_stylebox_override(&"panel", off)
	_row.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var stage := HeroStage.new()
	stage.name = "Stage"
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(120.0, 120.0)
	v.add_child(stage)
	# ข้อความกับปุ่มอยู่ในกล่องเดียว สูงเท่ากันทุกใบ (ฉากทุกใบจึงสูงเท่ากัน)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.add_theme_constant_override(&"separation", 4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(info)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	var name_l := _label(head, NAME_SIZE, accent, true)
	name_l.name = "Name"
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mult := _label(head, NAME_SIZE, CandleStyle.GOLD, true)
	mult.name = "Mult"
	mult.autowrap_mode = TextServer.AUTOWRAP_OFF
	mult.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var blurb := _label(info, TEXT_SIZE, CandleStyle.TEXT)
	blurb.name = "Blurb"
	var stats := _label(info, TEXT_SIZE, CandleStyle.MUTED)
	stats.name = "Stats"
	var rev := _label(info, TEXT_SIZE, CandleStyle.DANGER if int(CampaignRules.difficulty(id)["revives"]) == 0 else CandleStyle.MUTED)
	rev.name = "Revives"
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(spacer)
	var b := Button.new()
	b.name = "Choose"
	b.focus_mode = Control.FOCUS_NONE
	CandleStyle.button(b, true)
	b.pressed.connect(choose.bind(StringName(id)))
	info.add_child(b)
	return {"panel": panel, "stage": stage, "name": name_l, "mult": mult, "blurb": blurb, "stats": stats,
		"revives": rev, "button": b, "info": info, "on": on, "off": off}


func _label(parent: Control, size: int, colour: Color, bold := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	if bold:
		l.add_theme_font_override(&"font", CandleStyle.BOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _card_box(edge: Color, width: int, glow: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(8.0)
	sb.shadow_color = glow
	sb.shadow_size = 12 if glow.a > 0.0 else 0
	return sb


# ---- ฉาก ----

## เริ่มฉาก (หลังวางหน้าแล้ว): ใบที่เลือกเล่นสด แล้ววาดภาพนิ่งของใบอื่นทีละใบ · min: ภาพนิ่งทั้งหมด
func _start() -> void:
	if _started or not is_inside_tree():
		return
	_started = true
	_paint_selection()
	_go_live(String(_sel))
	_queue.clear()
	for id in CampaignGalaxy.DIFFICULTIES:
		if id != String(_sel):
			_queue.append(id)
	_next_still()


func _ctx() -> Dictionary:
	return {"level": level, "sel": Figures.selected()}


func _go_live(id: String) -> void:
	var st: HeroStage = _cards[id]["stage"]
	if st.id != id:
		if not st.still_ready.is_connected(_next_still):
			st.still_ready.connect(_next_still)
		st.show_hero(id, _ctx())
	if level != "min":
		st.set_live(true)


## ภาพนิ่งถัดไปในคิว (เรียกต่อกันจาก still_ready: ทีละใบ ไม่มี _process ของหน้า)
func _next_still() -> void:
	for st in stages():
		if (st as HeroStage).busy():
			return
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		var st: HeroStage = _cards[id]["stage"]
		if st.id == id:
			continue
		if not st.still_ready.is_connected(_next_still):
			st.still_ready.connect(_next_still)
		st.show_hero(id, _ctx())
		if st.busy():
			return


func _paint_selection() -> void:
	if _cards.is_empty():
		return
	for id in CampaignGalaxy.DIFFICULTIES:
		var c: Dictionary = _cards[id]
		var on := id == String(_sel)
		(c["panel"] as PanelContainer).add_theme_stylebox_override(&"panel", c["on"] if on else c["off"])
		(c["stage"] as Control).modulate = Color.WHITE if on else Color(0.78, 0.78, 0.8)
		(c["panel"] as Control).visible = on or not narrow
		# ปุ่มเลือกเฉพาะใบที่ชี้อยู่ (ใบอื่นแตะเพื่อชี้ก่อน)
		(c["button"] as Control).visible = on
	for b: Button in _tabs.get_children():
		b.set_pressed_no_signal(str(b.get_meta(&"id")) == String(_sel))
	var i := CampaignGalaxy.DIFFICULTIES.find(String(_sel))
	_prev.disabled = i <= 0
	_next.disabled = i >= CampaignGalaxy.DIFFICULTIES.size() - 1


func _step(dir: int) -> void:
	var ids := CampaignGalaxy.DIFFICULTIES
	var i := clampi(ids.find(String(_sel)) + dir, 0, ids.size() - 1)
	select(StringName(ids[i]))


func _set_unlocked() -> void:
	_done = false


# ---- ป้อนข้อมูล ----

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event.is_echo():
		return
	# เลือกแล้ว CampaignFlow แทนที่หน้านี้ทันที (หลุดจาก tree): จับ viewport ไว้ก่อน
	var vp := get_viewport()
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_step(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_step(1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		choose(_sel)
	else:
		return
	vp.set_input_as_handled()


## แตะ/คลิกการ์ด: ใบใหม่ = ชี้ · ใบที่ชี้อยู่ = ยืนยัน · จอแคบปัดซ้าย/ขวา = ใบถัดไป (สัมผัสมาเป็นเมาส์จำลอง)
func _on_card_input(event: InputEvent, id: String) -> void:
	if not event is InputEventMouseButton or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mb := event as InputEventMouseButton
	if mb.pressed:
		_press_id = id
		_press_at = mb.position
		return
	if _press_id != id:
		return
	_press_id = ""
	var d := mb.position - _press_at
	if narrow and absf(d.x) > SWIPE and absf(d.x) > absf(d.y):
		_step(-1 if d.x > 0.0 else 1)
	elif d.length() < SWIPE * 0.5:
		if StringName(id) == _sel:
			choose(StringName(id))
		else:
			select(StringName(id))
	if is_inside_tree():
		accept_event()


func _on_back() -> void:
	App.back()


# ---- วางหน้า ----

func _layout() -> void:
	if not is_inside_tree():
		return
	CandleStyle.safe_margins(_margin)
	var vs := get_viewport_rect().size
	narrow = vs.x < WIDE or vs.x < vs.y
	_tabs.visible = narrow
	_prev.visible = narrow
	_next.visible = narrow
	var h := 64.0 if touch_mode else 52.0
	for id in CampaignGalaxy.DIFFICULTIES:
		var c: Dictionary = _cards[id]
		(c["button"] as Button).custom_minimum_size.y = h
		for k in ["name", "mult"]:
			(c[k] as Label).add_theme_font_size_override(&"font_size", NAME_SIZE + (4 if narrow else 0))
	for b: Button in _tabs.get_children():
		b.custom_minimum_size.y = h
	_back.custom_minimum_size.y = h
	_paint_selection()
	_even_cards.call_deferred()
