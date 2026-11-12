class_name TouchStick
extends Control
## จอยบนจอของห้องโถง (LOBBY_SPEC §2.5): ฐานรัศมี 90 px ปุ่มกลาง 40 px เขตตาย 0.15 ดันเกิน 0.85 = วิ่ง
## จับนิ้วของตัวเอง (InputEventScreenTouch/Drag ตาม index) และรับลากเมาส์จริงด้วย (ลองด้วยเมาส์เมื่อบังคับเปิด)
## เมาส์ที่จำลองจากนิ้ว (DEVICE_ID_EMULATION) ถูกข้าม ไม่งั้นนิ้วเดียวนับสองครั้ง
## changed(v): v.y บวก = เดินหน้า (จอขึ้น), ยาวไม่เกิน 1 · วาดใหม่เมื่อค่าเปลี่ยนเท่านั้น ไม่มีงานต่อเฟรม

signal changed(v: Vector2)

const BASE_R := 90.0
const KNOB_R := 40.0
const DEAD := 0.15
const RUN := 0.85
const RIM := Color(0.91, 0.72, 0.38, 0.85)
const FILL := Color(0.08, 0.05, 0.03, 0.45)
const KNOB := Color(0.95, 0.80, 0.50, 0.9)

var value := Vector2.ZERO
var _finger := -1
var _mouse := false
var _knob := Vector2.ZERO          # ระยะปุ่มจากกลาง (px)


func _ready() -> void:
	custom_minimum_size = Vector2(BASE_R, BASE_R) * 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	set_physics_process(false)
	visibility_changed.connect(_on_visibility)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _finger < 0 and not _mouse:
			_finger = t.index
			_follow(t.position)
			accept_event()
		elif not t.pressed and t.index == _finger:
			release()
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _finger:
			_follow(d.position)
			accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and _finger < 0:
			_mouse = true
			_follow(mb.position)
		elif not mb.pressed and _mouse:
			release()
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _mouse:
		_follow((event as InputEventMouseMotion).position)
		accept_event()


## ปล่อยจอย (ยกนิ้ว ซ่อนจอ หรือหน้าจอถูกปิด)
func release() -> void:
	_finger = -1
	_mouse = false
	_knob = Vector2.ZERO
	_set_value(Vector2.ZERO)
	queue_redraw()


func held() -> bool:
	return _finger >= 0 or _mouse


func running() -> bool:
	return value.length() > RUN


## เส้นวงไม่ลบรอยหยัก (antialiased = false): แบบลบรอยหยักเพิ่ม draw call ละ 2 ต่อเส้น เกินงบ min ในห้องโถง
func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, BASE_R, FILL)
	draw_arc(c, BASE_R - 2.0, 0.0, TAU, 48, RIM, 3.0, false)
	draw_arc(c, BASE_R * RUN, 0.0, TAU, 40, Color(RIM, 0.3), 2.0, false)
	draw_circle(c + _knob, KNOB_R, KNOB)
	draw_arc(c + _knob, KNOB_R, 0.0, TAU, 32, Color(0.3, 0.18, 0.08, 0.9), 2.0, false)


## ตำแหน่งนิ้ว/เมาส์ในพิกัดของจอย → ค่าจอย (เขตตายเป็นศูนย์)
func _follow(local: Vector2) -> void:
	var off := (local - size * 0.5).limit_length(BASE_R)
	_knob = off
	var v := Vector2(off.x, -off.y) / BASE_R
	_set_value(Vector2.ZERO if v.length() < DEAD else v)
	queue_redraw()


func _set_value(v: Vector2) -> void:
	if v.is_equal_approx(value):
		return
	value = v
	changed.emit(v)


func _on_visibility() -> void:
	if not is_visible_in_tree() and held():
		release()
