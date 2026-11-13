class_name RoomLayout
extends RefCounted
## ผังของห้องเสริมหนึ่งห้อง (PACK_SPEC §9) สร้างจาก room.json ที่ผ่าน PackRooms.validate แล้ว
## ที่กันรูปแบบเดียวกับ HallLayout.blockers(): ผนังสี่ด้าน + เพดานล่องหน (นอกกล่องด้านใน) รอยเท้าสถานี (ยกเว้น solid false)
## แล้วของเพิ่มจากสคริปต์ห้อง · คณิตกล้อง/ชนใช้ตัวช่วยของ HallLayout ชุดเดียวกัน

const CAM_PAD := HallLayout.CAM_PAD
const WALL_T := HallLayout.WALL_T
const OCCLUDE_HALF := 0.75

var half := Vector2(6.0, 6.0)
var ceil_y := 5.0
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var ids := PackedStringArray()
## id → {c: Vector2, h: Vector2, round, height, reach, front: Vector2, sign (Vector3 หรือ null), face, action, walk_in, data}
var stations: Dictionary = {}

var _blockers: Array[Dictionary] = []
var _props: Array[Dictionary] = []


func _init(room: Dictionary = {}, extra: Array = []) -> void:
	if room.is_empty():
		return
	half = _v2(room.get("half"), half)
	ceil_y = float(room.get("ceil", ceil_y))
	var sp: Variant = room.get("spawn")
	if sp is Array and (sp as Array).size() == 3:
		spawn = Vector3(float(sp[0]), 0.0, float(sp[1]))
		spawn_yaw = float(sp[2])
	for s: Variant in room.get("stations", []):
		if not s is Dictionary:
			continue
		var d: Dictionary = s
		var id := str(d.get("id", ""))
		var sign: Variant = null
		if d.get("sign") is Array and (d["sign"] as Array).size() == 3:
			sign = Vector3(float(d["sign"][0]), float(d["sign"][1]), float(d["sign"][2]))
		ids.append(id)
		stations[id] = {"c": _v2(d.get("c"), Vector2.ZERO), "h": _v2(d.get("h"), Vector2(0.5, 0.5)),
			"round": bool(d.get("round", false)), "height": float(d.get("height", 1.0)), "reach": float(d.get("reach", 1.5)),
			"front": _v2(d.get("front"), Vector2.ZERO), "sign": sign, "face": float(d.get("face", 0.0)),
			"action": str(d.get("action", "")), "walk_in": bool(d.get("walk_in", false)),
			"solid": bool(d.get("solid", true)), "data": d}
	_build(extra)


## ที่กันทั้งหมด (ผนัง เพดาน รอยเท้าสถานี ของจากสคริปต์)
func blockers() -> Array[Dictionary]:
	return _blockers


