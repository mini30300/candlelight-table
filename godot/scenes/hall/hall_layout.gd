class_name HallLayout
extends RefCounted
## ผังดาดฟ้ายานรบ (ล็อบบี้ที่เดินได้, SHIP_LOBBY_SPEC §2): ข้อมูลล้วน ไม่มีโหนด ไม่มีข้อความบนจอ
## หน่วยเมตร y ชี้ขึ้น กล้องเริ่มมองไปทาง -z · ด้านในห้อง x ∈ [-12, 12], z ∈ [-8, 8] พื้นที่ y = 0
## เหนือ y = 6 (เพดานโค้ง หน้าต่างส่วนบน ป้ายชื่อ) วาดอย่างเดียว กล้องขึ้นไปไม่ถึง ไม่ต้องมีตัวชน
## จุดใช้งาน (station) = สี่เหลี่ยมรอยเท้า + ระยะเอื้อม: ตัวผู้เล่นอยู่ห่างขอบสี่เหลี่ยมไม่เกิน reach ก็ใช้ได้ (ใกล้สุดชนะ)
## ที่กัน (blockers) ทุกชิ้นมาจากที่นี่ ทั้งตัวชนของฉากและเทสเดินทั่วห้อง

const HALF := Vector2(12.0, 8.0)        # ครึ่งกว้าง x / ครึ่งลึก z ของด้านในห้อง
const WALL_T := 0.5                     # ผนังหนา (อยู่นอกกล่องด้านใน)
const WALL_H := 6.0
const CEIL_Y := 6.0                     # เพดานล่องหน (ตัวชนเท่านั้น ไม่วาด)
const AVATAR_R := 0.35
const SPAWN := Vector3(0.0, 0.0, 5.0)   # จุดเกิด หันไปทาง -z (z 6 ผนังหน้าดันกล้องชิดตัว เห็นไข่โปร่งเต็มจอ)
const SPAWN_YAW := 0.0                  # yaw ของกล้องตอนเกิด (0 = มอง -z)
## ชั้นฟิสิกส์: ผนังกับเพดาน (แขนกล้องชน) / ของในห้อง เสา เชิงเทียน เฟอร์นิเจอร์ (ตัวผู้เล่นชน แขนกล้องไม่ชน)
const SHELL_LAYER := 1
const PROP_LAYER := 4
const CAM_PAD := 0.15                   # กล้องห่างของในห้องอย่างน้อยเท่านี้

const PILLAR_R := 0.45
const PILLAR_H := 6.0
const PILLARS: PackedVector2Array = [Vector2(-8.5, -5.0), Vector2(8.5, -5.0), Vector2(-8.5, 0.5), Vector2(8.5, 0.5),
	Vector2(-8.5, 5.5), Vector2(8.5, 5.5)]
## เชิงเทียนตั้งพื้นชิดผนัง: ตำแหน่ง รัศมีที่กัน ความสูงถึงถาด
const STAND_R := 0.28
const STAND_H := 1.72
const STANDS: PackedVector2Array = [Vector2(-11.3, -6.0), Vector2(11.3, -6.0), Vector2(-11.3, 3.0), Vector2(11.3, 6.0),
	Vector2(-4.0, -7.5), Vector2(4.0, -7.5)]

