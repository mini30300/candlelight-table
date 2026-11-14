class_name GalaxyScreen
extends Control
## หน้ากาแล็กซี (CAMPAIGN_SPEC §1.5): แผนที่ดาว 44 ดวงของสัปดาห์ (GalaxyMap) + การ์ดดาว (PlanetCard) + บรีฟ (MissionBrief)
## แถบบน: ‹ ยาน (= ออกจากแคมเปญ) ชื่อ + สัปดาห์ เวลาจนสุ่มใหม่ (Timer 30 วิ) เหรียญ ปุ่มความยาก (= เปลี่ยนความยาก)
## จอกว้าง: การ์ด/บรีฟอยู่ขวา แผนที่อยู่ซ้าย · จอแคบ/แนวตั้ง: การ์ด/บรีฟเป็นแผ่นล่าง แผนที่อยู่บน
## Esc: บรีฟ → การ์ด → แผนที่ → ออก · กลับจากภารกิจ = การ์ดของดาว · ออกรบ = จอมืด (hi/mid ค่อย ๆ, lo/min ทันที) แล้ว CampaignFlow.launch
## จำสัปดาห์ตอนเปิด กลับมาโชว์แล้วสัปดาห์เปลี่ยน = โหลดใหม่ + แจ้ง · ไม่มีงานต่อเฟรม

const SCENE := "res://ui/screens/galaxy_screen.tscn"
const BACK_TEXT := "‹ ยาน"
const TITLE := "กาแล็กซี · สัปดาห์ {label}"
const COUNTDOWN := "เหตุการณ์ใหม่ในอีก {d} วัน {h} ชม."
const COINS := "เหรียญ {n}"
const DIFF := "ความยาก: {name} {mult}"
const HINT_KEYS := "คลิกดาวเพื่อดูภารกิจ · ลากเพื่อเลื่อน · ล้อเมาส์ซูม"
const HINT_TOUCH := "แตะดาวเพื่อดูภารกิจ · ลากเพื่อเลื่อน · สองนิ้วซูม"
const NEW_WEEK := "เหตุการณ์สัปดาห์ใหม่มาแล้ว"
const FADE_TIME := 0.25
const NOTE_SECONDS := 3.0
const SIDE_W := 470.0
const WIDE := 1000.0

var difficulty := "normal"
var week := 0
var level := "mid"
var touch_mode := false
var planet_id := ""
var event_idx := -1

var _map: GalaxyMap
var _top: PanelContainer
var _back: Button
## ชื่อหน้า + เหรียญ + เวลาจนสุ่มใหม่ ในข้อความเดียว (draw call น้อย)
var _title: RichTextLabel
var _title_text := ""
var _coins_text := ""
var _countdown_text := ""
var _chip: Button
var _hint: Label
var _card: PlanetCard
var _brief: MissionBrief
var _note: Label
var _note_timer: Timer
var _timer: Timer
var _fade: ColorRect
var _launching := false
var _note_key := ""
var _layout_queued := false


func _ready() -> void:
	level = App.gfx
	touch_mode = App.touch_active()
	_build()
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility)


## เรียกหลัง App.push / replace ทันที: ctx = {"difficulty": String, "week": int}
func open(ctx: Dictionary) -> void:
	difficulty = str(ctx.get("difficulty", "normal"))
	if not CampaignGalaxy.DIFFICULTIES.has(difficulty):
		difficulty = "normal"
	week = int(ctx.get("week", CampaignWeek.current()))
	_load_week()
	refresh()


## โหลดดาวของสัปดาห์ลงแผนที่ (สีผู้รุกราน ดาวเด่น ผ่านแล้วที่ความยากนี้)
func _load_week() -> void:
	var list: Array[Dictionary] = []
	for i in CampaignGalaxy.PLANETS.size():
		var p: Dictionary = CampaignGalaxy.PLANETS[i]
		var pw := CampaignGalaxy.planet_week(week, str(p["id"]))
		var cleared := false
		for e: Dictionary in pw["events"]:
			if CampaignSave.is_repeat({"week": week, "planet": p["id"], "primary": {"idx": e["idx"]}, "difficulty": difficulty}):
				cleared = true
		list.append({"id": str(p["id"]), "index": i, "biome": str(p["biome"]),
			"faction_col": Color(str(CampaignGalaxy.faction(str(pw["faction"])).get("col", "888888"))),
			"featured": bool(pw["featured"]), "cleared": cleared, "events": (pw["events"] as Array).size()})
	_map.set_level(level)
	_map.set_planets(list)


