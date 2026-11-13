class_name PackRooms
extends RefCounted
## ห้องเสริมจากชุดเสริม (PACK_SPEC §9): โฟลเดอร์ res://packs/rooms/<id>/ มี room.json (รูปแบบ 1) + สคริปต์ห้องหนึ่งไฟล์
## ไฟล์นี้อ่านรายการห้อง ตรวจรูปแบบ (ห้องเสียข้ามพร้อมคำเตือน ไม่ล่ม) และแปลงท่าในแถบห้อง (x + 30 ม.)
## แอปสาธารณะไม่มีโฟลเดอร์ packs/: list() ว่าง ดาดฟ้าเหมือนเดิมทุกอย่าง · ไฟล์นี้ไม่มีข้อความไทย

const ROOT := "res://packs/rooms"
const FORMAT := 1
## ประตูบนดาดฟ้าที่ห้องเสริมต่อได้ (v1 มีแค่ประตูเทียบยาน) และสวิตช์ฟีเจอร์ที่ต้องเปิด
const DOORS: PackedStringArray = ["online"]
const DOOR_FEATURE := {"online": &"online"}
const ACTIONS: PackedStringArray = ["soon", "cards", "online", "back"]
const CARD_ACTIONS: PackedStringArray = ["soon", "online"]
const ROOM_API: PackedStringArray = ["setup", "apply_level", "blockers"]
const ROOM_OPTIONAL: PackedStringArray = ["station_near", "station_used", "set_active", "set_english", "counts"]
## แถบห้อง (NetProto ไม่เปลี่ยน): ท่าในห้องส่ง x + 30 ม.; x ≥ 13.5 ม. = อยู่ในห้อง (ดาดฟ้าอยู่ใน ±12.5 ม.)
const POSE_X := 30.0
const BAND_X := 13.5
const MAX_HALF := Vector2(15.0, 20.0)
const MIN_HALF := Vector2(4.0, 4.0)

## เทสชี้รากห้องเอง (ว่าง = ROOT)
static var test_root := ""
static var _cache: Dictionary = {}     # root → Array[Dictionary] ห้องที่ผ่านแล้ว


## รากของห้องเสริมที่ใช้อยู่
static func root() -> String:
	return test_root if test_root != "" else ROOT


## ห้องที่ผ่านการตรวจทั้งหมด (เรียงตาม id) แต่ละห้อง = room.json + "dir" · จำผลไว้ต่อราก
static func list(from: String = "") -> Array[Dictionary]:
	var r := from if from != "" else root()
	if _cache.has(r):
		return _cache[r]
	var out: Array[Dictionary] = []
	var d := DirAccess.open(r)
	if d != null:
		var names := Array(d.get_directories())
		names.sort()
		for n: String in names:
			var dir := r.path_join(n)
			var path := dir.path_join("room.json")
			if not FileAccess.file_exists(path):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			var errs := validate(data, dir)
			if not errs.is_empty():
				push_warning("pack room %s skipped: %s" % [dir, "; ".join(errs)])
				continue
			var room: Dictionary = (data as Dictionary).duplicate(true)
			room["dir"] = dir
			out.append(room)
	_cache[r] = out
	return out


## ห้องแรกของประตู door ที่สวิตช์ฟีเจอร์เปิดอยู่ ({} = ไม่มี ดาดฟ้าเหมือนเดิม)
static func for_door(door: String, from: String = "") -> Dictionary:
	if not DOORS.has(door) or not Features.on(DOOR_FEATURE[door]):
		return {}
	for room in list(from):
		if str(room["door"]) == door:
			return room
	return {}


static func reset() -> void:
	_cache.clear()
	test_root = ""


## ข้อความจากคู่ {th, en} ตามภาษาที่ใช้อยู่
static func text(pair: Variant) -> String:
	if not pair is Dictionary:
		return ""
	var en := false
	var loop := Engine.get_main_loop() as SceneTree
	var i18n: Node = loop.root.get_node_or_null(^"I18n") if loop != null else null
	if i18n != null:
		en = bool(i18n.get("english"))
	return str((pair as Dictionary).get("en" if en else "th", ""))


