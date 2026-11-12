extends Node
## รากของแอป: World (โต๊ะ 3 มิติ คงอยู่ทุกหน้า) + UI (ScreenStack ของ App) + Overlay (toast/ถาดลูกเต๋า ภายหลัง)
## ครั้งแรกที่เปิด (ยังไม่มี settings.cfg) เดาระดับกราฟิกจากเครื่อง: มือถือ = lo (RAM ≤ 2 GB = min), PC RAM ≤ 2 GB = min,
## ≤ 4 GB = lo, อื่น ๆ = mid — มือถือของเจ้าของ (Mali-G52) ได้ 21 เฟรม/วิ กับเงาเต็มจอ จึงเริ่มที่ lo
## หน้าแรกคือเมนูธีมเทียน (LOBBY_SPEC §1): เล่นกับบอท → ห้องโถง; หน้าตรวจการ์ดจออยู่ในหน้าตั้งค่า
## โต๊ะตัวอย่างใน World ไม่สร้างตอนเริ่ม (auto_build = false) ซ่อนและปิดการประมวลผลไว้ จนหน้าตรวจการ์ดจอหรือการรบเรียกใช้

const MAIN_MENU := preload("res://ui/screens/main_menu.tscn")
const ARMY := preload("res://ui/screens/army.tscn")
const GB := 1024.0 * 1024.0 * 1024.0

## เทสตั้ง false ก่อน add_child เพื่อไม่เขียน settings.cfg ของเครื่อง
@export var first_run_guess := true

@onready var ui: CanvasLayer = $UI
@onready var table: TableView = $World/BattleTable


func _enter_tree() -> void:
	if first_run_guess and not FileAccess.file_exists(App.settings_file):
		App.set_gfx(guess_level())
		App.save_settings()
		Log.info("first run: graphics level " + App.gfx)


func _ready() -> void:
	App.set_screen_root(ui)
	App.push(MAIN_MENU)


## เปิดหน้าจัดกองทัพซ้อนบนหน้าปัจจุบัน คืนโหนดหน้าใหม่
func open_army() -> Node:
	return App.push(ARMY)


## ระดับเริ่มต้นจาก RAM และชนิดเครื่อง (ARCHITECTURE §6; มือถือไม่เกิน lo)
static func guess_level() -> String:
	var gb := float(OS.get_memory_info().get("physical", 0)) / GB
	if OS.has_feature("mobile"):
		return "min" if gb > 0.0 and gb <= 2.0 else "lo"
	if gb > 0.0 and gb <= 2.0:
		return "min"
	if gb > 0.0 and gb <= 4.0:
		return "lo"
	return "mid"
