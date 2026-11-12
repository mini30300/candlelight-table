extends Control
## หน้าล็อบบี้ "ดาดฟ้ายานรบ" (ล็อบบี้ที่เดินได้, LOBBY_SPEC §2.5, SHIP_LOBBY_SPEC): ปุ่มและข้อความบนห้อง 3 มิติ (HallWorld)
## ข้อความไทยทั้งหมดของล็อบบี้อยู่ในไฟล์นี้ (ป้าย 3 มิติรวมป้ายชื่อสถานที่ "title" รับข้อความผ่าน world.set_sign_text)
## เดินถึงสถานีแล้วกด E หรือแตะ %UseButton: โต๊ะรบโฮโลแกรม → ตั้งเกม, คลังแสง → หน้าจัดกองทัพ, คอนโซล → ตั้งค่า,
## ประตูเทียบยาน / โต๊ะผจญภัย / หีบสมบัติ → แผง "เร็วๆ นี้", ประตูทางออก (หรือ ‹ หน้าแรก) → กลับหน้าแรก
## ถูกหน้าอื่นทับ: ซ่อนห้อง หยุดงาน คืนกล้อง; กลับมาโชว์: อ่าน App.gfx / lang / touch ใหม่ทุกครั้ง
## งานต่อเฟรม: ไม่มี (ข้อความเปลี่ยนตามสัญญาณ แผง "เร็วๆ นี้" ปิดด้วย Timer)

signal station_changed(id: String)

const BATTLE_SETUP := "res://ui/screens/battle_setup.tscn"
const ARMY := "res://ui/screens/army.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings.tscn"
## ชื่อสถานีบนปุ่มใช้งาน
const NAMES := {
	"battle": "โต๊ะรบ",
	"army": "คลังแสงกองทัพ",
	"settings": "ตั้งค่า",
	"online": "ประตูเทียบยาน",
	"adventure": "โต๊ะผจญภัย",
	"exit": "ทางออก",
	"vault": "หีบสมบัติ",
}
## ป้าย 3 มิติเหนือสถานี
const SIGNS := {
	"battle": "โต๊ะรบ",
	"army": "คลังแสงกองทัพ",
	"settings": "ตั้งค่า",
	"online": "ออนไลน์ · เร็วๆ นี้",
	"adventure": "โต๊ะผจญภัย · เร็วๆ นี้",
	"exit": "ทางออก",
	"vault": "หีบสมบัติ · เร็วๆ นี้",
}
## แผง "เร็วๆ นี้" ของสถานีที่ยังไม่เปิด (หีบสมบัติ = ระบบสุ่มของรางวัลรอบหน้า ตอนนี้ยังไม่มีของรางวัลจริง)
const SOON := {
	"online": "ออนไลน์กับเพื่อน — เร็วๆ นี้",
	"adventure": "โต๊ะผจญภัย — เร็วๆ นี้",
	"vault": "หีบสมบัติ — เร็วๆ นี้: สุ่มรับชิ้นส่วนปืนและของตกแต่ง",
}
## ชื่อสถานที่บนแผ่นป้ายใต้หน้าต่างกลาง
const PLACE := "ดาดฟ้ายานรบ"
const YOU := "คุณ"
const MENU_TEXT := "‹ หน้าแรก"
const SETTINGS_TEXT := "ตั้งค่า"
const PROMPT_KEYS := "{name} · กด E"
const PROMPT_TOUCH := "{name} · แตะเพื่อใช้"
const HINT_KEYS := "WASD หรือลูกศร เดิน · Shift วิ่ง · ลากเมาส์หมุนกล้อง"
const HINT_TOUCH := "ใช้ปุ่มซ้ายล่างเดิน · ลากจอหมุนกล้อง"
const SOON_SECONDS := 2.5
const USE_H := 64.0
const USE_H_TOUCH := 80.0

@onready var world: HallWorld = $HallWorld
@onready var margin: MarginContainer = $Safe
@onready var use_button: Button = %UseButton
@onready var stick: TouchStick = %Stick
@onready var menu_button: Button = %MenuButton
@onready var settings_button: Button = %SettingsButton
@onready var soon_panel: PanelContainer = %SoonPanel
@onready var soon_label: Label = %SoonLabel
@onready var hint: Label = %Hint
@onready var soon_timer: Timer = %SoonTimer

var touch_mode := false
var active := false

var _hint_done := false
var _soon := ""
var _hint_tween: Tween


func _ready() -> void:
	CandleStyle.button(menu_button)
	CandleStyle.button(settings_button)
	CandleStyle.button(use_button, true)
	CandleStyle.panel(soon_panel)
	CandleStyle.text(soon_label, 24)
	CandleStyle.text(hint, 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.78)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	hint.add_theme_stylebox_override(&"normal", sb)
	for b: Button in [menu_button, settings_button, use_button]:
		b.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(_go_menu)
	settings_button.pressed.connect(_open_settings)
	use_button.pressed.connect(use_station)
	stick.changed.connect(world.set_stick)
	soon_timer.timeout.connect(close_soon)
	world.station_changed.connect(_on_station)
	world.avatar.moved.connect(_on_avatar_moved)
	soon_panel.hide()
	use_button.hide()
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_on_resize)
	_activate(is_visible_in_tree())


## อ่านตั้งค่าใหม่ (ระดับกราฟิก ภาษา ปุ่มบนจอ) แล้ววาดข้อความทั้งหมด
func refresh() -> void:
	touch_mode = App.touch_active()
	world.apply_level(App.gfx)
	stick.visible = touch_mode
	use_button.custom_minimum_size.y = USE_H_TOUCH if touch_mode else USE_H
	use_button.add_theme_font_size_override(&"font_size", 26 if touch_mode else 22)
	menu_button.text = I18n.t(MENU_TEXT)
	settings_button.text = I18n.t(SETTINGS_TEXT)
	for id in SIGNS:
		world.set_sign_text(id, I18n.t(SIGNS[id]))
	world.set_sign_text("title", I18n.t(PLACE))
	world.set_sign_text("you", I18n.t(YOU))
	hint.text = I18n.t(HINT_TOUCH if touch_mode else HINT_KEYS)
	hint.visible = not _hint_done
	if _soon != "":
		soon_label.text = I18n.t(SOON[_soon])
	_update_prompt()
	CandleStyle.safe_margins(margin)


## สถานีที่ตัวผู้เล่นเอื้อมถึงตอนนี้ ("" = ไม่มี)
func station() -> String:
	return world.station()


## ใช้สถานีตรงหน้า (เหมือนกด E หรือแตะปุ่มใช้งาน)
func use_station() -> void:
	if not active:
		return
	match station():
		"battle":
			_push(BATTLE_SETUP)
		"army":
			_push(ARMY)
		"settings":
			_push(SETTINGS_SCREEN)
		"online", "adventure", "vault":
			show_soon(station())
		"exit":
			_go_menu()


## แผง "เร็วๆ นี้" ของสถานีที่ยังไม่เปิด ปิดเองใน 2.5 วิ เมื่อเดิน หรือเมื่อกดย้อนกลับ
func show_soon(id: String) -> void:
	if not SOON.has(id):
		return
	_soon = id
	soon_label.text = I18n.t(SOON[id])
	soon_panel.show()
	soon_timer.start(SOON_SECONDS)


func close_soon() -> void:
	soon_timer.stop()
	soon_panel.hide()
	_soon = ""


## ปุ่มย้อนกลับ / Esc: ปิดแผง "เร็วๆ นี้" ก่อน ไม่มีแผงก็ให้ App ถอยกลับหน้าแรก
func handle_back() -> bool:
	if soon_panel.visible:
		close_soon()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not active or not InputMap.has_action(&"interact"):
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		use_station()


# ---- ภายใน ----

func _activate(on: bool) -> void:
	active = on
	world.set_active(on)
	if on:
		_hide_table()
		refresh()
	else:
		stick.release()
		close_soon()
		use_button.hide()


func _on_visibility() -> void:
	if is_visible_in_tree() != active:
		_activate(is_visible_in_tree())


func _on_resize() -> void:
	if active:
		CandleStyle.safe_margins(margin)


func _on_station(id: String) -> void:
	_update_prompt()
	station_changed.emit(id)


func _update_prompt() -> void:
	var id := world.station()
	use_button.visible = active and id != ""
	if id != "":
		use_button.text = I18n.t(PROMPT_TOUCH if touch_mode else PROMPT_KEYS).format({"name": I18n.t(NAMES[id])})


## ผู้เล่นเริ่มเดิน (มีคำสั่งเดินจริง ไม่ใช่แค่ชะลอตัว): ซ่อนคำแนะนำครั้งแรก และปิดแผง "เร็วๆ นี้"
func _on_avatar_moved(_p: Vector3) -> void:
	if world.avatar.input_vector() == Vector2.ZERO:
		return
	if soon_panel.visible:
		close_soon()
	if not _hint_done:
		_hint_done = true
		if App.gfx == "min" or App.gfx == "lo":
			hint.hide()
		else:
			_hint_tween = create_tween()
			_hint_tween.tween_property(hint, ^"modulate:a", 0.0, 0.4)
			_hint_tween.tween_callback(hint.hide)


func hint_done() -> bool:
	return _hint_done


func _go_menu() -> void:
	if active:
		App.pop()


func _open_settings() -> void:
	_push(SETTINGS_SCREEN)


func _push(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_warning("hall: no screen at " + path)
		return null
	return App.push(load(path))


## โต๊ะรบ (โลกเดียวกัน) ต้องซ่อนและหยุดเสมอขณะห้องโถงอยู่บนสุด
func _hide_table() -> void:
	var t := get_tree().get_first_node_in_group("table_view") as Node3D
	if t != null:
		t.visible = false
		t.process_mode = Node.PROCESS_MODE_DISABLED
