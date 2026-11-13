class_name HiveAI
extends RefCounted
## สมองของสัตว์รัง (ARENA_SPEC §8.3): เครื่องสถานะล้วน ไม่มีโหนด ไม่มีฟิสิกส์ เทสด้วยเวลาปลอมได้
## dummy (บอทปิด) · idle (เดินกลับแท่น) · chase (ไล่ตามทาง) · windup (ง้าง 0.6 วิ) · strike (ตะปบตอน 0.72 วิ) · recover
## hit (สะดุ้ง) · dead (ล้มจนกว่าจะรีเซ็ต) · คิดเลือกสถานะ 10 ครั้ง/วิ จากเวลาสะสม เวลาท่าโจมตีนับทุกเฟรม
## ทนทาน (poise): บอทเปิด ระหว่างสะดุ้งและอีก BEAST.poise วิหลังสะดุ้งจบ โดนอะไรก็ไม่สะดุ้งซ้ำ
## (ต่อย/ฟันรัวไม่ล็อกมันไว้ มันตะปบสวนได้; ดาบฟันทุก 0.8 วิพอดีกับเวลาสะดุ้งหนัก 0.8 วิ จึงนับตั้งแต่เริ่มสะดุ้ง)
## ทิศหน้า: yaw 0 มอง +z (เหมือนไข่บนดาดฟ้า) · ตัวเลขทั้งหมดจาก ArenaData · สุ่มท่าด้วย seed คงที่

const DUMMY := &"dummy"
const IDLE := &"idle"
const CHASE := &"chase"
const WINDUP := &"windup"
const STRIKE := &"strike"
const RECOVER := &"recover"
const HIT := &"hit"
const DEAD := &"dead"
const FACE_CONE_DEG := 35.0     # เริ่มง้างเมื่อเป้าอยู่ในมุมนี้ของทิศหน้า
const WAYPOINT_R := 0.3         # ถึงจุดทางแล้วไปจุดถัดไป
const HOME_R := 0.15            # ถึงแท่นแล้วหยุด
const VARIANTS := 3             # claw_0..2 / die_*

var state: StringName = DUMMY
var bot := false
var home := Vector2.ZERO
var home_face := 0.0
var variant := 0                # ท่าที่สุ่มล่าสุด (โจมตีหรือล้ม)
var strike_hit := false         # ผลการตะปบครั้งล่าสุด
var _seed := 0
var _rng := RandomNumberGenerator.new()
var _t := 0.0                   # เวลาในสถานะนี้
var _hit_len := 0.0
var _struck := false
var _think := 0.0
var _repath := 0.0
var _path := PackedVector2Array()
var _path_i := 0
var _grace := 0.0
var _target_was_alive := true
var _poise := 0.0               # เวลาทนทานที่เหลือ (วิ)
var _events: Array[StringName] = []
var _goal := Vector2.ZERO
var _want_path := false


func _init(p_seed: int = int(ArenaData.RANGE["seed"])) -> void:
	_seed = p_seed
	_rng.seed = p_seed


func set_home(p: Vector2, face: float) -> void:
	home = p
	home_face = face


## เปิด/ปิดบอท: ปิดตอนมีชีวิต → dummy ทันที · ตอนล้มเปลี่ยนแค่ธง (มีผลหลังรีเซ็ต)
func set_bot(on: bool) -> void:
	bot = on
	if state == DEAD:
		return
	if not on:
		_enter(DUMMY)
	elif state == DUMMY:
		_enter(IDLE)
		_think = INF


## คืนสภาพ: มีชีวิต สุ่มใหม่ด้วย seed เดิม · บอทเปิด → idle ไม่งั้น dummy
func reset(bot_on: bool) -> void:
	bot = bot_on
	_rng.seed = _seed
	_grace = 0.0
	_poise = 0.0
	_target_was_alive = true
	_path = PackedVector2Array()
	_path_i = 0
	_events.clear()
	variant = 0
	strike_hit = false
	_enter(IDLE if bot_on else DUMMY)
	_think = INF


## ทางที่ตัวละครหาให้ (ArenaPath.find)
func set_path(points: PackedVector2Array) -> void:
	_path = points
	_path_i = 1 if points.size() > 1 else 0


func path() -> PackedVector2Array:
	return _path


