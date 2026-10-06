extends Node
## I18n (autoload): พจนานุกรมไทย → อังกฤษ ของข้อความบนจอ (คีย์คือข้อความไทย แบบ BT_I18N ของหน้าเก่า)
## ค่าเริ่มต้นคือไทย; สลับด้วย I18n.english = true แล้วเรียก I18n.t("…") ทุกครั้งที่วาดข้อความ
## ลำดับค้นหา: EN ในไฟล์นี้ → res://ui/i18n_extra.json (ข้อความที่มีแต่ในแอปใหม่) → res://data/i18n_en.json (ของหน้าเก่า)
## โหลดใน _init() จึงใช้ได้ทันทีแม้ใน -s runner ก่อน _ready()

const EXTRA_PATH := "res://ui/i18n_extra.json"
const PAGE_PATH := "res://data/i18n_en.json"

## คำแปลที่ฝังในโค้ด (i18n_extra.json ต้องมีคู่เดียวกัน; เทสตรวจ)
const EN: Dictionary = {
	"โต๊ะเทียน แอปใหม่ รุ่นทดสอบ 0.0.1": "Candlelight Table — new app, test build 0.0.1",
	"เฟรม/วิ": "FPS",
	"การ์ดจอ": "GPU",
	"ระบบ": "OS",
	"จอ": "Screen",
	"ฟิกเกอร์ {n} ตัวจากชุดโมเดล": "{n} figures from the kits",
	"กล่องแทนฟิกเกอร์ {n} ใบ (ไม่พบชุดโมเดล)": "{n} box stand-ins (no kits found)",
	"ลากเพื่อหมุน · ล้อเมาส์หรือสองนิ้วเพื่อซูม": "Drag to orbit · wheel or two fingers to zoom",
}

var english: bool = false
var extra: Dictionary = {}   # จาก ui/i18n_extra.json
var page: Dictionary = {}    # จาก data/i18n_en.json


func _init() -> void:
	extra = load_json_dict(EXTRA_PATH)
	page = load_json_dict(PAGE_PATH)


## คืนข้อความตามภาษาที่เลือก; ไม่มีคำแปลก็คืนคีย์ไทยไป
func t(th: String) -> String:
	if not english:
		return th
	var en := lookup(th)
	return th if en.is_empty() else en


## หาคำแปลตามลำดับ EN → extra → page; ไม่พบคืน ""
func lookup(th: String) -> String:
	if EN.has(th):
		return EN[th]
	if extra.has(th):
		return str(extra[th])
	if page.has(th):
		return str(page[th])
	return ""


func has_key(th: String) -> bool:
	return not lookup(th).is_empty()


## คีย์ที่ยังไม่มีคำแปล (ใช้ในเทสและตอนดีบัก)
func missing(keys: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for k in keys:
		if not has_key(k):
			out.append(k)
	return out


## อ่านไฟล์ JSON ที่เป็น object ไทย→อังกฤษ; ไม่มีไฟล์คืน {} เงียบ ๆ, รูปแบบผิดคืน {} พร้อมคำเตือน
static func load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return data
	push_warning("i18n: " + path + " is not a JSON object")
	return {}