const IDS: PackedStringArray = ["battle", "army", "settings", "online", "adventure", "exit", "vault", "arena"]
## c = กลางรอยเท้า (x, z), h = ครึ่งขนาด, reach = ระยะเอื้อมจากขอบ, height = ความสูงของที่กัน,
## round = ที่กันเป็นวงกลม (รัศมี h.x), front = จุดวงแหวนหน้าที่ใช้งาน (x, z), sign = ตำแหน่งป้าย, face = yaw ของป้าย
const STATIONS := {
	"battle": {"c": Vector2(0.0, -2.0), "h": Vector2(3.0, 2.0), "reach": 1.6, "height": 0.95, "round": false,
		"front": Vector2(0.0, 0.85), "sign": Vector3(0.0, 2.3, -3.7), "face": 0.0},
	"army": {"c": Vector2(-11.4, -1.0), "h": Vector2(0.5, 2.6), "reach": 1.6, "height": 2.6, "round": false,
		"front": Vector2(-10.0, -1.0), "sign": Vector3(-10.75, 3.15, -1.0), "face": PI * 0.5},
	"settings": {"c": Vector2(10.0, -1.0), "h": Vector2(0.4, 0.4), "reach": 1.6, "height": 1.2, "round": false,
		"front": Vector2(9.0, -1.0), "sign": Vector3(10.0, 2.45, -1.0), "face": -PI * 0.5},
	# ช่องเทียบยานยื่นจากผนังแค่ 0.2 ม. (สูง 5.2 ม.): กล้องที่ถูกผนังดันมาไม่เกิน x 11.55 จึงไม่เข้าไปในที่กัน ไม่กระตุก
	"online": {"c": Vector2(11.95, 3.0), "h": Vector2(0.15, 1.7), "reach": 1.8, "height": 5.2, "round": false,
		"front": Vector2(10.6, 3.0), "sign": Vector3(11.45, 5.55, 3.0), "face": -PI * 0.5},
	"adventure": {"c": Vector2(-5.0, 4.0), "h": Vector2(1.3, 1.3), "reach": 1.5, "height": 0.8, "round": true,
		"front": Vector2(-2.95, 4.0), "sign": Vector3(-5.0, 2.2, 4.0), "face": PI * 0.5},
	"exit": {"c": Vector2(0.0, 7.9), "h": Vector2(1.2, 0.2), "reach": 1.4, "height": 3.2, "round": false,
		"front": Vector2(0.0, 6.95), "sign": Vector3(0.0, 3.75, 7.62), "face": PI},
	# โต๊ะทำงาน · คลังของ (id เดิม "vault"): ตู้สูงถึงยอดจั่ว 1.95 ม. ที่กันสูงเท่าตู้ ป้ายลอยเหนือ
	"vault": {"c": Vector2(5.0, 4.0), "h": Vector2(1.2, 1.2), "reach": 1.5, "height": 1.95, "round": true,
		"front": Vector2(3.15, 4.0), "sign": Vector3(5.0, 2.45, 4.0), "face": -PI * 0.5},
	# ประตูอารีน่าทดสอบอาวุธ (ARENA_SPEC §2): กล่องกันปิดช่องประตูเหมือนประตูทางออก ตัวผู้เล่นหยุดที่ z 7.35
	"arena": {"c": Vector2(-9.8, 7.9), "h": Vector2(1.0, 0.2), "reach": 1.4, "height": 3.8, "round": false,
		"front": Vector2(-9.8, 6.95), "sign": Vector3(-9.8, 4.3, 7.62), "face": PI},
}
## ช่องประตูอารีน่าในผนังหน้า (วาดอย่างเดียว ตัวชนผนังเต็มเหมือนเดิม): ช่วง x, จุดเริ่มโค้ง, ยอดโค้ง, ทางเดินสั้นหลังประตู
const ARENA_DOOR := {"x0": -10.8, "x1": -8.8, "spring": 2.5, "apex": 3.8, "stub": 2.5}
## เดินเข้าช่องประตูลึกกว่านี้ (เลยขอบกล่องกัน − รัศมีตัว − ค่านี้) = เข้าอารีน่า
const ARENA_AUTO := 0.12
## จุดที่กลับมาจากอารีน่า หันไป -z (ว่าง ไม่อยู่ในวงสถานีไหน)
const ARENA_RETURN := Vector3(-9.8, 0.0, 5.2)
## จุดที่กลับมาจากห้องเสริมหลังประตูเทียบยาน (PACK_SPEC §9) หันไป -x (ว่าง ไม่อยู่ในวงสถานีไหน)
const AIRLOCK_RETURN := Vector3(9.6, 0.0, 3.0)
## ม้านั่งกลมสี่ตัวรอบโต๊ะผจญภัย (ในกรอบสี่เหลี่ยมของมัน): ระยะทแยงจากกลาง รัศมี สูง
const STOOL_D := 1.06
const STOOL_R := 0.2
const STOOL_H := 0.46

