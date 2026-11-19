class_name SoldierFace
extends RefCounted
## หน้าของทหาร (ใหม่ 0.14 ข้อ 2): กะพริบตา อารมณ์ 10 แบบ ปากขยับตามคำพูด (FaceSpeech ไม่มีเสียง) และตาตอนตาย
## hi/mid: กระดูกหน้า (กราม มุมปาก คิ้ว) + เปลือกตาในเชดเดอร์ · lo: เชดเดอร์อย่างเดียว (เปลือกตา + ปากทาสี) · min: ไม่มีอะไร
## สุ่มด้วย seed ของตัวเอง (opts.seed ของตัวละคร) · เวลาเดินด้วย tick(dt) ของตัวละคร (ไม่อ่านนาฬิกา)
## เขียนลงกระดูก/instance uniform face_state เฉพาะค่าที่เปลี่ยน (writes() นับให้เทส)
## face_state (face.gdshaderinc): x เปลือกตาบนลง 0..1 · y เปลือกตาล่างขึ้น 0..1 · z ปากทาสีอ้า 0..1 (lo)
##   w: lo ปากทาสีกว้าง −1..1 · hi/mid กรามอ้า 0..1 (ช่องปากมืดตามนี้ ปากหุบไม่มีเส้นดำขาด ๆ)

const MOODS: PackedStringArray = ["neutral", "happy", "sad", "angry", "pain", "fear", "surprise", "focus", "tired", "shout"]
## ต่ออารมณ์: [คิ้วยก, คิ้วเข้าใน, มุมปากออก, มุมปากขึ้น, มุมปากยื่น (มม. ของร่างหลัก), กราม (องศา), เปลือกบนลง, เปลือกล่างขึ้น,
##   คิ้วเอียง (องศา รอบแกนหน้า บวก = หัวคิ้วขึ้น)]
## ช่วงจากขั้นปั้น: คิ้ว y −2.5…+4 x ±1.5 · มุมปาก x/y ±3 z ±2 · กรามพูด 1.5–5° ตะโกน/เจ็บไม่เกิน 8°
## (ผลตรวจภาพ: คิ้ว ≤ 2 มม. มุมปาก ≤ 2.5 มม. มองไม่เห็น จึงใช้สุดช่วง + เอียงคิ้ว + เปลือกตา)
const MOOD := {
	"neutral": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	"happy": [0.8, 0.0, 3.0, 3.0, 0.0, 2.5, 0.0, 0.5, 0.0],
	"sad": [4.0, 1.5, -0.5, -3.0, 0.0, 0.0, 0.35, 0.0, 10.0],
	"angry": [-2.5, 1.5, 0.6, -1.2, 0.0, 0.0, 0.4, 0.45, -10.0],
	"pain": [-1.5, 1.5, 2.6, -0.6, -0.5, 3.0, 0.5, 0.4, 0.0],
	"fear": [4.0, 1.5, 1.8, -1.2, 0.0, 2.5, 0.0, 0.0, 10.0],
	"surprise": [3.8, 0.0, -1.5, 0.0, 0.8, 6.0, 0.0, 0.0, 0.0],
	"focus": [-2.5, 1.5, 0.0, -0.3, -0.6, 0.0, 0.35, 0.55, -10.0],
	"tired": [-0.8, 0.0, 0.0, -1.0, 0.0, 1.5, 0.6, 0.1, 0.0],
	"shout": [-2.5, 1.5, 1.6, -0.6, 0.0, 7.5, 0.3, 0.35, -10.0],
}
## รูปปากของ FaceSpeech: [กราม องศา, มุมปากออก มม., มุมปากยื่น มม.]
const VIS := {
	"rest": [0.0, 0.0, -0.3],
	"A": [5.0, 0.5, 0.0],
	"E": [3.0, 1.6, 0.0],
	"I": [1.8, 2.0, -0.2],
	"O": [4.2, -2.0, 1.2],
	"U": [1.6, -2.6, 1.8],
	"F": [1.2, 0.3, -0.5],
	"C": [2.2, 0.4, 0.0],
}
const BONES: PackedStringArray = ["head_jaw", "head_lipL", "head_lipR", "head_browL", "head_browR"]
const BLINK_GAP := Vector2(2.0, 6.0)   # วิระหว่างกะพริบ (สุ่มเท่ากัน)
const BLINK_FIRST := Vector2(0.6, 3.0)
const BLINK_DOUBLE := 0.12             # โอกาสกะพริบสองครั้งติด
const BLINK_CLOSE := 0.07
const BLINK_HOLD := 0.04
const BLINK_OPEN := 0.11
const DOUBLE_GAP := 0.09
const DEAD_OPEN := 0.25                # ตายแล้วตายังเปิด (สุ่มต่อตัวด้วย seed ราว 1 ใน 4)
const DEAD_JAW := 2.0
const RATE_MOOD := 9.0                 # ต่อวิ: คิ้ว เปลือกตา
const RATE_MOUTH := 24.0               # ต่อวิ: ปาก กราม
const SNAP := 0.002
const HOLD_PAIN := 0.9
const HOLD_ANGRY := 1.0
const TALK_KEEP := 0.35                # ระหว่างพูด อารมณ์ของมุมปากยังเหลือเท่านี้
const LO_JAW := Vector2(1.2, 5.0)      # lo: กรามเกินค่าแรก (องศา) = ปากทาสีเริ่มอ้า เต็มที่ที่ +ค่าหลัง
const LO_WIDE := 2.6                   # lo: มุมปากออก (มม.) ต่อความกว้าง 1
const EPS_POS := 0.00001               # ม.
const EPS_DEG := 0.01
const EPS_STATE := 0.001
const JAW_SEAL := -0.4                 # องศา: กรามที่ 0 ปิดเข้าอีกนิด ริมฝีปากล่างทับบน (รอยต่อปากไม่เป็นเส้นดำขาด ๆ)
const JAW_OPEN := Vector2(0.4, 2.0)    # องศา: ช่องปากเริ่มมืด → มืดเต็ม (face_state.w ของ hi/mid)

