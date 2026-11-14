class_name MissionAI
extends RefCounted
## สมองของศัตรูในภารกิจ (CAMPAIGN_SPEC §5.4, track C): เครื่องสถานะล้วนแบบ HiveAI ไม่มีโหนด ไม่มีฟิสิกส์ เทสด้วยเวลาปลอมได้
## สุ่มด้วย RNG ของตัวเอง (seed จากโลก = spec.seed ผสมลำดับตัว) จึงเล่นซ้ำได้เหมือนเดิม · คิดเลือกเป้า/เป้าหมายทาง 10 ครั้งต่อวิ
## เวลาท่าทางนับทุกเฟรม · บทบาท rusher/brute/boss: วิ่งเข้าหา (บางตัวอ้อมโอบ ตาม flank_pct) → ง้าง (windup) → ฟาด (strike)
## → พักตัว · gunner: เข้าระยะยิง หลบไปหลังของบังที่โลกให้ (post) ถ้ายิงถึงเป้าจากตรงนั้น ใกล้เกินถอยออก → เล็ง (aim) → ยิง
## (fire: โลกปล่อยกระสุนช้าที่หลบได้) → พัก/ก้าวข้าง · โดนยิง/ฟัน: สะดุ้ง (ตัวเล็กบางนัด ตัวใหญ่เฉพาะหมัด/ดาบ) มีช่วงทนทาน
## เป้า: รายการ {pos, alive, r, kind, w} ที่โลกส่งมา เลือกแบบถ่วงน้ำหนัก w ด้วย RNG ทุก RETARGET วิหรือเมื่อเป้าตาย
## ทิศ: yaw 0 มอง +z (forward = (sin yaw, cos yaw)) เหมือนตัวละครทุกตัวของอารีน่า

const IDLE := &"idle"
const CHASE := &"chase"
const WINDUP := &"windup"
const RECOVER := &"recover"
const AIM := &"aim"
const COOL := &"cool"
const HIT := &"hit"
const DEAD := &"dead"
const THINK := 0.1
const RETARGET := 4.0
const RECOVER_T := 0.6
const FLINCH := 0.32
const POISE := 1.0
const POISE_BIG := 2.5
const FACE_RATE := 9.0           # เรเดียน/วิ
const STRIKE_CONE := 70.0        # ครึ่งมุมของการฟาด (องศา)
const START_CONE := 45.0         # เริ่มง้างเมื่อเป้าอยู่ในมุมนี้
const GUN_MIN := 5.0             # มือปืนถอยเมื่อเป้าใกล้กว่านี้
const FLANK_FAR := 7.0           # อ้อมโอบเมื่อยังไกลกว่านี้
const FLANK_OFF := 5.0
const WAYPOINT_R := 0.4
const BIG: PackedStringArray = ["brute", "boss"]

var state: StringName = IDLE
var role := "rusher"
var stats: Dictionary = {}
var flank := false
var flank_side := 1.0
var target := -1
var goal := Vector2.ZERO
var strikes := 0
var shots := 0
var alerted := false
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _think := 0.0
var _retarget := 0.0
var _poise := 0.0
var _side := 1.0
var _yaw := 0.0
var _yaw_set := false


## stats = MissionRoster.stats(spec, role) + "flank_pct"
func _init(p_seed: int, p_role: String, p_stats: Dictionary) -> void:
	_rng.seed = p_seed
	role = p_role
	stats = p_stats.duplicate()
	flank = role != "gunner" and _rng.randi_range(0, 99) < int(stats.get("flank_pct", 0))
	flank_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_side = flank_side
	_t = _rng.randf_range(0.2, 0.7)       # ตื่นตอนเกิดไม่พร้อมกัน