## ชื่อเมธอดบังคับที่ node ไม่มี (ว่าง = ครบ)
static func missing_api(node: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for m in ROOM_API:
		if node == null or not node.has_method(m):
			out.append(m)
	return out


## สถานีแรกที่พาไปหน้าเล่นกับเพื่อน (action online หรือโต๊ะการ์ดที่มีการ์ด online) "" = ไม่มี
static func online_station(room: Dictionary) -> String:
	for s: Dictionary in room.get("stations", []):
		if str(s.get("action", "")) == "online":
			return str(s["id"])
		if str(s.get("action", "")) == "cards":
			for c: Dictionary in s.get("cards", []):
				if str(c.get("action", "")) == "online":
					return str(s["id"])
	return ""


## ชื่อที่เลือกที่นั่งในห้อง (ข้อความ "เจ้าห้องกำลังตั้งเกม"): สถานีของ online_station ไม่มีใช้ชื่อห้อง
static func setup_place(room: Dictionary) -> String:
	var id := online_station(room)
	for s: Dictionary in room.get("stations", []):
		if str(s.get("id", "")) == id:
			return text(s.get("name"))
	return text(room.get("title"))


# ---- แถบห้องของท่า (presence) ----

static func to_band(x: float) -> float:
	return x + POSE_X


static func from_band(x: float) -> float:
	return x - POSE_X


## ท่าจากเครือข่าย (x เป็นซม.) อยู่ในแถบห้องไหม
static func in_band(pose: Dictionary) -> bool:
	return int(pose.get("x", 0)) >= roundi(BAND_X * 100.0)


# ---- ตรวจ room.json (รูปแบบ 1) ----

## ข้อผิดพลาดของห้อง (ภาษาอังกฤษ บรรทัดละเรื่อง) ว่าง = ใช้ได้; data = room.json ที่ parse แล้ว, dir = โฟลเดอร์ของห้อง
static func validate(data: Variant, dir: String) -> PackedStringArray:
	var e := PackedStringArray()
	if not data is Dictionary:
		e.append("room.json is not a JSON object")
		return e
	var d: Dictionary = data
	if not _num(d.get("format")) or int(d["format"]) != FORMAT:
		e.append("format must be %d" % FORMAT)
		return e
	var id := str(d.get("id", ""))
	if not _id_ok(id):
		e.append("id must match ^[a-z][a-z0-9_]{0,23}$")
	elif id != dir.get_file():
		e.append("id %s is not the folder name %s" % [id, dir.get_file()])
	if not DOORS.has(str(d.get("door", ""))):
		e.append("door must be one of %s" % ", ".join(DOORS))
	_pair(e, d.get("title"), "title", 40)
	_pair(e, d.get("door_sign"), "door_sign", 48)
	_script(e, d.get("script"), dir)
	var half := _vec(d.get("half"), 2)
	if half.is_empty() or half[0] < MIN_HALF.x or half[0] > MAX_HALF.x or half[1] < MIN_HALF.y or half[1] > MAX_HALF.y:
		e.append("half must be [x, z] with x in [4, 15] and z in [4, 20]")
		return e
	var hv := Vector2(half[0], half[1])
	if not _num(d.get("ceil")) or float(d["ceil"]) < 3.5 or float(d["ceil"]) > 14.0:
		e.append("ceil must be in [3.5, 14]")
	if d.has("bg") and not (d["bg"] is String and _hex6(str(d["bg"]))):
		e.append("bg must be a 6-digit hex colour")
	var st: Variant = d.get("stations")
	if not st is Array or (st as Array).is_empty() or (st as Array).size() > 8:
		e.append("stations must hold 1 to 8 entries")
		return e
	var ids := {}
	var backs := 0
	var foot: Array[Dictionary] = []
	for s: Variant in st:
		var n := e.size()
		_station(e, s, hv, ids)
		if e.size() == n:
			foot.append(s)
			if str((s as Dictionary)["action"]) == "back":
				backs += 1
	if backs != 1 and e.is_empty():
		e.append("exactly one station must have action back (found %d)" % backs)
	if not e.is_empty():
		return e
	# ตำแหน่งที่ต้องไม่ติด: จุดเกิด และวงแหวนหน้าสถานี (เทียบกับรอยเท้าสถานี ตัวกันของสคริปต์ตรวจตอนเปิด)
	var lay := RoomLayout.new(d)
	var spawn := _vec(d.get("spawn"), 3)
	if spawn.is_empty():
		e.append("spawn must be [x, z, yaw]")
	else:
		var p := Vector2(spawn[0], spawn[1])
		if lay.blocked(p, HallLayout.AVATAR_R):
			e.append("spawn (%.2f, %.2f) is blocked or outside the room" % [p.x, p.y])
		elif lay.station_at(p) != "":
			e.append("spawn is within the reach of station %s" % lay.station_at(p))
	for s: Dictionary in foot:
		var f := Vector2(float(s["front"][0]), float(s["front"][1]))
		if lay.blocked(f, HallLayout.AVATAR_R):
			e.append("station %s: front is blocked or outside the room" % str(s["id"]))
		elif lay.dist_to_station(f, str(s["id"])) > float(s["reach"]):
			e.append("station %s: front is out of its reach" % str(s["id"]))
	return e


static func _station(e: PackedStringArray, s: Variant, half: Vector2, ids: Dictionary) -> void:
	if not s is Dictionary:
		e.append("a station is not an object")
		return
	var d: Dictionary = s
	var id := str(d.get("id", ""))
	var tag := "station " + id
	if not _id_ok(id):
		e.append("station id %s must match ^[a-z][a-z0-9_]{0,23}$" % id)
		return
	if ids.has(id):
		e.append("station id %s is used twice" % id)
		return
	ids[id] = true
	_pair(e, d.get("name"), tag + " name", 32)
	var c := _vec(d.get("c"), 2)
	var h := _vec(d.get("h"), 2)
	var f := _vec(d.get("front"), 2)
	if c.is_empty() or h.is_empty() or f.is_empty() or h[0] <= 0.0 or h[1] <= 0.0:
		e.append(tag + ": c, h and front must be [x, z] (h > 0)")
		return
	var round_ := bool(d.get("round", false))
	var ext := Vector2(h[0], h[0] if round_ else h[1])
	# รอยเท้าเข้าไปในผนังได้ (ประตูแบบประตูทางออกของดาดฟ้า) แต่ไม่เลยผนัง
	var lim := half + Vector2(HallLayout.WALL_T, HallLayout.WALL_T)
	if absf(c[0]) + ext.x > lim.x + 0.001 or absf(c[1]) + ext.y > lim.y + 0.001:
		e.append(tag + ": footprint leaves the room")
	if not _num(d.get("height")) or float(d["height"]) < 0.1 or float(d["height"]) > 14.0:
		e.append(tag + ": height must be in [0.1, 14]")
	if not _num(d.get("reach")) or float(d["reach"]) < 0.8 or float(d["reach"]) > 2.5:
		e.append(tag + ": reach must be in [0.8, 2.5]")
	if d.has("sign") and _vec(d["sign"], 3).is_empty():
		e.append(tag + ": sign must be [x, y, z]")
	if d.has("face") and not _num(d["face"]):
		e.append(tag + ": face must be a number")
	var act := str(d.get("action", ""))
	if not ACTIONS.has(act):
		e.append(tag + ": action must be one of %s" % ", ".join(ACTIONS))
		return
	if act == "soon":
		_pair(e, d.get("soon"), tag + " soon", 120)
	elif act == "cards":
		var cards: Variant = d.get("cards")
		if not cards is Array or (cards as Array).is_empty() or (cards as Array).size() > 4:
			e.append(tag + ": cards must hold 1 to 4 entries")
		else:
			for card: Variant in cards:
				if not card is Dictionary:
					e.append(tag + ": a card is not an object")
					continue
				_pair(e, card.get("title"), tag + " card title", 24)
				_pair(e, card.get("text"), tag + " card text", 80)
				var ca := str(card.get("action", ""))
				if not CARD_ACTIONS.has(ca):
					e.append(tag + ": card action must be soon or online")
				elif ca == "soon":
					_pair(e, card.get("soon"), tag + " card soon", 120)
	if d.has("walk_in") and (not d["walk_in"] is bool or (bool(d["walk_in"]) and act != "back")):
		e.append(tag + ": walk_in is a bool and only on the back station")
	if d.has("solid") and not d["solid"] is bool:
		e.append(tag + ": solid must be a bool")


static func _pair(e: PackedStringArray, p: Variant, what: String, cap: int) -> void:
	if not p is Dictionary:
		e.append(what + " must be {th, en}")
		return
	for k in ["th", "en"]:
		var v: Variant = (p as Dictionary).get(k)
		if not v is String or str(v).strip_edges() == "":
			e.append("%s needs a non-empty %s" % [what, k])
		elif str(v).length() > cap:
			e.append("%s %s is longer than %d characters" % [what, k, cap])
	var en: Variant = (p as Dictionary).get("en")
	if en is String and _has_thai(str(en)):
		e.append(what + " en has Thai letters")


static func _script(e: PackedStringArray, s: Variant, dir: String) -> void:
	if not s is String or not str(s).ends_with(".gd") or str(s).contains("..") or str(s).begins_with("res://") \
			or str(s).begins_with("/") or str(s).contains(":") or str(s).contains("\\"):
		e.append("script must be a relative .gd path inside the room folder")
		return
	var path := dir.path_join(str(s))
	if not ResourceLoader.exists(path):
		e.append("script %s does not exist" % str(s))
		return
	var sc := load(path) as Script
	if sc == null or not sc.can_instantiate():
		e.append("script %s does not load" % str(s))
		return
	if not ClassDB.is_parent_class(sc.get_instance_base_type(), &"Node3D"):
		e.append("script %s must extend Node3D" % str(s))
		return
	var have := {}
	var cur: Script = sc
	while cur != null:
		for m: Dictionary in cur.get_script_method_list():
			have[str(m["name"])] = true
		cur = cur.get_base_script()
	var miss := PackedStringArray()
	for m in ROOM_API:
		if not have.has(m):
			miss.append(m)
	if not miss.is_empty():
		e.append("script %s lacks %s" % [str(s), ", ".join(miss)])


static func _id_ok(id: String) -> bool:
	if id.length() < 1 or id.length() > 24:
		return false
	for i in id.length():
		var ch := id.unicode_at(i)
		var low := ch >= 97 and ch <= 122
		if i == 0 and not low:
			return false
		if not (low or (ch >= 48 and ch <= 57) or ch == 95):
			return false
	return true


static func _hex6(s: String) -> bool:
	if s.length() != 6:
		return false
	# is_valid_hex_number รับเครื่องหมายนำหน้า: ตรวจทีละตัว
	for ch in s.to_lower():
		if not "0123456789abcdef".contains(ch):
			return false
	return true


static func _has_thai(s: String) -> bool:
	for i in s.length():
		var ch := s.unicode_at(i)
		if ch >= 0x0E00 and ch <= 0x0E7F:
			return true
	return false


static func _num(v: Variant) -> bool:
	return v is float or v is int


## อาร์เรย์ตัวเลขยาว n เป็น PackedFloat64Array (ผิดรูป = ว่าง)
static func _vec(v: Variant, n: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if not v is Array or (v as Array).size() != n:
		return out
	for x: Variant in v:
		if not _num(x):
			return PackedFloat64Array()
		out.append(float(x))
	return out
