class_name GameData
extends RefCounted
## ข้อมูลเกมจาก res://data/*.json (ส่งออกจากหน้าเก่า ห้ามแก้มือ) แปลงเป็นจำนวนเต็มทั้งหมดก่อนให้กติกาใช้
## ลำดับใน TYPES คือสัญญาข้ามเครื่อง (รายชื่อกองทัพส่งเป็นจำนวนหมู่ตามตำแหน่งนี้) ห้ามสลับ เพิ่มได้แค่ท้าย
## รัศมีฐาน r เป็นเศษนิ้ว จึงเก็บเป็น r_mi (หนึ่งในพันนิ้ว); เลขเศษที่อื่นในตารางกติกาถือว่าผิด (ดู problems())
## หน่วยลับ: ช่อง sec / lk เก็บไว้ตามเดิมแบบทึบ บอกได้แค่ว่าเป็นหน่วยลับ (is_hidden)
## ช่อง inf (ทหารเดินเท้า 1/0) ไม่มีในหน้าเก่า: export_data.js เรียก INF(k) ของหน้าเก่าแล้วเติมให้ทุกหน่วย

const DIR := "res://data"
## รัศมีฐานเมื่อไม่มี r (800 MI ตามหน้าเก่า)
const BASE_R_MI := 800
## ช่องที่เป็นระยะเศษนิ้ว: ชื่อเดิม -> ชื่อใหม่ที่เก็บเป็น MI
const MI_FIELDS := {"r": "r_mi"}
## ค่าคงที่ที่กติกาใช้: ต้องมีใน constants.json และเป็นจำนวนเต็ม ไม่งั้นเป็นปัญหา (ไม่ปล่อยให้ได้ค่า fallback เงียบ ๆ)
const RULES_CONSTS := ["ENGAGE", "CHARGE_R", "AURA_R", "OBJ_R", "VP_PER", "VP_CAP", "MAX_ROUND", "KILL_ROUNDS",
	"DEP_FOE", "DEP_MATE", "BLESS_INV", "REZ_AURA", "SLOT_MAX", "SPEC_TOTAL", "GREN_R", "HEAL_ON", "PAIN_ROUND"]

static var _loaded := false
static var _types: Array[Dictionary] = []
static var _index: Dictionary = {}          # k -> ตำแหน่งใน TYPES
static var _facs: Array[Dictionary] = []
static var _pools: Dictionary = {}          # รหัสกองทัพ -> PackedStringArray
static var _consts: Dictionary = {}         # ค่าคงที่ที่เป็นจำนวนเต็ม (ค่าเศษเป็นของฝั่งภาพ ไม่เก็บ)
static var _themes: Dictionary = {}         # ชื่อฉาก -> {relief_mi, rough_mi} (ความสูงเนินของฉาก)
static var _terrains := PackedStringArray()  # ชนิดพื้น: flat, hills, mountain, forest
static var _problems := PackedStringArray()


## ปัญหาของช่อง inf ในหน่วยหนึ่ง ("" = ไม่มีปัญหา): ต้องเป็นจำนวนเต็ม 0 หรือ 1
static func inf_problem(k: String, t: Dictionary) -> String:
	var v: Variant = t.get("inf", null)
	if typeof(v) == TYPE_INT and (v == 0 or v == 1):
		return ""
	return "types: " + k + " has no inf 0/1 (re-run tools/export_data.js)"


