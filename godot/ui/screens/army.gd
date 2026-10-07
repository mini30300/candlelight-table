extends Control
## หน้าจัดกองทัพ (R1-V4): เลือกหนึ่งใน 15 กองทัพ · การ์ดข้อมูลหน่วยของกองนั้นตามลำดับ TYPES (หน่วยลับไม่ขึ้นเลย)
## การ์ดมี ตัวต่อหมู่ แต้ม เดิน ทน เกราะ เกราะพิเศษ แผล ขวัญ คุมจุด ตารางอาวุธยิง/ประชิด ค่าพิเศษ และความสามารถ
## ปุ่ม −/+ ต่อหน่วย · แต้มรวมเทียบงบ (เริ่ม 1000 ขั้นจาก BUDGETS) · ปุ่มสุ่มกอง (seed เดียวกันได้กองเดียวกัน)
## ดูหน้าตาหน่วยที่เลือกบนแท่นหมุน (KitTurntable) · ไทยก่อน สลับอังกฤษได้ · ปุ่มสูง ≥ 44 px
## ไม่มี _process ในหน้านี้: ข้อความเปลี่ยนเมื่อกดเท่านั้น; ระหว่างเปิดหน้านี้ซ่อนโต๊ะ 3 มิติไว้ (จอทึบ ไม่ต้องวาดโต๊ะ)

const BUTTON_TO_ENGLISH := "ENGLISH"   # ป้ายปุ่มตอนเป็นไทย — เป็นอังกฤษตั้งใจ เหมือนหน้าเก่า
const BUTTON_TO_THAI := "ไทย"
const CHAPTERS_PATH := "res://data/chapters.json"
const BOLD := preload("res://assets/fonts/Sarabun-Bold.ttf")
const TAP_SLOP := 12.0          # ขยับนิ้วไม่เกินนี้ (px) ถือว่าแตะการ์ด ไม่ใช่เลื่อน
const TARGET := 48.0            # ปุ่มแตะ ≥ 44 px

const CREAM := Color(1.0, 0.96, 0.88)
const INK := Color(0.95, 0.95, 0.93)
const MUTED := Color(0.8, 0.77, 0.7)
const DIM := Color(0.62, 0.6, 0.56)
const GOLD := Color(0.93, 0.77, 0.43)
const RED := Color(0.96, 0.45, 0.38)
const GREEN := Color(0.58, 0.86, 0.56)
const CARD_BG := Color(0.11, 0.1, 0.13)
const CARD_EDGE := Color(0.22, 0.2, 0.25)
const STAT_BG := Color(0.18, 0.17, 0.215)
const ARMY_BG := Color(0.13, 0.12, 0.155)

@onready var title: Label = %Title
@onready var back_button: Button = %BackButton
@onready var budget_minus: Button = %BudgetMinus
@onready var budget_label: Label = %BudgetLabel
@onready var budget_plus: Button = %BudgetPlus
@onready var points_label: Label = %PointsLabel
@onready var points_bar: ProgressBar = %PointsBar
@onready var random_button: Button = %RandomButton
@onready var lang_button: Button = %LangButton
@onready var army_list: VBoxContainer = %ArmyList
@onready var army_name: Label = %ArmyName
@onready var army_desc: Label = %ArmyDesc
@onready var roster_scroll: ScrollContainer = %RosterScroll
@onready var roster_box: VBoxContainer = %Roster
@onready var status_label: Label = %StatusLabel
@onready var preview_title: Label = %PreviewTitle
@onready var preview: KitTurntable = %Preview
@onready var unit_name: Label = %UnitName
@onready var unit_sub: Label = %UnitSub
@onready var unit_desc: Label = %UnitDesc
@onready var drag_hint: Label = %DragHint

var roster: ArmyRoster
var selected := ""               # หน่วยที่ดูหน้าตาอยู่
var random_seed := 1             # seed ของการกดสุ่มครั้งถัดไป (เพิ่มทีละหนึ่ง)

