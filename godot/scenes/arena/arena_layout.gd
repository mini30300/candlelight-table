class_name ArenaLayout
extends RefCounted
## ผังอารีน่าทดสอบอาวุธ (ARENA_SPEC §4): ข้อมูลล้วน ไม่มีโหนด ไม่มีข้อความบนจอ แบบเดียวกับ HallLayout
## หน่วยเมตร y ชี้ขึ้น · ทางเดินเริ่มที่ประตูดาดฟ้า z = 0 ไปทาง -z (กล้องเริ่มที่ yaw 0 มอง -z)
## ทางเดิน x ∈ [-1.3, 1.3], z ∈ [-10, 0] สูง 4.6 · ผนังหน้าห้องหนา 0.5 มีช่องโค้งกว้าง 2 ม. · ห้อง x ∈ [-10, 10], z ∈ [-34.5, -10.5]
## ที่กันทุกชิ้นมาจากที่นี่ (ตัวชน เทสเดินทั่วห้อง ทางเดินของสัตว์รัง) layer "shell" = แขนกล้องชน, "prop" = ไม่ชน

const ROOM_MIN := Vector2(-10.0, -34.5)
const ROOM_MAX := Vector2(10.0, -10.5)
const ROOM_H := 7.0                      # เพดานที่วาด
const CEIL_Y := 6.5                      # เพดานล่องหน (ตัวชน กล้องขึ้นไปไม่ถึง)
const WALL_T := 0.5
const CORR_X := 1.3                      # ครึ่งกว้างทางเดิน
const CORR_Z0 := 0.0
const CORR_Z1 := -10.0
const CORR_H := 4.6
const AVATAR_R := 0.35
## ประตูกลับดาดฟ้า (ที่กันปลายทางเดิน): กลาง (x, z) ครึ่งขนาด ความสูง
const DOOR_BACK := {"c": Vector2(0.0, -0.15), "h": Vector2(1.3, 0.15), "height": 4.6}
## ช่องโค้งในผนังหน้าห้อง (z -10.0 ถึง -10.5) · ตัวชนเหนือช่องเป็นกล่องเรียบตั้งแต่ LINTEL_Y
const ARCH := {"x0": -1.0, "x1": 1.0, "spring": 2.8, "apex": 4.0}
const LINTEL_Y := 3.4
const SPAWN := Vector3(0.0, 0.0, -3.6)             # ห่างประตู 3.3 ม.: แขนกล้องตามยาวราว 3.2 ม. ไข่ไม่บังจอตอนเริ่ม
const SPAWN_FACE := PI
const SPAWN_YAW := 0.0
const SPAWN_PITCH := -0.25               # เงยกว่ากล้องเดินปกติ (−0.35): ป้ายเหนือช่องโค้งเข้าอารีน่าอยู่ในจอตั้งแต่เริ่ม
const SPAWN_ARM := 4.5
const LEAVE_Z := -0.95                   # โหมดเดิน: กลางตัวที่ z ≥ ค่านี้ = กลับดาดฟ้า (ประตูหยุดตัวที่ -0.65)
const SHOOT_Z := -11.3                   # เลยเส้นนี้ (z น้อยกว่า) = โหมดยิง
const WALK_Z := -10.8                    # กลับขึ้นมาเกินเส้นนี้ = โหมดเดิน (ห่างกัน 0.5 ม. กันสลับไปมา)
const RESPAWN := Vector3(0.0, 0.0, -12.5)
const BEAST_SPAWN := Vector3(0.0, 0.0, -29.0)
const BEAST_FACE := 0.0
const PAD_R := 1.6
## เสากำบังแปดเหลี่ยม · ช่องกลาง |x| < 2.4 โล่งจากเส้นยิงถึงแท่น
const PILLAR_R := 0.8
const PILLAR_H := 4.0
const PILLARS: PackedVector2Array = [Vector2(-4.5, -18.5), Vector2(4.5, -18.5), Vector2(-3.2, -24.5), Vector2(3.2, -24.5)]
const LANE_X := 2.4
## เชิงเทียนสองข้างช่องโค้ง (แบบดาดฟ้า) เทียนเล่มเดียว
const STAND_R := 0.28
const STAND_H := 1.72
const STANDS: PackedVector2Array = [Vector2(-2.4, -11.2), Vector2(2.4, -11.2)]
const STAND_FLAME_Y := 1.98
## เส้นระยะบนพื้นทุก 5 ม.
const RANGE_LINES: PackedFloat32Array = [-16.3, -21.3, -26.3, -31.3]

