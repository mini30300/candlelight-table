class_name ArenaState
extends RefCounted
## สถานะสนามทดสอบ (ARENA_SPEC §7): สวิตช์บอท ตัวนับการโดน ความเสียหายรวม · ข้อมูลล้วน ไม่มีโหนด
## สวิตช์กดซ้ำภายใน 1 วิไม่นับ · ยิง/ฟันโดนแผ่นต่อเนื่อง (ห่างกันไม่ถึง 1 วิ) = ชุดเดียว สลับครั้งเดียวต่อชุด
## (ยิงค้างนานเท่าไรก็ไม่สลับเปิดแล้วปิดเอง) · รีเซ็ตล้างตัวนับแต่สวิตช์คงตำแหน่งเดิม

var bot_on := false
var hits := 0
var damage := 0
var last_toggle := -INF
var last_plate_hit := -INF
var _burst_done := false        # ชุดยิง/ฟันที่กำลังโดนแผ่นสลับไปแล้ว


## สลับสวิตช์ที่เวลา now (วิ ตามเวลาสะสมของเกม) คืน false ถ้ายังไม่พ้นช่วงพัก
func toggle(now: float) -> bool:
	if now - last_toggle < cooldown():
		return false
	last_toggle = now
	bot_on = not bot_on
	return true


## โดนแผ่นสวิตช์ (กระสุน/หมัด/ดาบ) ที่เวลา now: เว้นไม่โดนแผ่นครบช่วงพัก = เริ่มชุดใหม่ · แต่ละชุดสลับครั้งเดียว
## ที่นัดแรกที่พ้นช่วงพักของการสลับครั้งก่อน (จำเวลาทุกนัด: ยิงค้างไว้จึงไม่สลับซ้ำ)
func plate_hit(now: float) -> bool:
	if now - last_plate_hit >= cooldown() - 0.000001:
		_burst_done = false
	last_plate_hit = now
	if _burst_done or not toggle(now):
		return false
	_burst_done = true
	return true


## นับการโดนที่สร้างความเสียหายจริง (applied > 0)
func record_hit(applied: int) -> void:
	if applied <= 0:
		return
	hits += 1
	damage += applied


func reset() -> void:
	hits = 0
	damage = 0


## สรุปสำหรับกระดาน: beast = {"hp", "hp_max", "state", "alive"} จากตัวศัตรู
func stats(beast: Dictionary) -> Dictionary:
	return {"bot_on": bot_on, "hp": int(beast.get("hp", 0)), "hp_max": int(beast.get("hp_max", 0)), "hits": hits,
		"damage": damage, "state": StringName(beast.get("state", &"dummy")), "dead": not bool(beast.get("alive", true))}


## ช่วงพักของสวิตช์ (ArenaData.RANGE.switch_cooldown)
static func cooldown() -> float:
	return float(ArenaData.RANGE["switch_cooldown"])
