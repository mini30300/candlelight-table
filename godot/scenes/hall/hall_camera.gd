class_name HallCamera
extends Node3D
## กล้องตามตัวผู้เล่นในห้องโถง (LOBBY_SPEC §2.4): จุดหมุนตามหัวตัวผู้เล่น (+1.3 ม.) แบบนุ่ม 1 − e^(−10·dt)
## แขน SpringArm3D (ชนเฉพาะผนังกับเพดาน ทรงกลม r 0.3 ระยะเผื่อ 0.1) · เสา เชิงเทียน เฟอร์นิเจอร์: ดึงกล้องเข้าเฉพาะตอน
## จุดกล้องจะอยู่ในของ (HallLayout.camera_clear) ของที่แค่บังแนวไม่ดึง · ดึงเข้าทันที ยืดกลับออกไม่เกิน EXTEND ม./วิ
## เมาส์ลากซ้าย/ขวา = หมุน, ล้อ = ซูม · นิ้วเดียวลากนอกจอย/ปุ่ม = หมุน, สองนิ้วหนีบ = ซูม
## เหตุการณ์เมาส์ที่จำลองจากนิ้ว (DEVICE_ID_EMULATION) ถูกข้ามเหมือน CameraRig
## งานต่อเฟรม: _process เฉพาะตอนจุดหมุนยังไล่ตาม (หยุดเมื่อห่างไม่ถึง 1 ซม.); แขนปิดตัวเองเมื่อนิ่งครบ 3 เฟรมฟิสิกส์

signal turned
## ตำแหน่ง/ทิศของกล้องเปลี่ยน (ป้ายชื่อ 2 มิติของเพื่อนวาดใหม่, NET_SPEC §6.2)
signal view_changed
## ความยาวแขนจริงหลังชน (ส่งเฉพาะตอนแขนยังไม่นิ่ง)
signal arm_settled(length: float)

const PITCH_MIN := -1.2
const PITCH_MAX := -0.15
const ARM_MIN := 3.0
const ARM_MAX := 9.0
const HEAD := Vector3(0.0, 1.3, 0.0)
const FOLLOW := 10.0
const EPS := 0.01
const ORBIT_SPEED := 0.006
const WHEEL := 0.9
const SETTLE_TICKS := 3
const WALL_PAD := 0.45      # ประมาณจุดที่ผนังดันกล้องมา (ทรงกลม 0.3 + เผื่อ 0.1 + กันพลาด)
const EXTEND := 4.0         # แขนยืดกลับออกไม่เกินกี่เมตรต่อวินาที (กันกล้องกระโดด)

@export var yaw := 0.0
@export var pitch := -0.45
@export var arm_length := 6.5

@onready var arm: SpringArm3D = $Arm
@onready var camera: Camera3D = $Arm/Camera3D

var target := Vector3.ZERO
## ผังห้องที่กล้องอยู่ (null = HallLayout ของดาดฟ้า; ห้องเสริมใส่ RoomLayout, PACK_SPEC §9)
var layout: Object = null

var _touches: Dictionary = {}          # นิ้ว index → ตำแหน่ง
var _pinch := 0.0
var _mouse_orbit := false
var _settle := 0
var _reach := -1.0          # ความยาวแขนที่ปล่อยให้ใช้ (-1 = ตั้งทันทีในเฟรมฟิสิกส์ถัดไป)


func _ready() -> void:
	process_physics_priority = -1   # ตั้งความยาวแขนก่อนแขนคิดเสมอ
	arm.collision_mask = HallLayout.SHELL_LAYER
	if arm.shape == null:
		var s := SphereShape3D.new()
		s.radius = 0.3
		arm.shape = s
	arm.margin = 0.1
	arm.spring_length = arm_length
	_apply()
	set_process(false)
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
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


## ตามตัวผู้เล่นที่ p (เท้า) แบบนุ่ม
func follow(p: Vector3) -> void:
	target = p + HEAD
	if global_position.distance_to(target) > EPS:
		set_process(true)
	_wake_arm()