const IDS: PackedStringArray = ["switch", "reset"]
## จุดใช้งาน: c = กลาง (x, z), round = เสากลม (รัศมี r) ไม่งั้นกล่อง (ครึ่งขนาด h), height, reach = ระยะเอื้อมจากขอบ,
## front = วงแหวนหน้า, sign = ป้าย, face = yaw ของป้าย · สวิตช์: plate = แผ่นเป้ากลม, beacon = โคมเหนือเสา
## รีเซ็ต: button = ยอดปุ่มเห็ด
const STATIONS := {
	"switch": {"c": Vector2(6.5, -13.5), "round": true, "r": 0.35, "h": Vector2(0.35, 0.35), "height": 2.4, "reach": 1.5,
		"front": Vector2(5.3, -13.5), "plate": Vector3(6.5, 2.1, -13.5), "plate_r": 0.45,
		"sign": Vector3(6.5, 2.95, -13.5), "face": -PI * 0.5, "beacon": Vector3(6.5, 2.7, -13.5)},
	"reset": {"c": Vector2(-6.5, -13.5), "round": false, "r": 0.35, "h": Vector2(0.35, 0.35), "height": 1.1, "reach": 1.5,
		"front": Vector2(-5.3, -13.5), "button": Vector3(-6.5, 1.18, -13.5),
		"sign": Vector3(-6.5, 1.95, -13.5), "face": PI * 0.5},
}
## กระดานสถานะบนผนังไกล: แผ่น (กลาง กว้าง สูง) ข้อความหัว ข้อความเนื้อ
const BOARD := {"c": Vector3(0.0, 4.6, -34.45), "w": 6.4, "h": 3.0}
const BOARD_TITLE := Vector3(0.0, 5.65, -34.38)
const BOARD_BODY := Vector3(0.0, 4.3, -34.38)
## ป้าย 3 มิติ: ตำแหน่ง, yaw (Label3D หันหน้า +z ตอน yaw 0)
const SIGNS := {
	"door_back": {"p": Vector3(0.0, 3.3, -0.32), "face": PI},
	"door_arena": {"p": Vector3(0.0, 4.25, -9.97), "face": 0.0},
	"switch": {"p": Vector3(6.5, 2.95, -13.5), "face": -PI * 0.5},
	"reset": {"p": Vector3(-6.5, 1.95, -13.5), "face": PI * 0.5},
	"board_title": {"p": Vector3(0.0, 5.65, -34.38), "face": 0.0},
	"board_body": {"p": Vector3(0.0, 4.3, -34.38), "face": 0.0},
}
const SCREEN_GREEN := Color("7dffa6")
const SCREEN_AMBER := Color("ffbb55")
const HAZARD := Color("d9a521")
const FLOOD := Color("dfe8ff")
## แสงเย็นที่อบลงสีจุดยอด (แบบ HallLayout.COOL_LIGHTS): ไฟสาดหกดวง ไฟแถบทางเดิน กระดาน แท่นสัตว์รัง
const LIGHTS := [
	{"p": Vector3(-5.0, 6.6, -15.0), "k": 0.55, "d": 40.0, "col": FLOOD},
	{"p": Vector3(5.0, 6.6, -15.0), "k": 0.55, "d": 40.0, "col": FLOOD},
	{"p": Vector3(-5.0, 6.6, -22.0), "k": 0.55, "d": 40.0, "col": FLOOD},
	{"p": Vector3(5.0, 6.6, -22.0), "k": 0.55, "d": 40.0, "col": FLOOD},
	{"p": Vector3(-5.0, 6.6, -29.0), "k": 0.55, "d": 40.0, "col": FLOOD},
	{"p": Vector3(5.0, 6.6, -29.0), "k": 0.55, "d": 40.0, "col": FLOOD},
	{"p": Vector3(0.0, 4.3, -2.0), "k": 0.45, "d": 3.0, "col": SCREEN_AMBER},
	{"p": Vector3(0.0, 4.3, -4.5), "k": 0.45, "d": 3.0, "col": SCREEN_AMBER},
	{"p": Vector3(0.0, 4.3, -7.0), "k": 0.45, "d": 3.0, "col": SCREEN_AMBER},
	{"p": Vector3(0.0, 4.3, -9.5), "k": 0.45, "d": 3.0, "col": SCREEN_AMBER},
	{"p": Vector3(0.0, 4.6, -33.8), "k": 0.4, "d": 6.0, "col": SCREEN_GREEN},
	{"p": Vector3(0.0, 0.3, -29.0), "k": 0.3, "d": 3.0, "col": HAZARD},
]
## ไฟสาดบนเพดาน (โคมสว่างไม่อบแสง) ตรงกับหกดวงแรกของ LIGHTS
const FLOODS: PackedVector3Array = [Vector3(-5.0, 6.95, -15.0), Vector3(5.0, 6.95, -15.0), Vector3(-5.0, 6.95, -22.0),
	Vector3(5.0, 6.95, -22.0), Vector3(-5.0, 6.95, -29.0), Vector3(5.0, 6.95, -29.0)]