## ธงผ้าบนผนัง: จุดกลางบนผิวผนัง, ทิศที่หันเข้าห้อง (x, z), ดัชนีสี 0 แดงเข้ม 1 ดำอมม่วง 2 บรอนซ์
const BANNERS := [
	{"p": Vector3(-4.0, 4.3, 8.0), "n": Vector2(0.0, -1.0), "col": 0},
	{"p": Vector3(4.0, 4.3, 8.0), "n": Vector2(0.0, -1.0), "col": 0},
	{"p": Vector3(-12.0, 4.3, -2.25), "n": Vector2(1.0, 0.0), "col": 1},
	{"p": Vector3(12.0, 4.3, -2.25), "n": Vector2(-1.0, 0.0), "col": 1},
	{"p": Vector3(-12.0, 4.3, 3.0), "n": Vector2(1.0, 0.0), "col": 2},
	{"p": Vector3(12.0, 4.3, 6.0), "n": Vector2(-1.0, 0.0), "col": 2},
]

## หน้าต่างบานใหญ่สามช่องในผนังหลัง (โค้งแหลม): ช่วง x, ขอบล่าง, จุดเริ่มโค้ง, ยอดโค้ง (ตัวชนผนังไม่เปลี่ยน)
## จุดเริ่มโค้งต่ำกว่ายอดมากกว่าครึ่งความกว้าง โค้งจึงแหลมจริง (ไม่ใช่ครึ่งวงกลม)
const WINDOWS := [
	{"x0": -3.2, "x1": 3.2, "sill": 0.9, "spring": 5.6, "apex": 9.4},
	{"x0": -7.4, "x1": -4.6, "sill": 0.9, "spring": 4.2, "apex": 6.0},
	{"x0": 4.6, "x1": 7.4, "sill": 0.9, "spring": 4.2, "apex": 6.0},
]
## ขอบหน้าต่างด้านในยื่นจากผนังเท่านี้ (ม.): ไม่เกิน 0.08 ไม่งั้นตัดผ่านไข่ที่เดินชิดหน้าต่าง (SHIP_LOBBY_SPEC §2.3)
const SILL_DEPTH := 0.06
## โปรไฟล์เพดานโค้งแหลมเหนือโถงกลาง (x, y) จากหัวเสาถึงสัน (ซีกขวา สะท้อนเป็นซีกซ้าย)
const VAULT_PROFILE: PackedVector2Array = [Vector2(8.5, 6.0), Vector2(7.6, 7.6), Vector2(6.0, 8.9), Vector2(3.8, 9.9),
	Vector2(1.6, 10.5), Vector2(0.0, 10.8)]
