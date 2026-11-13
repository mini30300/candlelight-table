class_name ArenaCamera
extends Node3D
## กล้องของผู้เล่นในอารีน่า (ARENA_SPEC §5.1, §5.4) มีสองแบบ:
## walk = กล้องตามแบบห้องโถง (จุดหมุนหัว +1.3 ตามนุ่ม แขน 4.5 ใน [2.5, 6] ก้ม −0.35 ใน [−1.0, −0.1] ลากหมุน ล้อ/หนีบซูม)
## shoot = กล้องข้ามไหล่ (จุดหมุน +1.8 เยื้องขวา 0.9 ม. แขน 3.0 ม. ไม่ซูม เงย/ก้มใน [−0.9, 0.6] FOV 65)
## แขน SpringArm3D ชนชั้น 1 (ผนัง เพดาน เสา) ทรงกลม r 0.25 · ของเตี้ยในห้อง (ชั้น 4) ดึงกล้องเข้าเฉพาะตอนจุดกล้องจะอยู่ในของ
## (ชั้น prop ของ ArenaLayout.blockers() ถ้ามี) · ไม่มีตัวชนพื้น: กล้องไม่ต่ำกว่า FLOOR_Y · ดึงเข้าทันที ยืดกลับไม่เกิน 4 ม./วิ
## หมุนสลับแบบ 0.3 วิบน hi/mid ทันทีบน lo/min · สั่นกล้องตอนต่อยโดน (hi/mid)
## ทิศ: forward_flat() = (−sin yaw, 0, −cos yaw), right_flat() = (cos yaw, 0, −sin yaw) เหมือน HallCamera
## เป้าเล็งอยู่กลางจอพอดี: รังสีเล็งคือแกน −z ของกล้อง (ภาพไม่เลื่อนศูนย์ h/v offset เป็นศูนย์ ยกเว้นตอนสั่น)
## งานต่อเฟรม: _process เฉพาะตอนจุดหมุนยังไล่ตาม กำลังสลับแบบ หรือกำลังสั่น; แขนปิดตัวเองเมื่อนิ่งครบ 3 เฟรมฟิสิกส์

signal turned
## ความยาวแขนจริงหลังชน (ส่งเฉพาะตอนแขนยังไม่นิ่ง)
signal arm_settled(length: float)

const WALK_HEAD := Vector3(0.0, 1.3, 0.0)
const SHOULDER_HEAD := Vector3(0.0, 1.8, 0.0)
const SHOULDER_RIGHT := 0.9
const SHOULDER_ARM := 3.0
const WALK_ARM := 4.5
const WALK_ARM_MIN := 2.5
const WALK_ARM_MAX := 6.0
const WALK_PITCH := -0.35
const WALK_PITCH_MIN := -1.0
const WALK_PITCH_MAX := -0.1
const AIM_PITCH_MIN := -0.9
const AIM_PITCH_MAX := 0.6
const FOV_WALK := 60.0
const FOV_SHOOT := 65.0
const NEAR := 0.05
const FAR := 80.0
## เมาส์ (เรเดียนต่อพิกเซล) และนิ้ว (เรเดียนต่อพิกเซลของ canvas) ตอนเล็ง
const LOOK_SPEED := 0.0025
const TOUCH_LOOK := 0.006
const ORBIT_SPEED := 0.006
const WHEEL := 0.9
const FOLLOW := 10.0
const EPS := 0.01
const EXTEND := 4.0
const SETTLE_TICKS := 3
## แขนที่ชนอยู่: ระยะชนของ SpringArm3D แกว่งราว 1 ซม. ตามความยาวที่ตั้ง (ความละเอียดของการกวาดทรงกลม)
## ขยับน้อยกว่านี้ถือว่านิ่ง ไม่งั้นแขนที่ชนผนัง/ประตูไม่เคยหยุดคิด (ยืดกลับ 4 ม./วิ = 6.7 ซม. ต่อเฟรมยังนับว่าขยับ)
const SETTLE_EPS := 0.02
const BLEND_TIME := 0.3
const ARM_R := 0.25
const ARM_MARGIN := 0.05
const SHELL_MASK := 1
const FLOOR_Y := 0.3         # ไม่มีตัวชนพื้น: จุดกล้องไม่ต่ำกว่านี้
const SOLID_PAD := 0.1       # ระยะเผื่อจากของเตี้ยในห้อง
const SHAKE_TIME := 0.1
const SHAKE_M := 0.04
const KICK_TIME := 0.05      # สั่นเบา ๆ ทุกนัดปืน (hi/mid)
const KICK_M := 0.012
const ARENA_LAYOUT := "res://scenes/arena/arena_layout.gd"

