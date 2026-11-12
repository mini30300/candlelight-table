class_name HallAvatar
extends CharacterBody3D
## ตัวผู้เล่นในห้องโถง (LOBBY_SPEC §2.3): ไข่สีทีม เดินด้วย WASD/ลูกศร (Shift วิ่ง) หรือจอยบนจอ เดินตามทิศกล้อง
## ลอยตัว (MOTION_MODE_FLOATING) อยู่ที่ y = 0 เสมอ ชนแคปซูล r 0.35 สูง 1.75 (ชั้น 2 ชนชั้น 1) ไถลไปตามผนัง
## งานต่อเฟรม: _physics_process เปิดเฉพาะตอนกดปุ่มเดิน จอยไม่อยู่กลาง หรือยังชะลอไม่หยุด แล้วปิดตัวเอง

signal moved(pos: Vector3)

const WALK := 3.0
const RUN := 6.0
const RUN_STICK := 0.85      # ดันจอยเกินนี้ = วิ่ง
const ACCEL := 12.0          # อัตราไล่ความเร็ว (ต่อวินาที)
const TURN := 10.0           # อัตราหันตามทิศที่เดิน
const STOP := 0.01           # ช้ากว่านี้ (ม./วิ) ถือว่าหยุด
const BOB_H := 0.06
const LEAN := 0.12
const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"run"]

## กล้องที่ใช้หาทิศเดิน (ต้องมี forward_flat() / right_flat())
var camera_rig: Node3D
## โยกตัวตอนเดิน (hi/mid เท่านั้น; lo/min เลื่อนเฉย ๆ)
var bob := true
var stick := Vector2.ZERO
var face := PI               # yaw ที่หันอยู่ (ไข่หันหน้าไป +z ที่ yaw 0; PI = มอง -z)

var _vel := Vector3.ZERO
var _phase := 0.0

@onready var egg: MeshInstance3D = $Egg
@onready var name_label: Label3D = $NameLabel


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = HallLayout.SHELL_LAYER | HallLayout.PROP_LAYER
	rotation.y = face
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	for a in MOVE_ACTIONS:
		if InputMap.has_action(a) and event.is_action(a):
			set_physics_process(true)
			return


## จอยบนจอ: v.y บวก = เดินหน้า; ค่าเปลี่ยนเมื่อไรก็ปลุกการเดิน (รวมตอนปล่อย เพื่อชะลอจนหยุด)
func set_stick(v: Vector2) -> void:
	stick = v
	set_physics_process(true)


## ทิศที่ผู้เล่นสั่ง (x = ขวา, y = หน้า) ความยาวไม่เกิน 1: จอยก่อน ไม่งั้นปุ่ม
func input_vector() -> Vector2:
	var v := stick
	if v == Vector2.ZERO:
		v = Vector2(_strength(&"move_right") - _strength(&"move_left"), _strength(&"move_forward") - _strength(&"move_back"))
	return v.limit_length(1.0)


func running() -> bool:
	return stick.length() > RUN_STICK or (InputMap.has_action(&"run") and Input.is_action_pressed(&"run"))


func speed() -> float:
	return Vector2(_vel.x, _vel.z).length()


## หยุดทันที (ห้องโถงถูกหน้าอื่นทับ): ไม่ไถลต่อตอนกลับมา
func halt() -> void:
	stick = Vector2.ZERO
	_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	_reset_pose()
	set_physics_process(false)


## วางตัวผู้เล่นทันที (จุดเกิด ย้ายในเทส) หันไปทาง yaw
func place(p: Vector3, yaw: float) -> void:
	global_position = Vector3(p.x, 0.0, p.z)
	_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	face = yaw
	rotation.y = yaw
	_reset_pose()
	moved.emit(global_position)


func _physics_process(delta: float) -> void:
	var iv := input_vector()
	var want := Vector3.ZERO
	if iv.length_squared() > 0.0001 and camera_rig != null:
		var m: Vector3 = camera_rig.call("right_flat") * iv.x + camera_rig.call("forward_flat") * iv.y
		want = m.limit_length(1.0) * (RUN if running() else WALK)
	_vel = _vel.lerp(want, 1.0 - exp(-ACCEL * delta))
	if want == Vector3.ZERO and _vel.length() < STOP:
		_vel = Vector3.ZERO
		velocity = Vector3.ZERO
		_reset_pose()
		set_physics_process(false)
		return
	velocity = _vel
	move_and_slide()
	_vel = Vector3(velocity.x, 0.0, velocity.z)
	global_position.y = 0.0
	if want.length_squared() > 0.0001:
		face = lerp_angle(face, atan2(want.x, want.z), 1.0 - exp(-TURN * delta))
		rotation.y = face
	if bob:
		var sp := speed()
		_phase += delta * sp * 2.8
		egg.position.y = absf(sin(_phase)) * BOB_H * minf(sp / WALK, 1.0)
		egg.rotation.x = LEAN * minf(sp / RUN, 1.0)
	moved.emit(global_position)


func _reset_pose() -> void:
	if egg != null:
		egg.position = Vector3.ZERO
		egg.rotation = Vector3.ZERO
	_phase = 0.0


func _strength(a: StringName) -> float:
	return Input.get_action_strength(a) if InputMap.has_action(a) else 0.0
