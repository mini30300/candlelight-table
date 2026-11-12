extends Node
## App (autoload): ตั้งค่าของแอปใน user://settings.cfg + ตัวสลับหน้าจอ (ScreenStack) + ปุ่มย้อนกลับ
## ตั้งค่า: gfx (hi/mid/lo/min), lang (th/en), snd (เปิด/ปิดเสียง), server (URL ของเซิร์ฟเวอร์),
## fig (egg ตัวไข่ / kit โมเดลชุดเดิม), touch (auto/on/off ปุ่มบนจอ)
## อ่านใน _init() จึงใช้ได้ทันทีแม้ใน -s runner; แอปต้องเปิดได้เสมอแม้ไม่มีไฟล์หรือไฟล์เสีย

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "app"
const GFX_LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const LANGS: PackedStringArray = ["th", "en"]
const DEFAULT_GFX := "mid"
const DEFAULT_LANG := "th"
const DEFAULT_SERVER := "https://candlelight-table.mini3030023450.workers.dev"
const FIG_STYLES: PackedStringArray = ["egg", "kit"]
const TOUCH_MODES: PackedStringArray = ["auto", "on", "off"]
const DEFAULT_FIG := "egg"
const DEFAULT_TOUCH := "auto"

var gfx: String = DEFAULT_GFX
var lang: String = DEFAULT_LANG
var snd: bool = true
var server: String = DEFAULT_SERVER
var fig: String = DEFAULT_FIG
var touch: String = DEFAULT_TOUCH
var settings_file: String = SETTINGS_PATH   # เทสชี้ไปไฟล์อื่น จะได้ไม่ทับตั้งค่าของเครื่อง
## ตัวเลือกตั้งเกมครั้งล่าสุด (แบบ SeatPlan; อยู่ในหน่วยความจำเท่านั้น) หน้าตั้งเกมเปิดด้วยค่านี้แทนค่าเริ่มต้น
var last_choice: Dictionary = {}

var _screens: Array[Node] = []     # หน้าจอที่ซ้อนกัน ตัวท้ายคือหน้าปัจจุบัน
var _screen_root: Node = null      # โหนดที่ใส่หน้าจอ (main.tscn ตั้งให้; ไม่ตั้งก็ใส่ใต้ App)


func _init() -> void:
	load_settings()


func _ready() -> void:
	get_tree().quit_on_go_back = false   # ปุ่มย้อนกลับบน Android มาที่ back() แทนการปิดแอป
	_apply_lang()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


## Esc (action "back") = ปุ่มย้อนกลับ
func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(&"back") and event.is_action_pressed(&"back"):
		get_viewport().set_input_as_handled()
		back()


# ---- ตั้งค่า ----

## อ่านตั้งค่าจากไฟล์ (ว่าง = settings_file); ไม่มีไฟล์หรืออ่านไม่ได้ก็กลับเป็นค่าเริ่มต้น คืน true เมื่ออ่านจากไฟล์ได้
func load_settings(path: String = "") -> bool:
	if path.is_empty():
		path = settings_file
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		reset_settings()
		if err != ERR_FILE_NOT_FOUND:
			push_warning("settings: cannot read " + path + ": " + error_string(err))
		return false
	set_gfx(str(cfg.get_value(SECTION, "gfx", DEFAULT_GFX)))
	set_lang(str(cfg.get_value(SECTION, "lang", DEFAULT_LANG)))
	snd = bool(cfg.get_value(SECTION, "snd", true))
	set_server(str(cfg.get_value(SECTION, "server", DEFAULT_SERVER)))
	if not set_fig(str(cfg.get_value(SECTION, "fig", DEFAULT_FIG))):
		fig = DEFAULT_FIG
	if not set_touch(str(cfg.get_value(SECTION, "touch", DEFAULT_TOUCH))):
		touch = DEFAULT_TOUCH
	return true


## เขียนตั้งค่าลงไฟล์ (ว่าง = settings_file); คืน false เมื่อเขียนไม่ได้ (แอปเล่นต่อได้)
func save_settings(path: String = "") -> bool:
	if path.is_empty():
		path = settings_file
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "gfx", gfx)
	cfg.set_value(SECTION, "lang", lang)
	cfg.set_value(SECTION, "snd", snd)
	cfg.set_value(SECTION, "server", server)
	cfg.set_value(SECTION, "fig", fig)
	cfg.set_value(SECTION, "touch", touch)
	var err := cfg.save(path)
	if err != OK:
		push_warning("settings: cannot write " + path + ": " + error_string(err))
	return err == OK