const AISLE_Y := 6.3                    # เพดานเรียบของทางเดินข้าง
## จอบนผนังข้าง: กลางจอบนผิวผนัง, ทิศเข้าห้อง (x, z), amber = จออำพัน (ไม่งั้นเขียว)
const SCREENS := [
	{"p": Vector3(-12.0, 2.3, -7.0), "n": Vector2(1.0, 0.0), "amber": false},
	{"p": Vector3(-12.0, 2.3, 6.75), "n": Vector2(1.0, 0.0), "amber": true},
	{"p": Vector3(12.0, 2.3, -7.0), "n": Vector2(-1.0, 0.0), "amber": false},
	{"p": Vector3(12.0, 2.3, -2.25), "n": Vector2(-1.0, 0.0), "amber": true},
]
const SCREEN_GREEN := Color("7dffa6")
const SCREEN_AMBER := Color("ffbb55")
const HOLO := Color("59f0b4")
const GOLD := Color(0.90, 0.70, 0.34)
## แสงเย็นที่อบลงสีจุดยอด: ตำแหน่ง, k, D, สี (ความสว่าง = k / (1 + d²/D))
const COOL_LIGHTS := [
	{"p": Vector3(0.0, 1.4, -2.0), "k": 1.1, "d": 4.0, "col": HOLO},
	{"p": Vector3(-6.0, 3.0, -7.4), "k": 0.35, "d": 6.0, "col": Color("9fb8ff")},
	{"p": Vector3(-3.0, 3.0, -7.4), "k": 0.35, "d": 6.0, "col": Color("9fb8ff")},
	{"p": Vector3(0.0, 3.0, -7.4), "k": 0.35, "d": 6.0, "col": Color("9fb8ff")},
	{"p": Vector3(3.0, 3.0, -7.4), "k": 0.35, "d": 6.0, "col": Color("9fb8ff")},
	{"p": Vector3(6.0, 3.0, -7.4), "k": 0.35, "d": 6.0, "col": Color("9fb8ff")},
	{"p": Vector3(-11.9, 2.3, -7.0), "k": 0.3, "d": 1.5, "col": SCREEN_GREEN},
	{"p": Vector3(-11.9, 2.3, 6.75), "k": 0.3, "d": 1.5, "col": SCREEN_AMBER},
	{"p": Vector3(11.9, 2.3, -7.0), "k": 0.3, "d": 1.5, "col": SCREEN_GREEN},
	{"p": Vector3(11.9, 2.3, -2.25), "k": 0.3, "d": 1.5, "col": SCREEN_AMBER},
	{"p": Vector3(11.4, 2.5, 3.0), "k": 0.5, "d": 3.0, "col": Color("7fb8ff")},
	# แสงเขียวอ่อนจากจอโต๊ะทำงาน (k ต่ำ ไม่ให้ทองเหลืองกลายเป็นสีเขียว)
	{"p": Vector3(4.9, 1.35, 4.0), "k": 0.25, "d": 1.5, "col": SCREEN_GREEN},
	# แสงดาวจากหน้าต่างกระจายทั่วดาดฟ้า (D ใหญ่มาก = เกือบคงที่ทั้งห้อง) ให้เหล็กอมฟ้า ไม่เป็นสีหินอุ่น
	{"p": Vector3(0.0, 3.0, 0.0), "k": 0.14, "d": 1.0e6, "col": Color("9fb8ff")},
	# แสงอำพันที่ปากประตูอารีน่า
	{"p": Vector3(-9.8, 2.6, 7.6), "k": 0.35, "d": 2.5, "col": SCREEN_AMBER},
]
## แสงอำพันในทางเดินสั้นหลังประตูอารีน่า (อยู่นอกห้อง จึงไม่อยู่ใน COOL_LIGHTS)
const ARENA_STUB_LIGHT := {"p": Vector3(-9.8, 3.2, 9.8), "k": 0.9, "d": 3.0, "col": SCREEN_AMBER}
## ป้ายชื่อสถานที่ใต้โค้งหน้าต่างกลาง (แผ่นบรอนซ์อยู่หลังป้าย 7 ซม.)
const TITLE_SIGN := Vector3(0.0, 6.45, -7.9)

## เทียนบนเชิงเทียน: เล่มกลางสูง (ติดทุกระดับ) สองเล่มข้างเตี้ยกว่า (ไม่ติดบน min)
const STAND_ARM := 0.22
const STAND_FLAME_MID := 1.98
const STAND_FLAME_SIDE := 1.86
## โต๊ะรบ: เทียนสี่มุม ห่างขอบเข้ามา, ยอดเทียน (= ฐานเปลวไฟ)
const TABLE_CANDLE_IN := 0.28
const TABLE_FLAME_Y := 1.2
const CONSOLE_FLAME := Vector3(10.22, 1.62, -0.72)
const ADVENTURE_FLAME := Vector3(-5.0, 1.0, 4.0)
## เทียนสองเล่มหน้าแท่นโต๊ะทำงาน (บนขั้นแท่น ในวงกันรัศมี 1.2)
const VAULT_FLAMES: PackedVector3Array = [Vector3(4.05, 0.78, 3.45), Vector3(4.05, 0.78, 4.55)]
const MAX_FLAMES := 26
const MAX_FLAMES_MIN := 12


## สี่เหลี่ยมรอยเท้าของจุดใช้งาน (x, z) ในรูป Rect2
static func rect_of(id: String) -> Rect2:
	var s: Dictionary = STATIONS[id]
	var c: Vector2 = s["c"]
	var h: Vector2 = s["h"]
	return Rect2(c - h, h * 2.0)


