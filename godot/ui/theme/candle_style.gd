class_name CandleStyle
extends RefCounted
## สีและสไตล์ธีมห้องแสงเทียน ใช้ร่วมกันทุกหน้า (หน้าแรก ตั้งค่า ล็อบบี้ ตั้งเกม)
## ธีมรวม default_theme.tres คงเดิม (เทสหน้ากองทัพอิงขนาดของมัน) ปุ่มไหนอยากได้ธีมเทียนก็เรียก button()

const BG := Color("140e0a")
const PANEL := Color(0.137, 0.094, 0.067, 0.92)   # #231811
const EDGE := Color("6b4a2a")
const GOLD := Color("e8b860")
const TEXT := Color("f3e6d0")
const MUTED := Color("b8a58a")
const DANGER := Color("d8746a")

const BOLD := preload("res://assets/fonts/Sarabun-Bold.ttf")
const GUTTER := 16.0
const MIN_TARGET := 44.0


static func _box(bg: Color, edge: Color, width: int = 2, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.anti_aliasing = true
	return sb


## ปุ่มธีมเทียน: กรอบทอง มุมโค้ง 10 สูงอย่างน้อย 56 ตัวหนา 22; primary = ปุ่มหลักสีอำพัน
static func button(b: Button, primary := false) -> void:
	var base := Color("7a4a1c") if primary else Color(0.17, 0.114, 0.078, 0.95)
	var hover := Color("8f5a24") if primary else Color(0.23, 0.157, 0.102, 0.97)
	var pressed := Color("5e3814") if primary else Color(0.29, 0.19, 0.10, 0.97)
	b.add_theme_stylebox_override(&"normal", _box(base, GOLD if primary else EDGE))
	b.add_theme_stylebox_override(&"hover", _box(hover, GOLD))
	b.add_theme_stylebox_override(&"pressed", _box(pressed, GOLD, 3))
	b.add_theme_stylebox_override(&"hover_pressed", _box(pressed, GOLD, 3))
	b.add_theme_stylebox_override(&"disabled", _box(Color(0.118, 0.086, 0.067, 0.7), Color("3d2c1e")))
	var focus := _box(Color(0, 0, 0, 0), GOLD, 2)
	focus.draw_center = false
	b.add_theme_stylebox_override(&"focus", focus)
	b.add_theme_font_override(&"font", BOLD)
	b.add_theme_font_size_override(&"font_size", 22)
	b.add_theme_color_override(&"font_color", TEXT)
	b.add_theme_color_override(&"font_hover_color", GOLD if not primary else TEXT)
	b.add_theme_color_override(&"font_focus_color", TEXT)
	b.add_theme_color_override(&"font_pressed_color", GOLD if not primary else TEXT)
	b.add_theme_color_override(&"font_hover_pressed_color", GOLD if not primary else TEXT)
	b.add_theme_color_override(&"font_disabled_color", Color(MUTED, 0.55))
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 56.0)


## รายการที่เด้งขึ้นของ OptionButton ธีมเทียน: ตัวหนา 22 แถวสูงอย่างน้อย POPUP_ROW (นิ้วกดได้บนมือถือ) ยาวเกินจอก็เลื่อนได้
const POPUP_ROW := 48.0


static func popup(pm: PopupMenu) -> void:
	var bg := _box(Color(0.137, 0.094, 0.067, 0.98), EDGE, 2, 10)
	bg.set_content_margin_all(8.0)
	pm.add_theme_stylebox_override(&"panel", bg)
	var hover := _box(Color("7a4a1c"), GOLD, 1, 6)
	hover.set_content_margin_all(0.0)
	pm.add_theme_stylebox_override(&"hover", hover)
	pm.add_theme_font_override(&"font", BOLD)
	pm.add_theme_font_size_override(&"font_size", 22)
	pm.add_theme_color_override(&"font_color", TEXT)
	pm.add_theme_color_override(&"font_hover_color", TEXT)
	pm.add_theme_constant_override(&"item_start_padding", 14)
	pm.add_theme_constant_override(&"item_end_padding", 14)
	var text_h := BOLD.get_height(22)
	pm.add_theme_constant_override(&"v_separation", maxi(4, ceili(POPUP_ROW - text_h)))


## กล่องพื้นหลังสีไม้เข้ม กรอบน้ำตาล (PanelContainer / Panel)
static func panel(c: Control) -> void:
	var sb := _box(PANEL, EDGE, 2, 12)
	sb.set_content_margin_all(16.0)
	c.add_theme_stylebox_override(&"panel", sb)


## หัวข้อตัวหนาสีทอง
static func title(l: Label, size := 40) -> void:
	l.add_theme_font_override(&"font", BOLD)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", GOLD)


## ข้อความธรรมดา (muted = สีจาง)
static func text(l: Label, size := 20, muted := false) -> void:
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", MUTED if muted else TEXT)


## ปุ่มเลือกได้ทีละอัน (radio) คืน ButtonGroup
static func toggle_group(buttons: Array) -> ButtonGroup:
	var g := ButtonGroup.new()
	for b in buttons:
		(b as BaseButton).toggle_mode = true
		(b as BaseButton).button_group = g
	return g


## ขอบ 16 px + พื้นที่ปลอดภัยของจอ (รอยบาก/ขอบโค้ง) แปลงเป็นหน่วย canvas; เรียกซ้ำเมื่อจอเปลี่ยนขนาด
static func safe_margins(m: MarginContainer) -> void:
	var inset := safe_insets(m)
	m.add_theme_constant_override(&"margin_left", int(GUTTER + inset.position.x))
	m.add_theme_constant_override(&"margin_top", int(GUTTER + inset.position.y))
	m.add_theme_constant_override(&"margin_right", int(GUTTER + inset.size.x))
	m.add_theme_constant_override(&"margin_bottom", int(GUTTER + inset.size.y))


## ระยะที่ต้องหลบ (ซ้าย บน ขวา ล่าง) ในหน่วย canvas; ไม่ใช่มือถือหรือไม่เต็มจอคืนศูนย์
static func safe_insets(c: CanvasItem) -> Rect2:
	if not c.is_inside_tree() or DisplayServer.get_name() == "headless":
		return Rect2()
	if not OS.has_feature("mobile") and DisplayServer.window_get_mode() < DisplayServer.WINDOW_MODE_FULLSCREEN:
		return Rect2()
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	var vis := c.get_viewport_rect().size
	if not safe.has_area() or win.size.x <= 0.0 or vis.x <= 0.0:
		return Rect2()
	var k := vis.x / win.size.x   # พิกเซลจอ → หน่วย canvas
	var cap := win.size * 0.25
	var l := clampf(safe.position.x - win.position.x, 0.0, cap.x) * k
	var t := clampf(safe.position.y - win.position.y, 0.0, cap.y) * k
	var r := clampf(win.end.x - safe.end.x, 0.0, cap.x) * k
	var b := clampf(win.end.y - safe.end.y, 0.0, cap.y) * k
	return Rect2(l, t, r, b)