var _manifest: Dictionary = {}
var _chapters: Dictionary = {}
var _army_group := ButtonGroup.new()
var _army_buttons: Dictionary = {}    # รหัสกองทัพ -> Button
var _cards: Dictionary = {}           # k -> {card, count, minus, plus}
var _table: Node3D
var _table_was_visible := true
var _press_pos := Vector2.ZERO
var _style_card: StyleBoxFlat
var _style_card_on: StyleBoxFlat
var _style_stat: StyleBoxFlat


func _ready() -> void:
	_style_card = _box_style(CARD_BG, CARD_EDGE, 1, 10)
	_style_card_on = _box_style(CARD_BG.lightened(0.025), GOLD, 2, 10)
	_style_stat = _box_style(STAT_BG, STAT_BG, 0, 6, 6.0, 3.0)
	_manifest = KitLibrary.load_manifest()
	var ch: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHAPTERS_PATH)) if FileAccess.file_exists(CHAPTERS_PATH) else null
	_chapters = ch if ch is Dictionary else {}
	roster = ArmyRoster.new()
	random_seed = maxi(1, GameData.const_int("SEED", 1))
	preview.manifest = _manifest
	preview.set_level(App.gfx)
	back_button.pressed.connect(_on_back)
	budget_minus.pressed.connect(step_budget.bind(-1))
	budget_plus.pressed.connect(step_budget.bind(1))
	random_button.pressed.connect(random_army)
	lang_button.pressed.connect(_on_lang)
	for fac in GameData.factions():
		var b := Button.new()
		b.name = "Army_" + fac
		b.toggle_mode = true
		b.button_group = _army_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0.0, TARGET + 2.0)
		b.add_theme_font_size_override("font_size", 17)
		b.focus_mode = Control.FOCUS_NONE
		_style_army_button(b)
		b.pressed.connect(select_army.bind(fac))
		army_list.add_child(b)
		_army_buttons[fac] = b
	_table = get_tree().get_first_node_in_group("table_view") as Node3D
	if _table != null:
		_table_was_visible = _table.visible
		_table.visible = false
	select_army(roster.fac)


func _exit_tree() -> void:
	if _table != null and is_instance_valid(_table):
		_table.visible = _table_was_visible


## วาดข้อความทุกชิ้นใหม่ตามภาษาปัจจุบัน (การ์ดสร้างใหม่ทั้งชุด จำนวนหมู่อยู่ใน roster)
func refresh() -> void:
	title.text = I18n.t("จัดกองทัพ")
	back_button.text = I18n.t("‹ กลับ")
	random_button.text = I18n.t("สุ่มกองทัพ")
	lang_button.text = BUTTON_TO_THAI if I18n.english else BUTTON_TO_ENGLISH
	preview_title.text = I18n.t("ดูหน้าตา")
	drag_hint.text = I18n.t("ลากเพื่อหมุน")
	for fac in _army_buttons:
		var b: Button = _army_buttons[fac]
		b.text = I18n.t(str(GameData.faction(fac).get("nm", fac)))
		b.set_pressed_no_signal(fac == roster.fac)
	var f := GameData.faction(roster.fac)
	army_name.text = I18n.t(str(f.get("nm", "")))
	army_desc.text = I18n.t(str(f.get("d", "")))
	var keep := roster_scroll.scroll_vertical
	_build_roster()
	roster_scroll.set_deferred("scroll_vertical", keep)
	_update_points()
	_update_preview_text()


## สลับภาษา (save = false ในเทส จะได้ไม่เขียน settings.cfg ของเครื่อง)
func set_language(english: bool, save: bool = true) -> void:
	App.set_lang("en" if english else "th")
	if save:
		App.save_settings()
	refresh()


## เลือกกองทัพ: หน่วยของกองอื่นออกจากรายชื่อ แล้วสร้างการ์ดใหม่
func select_army(fac: String) -> void:
	if not GameData.factions().has(fac):
		return
	roster.set_fac(fac)
	var units := ArmyRoster.units_of(fac)
	if not units.has(selected):
		selected = units[0] if not units.is_empty() else ""
	refresh()
	_show_selected()