static func reach_of(id: String) -> float:
	return float(STATIONS[id]["reach"])


## ระยะจากจุด p ถึงขอบสี่เหลี่ยม (0 เมื่ออยู่ข้างใน)
static func dist_to_rect(p: Vector2, r: Rect2) -> float:
	var c := r.get_center()
	var h := r.size * 0.5
	var dx := maxf(absf(p.x - c.x) - h.x, 0.0)
	var dz := maxf(absf(p.y - c.y) - h.y, 0.0)
	return sqrt(dx * dx + dz * dz)


static func dist_to_station(p: Vector2, id: String) -> float:
	return dist_to_rect(p, rect_of(id))


## จุดใช้งานที่ตัวผู้เล่น (กลางตัวที่ p = x, z) เอื้อมถึง; หลายจุดพร้อมกันเอาที่ใกล้สุด; ไม่มีคืน ""
## off = สถานีที่ปิดอยู่ (id → true) ไม่นับ
static func station_at(p: Vector2, off: Dictionary = {}) -> String:
	var best := ""
	var best_d := INF
	for id in IDS:
		if off.has(id):
			continue
		var d := dist_to_station(p, id)
		if d <= reach_of(id) and d < best_d:
			best = id
			best_d = d
	return best


## กลางตัวผู้เล่น p (x, z) เดินเข้าไปในช่องประตูอารีน่าแล้ว (ARENA_SPEC §2.1)
static func in_arena_doorway(p: Vector2) -> bool:
	var c: Vector2 = STATIONS["arena"]["c"]
	var h: Vector2 = STATIONS["arena"]["h"]
	return absf(p.x - c.x) <= 0.75 and p.y >= c.y - h.y - AVATAR_R - ARENA_AUTO


## กลางตัวผู้เล่น p (x, z) เดินชนช่องประตูเทียบยานแล้ว (ใช้เมื่อมีห้องเสริม PACK_SPEC §9)
static func in_airlock(p: Vector2) -> bool:
	var c: Vector2 = STATIONS["online"]["c"]
	var h: Vector2 = STATIONS["online"]["h"]
	return absf(p.y - c.y) <= h.y - 0.4 and p.x >= c.x - h.x - AVATAR_R - ARENA_AUTO


static func spawn_xz() -> Vector2:
	return Vector2(SPAWN.x, SPAWN.z)


## ที่กันทั้งหมด: {"kind": "box", "c": Vector3 กลาง, "h": Vector3 ครึ่งขนาด, "tag": ...}
## หรือ {"kind": "cyl", "c": Vector2 (x, z), "r": รัศมี, "y0": ล่าง, "y1": บน, "tag": ...}
## ผนังสี่ด้านกับเพดานอยู่นอกกล่องด้านใน; ของที่เหลืออยู่ข้างในทั้งหมด
static func blockers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hx := HALF.x + WALL_T
	var hz := HALF.y + WALL_T
	var wy := WALL_H * 0.5
	out.append({"kind": "box", "c": Vector3(0.0, wy, -HALF.y - WALL_T * 0.5), "h": Vector3(hx, wy, WALL_T * 0.5), "tag": "wall_back"})
	out.append({"kind": "box", "c": Vector3(0.0, wy, HALF.y + WALL_T * 0.5), "h": Vector3(hx, wy, WALL_T * 0.5), "tag": "wall_front"})
	out.append({"kind": "box", "c": Vector3(-HALF.x - WALL_T * 0.5, wy, 0.0), "h": Vector3(WALL_T * 0.5, wy, hz), "tag": "wall_left"})
	out.append({"kind": "box", "c": Vector3(HALF.x + WALL_T * 0.5, wy, 0.0), "h": Vector3(WALL_T * 0.5, wy, hz), "tag": "wall_right"})
	out.append({"kind": "box", "c": Vector3(0.0, CEIL_Y + WALL_T * 0.5, 0.0), "h": Vector3(hx, WALL_T * 0.5, hz), "tag": "ceiling"})
	for i in PILLARS.size():
		out.append({"kind": "cyl", "c": PILLARS[i], "r": PILLAR_R, "y0": 0.0, "y1": PILLAR_H, "tag": "pillar_%d" % i})
	for i in STANDS.size():
		out.append({"kind": "cyl", "c": STANDS[i], "r": STAND_R, "y0": 0.0, "y1": STAND_H, "tag": "stand_%d" % i})
	for id in IDS:
		var s: Dictionary = STATIONS[id]
		var c: Vector2 = s["c"]
		var h: Vector2 = s["h"]
		var top := float(s["height"])
		if bool(s["round"]):
			out.append({"kind": "cyl", "c": c, "r": h.x, "y0": 0.0, "y1": top, "tag": id})
		else:
			out.append({"kind": "box", "c": Vector3(c.x, top * 0.5, c.y), "h": Vector3(h.x, top * 0.5, h.y), "tag": id})
	for p in stools():
		out.append({"kind": "cyl", "c": p, "r": STOOL_R, "y0": 0.0, "y1": STOOL_H, "tag": "stool"})
	return out