var yaw := 0.0
var pitch := WALK_PITCH
var arm_length := WALK_ARM
## สลับแบบนุ่ม (hi/mid) และสั่นกล้อง; lo/min ปิดทั้งสองอย่าง
var smooth := true
var input_enabled := true
## ตำแหน่งเท้าของผู้เล่นที่กล้องตาม
var target := Vector3.ZERO

var arm: SpringArm3D
var camera: Camera3D

var _shoulder := false
var _foot := Vector3.ZERO     # ตำแหน่งเท้าที่จุดหมุนอยู่ตอนนี้ (walk ตามนุ่ม, shoot ตรงตัว)
var _blend := 0.0             # 0 = walk, 1 = ข้ามไหล่
var _shake := 0.0
var _shake_t := SHAKE_TIME
var _shake_m := SHAKE_M
var _shake_rng := RandomNumberGenerator.new()
var _touches: Dictionary = {}
var _pinch := 0.0
var _mouse_orbit := false
var _settle := 0
var _first := true            # ตั้งความยาวแขนทันทีในเฟรมฟิสิกส์ถัดไป
var _props: Array = []
var _layout_checked := false


func _ready() -> void:
	top_level = true
	process_physics_priority = -1   # ตั้งความยาวแขนก่อนแขนคิดเสมอ
	arm = get_node_or_null(^"Arm") as SpringArm3D
	if arm == null:
		arm = SpringArm3D.new()
		arm.name = "Arm"
		add_child(arm)
	camera = arm.get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		arm.add_child(camera)
	arm.collision_mask = SHELL_MASK
	var s := SphereShape3D.new()
	s.radius = ARM_R
	arm.shape = s
	arm.margin = ARM_MARGIN
	arm.spring_length = arm_length
	camera.fov = FOV_WALK
	camera.near = NEAR
	camera.far = FAR
	_shake_rng.seed = 4405
	_apply()
	set_process(false)
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _shoulder:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		_pinch = _pinch_distance()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _touches.has(d.index):
			return
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var dist := _pinch_distance()
			if _pinch > 1.0 and dist > 1.0:
				zoom(_pinch / dist)
			_pinch = dist
		else:
			orbit(-d.relative.x * ORBIT_SPEED, -d.relative.y * ORBIT_SPEED)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_mouse_orbit = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom(WHEEL)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom(1.0 / WHEEL)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _mouse_orbit:
		var mm := event as InputEventMouseMotion
		orbit(-mm.relative.x * ORBIT_SPEED, -mm.relative.y * ORBIT_SPEED)


# ---- คณิตของกล้องข้ามไหล่ (static: เทสเรียกได้โดยไม่ต้องมีฉาก) ----

static func flat_forward(y: float) -> Vector3:
	return Vector3(-sin(y), 0.0, -cos(y))


static func flat_right(y: float) -> Vector3:
	return Vector3(cos(y), 0.0, -sin(y))


## จุดหมุนของกล้องข้ามไหล่: เท้า + (0, 1.8, 0) + ขวา × 0.9
static func shoulder_pivot(foot: Vector3, y: float) -> Vector3:
	return foot + SHOULDER_HEAD + flat_right(y) * SHOULDER_RIGHT


