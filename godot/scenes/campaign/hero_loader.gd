class_name CampaignHeroes
extends RefCounted
## ฉากโชว์บนการ์ดความยาก (CAMPAIGN_SPEC §3, track B เป็นเจ้าของ): ของชุดเสริมก่อน ไม่มีหรือใช้ไม่ได้ = ฉากในตัวของแอป
## สัญญาฉาก: สคริปต์ extends Node3D มี setup(ctx: Dictionary) กับ set_active(on: bool)
##   ctx = {"level": "hi"|"mid"|"lo"|"min", "sel": Figures.selected()} (+ คีย์เสริมเช่น "aspect": กว้าง/สูง ที่ฉากไม่ต้องใช้ก็ได้)
##   setup สร้างทุกอย่างเอง รวม Camera3D (current = true) กับไฟ · set_active(false) = หยุดทุกอย่าง ไม่มีงานต่อเฟรม
## ที่ค้นของชุดเสริม: res://packs/campaign/hero_<id>.gd แล้ว res://packs/arena/campaign/hero_<id>.gd
## (CI ส่วนตัวคัด pack/ ไปไว้ที่ packs/arena/: ถ้ายังไม่ได้ย้าย campaign/ ออกมา ก็ยังเจอ)
## เพลงฉากภัยพิบัติ: catastrophe.ogg ในโฟลเดอร์เดียวกัน (ไม่มี = เงียบ)

const IDS: PackedStringArray = ["normal", "hard", "veryhard", "catastrophe"]
const PACK_DIRS: PackedStringArray = ["res://packs/campaign", "res://packs/arena/campaign"]
const BUILTIN := "res://scenes/campaign/hero_%s.gd"
const API: PackedStringArray = ["setup", "set_active"]
const MUSIC := "catastrophe.ogg"

## เทสชี้โฟลเดอร์ชุดเสริมเอง (ว่าง = PACK_DIRS)
static var test_dirs: PackedStringArray = []


static func dirs() -> PackedStringArray:
	return test_dirs if not test_dirs.is_empty() else PACK_DIRS


## ไฟล์ฉากของชุดเสริมสำหรับ id ("" = ไม่มี)
static func pack_path(id: String) -> String:
	if not IDS.has(id):
		return ""
	for d in dirs():
		var p := "%s/hero_%s.gd" % [d, id]
		if ResourceLoader.exists(p):
			return p
	return ""


static func builtin_path(id: String) -> String:
	return BUILTIN % id if IDS.has(id) else ""


## สร้างฉากของ id (ยังไม่ setup): ของชุดเสริมที่มีเมธอดครบ ไม่งั้นฉากในตัว · id ผิด = null
static func make(id: String) -> Node3D:
	if not IDS.has(id):
		return null
	var pp := pack_path(id)
	if pp != "":
		var n := _instance(pp)
		if n != null and missing_api(n).is_empty():
			return n
		push_warning("campaign hero: %s is not a hero scene (needs Node3D with %s); using the built-in one" % [pp, ", ".join(API)])
		if n != null:
			n.free()
	return _instance(builtin_path(id))


## มาจากชุดเสริมไหม (ไม่ใช่ฉากในตัว scenes/campaign/) สำหรับเทสและป้ายดีบัก
static func is_pack(node: Node) -> bool:
	if node == null or node.get_script() == null:
		return false
	return not str((node.get_script() as Script).resource_path).begins_with("res://scenes/campaign/")


## เพลงของฉากภัยพิบัติ ("" = ไม่มี)
static func music_path() -> String:
	for d in dirs():
		var p := "%s/%s" % [d, MUSIC]
		if ResourceLoader.exists(p):
			return p
	return ""


static func missing_api(n: Object) -> PackedStringArray:
	var out := PackedStringArray()
	if not n is Node3D:
		out.append("Node3D")
	for m in API:
		if n == null or not n.has_method(m):
			out.append(m)
	return out


static func _instance(p: String) -> Node3D:
	if p == "" or not ResourceLoader.exists(p):
		return null
	var res: Resource = load(p)
	var n: Object = null
	if res is GDScript and (res as GDScript).can_instantiate():
		n = (res as GDScript).new()
	elif res is PackedScene:
		n = (res as PackedScene).instantiate()
	if n is Node3D:
		return n
	if n is Node:
		(n as Node).free()
	return null