var _rng := RandomNumberGenerator.new()
var _sk: Skeleton3D
var _mi: MeshInstance3D
var _k := 1.0
var _bi := PackedInt32Array()
var _rest_pos: Array[Vector3] = []
var _rest_rot := Quaternion.IDENTITY
var _rest_q: Array[Quaternion] = []    # ท่าพัก (หมุน) ของกระดูกหน้า ตามลำดับ BONES
var _bones_ok := false
var _bones_on := false
var _shader_on := false
var _base: StringName = &"neutral"
var _hold: StringName = &""
var _hold_t := 0.0
var _aim := false
var _cur := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
var _clock := 0.0
var _next := 1.0
var _blink := -1.0
var _double := false
var _second := false
var _blinks := 0
var _times := PackedFloat32Array()
var _track: Array = []
var _say_t := 0.0
var _say_len := 0.0
var _dead := false
var _dead_open := false
var _writes := 0
var _last := {}                       # ชื่อค่า → ค่าที่เขียนล่าสุด (ไม่มี = ต้องเขียน)
var _state := Vector4.ZERO


## ตาตอนตายของ seed นี้: true = ยังเปิด (แยกจากลำดับสุ่มของการกะพริบ)
static func eyes_stay_open(seed: int) -> bool:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 9973 + 271
	return r.randf() < DEAD_OPEN


func attach(sk: Skeleton3D, mi: MeshInstance3D, k: float) -> void:
	_sk = sk
	_mi = mi
	_k = k
	_bi.clear()
	_rest_pos.clear()
	_rest_q.clear()
	_bones_ok = sk != null
	for b in BONES:
		var i := sk.find_bone(b) if sk != null else -1
		_bi.append(i)
		_bones_ok = _bones_ok and i >= 0
		_rest_pos.append(sk.get_bone_rest(i).origin if i >= 0 else Vector3.ZERO)
		_rest_q.append(sk.get_bone_rest(i).basis.get_rotation_quaternion() if i >= 0 else Quaternion.IDENTITY)
	if _bones_ok:
		_rest_rot = sk.get_bone_rest(_bi[0]).basis.get_rotation_quaternion()


func reseed(seed: int) -> void:
	_rng.seed = seed * 2731 + 5419
	_next = _rng.randf_range(BLINK_FIRST.x, BLINK_FIRST.y)
	_blink = -1.0
	_double = false
	_second = false
	_dead_open = eyes_stay_open(seed)


## ระดับภาพ (ตัวละครเรียกหลังเปลี่ยนเมช): hi/mid กระดูก + เชดเดอร์ · lo เชดเดอร์ · min ไม่มีอะไร (ไม่เขียนเลย)
func set_level(l: String) -> void:
	var was := _bones_on
	_bones_on = _bones_ok and (l == "hi" or l == "mid")
	var m: Mesh = _mi.mesh if _mi != null else null
	_shader_on = l != "min" and m != null and m.get_surface_count() > 0 \
		and (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM1) != 0
	if was and not _bones_on:
		_rest_bones()             # ออกจาก hi/mid: กระดูกหน้ากลับท่าพัก (ครั้งเดียวตอนเปลี่ยนระดับ)
	_last.clear()
	if _dead and active():
		_apply_dead()


func active() -> bool:
	return _bones_on or _shader_on