## จุดกล้องที่แขนยาว length ตามมุม (ยังไม่ชนอะไร)
static func camera_point(pivot: Vector3, y: float, p: float, length: float) -> Vector3:
	return pivot + Basis.from_euler(Vector3(p, y, 0.0)).z * length


# ---- คำสั่ง ----

## ตามผู้เล่นที่เท้า p: walk ตามนุ่ม, shoot ตรงตัวทันที
func follow(p: Vector3) -> void:
	target = p
	if _shoulder and _blend >= 1.0:
		_foot = p
		_apply()
	elif _foot.distance_to(target) > EPS:
		set_process(true)
	_wake_arm()


## ย้ายจุดหมุนไปที่ p ทันที (จุดเกิด วางตัวผู้เล่น)
func snap(p: Vector3) -> void:
	target = p
	_foot = p
	_first = true
	_apply()
	_wake_arm()


## หมุนแบบ walk (ลากจอ/เมาส์)
func orbit(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, WALK_PITCH_MIN, WALK_PITCH_MAX)
	_apply()


## เล็งแบบข้ามไหล่ (เรเดียน) ช่วงก้ม/เงยของการเล็ง
func look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, AIM_PITCH_MIN, AIM_PITCH_MAX)
	_apply()


func zoom(factor: float) -> void:
	if _shoulder:
		return
	arm_length = clampf(arm_length * factor, WALK_ARM_MIN, WALK_ARM_MAX)
	_apply()


func set_view(new_yaw: float, new_pitch: float, length: float) -> void:
	yaw = wrapf(new_yaw, -PI, PI)
	if _shoulder:
		pitch = clampf(new_pitch, AIM_PITCH_MIN, AIM_PITCH_MAX)
	else:
		pitch = clampf(new_pitch, WALK_PITCH_MIN, WALK_PITCH_MAX)
		arm_length = clampf(length, WALK_ARM_MIN, WALK_ARM_MAX)
	_first = true
	_apply()


## สลับเป็นกล้องข้ามไหล่ (on) หรือกล้องตาม: instant = ไม่หมุนสลับนุ่ม (lo/min, วางตัว)
func set_shoulder(on: bool, instant: bool = false) -> void:
	var changed := on != _shoulder
	_shoulder = on
	if changed:
		reset_input()
		if on:
			pitch = clampf(pitch, AIM_PITCH_MIN, AIM_PITCH_MAX)
		else:
			pitch = WALK_PITCH
			arm_length = WALK_ARM
	if instant or not smooth:
		_blend = 1.0 if on else 0.0
		_foot = target
	elif changed:
		set_process(true)
	_apply()


func shoulder() -> bool:
	return _shoulder


## สั่นกล้องสั้น ๆ ตอนต่อยโดน (ค่าตั้งต้น) หรือทุกนัดปืน (KICK_M, KICK_TIME) hi/mid เท่านั้น · ไม่ทับการสั่นที่แรงกว่า
func shake(m: float = SHAKE_M, t: float = SHAKE_TIME) -> void:
	if not smooth or camera == null:
		return
	if _shake > 0.0 and _shake_m * _shake / _shake_t > m:
		return
	_shake_m = m
	_shake_t = t
	_shake = t
	set_process(true)


## ลืมการลากที่ค้างอยู่ (หน้าถูกทับ หยุดเกม สลับแบบ)
func reset_input() -> void:
	_touches.clear()
	_pinch = 0.0
	_mouse_orbit = false


func forward_flat() -> Vector3:
	return flat_forward(yaw)


func right_flat() -> Vector3:
	return flat_right(yaw)


## จุดเริ่มรังสีเล็ง (ตำแหน่งกล้อง) และทิศผ่านกลางจอ
func aim_origin() -> Vector3:
	return camera.global_position if camera != null and camera.is_inside_tree() else camera_point(global_position, yaw, pitch, arm_length)