## ย้ายจุดหมุนไปที่ p ทันที (จุดเกิด ย้ายตัวผู้เล่น)
func snap(p: Vector3) -> void:
	target = p + HEAD
	global_position = target
	set_process(false)
	_reach = -1.0
	_clamp_camera()
	_wake_arm()
	view_changed.emit()


func orbit(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, PITCH_MIN, PITCH_MAX)
	_apply()


func zoom(factor: float) -> void:
	arm_length = clampf(arm_length * factor, ARM_MIN, ARM_MAX)
	_apply()


func set_view(new_yaw: float, new_pitch: float, length: float) -> void:
	yaw = wrapf(new_yaw, -PI, PI)
	pitch = clampf(new_pitch, PITCH_MIN, PITCH_MAX)
	arm_length = clampf(length, ARM_MIN, ARM_MAX)
	_reach = -1.0
	_apply()


## ลืมการลากที่ค้างอยู่ (ห้องโถงถูกหน้าอื่นทับ ปล่อยปุ่ม/นิ้วตอนนั้นจะไม่มาถึง)
func reset_input() -> void:
	_touches.clear()
	_pinch = 0.0
	_mouse_orbit = false


## ทิศหน้า/ขวาบนพื้นของกล้อง (ใช้หาทิศเดินของตัวผู้เล่น)
func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## ไล่ตามอยู่ หรือแขนยังไม่นิ่ง
func busy() -> bool:
	return is_processing() or is_physics_processing()


func _process(delta: float) -> void:
	global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW * delta))
	if global_position.distance_to(target) < EPS:
		global_position = target
		set_process(false)
	_clamp_camera()
	_wake_arm()
	view_changed.emit()


## ตั้งความยาวแขนก่อนแขนคำนวณ (process_physics_priority ต่ำกว่า) นับเฟรมให้แขนคิดระยะใหม่หลังขยับครั้งสุดท้าย แล้วปิดแขนกับตัวเอง
func _physics_process(delta: float) -> void:
	var want := clear_length()
	var next := want
	if _reach >= 0.0 and want > _reach:
		# ยืดออกทีละน้อย และไม่ผ่านกลางของ: จุดถัดไปอยู่ในของก็ค้างไว้หน้าของ
		next = clear_at(minf(want, _reach + EXTEND * delta))
	var moving := absf(next - _reach) > 0.001
	_reach = next
	arm.spring_length = _reach
	arm_settled.emit(arm.get_hit_length())
	view_changed.emit()
	_settle -= 1
	if _settle <= 0 and not is_processing() and not moving:
		arm.process_mode = Node.PROCESS_MODE_DISABLED
		set_physics_process(false)


## ความยาวแขนที่กล้องไม่ชนผนัง/เพดาน และไม่อยู่ในของในห้อง (ตามทิศแขนตอนนี้)
func clear_length() -> float:
	return clear_at(arm_length)


## ระยะราว length ตามทิศแขนตอนนี้ ที่จุดกล้องไม่ใกล้ผนัง/เพดานเกิน WALL_PAD และไม่อยู่ในของ (ถอยไปหลังของได้ไม่เกิน ARM_MAX)
func clear_at(length: float) -> float:
	var d := global_basis.z.normalized()
	var o := global_position
	if layout != null:
		var r: float = layout.room_clear(o, d, WALL_PAD)
		return layout.camera_clear(o, d, minf(length, r), HallLayout.CAM_PAD, minf(r, ARM_MAX))
	var room := HallLayout.room_clear(o, d, WALL_PAD)
	return HallLayout.camera_clear(o, d, minf(length, room), HallLayout.CAM_PAD, minf(room, ARM_MAX))


func _apply() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	_clamp_camera()
	_wake_arm()
	turned.emit()
	view_changed.emit()


## จุดหมุนกับทิศขยับหลังแขนคิดในเฟรมฟิสิกส์ (เฟรมภาพช้ากว่าฟิสิกส์ได้หลายก้าว): ดึงกล้องเข้าทันทีถ้าจะอยู่ในของหรือผนัง
func _clamp_camera() -> void:
	if camera == null:
		return
	var z := camera.position.z
	var c := clear_at(z)
	if absf(c - z) > 0.001:
		camera.position.z = c


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