## หนึ่งก้าว: me = {pos: Vector2, yaw, alive, way: Vector2 (จุดทางถัดไปที่ตัวเดินตาม; ไม่มี = ตรงไป goal), post (Vector2 หรือ null),
## los: bool} → {"move": Vector2 ม./วิ, "face": yaw, "event": &"" | &"windup" | &"strike" | &"aim" | &"fire", "goal", "target"}
func tick(dt: float, me: Dictionary, targets: Array) -> Dictionary:
	var pos: Vector2 = me.get("pos", Vector2.ZERO)
	if not _yaw_set:
		_yaw = float(me.get("yaw", 0.0))
		_yaw_set = true
	var ev: StringName = &""
	var mv := Vector2.ZERO
	if state == DEAD or not bool(me.get("alive", true)):
		state = DEAD
		return {"move": mv, "face": _yaw, "event": ev, "goal": goal, "target": target}
	_t -= dt
	_poise = maxf(_poise - dt, 0.0)
	_retarget -= dt
	_think += dt
	if _think >= THINK:
		_think = 0.0
		_choose(pos, targets)
	var t: Dictionary = targets[target] if target >= 0 and target < targets.size() else {}
	var has_t := not t.is_empty() and bool(t.get("alive", true))
	var tp: Vector2 = t.get("pos", pos) if has_t else pos
	var tr := float(t.get("r", 0.35)) if has_t else 0.0
	var dist := pos.distance_to(tp) - tr
	var want_yaw := _yaw
	var speed := float(stats.get("speed", 3.0))
	match state:
		IDLE:
			# ยาม (aggro > 0): ยืนเฝ้าจนเป้าแรก (ผู้เล่น) เข้ามาใกล้ หรือโดนยิง
			var aggro := float(stats.get("aggro", 0.0))
			if aggro > 0.0 and not alerted:
				var p0: Dictionary = targets[0] if not targets.is_empty() else {}
				if not p0.is_empty() and bool(p0.get("alive", true)) and pos.distance_to(p0.get("pos", pos)) <= aggro:
					alerted = true
			if _t <= 0.0 and (aggro <= 0.0 or alerted):
				state = CHASE
		CHASE:
			if not has_t:
				pass
			elif role == "gunner":
				var los := bool(me.get("los", true))
				var rng_m := float(stats.get("range", 14.0))
				if los and dist <= rng_m * 0.9 and dist >= GUN_MIN:
					state = AIM
					_t = float(stats.get("windup", 0.8))
					ev = &"aim"
				elif dist < GUN_MIN and los:
					var away := (pos - tp).normalized() if pos.distance_squared_to(tp) > 0.0001 else Vector2(0.0, -1.0)
					mv = away * speed * 0.8
				else:
					mv = _toward(pos, me, speed)
			else:
				var reach := float(stats.get("reach", 1.8))
				var ang := absf(angle_difference(_yaw, _yaw_to(pos, tp)))
				if dist <= reach * 0.85 and ang <= deg_to_rad(START_CONE):
					state = WINDUP
					_t = float(stats.get("windup", 0.5))
					ev = &"windup"
				else:
					mv = _toward(pos, me, speed)
					if dist <= reach * 0.85:
						mv = Vector2.ZERO       # ใกล้แล้ว หันก่อนค่อยง้าง
		WINDUP:
			if _t <= 0.0:
				ev = &"strike"
				strikes += 1
				state = RECOVER
				_t = RECOVER_T
		AIM:
			if _t <= 0.0:
				ev = &"fire"
				shots += 1
				state = COOL
				_t = _rng.randf_range(1.0, 1.6)
				_side = 1.0 if _rng.randf() < 0.5 else -1.0
		COOL:
			if has_t:
				var d := (tp - pos).normalized() if pos.distance_squared_to(tp) > 0.0001 else Vector2(0.0, 1.0)
				mv = Vector2(-d.y, d.x) * _side * speed * 0.35
			if _t <= 0.0:
				state = CHASE
		RECOVER, HIT:
			if _t <= 0.0:
				state = CHASE
	if state == WINDUP or state == AIM or (mv == Vector2.ZERO and has_t and state != IDLE):
		want_yaw = _yaw_to(pos, tp)
	elif mv.length_squared() > 0.0001:
		want_yaw = atan2(mv.x, mv.y)
	_yaw = _turn(_yaw, want_yaw, FACE_RATE * dt)
	return {"move": mv, "face": _yaw, "event": ev, "goal": goal, "target": target}


