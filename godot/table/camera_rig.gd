class_name CameraRig
extends Node3D
## กล้องของโต๊ะ (ใช้ร่วมทั้งสองโต๊ะ): นิ้วเดียวลาก = เลื่อน, สองนิ้วหนีบ = ซูม, บิด = หมุน, สองนิ้วลากขึ้นลง = ก้ม/เงย
## เมาส์: ซ้ายลาก = เลื่อน, ขวา/กลางลาก = หมุน, ล้อ = ซูม · WASD/ลูกศร = เลื่อน (ทำงานต่อเฟรมเฉพาะตอนกดค้าง)
## แตะสั้น ๆ ไม่ขยับ = tapped(ตำแหน่งจอ) · fit_table() ซูมให้เห็นทั้งโต๊ะ · ก้มกล้องได้ 20–80°
## เหตุการณ์เมาส์ที่จำลองจากนิ้ว (device == DEVICE_ID_EMULATION) ถูกข้าม ไม่งั้นนิ้วเดียวจะทำงานสองเท่า

signal tapped(screen_pos: Vector2)
signal moved

const PITCH_MIN := -1.3963   # 80° (ก้มสุด)
const PITCH_MAX := -0.3491   # 20°
const TAP_PX := 14.0
const TAP_MS := 350
const BIT_W := 1
const BIT_S := 2
const BIT_A := 4
const BIT_D := 8

@export var target := Vector3(0.0, 0.5, 0.0)
@export var distance := 31.0
@export var yaw := -0.35
@export var pitch := -0.95
@export var min_distance := 2.0
@export var max_distance := 140.0
@export var orbit_speed := 0.006
@export var wheel_step := 0.9
@export var key_speed := 0.7           # ส่วนของความกว้างที่เห็น ต่อวินาที

@onready var camera: Camera3D = $Camera3D

var bounds := Rect2(-24.0, -17.0, 48.0, 34.0)   # ขอบเขตของจุดเป้า (x, z)

var _touches: Dictionary = {}          # นิ้ว index → ตำแหน่ง
var _pinch_distance := 0.0
var _pinch_angle := 0.0
var _pinch_centre := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _press_moved := 0.0
var _press_live := false
var _mouse_pan := false
var _mouse_orbit := false
var _keys := 0


func _ready() -> void:
	set_process(false)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mm := event as InputEventMouseMotion
		if _mouse_orbit:
			_orbit(mm.relative)
		elif _mouse_pan:
			_press_moved += mm.relative.length()
			_pan(mm.relative)
	elif event is InputEventKey:
		_key(event as InputEventKey)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if _keys & BIT_W:
		dir.y -= 1.0
	if _keys & BIT_S:
		dir.y += 1.0
	if _keys & BIT_A:
		dir.x -= 1.0
	if _keys & BIT_D:
		dir.x += 1.0
	if dir == Vector2.ZERO:
		set_process(false)
		return
	# เลื่อนเหมือนลากจอทางตรงข้าม: W = ไปข้างหน้า
	var px := _visible_height_px() * key_speed * delta
	_pan(-dir.normalized() * px)


# ---- นิ้ว ----

func _touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_begin_press(t.position)
		else:
			_press_live = false
			_begin_pinch()
	else:
		_touches.erase(t.index)
		if _touches.is_empty():
			_end_press(t.position)
		else:
			_begin_pinch()   # เหลือนิ้วเดียว: ลากต่อโดยไม่นับเป็นแตะ


func _drag(d: InputEventScreenDrag) -> void:
	_touches[d.index] = d.position
	if _touches.size() >= 2:
		var pts := _two_points()
		var dist := pts[0].distance_to(pts[1])
		var ang := (pts[1] - pts[0]).angle()
		var centre := (pts[0] + pts[1]) * 0.5
		if _pinch_distance > 1.0 and dist > 1.0:
			_zoom(_pinch_distance / dist)
		yaw += wrapf(ang - _pinch_angle, -PI, PI)
		pitch = clampf(pitch - (centre.y - _pinch_centre.y) * orbit_speed, PITCH_MIN, PITCH_MAX)
		_pinch_distance = dist
		_pinch_angle = ang
		_pinch_centre = centre
		_apply()
	else:
		_press_moved += d.relative.length()
		_pan(d.relative)