## ม้านั่งรอบโต๊ะผจญภัย (x, z)
static func stools() -> PackedVector2Array:
	var c: Vector2 = STATIONS["adventure"]["c"]
	var out := PackedVector2Array()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(c + Vector2(sx, sz) * STOOL_D)
	return out


## วงกลมรัศมี r ที่ p (x, z) ชนอะไรไหม (ผนังด้วย ไม่นับเพดาน)
static func blocked(p: Vector2, r: float) -> bool:
	if absf(p.x) > HALF.x - r or absf(p.y) > HALF.y - r:
		return true
	for b in blockers():
		if _hits_circle(b, p, r):
			return true
	return false


## ชื่อที่กันที่วงกลมรัศมี r ที่ p ชน ("" = ไม่ชน); ใช้ในเทสเพื่อบอกว่าชนอะไร
static func blocker_at(p: Vector2, r: float) -> String:
	if absf(p.x) > HALF.x - r or absf(p.y) > HALF.y - r:
		return "wall"
	for b in blockers():
		if _hits_circle(b, p, r):
			return str(b["tag"])
	return ""


## จุด 3 มิติ p อยู่ในของแข็ง (ขยายออก margin) หรือหลุดออกนอกห้องไหม
static func inside_solid(p: Vector3, margin: float = 0.0) -> bool:
	if absf(p.x) > HALF.x - margin or absf(p.z) > HALF.y - margin or p.y > CEIL_Y - margin or p.y < margin:
		return true
	for b in blockers():
		if str(b["kind"]) == "box":
			var c: Vector3 = b["c"]
			var h: Vector3 = b["h"]
			if absf(p.x - c.x) <= h.x + margin and absf(p.y - c.y) <= h.y + margin and absf(p.z - c.z) <= h.z + margin:
				return true
		else:
			var cc: Vector2 = b["c"]
			if p.y >= float(b["y0"]) - margin and p.y <= float(b["y1"]) + margin \
					and Vector2(p.x, p.z).distance_to(cc) <= float(b["r"]) + margin:
				return true
	return false


## ผนังหรือเพดาน (เปลือกห้อง) ไม่ใช่ของในห้อง
static func is_shell(b: Dictionary) -> bool:
	var tag := str(b["tag"])
	return tag == "ceiling" or tag.begins_with("wall_")


## ระยะตามรังสี o + d·t (d ยาว 1) ก่อนจุดเข้าใกล้ผนังด้านในหรือเพดานเกิน r (รังสีชี้ขึ้นเสมอ ไม่ชนพื้น)
static func room_clear(o: Vector3, d: Vector3, r: float) -> float:
	var t := INF
	if d.x > 0.0001:
		t = minf(t, (HALF.x - r - o.x) / d.x)
	elif d.x < -0.0001:
		t = minf(t, (-HALF.x + r - o.x) / d.x)
	if d.z > 0.0001:
		t = minf(t, (HALF.y - r - o.z) / d.z)
	elif d.z < -0.0001:
		t = minf(t, (-HALF.y + r - o.z) / d.z)
	if d.y > 0.0001:
		t = minf(t, (CEIL_Y - r - o.y) / d.y)
	return maxf(t, 0.0)