func reset_settings() -> void:
	gfx = DEFAULT_GFX
	lang = DEFAULT_LANG
	snd = true
	server = DEFAULT_SERVER
	fig = DEFAULT_FIG
	touch = DEFAULT_TOUCH
	_apply_lang()


## ระดับกราฟิก; ค่าที่ไม่รู้จักถูกข้าม คืน false
func set_gfx(level: String) -> bool:
	if not GFX_LEVELS.has(level):
		return false
	gfx = level
	return true


## ภาษา th/en; ส่งต่อให้ I18n ทันทีถ้าอยู่ในฉากแล้ว
func set_lang(l: String) -> bool:
	if not LANGS.has(l):
		return false
	lang = l
	_apply_lang()
	return true


## URL เซิร์ฟเวอร์ (ตัดช่องว่างและ / ท้าย); ว่างคือค่าเริ่มต้น
func set_server(url: String) -> void:
	var u := url.strip_edges().rstrip("/")
	server = DEFAULT_SERVER if u.is_empty() else u


## รูปตัวละคร egg/kit; ค่าที่ไม่รู้จักถูกข้าม คืน false
func set_fig(s: String) -> bool:
	if not FIG_STYLES.has(s):
		return false
	fig = s
	return true


## ปุ่มบนจอ auto/on/off; ค่าที่ไม่รู้จักถูกข้าม คืน false
func set_touch(m: String) -> bool:
	if not TOUCH_MODES.has(m):
		return false
	touch = m
	return true


## ใช้ปุ่มบนจอไหม: on เสมอ, auto เฉพาะมือถือ
func touch_active() -> bool:
	return touch == "on" or (touch == "auto" and OS.has_feature("mobile"))


func _apply_lang() -> void:
	if not is_inside_tree():
		return
	var i18n := get_node_or_null(^"/root/I18n")
	if i18n != null:
		i18n.set("english", lang == "en")


# ---- หน้าจอ (ScreenStack) ----

## main.tscn เรียกเพื่อบอกว่าหน้าจอไปอยู่ใต้โหนดไหน
func set_screen_root(node: Node) -> void:
	_screen_root = node


func screen_root() -> Node:
	return _screen_root if _screen_root != null else self


## เปิดหน้าใหม่ซ้อนบนหน้าเดิม (หน้าเดิมซ่อนไว้ ไม่ทำลาย) คืนโหนดหน้าใหม่
func push(scene: PackedScene) -> Node:
	var screen := scene.instantiate()
	var top := current()
	if top is CanvasItem:
		(top as CanvasItem).hide()
	_screens.append(screen)
	screen_root().add_child(screen)
	return screen


## แทนหน้าปัจจุบันด้วยหน้าใหม่ (หน้าข้างล่างไม่โผล่ขึ้นมาระหว่างนั้น) คืนโหนดหน้าใหม่
func replace(scene: PackedScene) -> Node:
	if not _screens.is_empty():
		var top: Node = _screens.pop_back()
		if top.get_parent() != null:
			top.get_parent().remove_child(top)
		top.queue_free()
	return push(scene)


## ปิดหน้าปัจจุบันแล้วโชว์หน้าก่อน; คืน false ถ้าไม่มีหน้าซ้อนอยู่
func pop() -> bool:
	if _screens.is_empty():
		return false
	var top: Node = _screens.pop_back()
	if top.get_parent() != null:
		top.get_parent().remove_child(top)
	top.queue_free()
	var prev := current()
	if prev is CanvasItem:
		(prev as CanvasItem).show()
	return true


## หน้าปัจจุบัน หรือ null เมื่อไม่มีหน้าซ้อน
func current() -> Node:
	return null if _screens.is_empty() else _screens.back()


func depth() -> int:
	return _screens.size()


## ปุ่มย้อนกลับ: ถามหน้าปัจจุบันก่อน (handle_back() คืน true = จัดการเองแล้ว)
## ไม่งั้นมีหน้าซ้อนอยู่ก็ถอยหนึ่งหน้า ถึงหน้าแรกแล้วค่อยออกจากแอป
func back() -> void:
	var top := current()
	if top != null and top.has_method(&"handle_back") and top.call(&"handle_back"):
		return
	if _screens.size() > 1:
		pop()
	elif is_inside_tree():
		get_tree().quit()
