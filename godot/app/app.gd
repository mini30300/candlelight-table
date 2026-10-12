extends Node
## App (autoload): ตั้งค่าของแอปใน user://settings.cfg + ตัวสลับหน้าจอ (ScreenStack) + ปุ่มย้อนกลับ
## ตั้งค่า: gfx (hi/mid/lo/min), lang (th/en), snd (เปิด/ปิดเสียง), server (URL ของเซิร์ฟเวอร์)
## อ่านใน _init() จึงใช้ได้ทันทีแม้ใน -s runner; แอปต้องเปิดได้เสมอแม้ไม่มีไฟล์หรือไฟล์เสีย

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "app"
const GFX_LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const LANGS: PackedStringArray = ["th", "en"]
const DEFAULT_GFX := "mid"
const DEFAULT_LANG := "th"
const DEFAULT_SERVER := "https://candlelight-table.mini3030023450.workers.dev"

var gfx: String = DEFAULT_GFX
var lang: String = DEFAULT_LANG
var snd: bool = true
var server: String = DEFAULT_SERVER

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


# ---- ตั้งค่า ----

## อ่านตั้งค่าจากไฟล์; ไม่มีไฟล์หรืออ่านไม่ได้ก็กลับเป็นค่าเริ่มต้น คืน true เมื่ออ่านจากไฟล์ได้
func load_settings(path: String = SETTINGS_PATH) -> bool:
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
	return true


## เขียนตั้งค่าลงไฟล์; คืน false เมื่อเขียนไม่ได้ (แอปเล่นต่อได้)
func save_settings(path: String = SETTINGS_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "gfx", gfx)
	cfg.set_value(SECTION, "lang", lang)
	cfg.set_value(SECTION, "snd", snd)
	cfg.set_value(SECTION, "server", server)
	var err := cfg.save(path)
	if err != OK:
		push_warning("settings: cannot write " + path + ": " + error_string(err))
	return err == OK


func reset_settings() -> void:
	gfx = DEFAULT_GFX
	lang = DEFAULT_LANG
	snd = true
	server = DEFAULT_SERVER
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


## ปุ่มย้อนกลับ: มีหน้าซ้อนอยู่ก็ถอยหนึ่งหน้า ถึงหน้าแรกแล้วค่อยออกจากแอป
func back() -> void:
	if _screens.size() > 1:
		pop()
	elif is_inside_tree():
		get_tree().quit()
