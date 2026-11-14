class_name KitWalker
extends KitBeast
## ตัวเดินบนดาดฟ้าจากชุดโมเดลเดิมของโต๊ะรบ (PACK_SPEC §10): ชุดมีโครง 23 กระดูก + ท่า idle/walk/run ใน humanoid.res
## (ทั้งหมดของ KitBeast: motion_scale = scale ของชุด, ท่าโพสของชุด, อัตราเล่นตามความเร็วจึงเท้าไม่ไถล)
## ดาดฟ้า (H1–H4): lo กับ min ยืนนิ่งท่าเดียวหลังหยุด (PACK_SPEC §3.2) · 1 draw call · ไม่มีงานต่อเฟรมตอนยืนนิ่ง
## ชุดสี (H10 apply_scheme): ตารางทาสี paint_tex แถวเดียว ช่องเกราะ = primary, ช่องผ้า = secondary
## ช่องสีตายตัว (อาวุธ เลนส์ ขอบ และช่องธรรมชาติ: ผิว เหล็ก ทอง หนัง ...) คงสีเดิม

## ช่องที่คงสีเดิมเสมอ (นอกจากช่องธรรมชาติที่ tint = false)
const FIXED_KEYS: PackedStringArray = ["gun", "visor", "trim", "jet", "flame", "lambda", "maw", "red", "glow", "eye"]
## ช่องผ้า/ชุดใน = สีรอง
const SECONDARY_KEYS: PackedStringArray = ["cloth", "cloth2", "under", "lining", "cape", "cloak", "cloak2", "robe", "pants",
	"sash", "sash2", "hood", "wrap", "quilt", "glove", "boot", "pouch", "strap", "band", "ghillie", "ghillie2"]
## ความเร็วบนดาดฟ้า = ความเร็วของท่า × scale × ค่านี้ (เล่นท่าเร็วขึ้นเท่านี้ เท้าไม่ไถล)
const DECK_RATE := 1.4

var walk_kit := ""
## ระดับกราฟิกของแอป (level ของ KitBeast เป็น min แทน lo: ยืนนิ่งเหมือนกัน)
var gfx := "mid"
var role: StringName = &"deck"
var _scheme: Array = []         # [primary, secondary] ที่ยังไม่ได้ทา (มาก่อน setup)
var _paint: ImageTexture


func setup(opts: Dictionary) -> void:
	var o := opts.duplicate()
	o["kit"] = walk_kit
	role = StringName(str(o.get("role", "deck")))
	gfx = str(o.get("level", gfx))
	var l := gfx
	o["level"] = _anim_level(l)
	super.setup(o)
	gfx = l
	if not _scheme.is_empty():
		apply_scheme(_scheme[0], _scheme[1])


func apply_level(l: String) -> void:
	gfx = l
	super.apply_level(_anim_level(l))


## (เดิน, วิ่ง) ม./วิ ที่ท่าเดิน/วิ่งของชุดไม่ไถล (HallAvatar ใช้แทน 3 / 6)
func deck_speeds() -> Vector2:
	var lib := load(LIB_PATH) as AnimationLibrary
	if lib == null or not lib.has_animation(&"walk") or not lib.has_animation(&"run"):
		return Vector2(HallAvatar.WALK, HallAvatar.RUN)
	var w := float(lib.get_animation(&"walk").get_meta("speed", 1.0)) * _scale * DECK_RATE
	var r := float(lib.get_animation(&"run").get_meta("speed", 2.0)) * _scale * DECK_RATE
	return Vector2(w, r)


## H10: ทาชุดสี (ก่อนหรือหลัง setup ก็ได้)
func apply_scheme(primary: Color, secondary: Color) -> void:
	_scheme = [primary, secondary]
	if _mat == null:
		return
	var keys := palette_keys(walk_kit)
	var img := Image.create(maxi(keys.size(), 1), 1, false, Image.FORMAT_RGBA8)
	for i in keys.size():
		match paint_slot(walk_kit, i):
			1: img.set_pixel(i, 0, Color(primary, 1.0))
			2: img.set_pixel(i, 0, Color(secondary, 1.0))
			_: img.set_pixel(i, 0, Color(0, 0, 0, 0))
	if _paint == null or _paint.get_width() != img.get_width():
		_paint = ImageTexture.create_from_image(img)
	else:
		_paint.update(img)
	_mat.set_shader_parameter("paint_tex", _paint)
	_mat.set_shader_parameter("paint_row", 0)


## สีที่ช่อง i ได้: 0 = คงสีเดิม, 1 = primary, 2 = secondary
static func paint_slot(kit: String, i: int) -> int:
	var mats := _materials(kit)
	if i < 0 or i >= mats.size():
		return 0
	var m: Dictionary = mats[i]
	var key := str(m.get("key", ""))
	if not bool(m.get("tint", false)) or FIXED_KEYS.has(key):
		return 0
	return 2 if SECONDARY_KEYS.has(key) else 1


## ชื่อช่องสีตามลำดับดัชนีจานสี (kits.json materials[])
static func palette_keys(kit: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in _materials(kit):
		out.append(str((m as Dictionary).get("key", "")))
	return out


func scheme() -> Array:
	return _scheme


static func _materials(kit: String) -> Array:
	var e: Variant = _manifest().get(kit, {})
	var v: Variant = (e as Dictionary).get("materials", []) if e is Dictionary else []
	return v if v is Array else []


static func _anim_level(l: String) -> String:
	return "min" if l == "lo" else l