## ค่าคงที่ของกติกา (RULES_CONSTS) ที่หายหรือไม่ใช่จำนวนเต็ม ในตารางค่าคงที่ที่แปลงแล้ว
static func const_problems(consts: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in RULES_CONSTS:
		if typeof(consts.get(name, null)) != TYPE_INT:
			out.append("constants.json: " + name + " is missing or not a whole number")
	return out


## โหลดครั้งเดียว (force = โหลดใหม่); คืน true เมื่อไม่มีปัญหา
static func load_all(force: bool = false) -> bool:
	if _loaded and not force:
		return _problems.is_empty()
	_types.clear()
	_index.clear()
	_facs.clear()
	_pools.clear()
	_consts.clear()
	_themes.clear()
	_terrains = PackedStringArray()
	_problems = PackedStringArray()
	var raw_types: Variant = _read("types.json")
	if raw_types is Array:
		for i: int in (raw_types as Array).size():
			var e: Variant = _intify((raw_types as Array)[i], "types[%d]" % i, true)
			if not (e is Dictionary) or not (e as Dictionary).has("k"):
				_problems.append("types[%d]: not a datasheet" % i)
				continue
			var k := str((e as Dictionary)["k"])
			if _index.has(k):
				_problems.append("types: duplicate key " + k)
				continue
			var bad_inf := inf_problem(k, e as Dictionary)
			if bad_inf != "":
				_problems.append(bad_inf)
			_index[k] = _types.size()
			_types.append(e)
	else:
		_problems.append("types.json: not an array")
	var raw_facs: Variant = _read("facs.json")
	if raw_facs is Array:
		for f: Variant in raw_facs:
			if f is Dictionary:
				_facs.append(f)
	var raw_core: Variant = _read("core.json")
	if raw_core is Dictionary:
		for fac: Variant in raw_core:
			_pools[str(fac)] = PackedStringArray(raw_core[fac])
	var raw_consts: Variant = _read("constants.json")
	if raw_consts is Dictionary:
		for name: Variant in raw_consts:
			var v: Variant = _intify(raw_consts[name], "", false)
			if v != null:
				_consts[str(name)] = v
	_problems.append_array(const_problems(_consts))
	var raw_themes: Variant = _read("themes.json")
	if raw_themes is Dictionary:
		for name: Variant in raw_themes:
			var th: Variant = raw_themes[name]
			if th is Dictionary and (th as Dictionary).has("relief") and (th as Dictionary).has("rough"):
				_themes[str(name)] = {"relief_mi": to_mi(th["relief"]), "rough_mi": to_mi(th["rough"])}
			else:
				_problems.append("themes.json: " + str(name) + " has no relief/rough")
	var raw_terrains: Variant = _read("terrains.json")
	if raw_terrains is Dictionary:
		for name: Variant in raw_terrains:
			_terrains.append(str(name))
	_loaded = true
	return _problems.is_empty()


## ปัญหาที่พบตอนโหลด (ไฟล์หาย เลขเศษในตารางกติกา คีย์ซ้ำ)
static func problems() -> PackedStringArray:
	load_all()
	return _problems


static func types() -> Array[Dictionary]:
	load_all()
	return _types


static func count() -> int:
	load_all()
	return _types.size()


## ข้อมูลหน่วยตามคีย์; ไม่รู้จักคืน {}
static func ty(k: String) -> Dictionary:
	load_all()
	return _types[_index[k]] if _index.has(k) else {}


## ตำแหน่งใน TYPES; ไม่รู้จักคืน -1
static func index_of(k: String) -> int:
	load_all()
	return int(_index.get(k, -1))


static func key_at(i: int) -> String:
	load_all()
	return str(_types[i]["k"]) if i >= 0 and i < _types.size() else ""


## รหัสกองทัพของหน่วย ("*" = ใช้ได้ทุกกองทัพ)
static func fac_of(k: String) -> String:
	return str(ty(k).get("fac", ""))


## รหัสกองทัพทั้ง 15 ตามลำดับบนจอ
static func factions() -> PackedStringArray:
	load_all()
	var out := PackedStringArray()
	for f: Dictionary in _facs:
		out.append(str(f.get("k", "")))
	return out


static func faction(fac: String) -> Dictionary:
	load_all()
	for f: Dictionary in _facs:
		if str(f.get("k", "")) == fac:
			return f
	return {}


## หน่วยที่บอทสุ่มได้ของกองทัพนี้ (ไม่มีหน่วยลับ)
static func pool(fac: String) -> PackedStringArray:
	load_all()
	return _pools.get(fac, PackedStringArray())


static func is_hidden(k: String) -> bool:
	var t := ty(k)
	return t.has("sec") or t.has("lk")


## ทหารเดินเท้า = INF(k) ของหน้าเก่า (ไม่ใช่พาหนะ ไม่ใช่สัตว์หรือตัวขี่ ตัวไม่ใหญ่): โดนพิษได้ ปาระเบิดได้ หมอบหลบได้
## อ่านจากช่อง inf ที่ส่งออกมา; คีย์ที่ไม่รู้จักคืน false (กติกาไม่รับคีย์แปลกตั้งแต่ตอนจัดทัพ)
static func is_inf(k: String) -> bool:
	return int(ty(k).get("inf", 0)) == 1


## รัศมีฐานเป็น MI
static func base_r_mi(k: String) -> int:
	return int(ty(k).get("r_mi", BASE_R_MI))


## ค่าคงที่จำนวนเต็มจาก constants.json; ไม่มีหรือเป็นเศษคืน fallback
static func const_int(name: String, fallback: int = 0) -> int:
	load_all()
	var v: Variant = _consts.get(name, null)
	return int(v) if typeof(v) == TYPE_INT else fallback


## ความสูงเนินของฉาก (MI): {relief_mi, rough_mi}; ไม่รู้จักคืน {}
static func theme_mi(name: String) -> Dictionary:
	load_all()
	return _themes.get(name, {})


static func theme_names() -> PackedStringArray:
	load_all()
	return PackedStringArray(_themes.keys())


static func terrain_names() -> PackedStringArray:
	load_all()
	return _terrains


## รุ่นกติกาของหน้าเก่าที่ข้อมูลนี้มาจาก (แอปใหม่ใช้ Version.RULES_V)
static func page_rules_v() -> int:
	return const_int("RULES_V")


static func _read(file: String) -> Variant:
	var path := DIR + "/" + file
	if not FileAccess.file_exists(path):
		_problems.append(file + ": missing")
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		_problems.append(file + ": " + parser.get_error_message())
		return null
	return parser.data


## แปลงค่าจาก JSON เป็นจำนวนเต็มทั้งหมด (JSON ให้เลขทุกตัวเป็นทศนิยม)
## strict: เลขเศษนอก MI_FIELDS = ปัญหา; ไม่ strict: ค่าที่มีเศษถูกตัดทิ้ง (คืน null)
static func _intify(v: Variant, path: String, strict: bool) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT:
			return v
		TYPE_ARRAY:
			var out: Array = []
			for i: int in (v as Array).size():
				var x: Variant = _intify(v[i], path + "[%d]" % i, strict)
				if x == null and v[i] != null:
					return null
				out.append(x)
			return out
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in v:
				var ks := str(key)
				if MI_FIELDS.has(ks) and typeof(v[key]) != TYPE_STRING:
					out[MI_FIELDS[ks]] = to_mi(v[key])
					continue
				var x: Variant = _intify(v[key], path + "." + ks, strict)
				if x == null and v[key] != null:
					if strict:
						continue
					return null
				out[ks] = x
			return out
	var i := int(v)
	if i == v:
		return i
	if strict:
		_problems.append(path + ": not a whole number (" + str(v) + ")")
	return null


## ระยะเป็นนิ้ว (เลขจาก JSON) -> MI ปัดเป็นจำนวนเต็มที่ใกล้ที่สุด ผลเหมือนกันทุกเครื่อง (คูณแบบ IEEE ครั้งเดียว)
static func to_mi(inches: Variant) -> int:
	var x: Variant = inches * 1000
	if x < 0:
		return -to_mi(-inches)
	var m := int(x)
	if (x - m) * 2 >= 1:
		m += 1
	return m