func set_mood(m: StringName, hold := 0.0) -> bool:
	if not MOODS.has(String(m)):
		return false
	if hold > 0.0:
		_hold = m
		_hold_t = hold
	else:
		_base = m
		_hold = &""
		_hold_t = 0.0
	return true


## อารมณ์ที่หน้าแสดงตอนนี้ (ชั่วคราว > เล็ง > หลัก)
func mood() -> StringName:
	if _hold != &"" and _hold_t > 0.0:
		return _hold
	if _aim:
		return &"focus"
	return _base


## เหตุการณ์ในเกม: &"pain" ถูกตี · &"angry" ต่อย/ฟัน
func event(kind: StringName) -> void:
	if kind == &"pain":
		set_mood(&"pain", HOLD_PAIN)
	elif kind == &"angry":
		set_mood(&"angry", HOLD_ANGRY)


## พูด (ข้อความว่าง = หยุดพูด) · คืนความยาว (วิ) · 0 = พูดไม่ได้ (min หรือตายแล้ว)
func say(text: String, lang := "") -> float:
	_track = [] if _dead or not active() else FaceSpeech.visemes(text, lang)
	_say_t = 0.0
	_say_len = FaceSpeech.duration(_track)
	return _say_len


func speaking() -> bool:
	return not _track.is_empty()


func die() -> void:
	_dead = true
	_track = []
	_hold = &""
	_blink = -1.0
	if active():
		_apply_dead()


func revive() -> void:
	if not _dead:
		return
	_dead = false
	_cur.fill(0.0)
	_next = _rng.randf_range(BLINK_GAP.x, BLINK_GAP.y)
	_last.clear()


func dead() -> bool:
	return _dead


func dead_open() -> bool:
	return _dead_open


func blinks() -> int:
	return _blinks


func blink_times() -> PackedFloat32Array:
	return _times


func writes() -> int:
	return _writes


## face_state ที่เขียนล่าสุด
func state() -> Vector4:
	return _state


## ค่าปัจจุบัน [คิ้วยก, คิ้วเข้า, มุมปากออก, มุมปากขึ้น, มุมปากยื่น, กราม°, เปลือกบน, เปลือกล่าง, คิ้วเอียง°]
func values() -> PackedFloat32Array:
	return _cur


func tick(dt: float, aiming := false) -> void:
	if _dead or dt <= 0.0 or not active():
		return
	_clock += dt
	_aim = aiming
	if _hold_t > 0.0:
		_hold_t -= dt
		if _hold_t <= 0.0:
			_hold = &""
	var b := _blink_step(dt)
	var code := ""
	if not _track.is_empty():
		_say_t += dt
		code = FaceSpeech.code_at(_track, _say_t)
		if code == "":
			_track = []
	var tgt := _target(mood(), code)
	var am := 1.0 - exp(-RATE_MOOD * dt)
	var au := 1.0 - exp(-RATE_MOUTH * dt)
	for i in _cur.size():
		var a := au if i >= 2 and i <= 5 else am
		var t := float(tgt[i])
		var c := _cur[i] + (t - _cur[i]) * a
		_cur[i] = t if absf(t - c) < SNAP else c
	_write(maxf(_cur[6], b), _cur[7])


func blinking() -> bool:
	return _blink >= 0.0


## ภาพเทียบ/เทส: วางหน้าตามอารมณ์ m (+ รูปปาก code ของ FaceSpeech, เปลือกตาปิด lids 0..1) ทันที ไม่ไล่ค่า ไม่กะพริบ
func show_pose(m: StringName, code := "", lids := 0.0) -> void:
	if _dead or not active():
		return
	var tgt := _target(m if MOODS.has(String(m)) else &"neutral", code)
	for i in _cur.size():
		_cur[i] = float(tgt[i])
	_write(maxf(_cur[6], lids), _cur[7])


# ---------------- ภายใน ----------------

## ค่าเป้าหมายของอารมณ์ m · ระหว่างพูด ปาก/กรามตามรูปปาก code (อารมณ์ของมุมปากเหลือ TALK_KEEP)
func _target(m: StringName, code: String) -> Array:
	var tgt: Array = (MOOD[String(m)] as Array).duplicate()
	if VIS.has(code):
		var v: Array = VIS[code]
		tgt[2] = float(v[1]) + TALK_KEEP * float(tgt[2])
		tgt[3] = TALK_KEEP * float(tgt[3])
		tgt[4] = float(v[2])
		tgt[5] = float(v[0]) + TALK_KEEP * float(tgt[5])
	return tgt