## ระยะกล้องตามรังสี o + d·t (ตั้งต้นที่ length) ที่ไม่อยู่ในของในห้อง (ขยายออก pad) · ของที่แค่บังแนวไม่ดึง
## จุดที่อยู่ในของไปขอบที่ใกล้กว่า: หลังของ (ไม่เกิน far) หรือหน้าของ เสาที่ผ่านด้านข้างจึงไม่ทำให้กล้องกระโดด
## far ≤ 0 = ดึงเข้าหน้าของอย่างเดียว (และใช้เมื่อขอบหลังพาไปชนของอื่นจนวนไม่จบ)
static func camera_clear(o: Vector3, d: Vector3, length: float, pad: float = CAM_PAD, far: float = 0.0) -> float:
	var t := length
	for _i in 8:
		var moved := false
		for b in _props():
			var span := _ray_span(b, o, d, pad)
			if span.x > 0.0 and t > span.x and t < span.y:
				t = span.y if far > 0.0 and span.y <= far and span.y - t < t - span.x else span.x
				moved = true
		if not moved:
			return t
	return camera_clear(o, d, length, pad) if far > 0.0 else t


## ตัวช่วยสาธารณะของ RoomLayout (คณิตเดียวกับห้องโถง)
static func ray_span(b: Dictionary, o: Vector3, d: Vector3, pad: float) -> Vector2:
	return _ray_span(b, o, d, pad)


static func hits_circle(b: Dictionary, p: Vector2, r: float) -> bool:
	return _hits_circle(b, p, r)


static var _prop_list: Array[Dictionary] = []


## ที่กันที่ไม่ใช่ผนัง/เพดาน (จำไว้ เพราะกล้องถามทุกเฟรมฟิสิกส์ตอนขยับ)
static func _props() -> Array[Dictionary]:
	if _prop_list.is_empty():
		for b in blockers():
			if not is_shell(b):
				_prop_list.append(b)
	return _prop_list


## ช่วง t (เข้า, ออก) ที่รังสี o + d·t อยู่ในที่กัน b ที่ขยายออก pad; ไม่ผ่านคืน (INF, -INF)
static func _ray_span(b: Dictionary, o: Vector3, d: Vector3, pad: float) -> Vector2:
	var lo := -INF
	var hi := INF
	if str(b["kind"]) == "box":
		var c: Vector3 = b["c"]
		var h: Vector3 = b["h"]
		for k in 3:
			var span := _slab(o[k], d[k], c[k] - h[k] - pad, c[k] + h[k] + pad)
			lo = maxf(lo, span.x)
			hi = minf(hi, span.y)
	else:
		var cc: Vector2 = b["c"]
		var r := float(b["r"]) + pad
		var px := o.x - cc.x
		var pz := o.z - cc.y
		var qa := d.x * d.x + d.z * d.z
		var qb := 2.0 * (px * d.x + pz * d.z)
		var qc := px * px + pz * pz - r * r
		if qa < 0.000001:
			if qc > 0.0:
				return Vector2(INF, -INF)
		else:
			var disc := qb * qb - 4.0 * qa * qc
			if disc < 0.0:
				return Vector2(INF, -INF)
			var sq := sqrt(disc)
			lo = (-qb - sq) / (2.0 * qa)
			hi = (-qb + sq) / (2.0 * qa)
		var ys := _slab(o.y, d.y, float(b["y0"]) - pad, float(b["y1"]) + pad)
		lo = maxf(lo, ys.x)
		hi = minf(hi, ys.y)
	return Vector2(lo, hi) if lo < hi else Vector2(INF, -INF)


## ช่วง t ที่ o + d·t อยู่ระหว่าง a กับ b บนแกนเดียว
static func _slab(o: float, d: float, a: float, b: float) -> Vector2:
	if absf(d) < 0.000001:
		return Vector2(-INF, INF) if o >= a and o <= b else Vector2(INF, -INF)
	var t0 := (a - o) / d
	var t1 := (b - o) / d
	return Vector2(minf(t0, t1), maxf(t0, t1))