## ความแรงของสัญญาณง้าง 0..1 (วงแดงใต้ตัว/สีแดง)
func telegraph() -> float:
	if state == WINDUP:
		return clampf(_t / float(ArenaData.BEAST["windup"]), 0.0, 1.0)
	if state == STRIKE:
		return 1.0
	return 0.0


func alive() -> bool:
	return state != DEAD


## โดนตี: คืนท่าตอบสนอง &"none" | &"flinch" | &"flinch_heavy" | &"dead" (ตายแล้วไม่สนอะไรนอกจาก reset)
func on_damage(amount: int, stagger: bool, killed: bool) -> StringName:
	if state == DEAD:
		return &"none"
	if killed:
		variant = _rng.randi_range(0, VARIANTS - 1)
		_enter(DEAD)
		_events.append(&"died")
		return DEAD
	var r := ArenaCombat.reaction(amount, stagger)
	if r == &"none":
		return r
	# ช่วงทนทานหลังสะดุ้ง (บอทเปิดเท่านั้น: เป้านิ่งยังสะดุ้งทุกหมัดให้เห็นผล)
	if bot and _poise > 0.0:
		return &"none"
	_hit_len = float(ArenaData.BEAST["flinch_heavy" if r == &"flinch_heavy" else "flinch"])
	_poise = _hit_len + float(ArenaData.BEAST["poise"])
	_enter(HIT)
	return r


## หนึ่งก้าวเวลา: me = {"pos": Vector2, "yaw", "hp", "alive"}, target = {"pos": Vector2, "alive", "in_room", "r"}
## คืน {"move": Vector2 (ม./วิ), "face", "run", "events", "repath": bool, "goal": Vector2}
func tick(dt: float, me: Dictionary, target: Dictionary) -> Dictionary:
	var pos: Vector2 = me.get("pos", Vector2.ZERO)
	var yaw := float(me.get("yaw", 0.0))
	var t_alive := bool(target.get("alive", false))
	# เป้าเพิ่งล้ม: พักไล่ grace วิ
	if _target_was_alive and not t_alive:
		_grace = float(ArenaData.BEAST["grace"])
	_target_was_alive = t_alive
	_grace = maxf(_grace - dt, 0.0)
	_poise = maxf(_poise - dt, 0.0)
	_t += dt
	_want_path = false
	var move := Vector2.ZERO
	var face := yaw
	var run := false
	var turn := float(ArenaData.BEAST["turn"])
	var tpos: Vector2 = target.get("pos", pos)
	var want_chase := bot and t_alive and bool(target.get("in_room", false)) and _grace <= 0.0
	_think += dt
	_repath += dt
	var thinking := _think >= 1.0 / float(ArenaData.BEAST["think_hz"])
	if thinking:
		_think = 0.0
	match state:
		DUMMY, DEAD:
			pass
		IDLE:
			if thinking and want_chase:
				_enter(CHASE)
				_repath = INF
			else:
				var r := _follow(pos, home, float(ArenaData.BEAST["home_speed"]), yaw, turn, dt, HOME_R)
				move = r["move"]
				face = r["face"]
				if move == Vector2.ZERO and pos.distance_to(home) <= HOME_R + 0.01:
					face = _turn(yaw, home_face, turn * dt)
		CHASE:
			if thinking and not want_chase:
				_enter(IDLE)
				_repath = INF
			else:
				var d := pos.distance_to(tpos)
				var ang := absf(angle_difference(yaw, _yaw_to(pos, tpos)))
				if thinking and d <= float(ArenaData.BEAST["attack_range"]) and ang <= deg_to_rad(FACE_CONE_DEG):
					variant = _rng.randi_range(0, VARIANTS - 1)
					_enter(WINDUP)
					_events.append(&"windup")
					face = _turn(yaw, _yaw_to(pos, tpos), turn * 0.5 * dt)
				elif d <= float(ArenaData.BEAST["attack_range"]):
					# ในระยะแล้ว: หยุดเดิน หันเข้าหา
					face = _turn(yaw, _yaw_to(pos, tpos), turn * dt)
				else:
					var stop := float(ArenaData.BEAST["radius"]) + float(target.get("r", 0.35)) + 0.1
					var r := _follow(pos, tpos, float(ArenaData.BEAST["run"]), yaw, turn, dt, stop)
					move = r["move"]
					face = r["face"]
					run = true
		WINDUP:
			face = _turn(yaw, _yaw_to(pos, tpos), turn * 0.5 * dt)
			if _t >= float(ArenaData.BEAST["windup"]):
				var over := _t - float(ArenaData.BEAST["windup"])
				_enter(STRIKE)
				_t = over
				_struck = false
				_strike_check(pos, face, tpos, t_alive)
		STRIKE:
			_strike_check(pos, yaw, tpos, t_alive)
		RECOVER:
			if _t >= float(ArenaData.BEAST["recover"]):
				_events.append(&"recovered")
				_enter(_next_live(want_chase))
				_think = INF
		HIT:
			if _t >= _hit_len:
				_enter(_next_live(want_chase))
				_think = INF
	# ทางใหม่ทุก repath วิ ระหว่างไล่หรือเดินกลับ
	if state == CHASE or (state == IDLE and pos.distance_to(home) > HOME_R):
		if _repath >= float(ArenaData.BEAST["repath"]):
			_repath = 0.0
			_want_path = true
			_goal = tpos if state == CHASE else home
	var ev := _events.duplicate()
	_events.clear()
	return {"move": move, "face": face, "run": run, "events": ev, "repath": _want_path, "goal": _goal}