## กะพริบ: คืนเปลือกตาบนจากการกะพริบ 0..1 (ปิดเร็ว ค้างสั้น ๆ เปิดช้ากว่า)
func _blink_step(dt: float) -> float:
	if _blink < 0.0:
		_next -= dt
		if _next > 0.0:
			return 0.0
		_blink = 0.0
		_blinks += 1
		_times.append(_clock)
		_double = not _second and _rng.randf() < BLINK_DOUBLE
	else:
		_blink += dt
	var t := _blink
	if t >= BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN:
		_blink = -1.0
		_second = _double
		_next = DOUBLE_GAP if _double else _rng.randf_range(BLINK_GAP.x, BLINK_GAP.y)
		_double = false
		return 0.0
	if t < BLINK_CLOSE:
		return smoothstep(0.0, BLINK_CLOSE, t)
	if t < BLINK_CLOSE + BLINK_HOLD:
		return 1.0
	return 1.0 - smoothstep(0.0, BLINK_OPEN, t - BLINK_CLOSE - BLINK_HOLD)


## เขียนกระดูก (hi/mid) และ face_state (hi/mid/lo) เฉพาะที่เปลี่ยน
func _write(lid_top: float, lid_bot: float) -> void:
	var c := _cur
	if _bones_on:
		var mm := _k * 0.001
		_bone_rot(0, c[5] + JAW_SEAL * clampf(1.0 - c[5], 0.0, 1.0))
		_bone_pos(1, _rest_pos[1] + Vector3(c[2], c[3], c[4]) * mm)
		_bone_pos(2, _rest_pos[2] + Vector3(-c[2], c[3], c[4]) * mm)
		# คิ้วซ้ายอยู่ +x: หัวคิ้วขึ้น = หมุนรอบ +z ทางลบ · ขวากลับกัน
		_bone_pos(3, _rest_pos[3] + Vector3(-c[1], c[0], 0.0) * mm, -c[8])
		_bone_pos(4, _rest_pos[4] + Vector3(c[1], c[0], 0.0) * mm, c[8])
	if _shader_on:
		var z := 0.0
		var w := 0.0
		if not _bones_on:
			z = clampf((c[5] - LO_JAW.x) / LO_JAW.y, 0.0, 1.0)
			w = clampf(c[2] / LO_WIDE, -1.0, 1.0) if z > 0.0 else 0.0
		else:
			w = smoothstep(JAW_OPEN.x, JAW_OPEN.y, c[5])
		_set_state(Vector4(clampf(lid_top, 0.0, 1.0), clampf(lid_bot, 0.0, 1.0), z, w))


## ตำแหน่งกระดูก (+ เอียงรอบแกนหน้า tilt องศา สำหรับคิ้ว) = เขียนหนึ่งครั้งต่อกระดูก
func _bone_pos(slot: int, p: Vector3, tilt := 0.0) -> void:
	var key := BONES[slot]
	var rk := key + ":r"
	if _last.has(key) and (_last[key] as Vector3).distance_to(p) < EPS_POS \
			and absf(float(_last.get(rk, 0.0)) - tilt) < EPS_DEG:
		return
	_last[key] = p
	_sk.set_bone_pose_position(_bi[slot], p)
	if slot >= 3:
		_last[rk] = tilt
		_sk.set_bone_pose_rotation(_bi[slot], _rest_q[slot] * Quaternion(Vector3.BACK, deg_to_rad(tilt)))
	_writes += 1


func _bone_rot(slot: int, deg: float) -> void:
	var key := BONES[slot]
	if _last.has(key) and absf(float(_last[key]) - deg) < EPS_DEG:
		return
	_last[key] = deg
	_sk.set_bone_pose_rotation(_bi[slot], _rest_rot * Quaternion(Vector3.RIGHT, deg_to_rad(deg)))
	_writes += 1


func _set_state(s: Vector4) -> void:
	if _last.has("state"):
		var d := ((_last["state"] as Vector4) - s).abs()
		if maxf(maxf(d.x, d.y), maxf(d.z, d.w)) < EPS_STATE:
			return
	_last["state"] = s
	_state = s
	_mi.set_instance_shader_parameter("face_state", s)
	_writes += 1


func _rest_bones() -> void:
	for slot in BONES.size():
		if _bi[slot] < 0:
			continue
		_sk.set_bone_pose_position(_bi[slot], _rest_pos[slot])
		_sk.set_bone_pose_rotation(_bi[slot], _rest_q[slot])
		_writes += 1


## หน้าตอนตาย: คิ้ว/มุมปากพัก กรามหย่อนเล็กน้อย ตาปิด (หรือเปิดค้าง ตาม seed) · เขียนครั้งเดียว
func _apply_dead() -> void:
	_cur.fill(0.0)
	_cur[5] = DEAD_JAW
	_cur[6] = 0.0 if _dead_open else 1.0
	_last.clear()
	_write(_cur[6], 0.0)