## ที่กันทั้งหมดแบบ HallLayout.blockers() + "layer": {"kind": "box", "c": Vector3, "h": Vector3, "tag", "layer"}
## หรือ {"kind": "cyl", "c": Vector2, "r", "y0", "y1", "tag", "layer"}
static func blockers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := WALL_T
	var hy := ROOM_H * 0.5
	var zc := (ROOM_MIN.y + ROOM_MAX.y) * 0.5
	var hz := (ROOM_MAX.y - ROOM_MIN.y) * 0.5 + t
	var hx := ROOM_MAX.x + t
	var zn := ROOM_MAX.y + t * 0.5
	var ax0 := float(ARCH["x0"])
	var ax1 := float(ARCH["x1"])
	out.append(_box(Vector3(0.0, hy, ROOM_MIN.y - t * 0.5), Vector3(hx, hy, t * 0.5), "wall_far", "shell"))
	out.append(_box(Vector3(ROOM_MIN.x - t * 0.5, hy, zc), Vector3(t * 0.5, hy, hz), "wall_left", "shell"))
	out.append(_box(Vector3(ROOM_MAX.x + t * 0.5, hy, zc), Vector3(t * 0.5, hy, hz), "wall_right", "shell"))
	out.append(_box(Vector3((-hx + ax0) * 0.5, hy, zn), Vector3((ax0 + hx) * 0.5, hy, t * 0.5), "wall_near_left", "shell"))
	out.append(_box(Vector3((hx + ax1) * 0.5, hy, zn), Vector3((hx - ax1) * 0.5, hy, t * 0.5), "wall_near_right", "shell"))
	out.append(_box(Vector3((ax0 + ax1) * 0.5, (LINTEL_Y + ROOM_H) * 0.5, zn), Vector3((ax1 - ax0) * 0.5, (ROOM_H - LINTEL_Y) * 0.5, t * 0.5),
		"lintel", "shell"))
	out.append(_box(Vector3(0.0, CEIL_Y + t * 0.5, zc), Vector3(hx, t * 0.5, hz), "ceiling", "shell"))
	var cz := (CORR_Z0 + CORR_Z1) * 0.5
	var chz := (CORR_Z0 - CORR_Z1) * 0.5
	for sx in [-1.0, 1.0]:
		out.append(_box(Vector3(sx * (CORR_X + t * 0.5), CORR_H * 0.5, cz), Vector3(t * 0.5, CORR_H * 0.5, chz),
			"corr_left" if sx < 0.0 else "corr_right", "shell"))
	out.append(_box(Vector3(0.0, CORR_H + t * 0.5, cz), Vector3(CORR_X + t, t * 0.5, chz), "corr_ceiling", "shell"))
	var dc: Vector2 = DOOR_BACK["c"]
	var dh: Vector2 = DOOR_BACK["h"]
	var dy := float(DOOR_BACK["height"])
	out.append(_box(Vector3(dc.x, dy * 0.5, dc.y), Vector3(dh.x, dy * 0.5, dh.y), "door_back", "shell"))
	for i in PILLARS.size():
		out.append({"kind": "cyl", "c": PILLARS[i], "r": PILLAR_R, "y0": 0.0, "y1": PILLAR_H, "tag": "pillar_%d" % i, "layer": "shell"})
	for i in STANDS.size():
		out.append({"kind": "cyl", "c": STANDS[i], "r": STAND_R, "y0": 0.0, "y1": STAND_H, "tag": "stand_%d" % i, "layer": "prop"})
	for id in IDS:
		var s: Dictionary = STATIONS[id]
		var c: Vector2 = s["c"]
		var top := float(s["height"])
		if bool(s["round"]):
			out.append({"kind": "cyl", "c": c, "r": float(s["r"]), "y0": 0.0, "y1": top, "tag": id, "layer": "prop"})
		else:
			var h: Vector2 = s["h"]
			out.append(_box(Vector3(c.x, top * 0.5, c.y), Vector3(h.x, top * 0.5, h.y), id, "prop"))
	return out