## เลือกหน่วยที่จะดูหน้าตา (เฉพาะหน่วยที่อยู่ในรายชื่อ)
func select_unit(k: String) -> void:
	if not _cards.has(k):
		return
	var old: Dictionary = _cards.get(selected, {})
	if not old.is_empty():
		(old["card"] as PanelContainer).add_theme_stylebox_override("panel", _style_card)
	selected = k
	var c: PanelContainer = _cards[k]["card"]
	c.add_theme_stylebox_override("panel", _style_card_on)
	# เลื่อนให้เห็นทั้งการ์ดหลังจัดวางเสร็จ (เฟรมถัดไป ข้อความที่ตัดบรรทัดถึงจะได้ความสูงจริง)
	if not get_tree().process_frame.is_connected(_scroll_to_selected):
		get_tree().process_frame.connect(_scroll_to_selected, CONNECT_ONE_SHOT)
	_update_preview_text()
	_show_selected()


## เพิ่ม/ลดหมู่ของหน่วย k; คืน true เมื่อเปลี่ยน
func add_unit(k: String, delta: int) -> bool:
	if not roster.add(k, delta):
		return false
	_update_card(k)
	_update_points()
	return true


## สุ่มกองของกองทัพที่เลือก จาก seed (ไม่ส่ง = seed ถัดไปของหน้านี้); คืนรายชื่อแบบส่งข้ามเครื่อง
func random_army(seed_v: int = -1) -> PackedInt32Array:
	if seed_v < 0:
		seed_v = random_seed
		random_seed += 1
	roster.random_fill(seed_v)
	for k in _cards:
		_update_card(k)
	_update_points()
	return roster.list()


func step_budget(dir: int) -> void:
	if roster.step_budget(dir):
		_update_points()


## ระดับกราฟิกเปลี่ยน: แท่นหมุนหยุดบน min
func apply_level(l: String) -> void:
	preview.set_level(l)


## หน่วยบนจอตามลำดับ (ไว้ตรวจในเทส)
func listed_units() -> PackedStringArray:
	var out := PackedStringArray()
	for c in roster_box.get_children():
		if c.has_meta("k"):
			out.append(str(c.get_meta("k")))
	return out


func card(k: String) -> PanelContainer:
	return _cards[k]["card"] if _cards.has(k) else null


func points() -> int:
	return roster.points()


# ---- การ์ด ----

func _build_roster() -> void:
	for c in roster_box.get_children():
		roster_box.remove_child(c)
		c.queue_free()
	_cards.clear()
	var units := ArmyRoster.units_of(roster.fac)
	var any_ch := false
	for k in units:
		if str(GameData.ty(k).get("ch", "")) != "":
			any_ch = true
	var chap := "-"
	for k in units:
		var t := GameData.ty(k)
		var ch := str(t.get("ch", ""))
		if any_ch and ch != chap:
			chap = ch
			roster_box.add_child(_chapter_row(ch))
		var c := _make_card(k, t)
		roster_box.add_child(c)
	if units.is_empty():
		roster_box.add_child(_label(I18n.t("ไม่มีหน่วยในกองทัพนี้"), 16, MUTED))