## อ่านภาษา/ตัวเลขใหม่แล้ววาดข้อความทั้งหมด
func refresh() -> void:
	_back.text = I18n.t(BACK_TEXT)
	_title_text = I18n.t(TITLE).format({"label": CampaignWeek.iso_label(week)})
	_coins_text = I18n.t(COINS).format({"n": CampaignSave.coins()})
	var d := CampaignRules.difficulty(difficulty)
	_chip.text = I18n.t(DIFF).format({"name": I18n.t(str(d["th"])), "mult": CampaignRules.mult_text(difficulty)})
	_hint.text = I18n.t(HINT_TOUCH if touch_mode else HINT_KEYS)
	_tick()
	if _card.visible:
		_card.refresh()
	if _brief.visible:
		_brief.refresh()
	if _note_key != "":
		_note.text = I18n.t(_note_key)
	_layout()


## เวลาจนสุ่มใหม่ (Timer ทุก 30 วิ ไม่ใช่ทุกเฟรม) · ข้ามสัปดาห์ขณะเปิดหน้าอยู่ = โหลดสัปดาห์ใหม่ + แจ้ง
func _tick() -> void:
	if CampaignWeek.current() != week and week != 0 and not _launching and _map != null:
		_new_week()
		return
	var left := CampaignWeek.seconds_to_reroll(CampaignWeek.now_unix())
	if CampaignWeek.current() != week:
		left = 0
	_countdown_text = I18n.t(COUNTDOWN).format(CampaignWeek.split(left))
	_title.text = "[b][font_size=30]%s[/font_size][/b]    %s\n%s" % [PlanetCard.colour(_title_text, CandleStyle.GOLD),
		PlanetCard.colour(_coins_text, GalaxyMap.GOLD), PlanetCard.colour(_countdown_text, CandleStyle.MUTED)]
	if _card.visible:
		_card.set_left(left)


# ---- การกด (เทสเรียกตรงได้) ----

## เปิดการ์ดของดาว id
func select_planet(id: String) -> void:
	if CampaignGalaxy.planet(id).is_empty() or _launching:
		return
	planet_id = id
	event_idx = -1
	_map.select(id)
	_brief.hide()
	_card.show_planet(week, id, difficulty, CampaignWeek.seconds_to_reroll(CampaignWeek.now_unix()))
	_card.show()
	_relayout()
	_sfx(&"ui")


## เปิดบรีฟของเหตุการณ์ event_idx บนดาวที่เลือก
func open_brief(idx: int) -> void:
	var spec := CampaignGalaxy.mission_spec(week, planet_id, idx, difficulty)
	if spec.is_empty() or _launching:
		return
	event_idx = idx
	_brief.show_spec(spec)
	_card.hide()
	_brief.show()
	_relayout()
	_sfx(&"ui")


func close_brief() -> void:
	if not _brief.visible:
		return
	_brief.hide()
	event_idx = -1
	if planet_id != "":
		_card.show()
		_card.refresh()
	_relayout()


func close_card() -> void:
	_card.hide()
	_brief.hide()
	planet_id = ""
	event_idx = -1
	_map.select("")
	_relayout()


## spec ของภารกิจในบรีฟ ({} = ยังไม่ได้เลือก)
func current_spec() -> Dictionary:
	if planet_id == "" or event_idx < 0:
		return {}
	return CampaignGalaxy.mission_spec(week, planet_id, event_idx, difficulty)


## ออกรบทันที (เทส / หลังจอมืด) = CampaignFlow.launch(spec ปัจจุบัน)
func launch() -> Node:
	var spec := current_spec()
	if spec.is_empty():
		return null
	return CampaignFlow.launch(spec)


## ปุ่มออกรบ: จอมืดแล้วค่อยเปิดภารกิจ (กดซ้ำระหว่างนั้นไม่มีผล)
func launch_faded() -> void:
	if _launching or current_spec().is_empty():
		return
	_launching = true
	_sfx(&"heal")
	_fade.show()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if level == "hi" or level == "mid":
		_fade.color.a = 0.0
		var tw := create_tween()
		tw.tween_property(_fade, ^"color:a", 1.0, FADE_TIME)
		await tw.finished
	else:
		_fade.color.a = 1.0
		await get_tree().process_frame
	var ms := launch()
	_launching = false
	if ms == null:
		_clear_fade()