## ตะปบลงตอน strike_at หลังเริ่มง้าง (นับจากเริ่ม strike = strike_at − windup) ครั้งเดียว
func _strike_check(pos: Vector2, face: float, tpos: Vector2, t_alive: bool) -> void:
	var at := float(ArenaData.BEAST["strike_at"]) - float(ArenaData.BEAST["windup"])
	if _struck or _t < at - 0.000001:
		return
	_struck = true
	strike_hit = t_alive and ArenaCombat.in_cone(pos, face, tpos, 0.0, float(ArenaData.BEAST["strike_reach"]),
		float(ArenaData.BEAST["strike_half_angle_deg"]))
	_events.append(&"strike")
	var over := _t - at
	_enter(RECOVER)
	_t = over


## เวลาทนทานที่เหลือ (เทสใช้)
func poise_left() -> float:
	return _poise


## เวลาที่ผ่านไปตั้งแต่เริ่มง้าง (เทสใช้)
func windup_elapsed() -> float:
	if state == WINDUP:
		return _t
	if state == STRIKE:
		return _t + float(ArenaData.BEAST["windup"])
	return -1.0


func _next_live(want_chase: bool) -> StringName:
	if not bot:
		return DUMMY
	return CHASE if want_chase else IDLE


func _enter(s: StringName) -> void:
	state = s
	_t = 0.0
	if s != STRIKE:
		_struck = false


## เดินตามทาง (หรือตรงไปเมื่อไม่มีทาง) ด้วยความเร็ว speed หยุดเมื่อห่างเป้าไม่เกิน stop
func _follow(pos: Vector2, goal: Vector2, speed: float, yaw: float, turn: float, dt: float, stop: float) -> Dictionary:
	if pos.distance_to(goal) <= stop + 0.002:
		return {"move": Vector2.ZERO, "face": yaw}
	var wp := goal
	if _path.size() > 1:
		while _path_i < _path.size() - 1 and pos.distance_to(_path[_path_i]) <= WAYPOINT_R:
			_path_i += 1
		wp = _path[mini(_path_i, _path.size() - 1)]
		# จุดสุดท้ายของทางคือเป้าเก่า: ใช้เป้าจริงแทน
		if _path_i >= _path.size() - 1:
			wp = goal
	var dir := wp - pos
	if dir.length() < 0.0001:
		return {"move": Vector2.ZERO, "face": yaw}
	dir = dir.normalized()
	var want := atan2(dir.x, dir.y)
	var face := _turn(yaw, want, turn * dt)
	# หันยังไม่ตรง: ช้าลง (ไม่วิ่งวนรอบเป้า)
	var k := clampf((cos(angle_difference(face, want)) + 0.2) / 1.2, 0.0, 1.0)
	var left := pos.distance_to(goal) - stop
	var v := minf(speed * k, left / maxf(dt, 0.0001))
	return {"move": dir * v, "face": face}


static func _turn(from: float, to: float, max_step: float) -> float:
	var d := angle_difference(from, to)
	if absf(d) <= max_step:
		return to
	return from + signf(d) * max_step


static func _yaw_to(a: Vector2, b: Vector2) -> float:
	return atan2(b.x - a.x, b.y - a.y)