func _chapter_row(ch: String) -> Control:
	var head := DatasheetText.chapter_heading(ch, _chapters)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(28.0, 6.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cols: Variant = _chapters.get(ch)
	bar.color = Color.html(str(cols[0])) if cols is Array and not (cols as Array).is_empty() else Color(0.35, 0.36, 0.4)
	row.add_child(bar)
	row.add_child(_label(head[0], 17, CREAM, true))
	if head[1] != "":
		row.add_child(_label(head[1], 14, MUTED))
	return row


func _make_card(k: String, t: Dictionary) -> PanelContainer:
	var card_node := PanelContainer.new()
	card_node.name = "Card_" + k
	card_node.set_meta("k", k)
	card_node.mouse_filter = Control.MOUSE_FILTER_PASS
	card_node.add_theme_stylebox_override("panel", _style_card_on if k == selected else _style_card)
	card_node.gui_input.connect(_on_card_input.bind(k))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	card_node.add_child(col)
	# หัวการ์ด: แถบสีของชุด ชื่อ ตัวต่อหมู่/แต้ม และปุ่ม −/+
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(head)
	var sw := VBoxContainer.new()
	sw.add_theme_constant_override("separation", 0)
	sw.custom_minimum_size = Vector2(8.0, 0.0)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols := KitLibrary.kit_colours(_manifest, k)
	for i in 2:
		var cr := ColorRect.new()
		cr.color = cols[i] if i < cols.size() else Color(0.4, 0.4, 0.45)
		cr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(cr)
	head.add_child(sw)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	names.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(names)
	var nm := _label(DatasheetText.name_of(t), 19, CREAM, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.name = "Name"
	names.add_child(nm)
	var sub := _label(DatasheetText.sub_of(t), 14, MUTED)
	sub.name = "Sub"
	names.add_child(sub)
	var minus := _square_button("−", "Minus")
	minus.pressed.connect(add_unit.bind(k, -1))
	head.add_child(minus)
	var count := _label("0", 20, INK, true)
	count.name = "Count"
	count.custom_minimum_size = Vector2(40.0, TARGET)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(count)
	var plus := _square_button("+", "Plus")
	plus.pressed.connect(add_unit.bind(k, 1))
	head.add_child(plus)
	# ค่าประจำตัว
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 6)
	stats.add_theme_constant_override("v_separation", 6)
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	for pair in DatasheetText.stats(t):
		stats.add_child(_stat_box(pair[0], pair[1]))
	col.add_child(stats)
	# อาวุธ
	var grid := GridContainer.new()
	grid.columns = DatasheetText.WEAPON_HEAD.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	for h in DatasheetText.weapon_head():
		var hl := _label(h.to_upper(), 12, DIM, true)
		if grid.get_child_count() == 0:
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(hl)
	var notes := PackedStringArray()
	for melee in [false, true]:
		var w: Variant = t.get("mel" if melee else "gun")
		if not (w is Dictionary):
			continue
		var row := DatasheetText.weapon_row(w, melee)
		for i in row.size():
			var cell := _label(row[i], 15, INK if i > 0 else CREAM, i == 0)
			if i == 0:
				cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				cell.custom_minimum_size = Vector2(120.0, 0.0)
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else:
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.custom_minimum_size = Vector2(44.0, 0.0)
			grid.add_child(cell)
		var kw := DatasheetText.weapon_keywords(w)
		if not kw.is_empty():
			notes.append(row[0] + ": " + " · ".join(kw))
	col.add_child(grid)
	if not (t.get("gun") is Dictionary):
		col.add_child(_label(I18n.t("ต้องบุกเข้าประชิด"), 14, RED.lerp(GOLD, 0.5)))
	for n in notes:
		var nl := _label(n, 13, MUTED)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(nl)
	var ab := DatasheetText.abilities(t)
	if not ab.is_empty():
		var al := _label(" · ".join(ab), 14, GOLD)
		al.name = "Abilities"
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(al)
	_cards[k] = {"card": card_node, "count": count, "minus": minus, "plus": plus}
	_update_card(k)
	return card_node


func _stat_box(caption: String, value: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _style_stat)
	box.custom_minimum_size = Vector2(62.0, 0.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	var c := _label(caption.to_upper(), 12, DIM, true)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var val := _label(value, 19, INK, true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	return box


func _update_card(k: String) -> void:
	if not _cards.has(k):
		return
	var d: Dictionary = _cards[k]
	var n := roster.count_of(k)
	(d["count"] as Label).text = str(n)
	(d["minus"] as Button).disabled = n <= 0
	(d["plus"] as Button).disabled = n >= ArmyRoster.slot_max()


func _update_points() -> void:
	var used := roster.points()
	var budget := roster.budget
	var list := ArmyRoster.budgets()
	budget_label.text = DatasheetText.tf("งบ {pts} แต้ม", {"pts": DatasheetText.fmt_pts(budget)})
	budget_minus.disabled = list.find(budget) <= 0
	budget_plus.disabled = list.find(budget) >= list.size() - 1
	points_label.text = DatasheetText.tf("ใช้ไป {used} / {budget} แต้ม", {"used": DatasheetText.fmt_pts(used), "budget": DatasheetText.fmt_pts(budget)})
	points_bar.max_value = maxi(1, budget)
	points_bar.value = mini(used, budget)
	var over := roster.is_over()
	points_label.add_theme_color_override("font_color", RED if over else INK)
	points_bar.modulate = Color(1.0, 0.55, 0.5) if over else Color.WHITE
	if over:
		status_label.text = I18n.t("เกินงบ ลดหน่วยลงก่อน")
		status_label.add_theme_color_override("font_color", RED)
	elif roster.is_empty():
		status_label.text = I18n.t("ต้องมีหน่วยอย่างน้อยหนึ่งตัว")
		status_label.add_theme_color_override("font_color", MUTED)
	else:
		status_label.text = DatasheetText.tf("พร้อม · {pts} แต้ม · {models} ตัว", {"pts": DatasheetText.fmt_pts(used), "models": roster.models()})
		status_label.add_theme_color_override("font_color", GREEN)


func _update_preview_text() -> void:
	var t := GameData.ty(selected) if selected != "" else {}
	if t.is_empty():
		unit_name.text = ""
		unit_sub.text = ""
		unit_desc.text = ""
		return
	unit_name.text = DatasheetText.name_of(t)
	unit_sub.text = DatasheetText.sub_of(t)
	unit_desc.text = DatasheetText.desc_of(t) if KitLibrary.has_kit(selected) else DatasheetText.desc_of(t) + "\n" + I18n.t("ไม่มีชุดโมเดลของหน่วยนี้")


func _scroll_to_selected() -> void:
	var c := card(selected)
	if c == null or not is_instance_valid(c):
		return
	var top := int(c.position.y)
	var bottom := int(c.position.y + c.size.y)
	var view := int(roster_scroll.size.y)
	var at := roster_scroll.scroll_vertical
	if bottom > at + view:
		at = bottom - view
	if top < at:
		at = top
	roster_scroll.scroll_vertical = at


func _show_selected() -> void:
	if selected != "" and preview != null:
		preview.show_kit(selected)


func _on_card_input(event: InputEvent, k: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_press_pos = mb.position
		elif mb.position.distance_to(_press_pos) <= TAP_SLOP:
			select_unit(k)


func _on_back() -> void:
	App.pop()


func _on_lang() -> void:
	set_language(not I18n.english)


# ---- ชิ้นส่วนเล็ก ----

func _label(text: String, size_px: int, colour: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", colour)
	if bold:
		l.add_theme_font_override("font", BOLD)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## ปุ่มกองทัพ: พื้นเข้ม กองที่เลือกมีขอบทองด้านซ้าย
func _style_army_button(b: Button) -> void:
	var normal := _box_style(ARMY_BG, ARMY_BG, 0, 8, 12.0, 6.0)
	var hover := _box_style(ARMY_BG.lightened(0.06), ARMY_BG.lightened(0.06), 0, 8, 12.0, 6.0)
	var on := _box_style(ARMY_BG.lightened(0.1), GOLD, 0, 8, 12.0, 6.0)
	on.border_width_left = 4
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", CREAM)
	b.add_theme_color_override("font_hover_pressed_color", CREAM)


func _square_button(text: String, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(TARGET, TARGET)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func _box_style(bg: Color, edge: Color, border: int, radius: int, pad_x: float = 12.0, pad_y: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y + 2.0
	return s