func change_difficulty() -> void:
	if not _launching:
		CampaignFlow.change_difficulty()


func leave() -> void:
	if not _launching:
		CampaignFlow.leave()


## Esc / ปุ่มย้อนกลับ: บรีฟ → การ์ด → แผนที่ → ออกจากแคมเปญ (คืน true เสมอ)
func handle_back() -> bool:
	if _launching:
		return true
	if _brief.visible:
		close_brief()
	elif _card.visible:
		close_card()
	else:
		leave()
	return true


func show_note(key: String) -> void:
	_note_key = key
	_note.text = I18n.t(key)
	_note.show()
	_note_timer.start(NOTE_SECONDS)


# ---- สำหรับเทส ----

func map() -> GalaxyMap:
	return _map


func card() -> PlanetCard:
	return _card


func brief() -> MissionBrief:
	return _brief


func card_open() -> bool:
	return _card.visible


func brief_open() -> bool:
	return _brief.visible


func note_text() -> String:
	return _note.text if _note.visible else ""


func countdown_text() -> String:
	return _countdown_text


func coins_text() -> String:
	return _coins_text


func narrow() -> bool:
	return size.x < WIDE or size.x <= size.y


func timer() -> Timer:
	return _timer


func chip() -> Button:
	return _chip


# ---- ภายใน ----

func _on_visibility() -> void:
	if not is_visible_in_tree():
		_timer.stop()
		return
	# กลับมาจากภารกิจ/สรุปผล: จอสว่าง ตัวเลขใหม่ สัปดาห์เปลี่ยนไหม
	level = App.gfx
	touch_mode = App.touch_active()
	_style_buttons()
	_clear_fade()
	if CampaignWeek.current() != week and week != 0:
		_new_week()
	elif _brief.visible:
		# กลับจากภารกิจ: โชว์การ์ดของดาว (เหตุการณ์ที่ผ่านแล้วมีเครื่องหมาย) แทนบรีฟเดิม
		close_brief()
	_load_week()
	refresh()
	_timer.start()


## สัปดาห์ใหม่: ปิดการ์ด/บรีฟของสัปดาห์เก่า โหลดดาวใหม่ แจ้งผู้เล่น (ทุกคนเห็นกาแล็กซีเดียวกัน)
func _new_week() -> void:
	week = CampaignWeek.current()
	close_card()
	show_note(NEW_WEEK)
	_load_week()
	refresh()