static func _box(c: Vector3, h: Vector3, tag: String, layer: String) -> Dictionary:
	return {"kind": "box", "c": c, "h": h, "tag": tag, "layer": layer}


static func is_shell(b: Dictionary) -> bool:
	return str(b.get("layer", "")) == "shell"


static func room_rect() -> Rect2:
	return Rect2(ROOM_MIN, ROOM_MAX - ROOM_MIN)


## จุด (x, z) อยู่ในห้องอารีน่า
static func in_room(p: Vector2) -> bool:
	return p.x >= ROOM_MIN.x and p.x <= ROOM_MAX.x and p.y >= ROOM_MIN.y and p.y <= ROOM_MAX.y


## จุด (x, z) อยู่ในทางเดิน (รวมช่องโค้งในผนังหน้าห้อง)
static func in_corridor(p: Vector2) -> bool:
	if absf(p.x) <= CORR_X and p.y <= CORR_Z0 and p.y >= CORR_Z1:
		return true
	return p.x >= float(ARCH["x0"]) and p.x <= float(ARCH["x1"]) and p.y < CORR_Z1 and p.y > ROOM_MAX.y


## โหมดตาม z ของกลางตัว (เปลี่ยนเมื่อเลยเส้นเท่านั้น: เส้นเข้าโหมดยิงกับเส้นกลับโหมดเดินห่างกัน 0.5 ม.)
static func mode_for(z: float, current: StringName) -> StringName:
	if current == &"shoot":
		return &"walk" if z > WALK_Z else &"shoot"
	return &"shoot" if z < SHOOT_Z else &"walk"


## เดินกลับเข้าประตูดาดฟ้า (โหมดเดินเท่านั้น)
static func leaving(z: float, mode: StringName) -> bool:
	return mode == &"walk" and z >= LEAVE_Z


