extends Node
## รากของแอป: World (โต๊ะ 3 มิติ คงอยู่ทุกหน้า) + UI (ScreenStack ของ App) + Overlay (toast/ถาดลูกเต๋า ภายหลัง)
## ครั้งแรกที่เปิด (ยังไม่มี settings.cfg) เดาระดับกราฟิกจากเครื่อง: มือถือ = lo (RAM ≤ 2 GB = min), PC RAM ≤ 2 GB = min,
## ≤ 4 GB = lo, อื่น ๆ = mid — มือถือของเจ้าของ (Mali-G52) ได้ 21 เฟรม/วิ กับเงาเต็มจอ จึงเริ่มที่ lo
## หน้าแรกของภาพทดลอง R0-E คือหน้าตรวจการ์ดจอ

const GPU_CHECK := preload("res://ui/screens/gpu_check.tscn")
const GB := 1024.0 * 1024.0 * 1024.0

## เทสตั้ง false ก่อน add_child เพื่อไม่เขียน settings.cfg ของเครื่อง
@export var first_run_guess := true

@onready var ui: CanvasLayer = $UI
@onready var table: TableView = $World/BattleTable


func _enter_tree() -> void:
	if first_run_guess and not FileAccess.file_exists(App.SETTINGS_PATH):
		App.set_gfx(guess_level())
		App.save_settings()
		Log.info("first run: graphics level " + App.gfx)


func _ready() -> void:
	App.set_screen_root(ui)
	App.push(GPU_CHECK)


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