static func _hits_circle(b: Dictionary, p: Vector2, r: float) -> bool:
	if str(b["tag"]) == "ceiling":
		return false
	if str(b["kind"]) == "box":
		var c: Vector3 = b["c"]
		var h: Vector3 = b["h"]
		return dist_to_rect(p, Rect2(c.x - h.x, c.z - h.z, h.x * 2.0, h.z * 2.0)) < r
	return p.distance_to(b["c"] as Vector2) < float(b["r"]) + r


## ฐานเปลวไฟทุกดวง (บน min เหลือเล่มกลางของเชิงเทียน + เทียนบนโต๊ะ/คอนโซล = 12 ดวง) เรียงคงที่
## ครบชุด 26 = 12 ดวงแรก + เล่มข้างของเชิงเทียน 12 + เทียนหน้าหีบ 2
static func flames(min_level: bool = false) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in STANDS:
		out.append(Vector3(s.x, STAND_FLAME_MID, s.y))
	var bc: Vector2 = STATIONS["battle"]["c"]
	var bh: Vector2 = STATIONS["battle"]["h"]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(Vector3(bc.x + sx * (bh.x - TABLE_CANDLE_IN), TABLE_FLAME_Y, bc.y + sz * (bh.y - TABLE_CANDLE_IN)))
	out.append(CONSOLE_FLAME)
	out.append(ADVENTURE_FLAME)
	if min_level:
		return out
	for s in STANDS:
		var arm := stand_arm(s)
		out.append(Vector3(s.x, STAND_FLAME_SIDE, s.y) + arm * STAND_ARM)
		out.append(Vector3(s.x, STAND_FLAME_SIDE, s.y) - arm * STAND_ARM)
	out.append_array(VAULT_FLAMES)
	return out


## ทิศของแขนเชิงเทียน (ขนานกับผนังที่มันชิด)
static func stand_arm(s: Vector2) -> Vector3:
	return Vector3(0.0, 0.0, 1.0) if absf(s.x) > absf(s.y) * 1.2 else Vector3(1.0, 0.0, 0.0)


## ทิศที่ป้ายของจุดใช้งานหันไป (x, z) จาก yaw (Label3D หันหน้าไป +z ตอน yaw 0)
static func sign_normal(id: String) -> Vector2:
	var yaw := float(STATIONS[id]["face"])
	return Vector2(sin(yaw), cos(yaw))


## ความสูงของเพดานโค้งโถงกลางที่ x (ด้านล่างของแผ่นเพดาน); นอกโถงกลางคืนเพดานทางเดินข้าง
static func vault_y(x: float) -> float:
	var ax := absf(x)
	if ax >= VAULT_PROFILE[0].x:
		return AISLE_Y
	for i in VAULT_PROFILE.size() - 1:
		var a := VAULT_PROFILE[i]
		var b := VAULT_PROFILE[i + 1]
		if ax <= a.x and ax >= b.x:
			return lerpf(a.y, b.y, (a.x - ax) / (a.x - b.x))
	return VAULT_PROFILE[VAULT_PROFILE.size() - 1].y


## ขอบโค้งแหลมของหน้าต่าง w ที่ความสูง y: ครึ่งกว้างของช่อง (วัดจากกลางช่อง) ; ต่ำกว่าจุดเริ่มโค้ง = ครึ่งกว้างเต็ม
static func window_half(w: Dictionary, y: float) -> float:
	var a := (float(w["x1"]) - float(w["x0"])) * 0.5
	var sp := float(w["spring"])
	var h := float(w["apex"]) - sp
	if y <= sp:
		return a
	if y >= sp + h:
		return 0.0
	var xc := (a * a - h * h) / (2.0 * a)         # จุดศูนย์กลางโค้งขวาอยู่ฝั่งซ้าย (x < 0 = โค้งแหลม)
	var r := a - xc
	return maxf(xc + sqrt(maxf(r * r - (y - sp) * (y - sp), 0.0)), 0.0)