func aim_dir() -> Vector3:
	if camera != null and camera.is_inside_tree():
		return -camera.global_basis.z.normalized()
	return -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z


## ไล่ตามอยู่ สลับแบบอยู่ หรือแขนยังไม่นิ่ง
func busy() -> bool:
	return is_processing() or is_physics_processing()


## หยุดเกม: ปิดงานต่อเฟรมทั้งหมด (ตัวชนยังอยู่); เล่นต่อ: ปลุกให้คิดตำแหน่งใหม่
func set_paused(on: bool) -> void:
	reset_input()
	if on:
		_shake = 0.0
		if camera != null:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		set_process(false)
		set_physics_process(false)
		if arm != null:
			arm.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		if _foot.distance_to(target) > EPS:
			set_process(true)
		_wake_arm()


func _process(delta: float) -> void:
	var busy_now := false
	if _shoulder and _blend < 1.0:
		_blend = minf(_blend + delta / BLEND_TIME, 1.0)
		busy_now = _blend < 1.0
	elif not _shoulder and _blend > 0.0:
		_blend = maxf(_blend - delta / BLEND_TIME, 0.0)
		busy_now = _blend > 0.0
	if _shoulder and _blend >= 1.0:
		_foot = target
	else:
		_foot = _foot.lerp(target, 1.0 - exp(-FOLLOW * delta))
		if _foot.distance_to(target) < EPS:
			_foot = target
		else:
			busy_now = true
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		var k := _shake_m * _shake / _shake_t
		camera.h_offset = _shake_rng.randf_range(-k, k)
		camera.v_offset = _shake_rng.randf_range(-k, k)
		busy_now = busy_now or _shake > 0.0
		if _shake <= 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
	_apply()
	if not busy_now:
		set_process(false)


## ตั้งความยาวแขนก่อนแขนคำนวณ: ดึงเข้าทันที ยืดออกจากระยะชนจริงครั้งก่อนไม่เกิน EXTEND ม./วิ แล้วปิดตัวเองเมื่อนิ่ง
func _physics_process(delta: float) -> void:
	var want := clear_at(_arm_target())
	var next := want
	if not _first:
		next = minf(want, arm.get_hit_length() + EXTEND * delta)
	_first = false
	var moving := absf(next - arm.spring_length) > SETTLE_EPS
	arm.spring_length = next
	arm_settled.emit(arm.get_hit_length())
	_settle -= 1
	if _settle <= 0 and not is_processing() and not moving:
		arm.process_mode = Node.PROCESS_MODE_DISABLED
		set_physics_process(false)


## ความยาวแขนที่ต้องการตามแบบตอนนี้ (สลับแบบ = ค่ากลาง)
func _arm_target() -> float:
	return lerpf(arm_length, SHOULDER_ARM, _blend)


## ระยะราว length ตามทิศแขนตอนนี้ที่จุดกล้องไม่ต่ำกว่าพื้น และไม่อยู่ในของเตี้ยในห้อง (ผนัง เพดาน เสา = SpringArm3D)
func clear_at(length: float) -> float:
	var d := global_basis.z.normalized()
	var o := global_position
	var l := length
	if d.y < -0.001:
		l = minf(l, maxf((o.y - FLOOR_Y) / -d.y, 0.3))
	var props := _prop_blockers()
	var steps := 0
	while l > 0.3 and steps < 60 and _in_prop(props, o + d * l, SOLID_PAD):
		l -= 0.1
		steps += 1
	return maxf(l, 0.3)


## ของเตี้ยในห้อง (ชั้น prop ของ ArenaLayout.blockers()) อ่านครั้งเดียว; ไม่มี ArenaLayout = ไม่มีของ
func _prop_blockers() -> Array:
	if not _layout_checked:
		_layout_checked = true
		_props = []
		if ResourceLoader.exists(ARENA_LAYOUT):
			var s := load(ARENA_LAYOUT) as Script
			if s != null and s.has_method("blockers"):
				for b in s.call("blockers"):
					if str((b as Dictionary).get("layer", "")) == "prop":
						_props.append(b)
	return _props