## ของสคริปต์ที่ผิดกฎ (ไม่มีป้าย ขนาด ≤ 0 นอกห้อง หรือใช้ป้ายผนัง/เพดาน) เป็นข้อความภาษาอังกฤษ; ว่าง = ใช้ได้
static func extra_problems(room_half: Vector2, extra: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for b: Variant in extra:
		if not b is Dictionary:
			out.append("a blocker is not an object")
			continue
		var d: Dictionary = b
		# ป้าย tag ต้องเป็นข้อความไม่ว่าง (ตัวชนและ blocker_at อ่าน b["tag"] ตรง ๆ)
		if not d.get("tag") is String or str(d["tag"]) == "":
			out.append("a blocker has no tag")
			continue
		var tag := str(d["tag"])
		if tag == "ceiling" or tag.begins_with("wall_"):
			out.append("blocker %s uses a shell tag" % tag)
			continue
		if str(d.get("kind", "")) == "box" and d.get("c") is Vector3 and d.get("h") is Vector3:
			var c: Vector3 = d["c"]
			var h: Vector3 = d["h"]
			if h.x <= 0.0 or h.y <= 0.0 or h.z <= 0.0:
				out.append("blocker %s has a box size <= 0" % tag)
			elif absf(c.x) + h.x > room_half.x + 0.001 or absf(c.z) + h.z > room_half.y + 0.001:
				out.append("blocker %s leaves the room" % tag)
		elif str(d.get("kind", "")) == "cyl" and d.get("c") is Vector2:
			var cc: Vector2 = d["c"]
			var r := float(d.get("r", 0.0))
			if absf(cc.x) + r > room_half.x + 0.001 or absf(cc.y) + r > room_half.y + 0.001 or r <= 0.0 \
					or float(d.get("y1", 0.0)) <= float(d.get("y0", 0.0)):
				out.append("blocker %s leaves the room" % tag)
		else:
			out.append("blocker %s has a bad kind or shape" % tag)
	return out


## จุดเกิดหรือหน้าสถานีที่ติดของ (รวมตัวกันของสคริปต์) เป็นข้อความภาษาอังกฤษ; ว่าง = เดินได้
func clear_problems() -> PackedStringArray:
	var out := PackedStringArray()
	var sp := Vector2(spawn.x, spawn.z)
	if blocked(sp, HallLayout.AVATAR_R):
		out.append("spawn is blocked by %s" % blocker_at(sp, HallLayout.AVATAR_R))
	for id in ids:
		var f: Vector2 = stations[id]["front"]
		if blocked(f, HallLayout.AVATAR_R):
			out.append("the front of %s is blocked by %s" % [id, blocker_at(f, HallLayout.AVATAR_R)])
	return out


func rect_of(id: String) -> Rect2:
	var s: Dictionary = stations[id]
	var c: Vector2 = s["c"]
	var h: Vector2 = s["h"]
	if bool(s["round"]):
		h = Vector2(h.x, h.x)
	return Rect2(c - h, h * 2.0)


func dist_to_station(p: Vector2, id: String) -> float:
	return HallLayout.dist_to_rect(p, rect_of(id))


## สถานีที่ตัวผู้เล่น (กลางตัวที่ p) เอื้อมถึง; หลายจุดเอาที่ใกล้สุด; ไม่มีคืน ""
func station_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in ids:
		var d := dist_to_station(p, id)
		if d <= float(stations[id]["reach"]) and d < best_d:
			best = id
			best_d = d
	return best


## เดินชนรอยเท้าของสถานี id แล้ว (ประตูที่เดินเข้า walk_in เหมือนประตูอารีน่า)
func in_walk_in(id: String, p: Vector2) -> bool:
	if not stations.has(id):
		return false
	return dist_to_station(p, id) <= HallLayout.AVATAR_R + HallLayout.ARENA_AUTO


func blocked(p: Vector2, r: float) -> bool:
	return blocker_at(p, r) != ""


func blocker_at(p: Vector2, r: float) -> String:
	if absf(p.x) > half.x - r or absf(p.y) > half.y - r:
		return "wall"
	for b in _blockers:
		if HallLayout.hits_circle(b, p, r):
			return str(b["tag"])
	return ""


## เหมือน HallLayout.room_clear แต่ใช้ขนาดห้องนี้
func room_clear(o: Vector3, d: Vector3, r: float) -> float:
	var t := INF
	if d.x > 0.0001:
		t = minf(t, (half.x - r - o.x) / d.x)
	elif d.x < -0.0001:
		t = minf(t, (-half.x + r - o.x) / d.x)
	if d.z > 0.0001:
		t = minf(t, (half.y - r - o.z) / d.z)
	elif d.z < -0.0001:
		t = minf(t, (-half.y + r - o.z) / d.z)
	if d.y > 0.0001:
		t = minf(t, (ceil_y - r - o.y) / d.y)
	return maxf(t, 0.0)


## เหมือน HallLayout.camera_clear แต่ใช้ของในห้องนี้ · ของใหญ่ (ครึ่งกว้าง ≥ OCCLUDE_HALF ทั้งสองแกน) ที่บังแนวดึงกล้องมาหน้าของ
## (ห้องเสริมมีของใหญ่ชิดผนัง กล้องที่ทะลุไปจอดหลังของจะเห็นแต่ของ) · เสา/ลังเล็กยังผ่านได้เหมือนดาดฟ้า
func camera_clear(o: Vector3, d: Vector3, length: float, pad: float = CAM_PAD, far: float = 0.0) -> float:
	var t := length
	for _i in 8:
		var moved := false
		for b in _props:
			var span := HallLayout.ray_span(b, o, d, pad)
			if span.x > 0.0 and t > span.x and t < span.y:
				t = span.y if far > 0.0 and span.y <= far and span.y - t < t - span.x and not occludes(b) else span.x
				moved = true
			elif span.x > 0.0 and span.x < span.y and span.y <= t and occludes(b):
				t = span.x
				moved = true
		if not moved:
			return t
	return camera_clear(o, d, length, pad) if far > 0.0 else t


## ของที่ใหญ่พอจะบังตัวละครทั้งตัว (ใช้ใน camera_clear)
static func occludes(b: Dictionary) -> bool:
	if str(b["kind"]) == "cyl":
		return float(b["r"]) >= OCCLUDE_HALF
	var h: Vector3 = b["h"]
	return h.x >= OCCLUDE_HALF and h.z >= OCCLUDE_HALF


# ---- ภายใน ----

func _build(extra: Array) -> void:
	var hx := half.x + WALL_T
	var hz := half.y + WALL_T
	var wy := ceil_y * 0.5
	_blockers.append({"kind": "box", "c": Vector3(0.0, wy, -half.y - WALL_T * 0.5), "h": Vector3(hx, wy, WALL_T * 0.5), "tag": "wall_back"})
	_blockers.append({"kind": "box", "c": Vector3(0.0, wy, half.y + WALL_T * 0.5), "h": Vector3(hx, wy, WALL_T * 0.5), "tag": "wall_front"})
	_blockers.append({"kind": "box", "c": Vector3(-half.x - WALL_T * 0.5, wy, 0.0), "h": Vector3(WALL_T * 0.5, wy, hz), "tag": "wall_left"})
	_blockers.append({"kind": "box", "c": Vector3(half.x + WALL_T * 0.5, wy, 0.0), "h": Vector3(WALL_T * 0.5, wy, hz), "tag": "wall_right"})
	_blockers.append({"kind": "box", "c": Vector3(0.0, ceil_y + WALL_T * 0.5, 0.0), "h": Vector3(hx, WALL_T * 0.5, hz), "tag": "ceiling"})
	for id in ids:
		var s: Dictionary = stations[id]
		if not bool(s["solid"]):
			continue
		var c: Vector2 = s["c"]
		var h: Vector2 = s["h"]
		var top := float(s["height"])
		if bool(s["round"]):
			_blockers.append({"kind": "cyl", "c": c, "r": h.x, "y0": 0.0, "y1": top, "tag": id})
		else:
			_blockers.append({"kind": "box", "c": Vector3(c.x, top * 0.5, c.y), "h": Vector3(h.x, top * 0.5, h.y), "tag": id})
	if extra_problems(half, extra).is_empty():
		for b: Dictionary in extra:
			_blockers.append(b)
	for b in _blockers:
		if not HallLayout.is_shell(b):
			_props.append(b)


static func _v2(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback
