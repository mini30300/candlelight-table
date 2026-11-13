extends Control
## หน้าแรก (LOBBY_SPEC §1.1): ภาพหัวธีมเทียน (TitleArt) + คอลัมน์ปุ่มขวา: เล่นกับบอท → ห้องโถง,
## ออนไลน์ → ห้องโถงยืนหน้าประตูเทียบยาน แล้วเปิดหน้าเล่นกับเพื่อนทับ (NET_SPEC §7.1, ไม่มีป้าย "เร็วๆ นี้" แล้ว),
## ตั้งค่า, ENGLISH/ไทย, ออก (เฉพาะคอม) · ปุ่มย้อนกลับ/Esc เปิดกล่องถามก่อนออก กดซ้ำปิดกล่อง
## ทึบเต็มจอ 2 มิติล้วน (ไม่มีกล้อง 3 มิติทำงานใต้หน้านี้) · ไม่มี _process: เปลวเทียนขยับด้วย Timer เฉพาะ hi/mid, ป้ายแจ้งเตือนปิดด้วย Timer

signal quit_confirmed

const HALL_SCREEN := "res://ui/screens/hall_screen.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings.tscn"
const TOAST_SECONDS := 2.5
const BUTTON_TO_ENGLISH := "ENGLISH"   # ป้ายปุ่มตอนเป็นไทย — อังกฤษตั้งใจ เหมือนหน้าเก่า
const BUTTON_TO_THAI := "ไทย"
const QUIT_HOSTING := "ออกจากเกม? ห้องจะปิด เพื่อนทุกคนจะหลุดจากห้อง"

@onready var art: TitleArt = %Art
@onready var margin: MarginContainer = %Margin
@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var play_button: Button = %PlayButton
@onready var online_button: Button = %OnlineButton
@onready var online_badge: Label = %OnlineBadge
@onready var settings_button: Button = %SettingsButton
@onready var lang_button: Button = %LangButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel
@onready var toast: PanelContainer = %Toast
@onready var toast_text: Label = %ToastText
@onready var toast_timer: Timer = %ToastTimer
@onready var quit_confirm: Control = %QuitConfirm
@onready var quit_panel: PanelContainer = %QuitPanel
@onready var quit_text: Label = %QuitText
@onready var quit_yes: Button = %QuitYes
@onready var quit_no: Button = %QuitNo

## เทสตั้ง false: ปุ่มออกส่งแค่สัญญาณ quit_confirmed ไม่ปิดโปรแกรมจริง
var quit_for_real := true
## เทสบังคับโชว์/ซ่อนปุ่มออก ("" = ตามเครื่อง: ซ่อนบนมือถือ)
var quit_override := ""

var _toast_key := ""


func _ready() -> void:
	CandleStyle.title(title, 72)
	title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.65))
	title.add_theme_constant_override(&"shadow_offset_y", 4)
	CandleStyle.text(subtitle, 24)
	subtitle.add_theme_color_override(&"font_color", CandleStyle.TEXT)
	CandleStyle.button(play_button, true)
	for b in [online_button, settings_button, lang_button, quit_button]:
		CandleStyle.button(b)
	for b in [play_button, online_button, settings_button, lang_button, quit_button]:
		(b as Button).custom_minimum_size.y = 64.0
	play_button.custom_minimum_size.y = 76.0
	play_button.add_theme_font_size_override(&"font_size", 28)
	_style_badge()
	CandleStyle.text(version_label, 16, true)
	CandleStyle.panel(toast)
	CandleStyle.text(toast_text, 22)
	CandleStyle.panel(quit_panel)
	CandleStyle.title(quit_text, 32)
	CandleStyle.button(quit_yes, true)
	CandleStyle.button(quit_no)
	quit_yes.custom_minimum_size = Vector2(160, 64)
	quit_no.custom_minimum_size = Vector2(160, 64)
	play_button.pressed.connect(open_hall)
	online_button.pressed.connect(open_online)
	settings_button.pressed.connect(open_settings)
	lang_button.pressed.connect(func() -> void: set_language(not I18n.english))
	quit_button.pressed.connect(open_quit_confirm)
	quit_yes.pressed.connect(confirm_quit)
	quit_no.pressed.connect(close_quit_confirm)
	toast_timer.one_shot = true
	toast_timer.wait_time = TOAST_SECONDS
	toast_timer.timeout.connect(hide_toast)
	toast.hide()
	quit_confirm.hide()
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()
	_apply_idle()
	_drop_camera.call_deferred()   # หลัง READY ของวิวพอร์ตราก (มันเลือกกล้องตัวแรกให้เองถ้ายังไม่มี)
	if visible:
		_music()


## วาดข้อความทุกชิ้นใหม่ตามภาษา และอ่านระดับกราฟิกใหม่
func refresh() -> void:
	title.text = I18n.t("โต๊ะเทียน")
	subtitle.text = I18n.t("โต๊ะรบกับเพื่อน บอท หรือ Claude")
	play_button.text = I18n.t("เล่นกับบอท")
	online_button.text = I18n.t("ออนไลน์")
	online_badge.text = I18n.t("เร็วๆ นี้")
	online_badge.visible = false   # ออนไลน์เปิดแล้ว (NET_SPEC §7.1)
	online_button.visible = Features.on(&"online")   # แอปสาธารณะซ่อน: ออนไลน์อยู่ในแอปรุ่นส่วนตัว (PACK_SPEC §5.1)
	settings_button.text = I18n.t("ตั้งค่า")
	lang_button.text = BUTTON_TO_THAI if I18n.english else BUTTON_TO_ENGLISH
	quit_button.text = I18n.t("ออก")
	quit_button.visible = _quit_shown()
	version_label.text = version_text()
	quit_text.text = I18n.t(QUIT_HOSTING if _hosting() else "ออกจากเกม?")
	quit_yes.text = I18n.t("ออก")
	quit_no.text = I18n.t("ยกเลิก")
	toast_text.text = I18n.t(_toast_key) if _toast_key != "" else ""   # ซ่อนอยู่ก็แปลไว้ ไม่ค้างไทย
	art.set_level(App.gfx)
	art.set_active(is_visible_in_tree())