## ระยะจากจุด p ถึงขอบที่กันของจุดใช้งาน (0 เมื่ออยู่ข้างใน)
static func dist_to_station(p: Vector2, id: String) -> float:
	var s: Dictionary = STATIONS[id]
	var c: Vector2 = s["c"]
	if bool(s["round"]):
		return maxf(p.distance_to(c) - float(s["r"]), 0.0)
	var h: Vector2 = s["h"]
	return HallLayout.dist_to_rect(p, Rect2(c - h, h * 2.0))


## จุดใช้งานที่กลางตัว p (x, z) เอื้อมถึง ใกล้สุดชนะ; ไม่มีคืน ""
static func station_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in IDS:
		var d := dist_to_station(p, id)
		if d <= float(STATIONS[id]["reach"]) and d < best_d:
			best = id
			best_d = d
	return best


## วงกลมรัศมี r ที่ p (x, z) ชนอะไรไหม (ผนังด้วย ไม่นับเพดานกับคานเหนือช่องโค้ง) หรือหลุดออกนอกที่เดินได้
static func blocked(p: Vector2, r: float) -> bool:
	return blocker_at(p, r) != ""


## ชื่อที่กันที่วงกลมชน ("" = ไม่ชน, "outside" = นอกห้องและทางเดิน)
static func blocker_at(p: Vector2, r: float) -> String:
	if not (in_room(p) or in_corridor(p)):
		return "outside"
	for b in blockers():
		if _hits_circle(b, p, r):
			return str(b["tag"])
	return ""


## จุด 3 มิติ p อยู่ในของแข็ง (ขยายออก margin) หรือหลุดออกนอกห้อง/ทางเดินไหม
static func inside_solid(p: Vector3, margin: float = 0.0) -> bool:
	var q := Vector2(p.x, p.z)
	if p.y < margin:
		return true
	if in_room(q):
		if p.y > CEIL_Y - margin:
			return true
	elif in_corridor(q):
		if p.y > CORR_H - margin:
			return true
	else:
		return true
	for b in blockers():
		if str(b["kind"]) == "box":
			var c: Vector3 = b["c"]
			var h: Vector3 = b["h"]
			if absf(p.x - c.x) <= h.x + margin and absf(p.y - c.y) <= h.y + margin and absf(p.z - c.z) <= h.z + margin:
				return true
		else:
			var cc: Vector2 = b["c"]
			if p.y >= float(b["y0"]) - margin and p.y <= float(b["y1"]) + margin and q.distance_to(cc) <= float(b["r"]) + margin:
				return true
	return false


static func _hits_circle(b: Dictionary, p: Vector2, r: float) -> bool:
	if str(b["kind"]) == "box":
		var c: Vector3 = b["c"]
		var h: Vector3 = b["h"]
		if c.y - h.y > 2.0:          # เพดาน คานเหนือช่องโค้ง: ตัวผู้เล่นเดินลอดได้
			return false
		return HallLayout.dist_to_rect(p, Rect2(c.x - h.x, c.z - h.z, h.x * 2.0, h.z * 2.0)) < r
	return p.distance_to(b["c"] as Vector2) < float(b["r"]) + r


## ฐานเปลวไฟสองดวงบนเชิงเทียน
static func flames() -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in STANDS:
		out.append(Vector3(s.x, STAND_FLAME_Y, s.y))
	return out


## ความสูงของโค้งแหลมในผนังหน้าห้องที่ x (0 นอกช่อง)
static func arch_top(x: float) -> float:
	var a := (float(ARCH["x1"]) - float(ARCH["x0"])) * 0.5
	var w := {"x0": -a, "x1": a, "spring": float(ARCH["spring"]), "apex": float(ARCH["apex"])}
	var dx := absf(x - (float(ARCH["x0"]) + float(ARCH["x1"])) * 0.5)
	if dx > a:
		return 0.0
	# หาความสูงที่ครึ่งกว้างของโค้งเท่ากับ dx (ไล่ทีละ 1 ซม.)
	var y := float(ARCH["apex"])
	while y > float(ARCH["spring"]) and HallLayout.window_half(w, y) < dx:
		y -= 0.01
	return y