static func _in_prop(props: Array, p: Vector3, margin: float) -> bool:
	for b in props:
		if str(b["kind"]) == "box":
			var c: Vector3 = b["c"]
			var h: Vector3 = b["h"]
			if absf(p.x - c.x) <= h.x + margin and absf(p.y - c.y) <= h.y + margin and absf(p.z - c.z) <= h.z + margin:
				return true
		else:
			var cc: Vector2 = b["c"]
			if p.y >= float(b["y0"]) - margin and p.y <= float(b["y1"]) + margin and Vector2(p.x, p.z).distance_to(cc) <= float(b["r"]) + margin:
				return true
	return false


func _apply() -> void:
	var side := _side_room(_foot + WALK_HEAD.lerp(SHOULDER_HEAD, _blend), flat_right(yaw), SHOULDER_RIGHT * _blend)
	var head := WALK_HEAD.lerp(SHOULDER_HEAD, _blend) + flat_right(yaw) * side
	global_position = _foot + head
	rotation = Vector3(pitch, yaw, 0.0)
	if camera != null:
		camera.fov = lerpf(FOV_WALK, FOV_SHOOT, _blend)
	_clamp_now()
	_wake_arm()
	turned.emit()


## ระยะเยื้องขวาที่ทำได้จริง: ชิดผนัง/เสาด้านขวา จุดหมุนหดเข้าหาหัว ให้ทรงกลมของแขนไม่เริ่มในผนัง
## (เลื่อนทรงกลม r 0.25 จากหัวไปทางขวา; หัวอยู่ในแคปซูลตัวผู้เล่น r 0.35 จึงห่างผนังพออยู่แล้ว)
func _side_room(head: Vector3, right: Vector3, want: float) -> float:
	if want <= 0.001 or not is_inside_tree() or arm == null or arm.shape == null:
		return want
	var w := get_world_3d()
	if w == null or w.direct_space_state == null:
		return want
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = arm.shape
	q.transform = Transform3D(Basis(), head)
	q.motion = right * (want + ARM_MARGIN)
	q.collision_mask = SHELL_MASK
	var r := w.direct_space_state.cast_motion(q)
	if r.size() < 1 or r[0] >= 1.0:
		return want
	return clampf((want + ARM_MARGIN) * r[0] - ARM_MARGIN, 0.0, want)


## หมุนระหว่างเฟรมฟิสิกส์ (เมาส์เล็ง): ดึงกล้องเข้าทันทีถ้าทิศใหม่ชนผนัง/เสา ไม่รอแขนคิดในเฟรมถัดไป
func _clamp_now() -> void:
	if camera == null or not is_inside_tree() or arm == null:
		return
	var w := get_world_3d()
	if w == null:
		return
	var space := w.direct_space_state
	if space == null:
		return
	var d := global_basis.z.normalized()
	var z := minf(camera.position.z, clear_at(_arm_target()))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = arm.shape
	q.transform = Transform3D(Basis(), global_position)
	q.motion = d * z
	q.collision_mask = SHELL_MASK
	var r := space.cast_motion(q)
	if r.size() >= 1 and r[0] < 1.0:
		z = maxf(z * r[0] - ARM_MARGIN, 0.0)
	if absf(camera.position.z - z) > 0.001:
		camera.position.z = z


func _wake_arm() -> void:
	if arm == null:
		return
	arm.process_mode = Node.PROCESS_MODE_INHERIT
	_settle = SETTLE_TICKS
	set_physics_process(true)


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var k := _touches.keys()
	return (_touches[k[0]] as Vector2).distance_to(_touches[k[1]])
