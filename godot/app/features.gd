class_name Features
extends RefCounted
## สวิตช์ฟีเจอร์ที่เปิดเฉพาะแอปรุ่นส่วนตัว (PACK_SPEC §5.1): อ่าน res://packs/features.json ครั้งแรกที่ถาม
## รูป {"online": true} · ไม่มีไฟล์ (แอปสาธารณะ) = ปิดทุกอย่าง · เทสเปิดเองด้วย set_flag()
## online = เปิดห้องเสริมหลังประตูเทียบยาน (รอบ B: เล่นกับเพื่อนเปิดทุกแอป ไม่ขึ้นกับสวิตช์นี้แล้ว)

const PATH := "res://packs/features.json"
const KNOWN: PackedStringArray = ["online"]

static var _flags: Dictionary = {}
static var _loaded := false


## เปิดอยู่ไหม (อ่านไฟล์ครั้งแรก)
static func on(name: StringName) -> bool:
	if not _loaded:
		load_file()
	return bool(_flags.get(str(name), false))


## อ่านไฟล์ใหม่ (path ว่าง = PATH) · คีย์ที่ไม่รู้จักหรือค่าที่ไม่ใช่ bool ถูกข้าม · คืน true เมื่ออ่านได้
static func load_file(path: String = PATH) -> bool:
	_loaded = true
	_flags = {}
	if not FileAccess.file_exists(path):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_warning("features: %s is not a JSON object" % path)
		return false
	for k: Variant in d:
		if KNOWN.has(str(k)) and d[k] is bool:
			_flags[str(k)] = d[k]
	return true


## เทส: เปิด/ปิดเอง (ไม่แตะไฟล์)
static func set_flag(name: StringName, v: bool) -> void:
	_loaded = true
	_flags[str(name)] = v


static func reset() -> void:
	_loaded = false
	_flags = {}