## "แอปใหม่ รุ่น 0.2": APP_VER มีคำไทยนำหน้า ("ใหม่ 0.2") จึงใช้แค่ตัวเลขคำสุดท้าย ห้ามโชว์ดิบ
static func version_text() -> String:
	return I18n.t("แอปใหม่ รุ่น {v}").format({"v": version_number()})


static func version_number() -> String:
	var parts := Version.APP_VER.strip_edges().split(" ", false)
	return parts[parts.size() - 1] if not parts.is_empty() else ""


## สลับภาษา บันทึก (save = false ในเทสที่ไม่อยากเขียนไฟล์) แล้ววาดใหม่
func set_language(english: bool, save := true) -> void:
	App.set_lang("en" if english else "th")
	if save:
		App.save_settings()
	refresh()


func open_hall() -> Node:
	if not ResourceLoader.exists(HALL_SCREEN):
		push_error("main menu: no hall screen at " + HALL_SCREEN)
		return null
	hide_toast()
	return App.push(load(HALL_SCREEN))


## ออนไลน์: เปิดห้องโถง ยืนหน้าประตูเทียบยาน แล้วเปิดหน้าเล่นกับเพื่อนทับ (ลึก 3; ย้อนกลับ = ดาดฟ้าหน้าประตู)
func open_online() -> Node:
	var hall := open_hall()
	if hall == null or not hall.has_method("open_online") or not Features.on(&"online"):
		return hall
	hall.call("enter_airlock")
	return hall.call("open_online")


func open_settings() -> Node:
	hide_toast()
	return App.push(load(SETTINGS_SCREEN))


## ป้ายแจ้งเตือนกลางล่าง หายเองใน 2.5 วิ (key = ข้อความไทย แปลตอนวาด)
func show_toast(key: String) -> void:
	_toast_key = key
	toast_text.text = I18n.t(key)
	toast.show()
	toast_timer.start(TOAST_SECONDS)


func hide_toast() -> void:
	_toast_key = ""
	toast_timer.stop()
	toast.hide()


func open_quit_confirm() -> void:
	hide_toast()
	quit_text.text = I18n.t(QUIT_HOSTING if _hosting() else "ออกจากเกม?")   # เปิดห้องอยู่: บอกว่าเพื่อนจะหลุด
	quit_confirm.show()


func _hosting() -> bool:
	var net := get_node_or_null(^"/root/Net")
	return net != null and net.has_method("is_host") and bool(net.call("is_host"))


func close_quit_confirm() -> void:
	quit_confirm.hide()


func confirm_quit() -> void:
	quit_confirmed.emit()
	if quit_for_real and is_inside_tree():
		get_tree().quit()


## ปุ่มย้อนกลับ/Esc (App.back ถามก่อน): เปิดกล่องถามก่อนออก กดซ้ำปิดกล่อง — หน้าแรกจัดการเองเสมอ
func handle_back() -> bool:
	if quit_confirm.visible:
		close_quit_confirm()
	else:
		open_quit_confirm()
	return true


func _quit_shown() -> bool:
	if quit_override != "":
		return quit_override == "on"
	return not OS.has_feature("mobile")


func _style_badge() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CandleStyle.GOLD
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	online_badge.add_theme_stylebox_override(&"normal", sb)
	online_badge.add_theme_font_override(&"font", CandleStyle.BOLD)
	online_badge.add_theme_font_size_override(&"font_size", 15)
	online_badge.add_theme_color_override(&"font_color", CandleStyle.BG)


func _layout() -> void:
	CandleStyle.safe_margins(margin)


## ระดับกราฟิกที่เปลี่ยนในหน้าตั้งค่า: fps และโหมดประหยัดตอนนิ่งใช้ค่าเดียวกับโต๊ะ (TableView.LEVELS)
func _apply_idle() -> void:
	var cfg: Dictionary = TableView.LEVELS.get(App.gfx, TableView.LEVELS["mid"])
	Engine.max_fps = int(cfg["fps"])
	OS.low_processor_usage_mode = bool(cfg["idle"])


## หน้านี้ทึบและ 2 มิติล้วน: ปล่อยกล้อง 3 มิติที่ค้างอยู่ (กล้องโต๊ะที่ซ่อน) จะได้ไม่วาดโลก 3 มิติข้างหลังเปล่า ๆ
func _drop_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		cam.clear_current(false)


func _on_visibility() -> void:
	if visible:
		refresh()
		_apply_idle()
		_drop_camera()
		_music()
		# บอกห้องว่ากลับมาอยู่หน้าแรก (NET_SPEC §6.1; ออฟไลน์ Net แค่จำไว้)
		var net := get_node_or_null(^"/root/Net")
		if net != null and net.has_method("set_where"):
			net.call("set_where", &"menu")
	else:
		hide_toast()
		close_quit_confirm()
	art.set_active(visible)


## เพลงหน้าแรก (เพลงเดิมช้า ๆ ของหน้าเก่า)
func _music() -> void:
	var music := get_node_or_null(^"/root/Music")
	if music != null:
		music.call("set_mood", &"menu")
