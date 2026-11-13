class_name ArenaCombat
extends RefCounted
## คณิตการต่อสู้ของอารีน่า (ARENA_SPEC §6.2) · static ล้วน ไม่มีโหนด ไม่มีฟิสิกส์ ไม่มีข้อความไทย
## ทิศหน้าแบบไข่บนดาดฟ้า: yaw 0 มอง +z, yaw_to(a, b) = atan2(b.x − a.x, b.z − a.z), หน้า = (sin yaw, cos yaw)
## ตัวเลขทั้งหมดมาจาก ArenaData


static func weapon(id: String) -> Dictionary:
	return ArenaData.WEAPONS.get(id, {})


## ช่วงห่างระหว่างนัด: ปืน 1 / rate (0.125 วิ) · อาวุธระยะประชิดใช้ cooldown
static func fire_interval(id: String) -> float:
	var w := weapon(id)
	if w.has("rate"):
		return 1.0 / maxf(float(w["rate"]), 0.0001)
	return float(w.get("cooldown", 0.0))


static func can_fire(now: float, last: float, id: String) -> bool:
	return now - last >= fire_interval(id)


static func after_shot(in_mag: int) -> int:
	return maxi(in_mag - 1, 0)


static func needs_reload(in_mag: int) -> bool:
	return in_mag <= 0


static func full_mag(id: String) -> int:
	return int(weapon(id).get("mag", 0))


## เป้าวงกลม (ศูนย์, รัศมี) อยู่ในระยะ reach ของจุดเริ่ม และศูนย์อยู่ในมุมครึ่ง half_angle_deg ของทิศหน้า
## เป้าที่ทับจุดเริ่มนับว่าโดนเสมอ
static func in_cone(origin: Vector2, face_yaw: float, target: Vector2, target_r: float, reach: float,
		half_angle_deg: float) -> bool:
	var d := target - origin
	var dist := d.length()
	if dist <= target_r:
		return true
	if dist - target_r > reach:
		return false
	var fwd := Vector2(sin(face_yaw), cos(face_yaw))
	var cosang := clampf(fwd.dot(d / dist), -1.0, 1.0)
	return acos(cosang) <= deg_to_rad(half_angle_deg) + 0.000001


static func melee_hits(id: String, origin: Vector2, face_yaw: float, target: Vector2, target_r: float) -> bool:
	var w := weapon(id)
	if w.is_empty() or not w.has("reach"):
		return false
	return in_cone(origin, face_yaw, target, target_r, float(w["reach"]), float(w["half_angle_deg"]))


## หักเลือด: applied ไม่เกินเลือดที่เหลือ · killed เมื่อถึง 0 พอดีจากการโดนครั้งนี้
static func apply(hp: int, amount: int) -> Dictionary:
	var a := clampi(amount, 0, maxi(hp, 0))
	var left := maxi(hp, 0) - a
	return {"hp": left, "applied": a, "killed": hp > 0 and left <= 0}


## ท่าสะดุ้ง: ไม่มี stagger ไม่สะดุ้ง (กระสุน) · ถึง heavy_at สะดุ้งหนัก
static func reaction(amount: int, stagger: bool) -> StringName:
	if not stagger or amount <= 0:
		return &"none"
	if amount >= int(ArenaData.BEAST["heavy_at"]):
		return &"flinch_heavy"
	return &"flinch"


## แรงผลักแนวนอน (y = 0) ยาว strength ม./วิ
static func knockback(dir: Vector3, strength: float) -> Vector3:
	var h := Vector3(dir.x, 0.0, dir.z)
	if h.length_squared() < 0.000001:
		return Vector3.ZERO
	return h.normalized() * strength


static func decay(v: Vector3, friction: float, dt: float) -> Vector3:
	return v * exp(-friction * dt)


static func number_style(amount: int) -> StringName:
	return &"heavy" if amount >= int(ArenaData.NUMBERS["heavy_at"]) else &"normal"


static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


# ---- พุ่งหลบ (ArenaData.DODGE) ----

## ทิศพุ่งในกรอบที่ผู้เล่นสั่ง (x = ขวา, y = หน้า): ทิศที่กด (ยาว 1) ไม่กด/กดเบากว่า 0.1 = ถอยหลัง (0, −1)
static func dodge_dir(input: Vector2) -> Vector2:
	if input.length() < 0.1:
		return Vector2(0.0, -1.0)
	return input.normalized()


## พุ่งได้ไหม: ยังไม่ล้ม ไม่ได้พุ่งอยู่ และพ้นคูลดาวน์นับจากพุ่งครั้งก่อนจบ (last_end = เวลาที่พุ่งครั้งก่อนจบ)
static func can_dodge(now: float, last_end: float, alive: bool, dodging: bool) -> bool:
	return alive and not dodging and now - last_end >= float(ArenaData.DODGE["cooldown"])


## ความเร็วพุ่ง (ม./วิ) ที่เวลา t นับจากเริ่ม: ลดเป็นเส้นตรง รวมทั้งช่วงได้ระยะ distance พอดี · นอกช่วง = 0
static func dodge_speed(t: float) -> float:
	var d := ArenaData.DODGE
	var dur := float(d["time"])
	if t < 0.0 or t >= dur:
		return 0.0
	var avg := float(d["distance"]) / dur
	return avg * (1.0 + float(d["ease"]) * (1.0 - 2.0 * t / dur))


## ระยะที่พุ่งไปแล้วที่เวลา t (ม.) · ถึง distance เมื่อ t ≥ time
static func dodge_travel(t: float) -> float:
	var d := ArenaData.DODGE
	var dur := float(d["time"])
	var tt := clampf(t, 0.0, dur)
	var avg := float(d["distance"]) / dur
	return avg * (tt + float(d["ease"]) * (tt - tt * tt / dur))


## อมตะช่วงต้นของการพุ่ง (กรงเล็บที่ลงตอนนี้พลาด)
static func dodge_invulnerable(t: float) -> bool:
	return t >= 0.0 and t < float(ArenaData.DODGE["invuln"])


## ตัวละครที่ไม่เดินเยื้อง (H9 false) ในโหมดยิง: หันตามทิศเล็งตอนยืนนิ่ง ตอนยิง/ฟัน/ต่อย (acting)
## และอีก hold_aim วิหลังจากนั้น · นอกนั้นหันตามทิศเดิน
static func faces_aim(acting: bool, moving: bool, since_action: float) -> bool:
	return acting or not moving or since_action < float(ArenaData.DODGE["hold_aim"])