func _clear_fade() -> void:
	_launching = false
	_fade.hide()
	_fade.color.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.012, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_map = GalaxyMap.new()
	_map.name = "Map"
	_map.planet_tapped.connect(select_planet)
	_map.empty_tapped.connect(func() -> void:
		if _brief.visible:
			return
		close_card())
	add_child(_map)
	_top = PanelContainer.new()
	_top.name = "TopBar"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.04, 0.82)
	sb.border_color = CandleStyle.EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	_top.add_theme_stylebox_override(&"panel", sb)
	add_child(_top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	_top.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	col.add_child(row)
	_back = Button.new()
	_back.name = "BackButton"
	_back.custom_minimum_size = Vector2(120, 52)
	_back.focus_mode = Control.FOCUS_NONE
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(leave)
	row.add_child(_back)
	_title = PlanetCard.rich(19)
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.add_theme_font_size_override(&"bold_font_size", 30)
	row.add_child(_title)
	_chip = Button.new()
	_chip.name = "DifficultyChip"
	_chip.custom_minimum_size.y = 52
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip.add_theme_font_size_override(&"font_size", 20)
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.pressed.connect(change_difficulty)
	row.add_child(_chip)
	_style_buttons()
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CandleStyle.text(_hint, 19, true)
	add_child(_hint)
	_card = PlanetCard.new()
	_card.name = "PlanetCard"
	_card.hide()
	_card.event_chosen.connect(open_brief)
	_card.closed.connect(close_card)
	add_child(_card)
	_brief = MissionBrief.new()
	_brief.name = "Brief"
	_brief.hide()
	_brief.launch_pressed.connect(launch_faded)
	_brief.back_pressed.connect(close_brief)
	add_child(_brief)
	# ข้อความในแผงจัดบรรทัดใหม่ (ขนาดขั้นต่ำเปลี่ยน): จัดตำแหน่งใหม่ ไม่ให้แผงค้างขนาดใหญ่เกินจอ
	_card.minimum_size_changed.connect(_queue_layout)
	_top.minimum_size_changed.connect(_queue_layout)
	_brief.minimum_size_changed.connect(_queue_layout)
	_note = Label.new()
	_note.name = "Note"
	_note.hide()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CandleStyle.title(_note, 26)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(0.1, 0.07, 0.04, 0.92)
	nsb.border_color = CandleStyle.GOLD
	nsb.set_border_width_all(2)
	nsb.set_corner_radius_all(10)
	nsb.set_content_margin_all(12.0)
	_note.add_theme_stylebox_override(&"normal", nsb)
	add_child(_note)
	_note_timer = Timer.new()
	_note_timer.one_shot = true
	_note_timer.timeout.connect(func() -> void:
		_note.hide()
		_note_key = "")
	add_child(_note_timer)
	_timer = Timer.new()
	_timer.name = "CountdownTimer"
	_timer.wait_time = 30.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.hide()
	add_child(_fade)
	_timer.start()


func _layout() -> void:
	if _map == null:
		return
	var inset := CandleStyle.safe_insets(self)
	var m := CandleStyle.GUTTER
	var l := m + inset.position.x
	var t := m + inset.position.y
	var r := m + inset.size.x
	var b := m + inset.size.y
	var w := size.x
	var h := size.y
	_top.position = Vector2(l, t)
	_top.size = Vector2(w - l - r, 0.0)
	_top.reset_size()
	_top.size.x = w - l - r
	var top_h := _top.get_combined_minimum_size().y
	var under := t + top_h + 10.0
	var panel_on := _card.visible or _brief.visible
	var map_rect := Rect2(0.0, 0.0, w, h)
	var side := Rect2()
	if narrow():
		var sh := clampf(h * 0.42, 360.0, h - under - 140.0)
		side = Rect2(l, h - b - sh, w - l - r, sh)
		if panel_on:
			map_rect = Rect2(0.0, under, w, side.position.y - under - 6.0)
		else:
			map_rect = Rect2(0.0, under, w, h - under)
	else:
		var sw := minf(SIDE_W, w * 0.42)
		side = Rect2(w - r - sw, under, sw, h - under - b)
		if panel_on:
			map_rect = Rect2(0.0, under, side.position.x - 8.0, h - under)
		else:
			map_rect = Rect2(0.0, under, w, h - under)
	_map.position = map_rect.position
	_map.size = map_rect.size
	for p: Control in [_card, _brief]:
		p.position = side.position
		p.size = side.size
	_hint.visible = not panel_on
	_hint.position = Vector2(l, h - b - 30.0)
	_hint.size = Vector2(w - l - r, 30.0)
	_note.reset_size()
	_note.position = Vector2((w - _note.size.x) * 0.5, under + 12.0)


## จัดตำแหน่งทันที และอีกครั้งหลังข้อความในแผงจัดบรรทัดเสร็จ (ขนาดขั้นต่ำของแผงเปลี่ยนหลังวาดเฟรมแรก)
## ปุ่มแถบบน: กรอบเทียนทุกระดับ ยกเว้น min เป็นตัวอักษรทองอย่างเดียว (draw call น้อยลง)
func _style_buttons() -> void:
	for b: Button in [_back, _chip]:
		if level == "min":
			for k in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
				b.remove_theme_stylebox_override(k)
			b.flat = true
			b.add_theme_font_override(&"font", CandleStyle.BOLD)
			for k in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
				b.add_theme_color_override(k, CandleStyle.GOLD)
		else:
			b.flat = false
			CandleStyle.button(b)
	_chip.add_theme_font_size_override(&"font_size", 20)
	_back.add_theme_font_size_override(&"font_size", 22)


func _relayout() -> void:
	_layout()
	_queue_layout()


func _queue_layout() -> void:
	if not _layout_queued:
		_layout_queued = true
		_deferred_layout.call_deferred()


func _deferred_layout() -> void:
	_layout_queued = false
	_layout()


func _sfx(kind: StringName) -> void:
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.call("play_ui", kind)