func _begin_pinch() -> void:
	if _touches.size() < 2:
		return
	var pts := _two_points()
	_pinch_distance = pts[0].distance_to(pts[1])
	_pinch_angle = (pts[1] - pts[0]).angle()
	_pinch_centre = (pts[0] + pts[1]) * 0.5


func _two_points() -> Array[Vector2]:
	var keys := _touches.keys()
	return [_touches[keys[0]] as Vector2, _touches[keys[1]] as Vector2]


# ---- เมาส์ ----

func _mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			_mouse_pan = mb.pressed
			if mb.pressed:
				_begin_press(mb.position)
			else:
				_end_press(mb.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_mouse_orbit = mb.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom(wheel_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom(1.0 / wheel_step)


func _key(k: InputEventKey) -> void:
	var bit := 0
	match k.keycode:
		KEY_W, KEY_UP:
			bit = BIT_W
		KEY_S, KEY_DOWN:
			bit = BIT_S
		KEY_A, KEY_LEFT:
			bit = BIT_A
		KEY_D, KEY_RIGHT:
			bit = BIT_D
		_:
			return
	if k.pressed:
		_keys |= bit
	else:
		_keys &= ~bit
	set_process(_keys != 0)


# ---- แตะกับลาก ----

func _begin_press(pos: Vector2) -> void:
	_press_pos = pos
	_press_ms = Time.get_ticks_msec()
	_press_moved = 0.0
	_press_live = true


func _end_press(pos: Vector2) -> void:
	if not _press_live:
		return
	_press_live = false
	if _press_moved <= TAP_PX and pos.distance_to(_press_pos) <= TAP_PX and Time.get_ticks_msec() - _press_ms <= TAP_MS:
		tapped.emit(pos)


# ---- การเคลื่อนกล้อง ----

## ซูมให้เห็นทั้งโต๊ะ w×d (จุดเป้ากลางโต๊ะ) และจำขอบเขตไว้กันเลื่อนหลุดโต๊ะ
func fit_table(w: float, d: float) -> void:
	bounds = Rect2(-w * 0.5, -d * 0.5, w, d)
	target = Vector3(0.0, 0.5, 0.0)
	pitch = -0.95
	var r := sqrt(w * w + d * d) * 0.5
	var half_v := deg_to_rad(camera.fov) * 0.5
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var aspect := size.x / maxf(size.y, 1.0)
	var half_h := atan(tan(half_v) * aspect)
	distance = clampf(r / sin(minf(half_v, half_h)) * 0.8, min_distance, max_distance)
	_apply()


func _visible_height_px() -> float:
	return get_viewport().get_visible_rect().size.y if is_inside_tree() else 720.0


## เลื่อนจุดเป้าตามการลาก rel (พิกเซล): ความกว้างที่เห็นที่ระยะเป้าหารด้วยความสูงจอ
func _pan(rel: Vector2) -> void:
	var per_px := 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5) / _visible_height_px()
	var right := camera.global_basis.x
	right.y = 0.0
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if right.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return
	right = right.normalized()
	forward = forward.normalized()
	target += (-right * rel.x + forward * rel.y) * per_px
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	_apply()


func _orbit(rel: Vector2) -> void:
	yaw -= rel.x * orbit_speed
	pitch = clampf(pitch - rel.y * orbit_speed, PITCH_MIN, PITCH_MAX)
	_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func _apply() -> void:
	pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	camera.global_position = target + basis * Vector3(0.0, 0.0, distance)
	camera.look_at(target, Vector3.UP)
	moved.emit()