## โดน: คืนท่า &"die" | &"flinch" | &"none" (ตัวเล็กสะดุ้งจากกระสุนครึ่งหนึ่งของนัดโดยสุ่ม; ตัวใหญ่เฉพาะหมัด/ดาบ)
func on_damage(applied: int, stagger: bool, killed: bool) -> StringName:
	if state == DEAD:
		return &"none"
	alerted = true
	if killed:
		state = DEAD
		return &"die"
	if applied <= 0 or _poise > 0.0:
		return &"none"
	var big := BIG.has(role)
	if big and not stagger:
		return &"none"
	if not stagger and _rng.randf() >= 0.5:
		return &"none"
	state = HIT
	_t = FLINCH
	_poise = POISE_BIG if big else POISE
	return &"flinch"


## ฟาดโดนไหม: เป้าอยู่ในระยะ reach + รัศมีเป้า และในมุม ±STRIKE_CONE ของทิศหน้า
func strike_hits(pos: Vector2, yaw: float, tp: Vector2, tr: float) -> bool:
	return ArenaCombat.in_cone(pos, yaw, tp, tr, float(stats.get("reach", 1.8)), STRIKE_CONE)


func busy() -> bool:
	return state == WINDUP or state == AIM or state == RECOVER or state == HIT


func telegraph() -> float:
	if state != WINDUP:
		return 0.0
	var w := maxf(float(stats.get("windup", 0.5)), 0.01)
	return clampf(1.0 - _t / w, 0.0, 1.0)


# ---- ภายใน ----

## เลือกเป้า (ถ่วงน้ำหนัก) แล้วคิดจุดหมาย: อ้อมโอบเมื่อยังไกล · มือปืนไปจุดหลบที่ยิงถึงเป้า
func _choose(pos: Vector2, targets: Array) -> void:
	var cur_ok := target >= 0 and target < targets.size() and bool((targets[target] as Dictionary).get("alive", true))
	if not cur_ok or _retarget <= 0.0:
		_retarget = RETARGET
		var wsum := 0.0
		for t: Dictionary in targets:
			if bool(t.get("alive", true)):
				wsum += maxf(float(t.get("w", 1.0)), 0.0)
		target = -1
		if wsum > 0.0:
			var pick := _rng.randf() * wsum
			for i in targets.size():
				var t: Dictionary = targets[i]
				if not bool(t.get("alive", true)):
					continue
				pick -= maxf(float(t.get("w", 1.0)), 0.0)
				if pick <= 0.0:
					target = i
					break
			if target < 0:
				for i in range(targets.size() - 1, -1, -1):
					if bool((targets[i] as Dictionary).get("alive", true)):
						target = i
						break
	if target < 0:
		goal = pos
		return
	var tp: Vector2 = (targets[target] as Dictionary).get("pos", pos)
	goal = tp
	if flank and pos.distance_to(tp) > FLANK_FAR:
		var d := (tp - pos).normalized()
		goal = tp - d * 2.0 + Vector2(-d.y, d.x) * flank_side * FLANK_OFF


## ความเร็วไปจุดทางถัดไป (me.way) หรือจุดหมาย · มือปืนที่มี post ใช้ post เมื่อยิงจาก post ถึงเป้า
func _toward(pos: Vector2, me: Dictionary, speed: float) -> Vector2:
	var w: Vector2 = me.get("way", goal) if me.get("way") is Vector2 else goal
	if role == "gunner" and me.get("post") is Vector2:
		var post: Vector2 = me["post"]
		if post.distance_to(goal) <= float(stats.get("range", 14.0)) * 0.85 and pos.distance_to(post) > WAYPOINT_R:
			goal = post
			w = me.get("way", post) if me.get("way") is Vector2 else post
	var d := w - pos
	if d.length() < 0.05:
		return Vector2.ZERO
	return d.normalized() * speed


static func _yaw_to(a: Vector2, b: Vector2) -> float:
	var d := b - a
	if d.length_squared() < 0.000001:
		return 0.0
	return atan2(d.x, d.y)


static func _turn(cur: float, want: float, step: float) -> float:
	var d := angle_difference(cur, want)
	if absf(d) <= step:
		return wrapf(want, -PI, PI)
	return wrapf(cur + signf(d) * step, -PI, PI)
