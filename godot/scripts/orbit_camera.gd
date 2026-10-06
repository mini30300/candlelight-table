extends Node3D
## กล้องวงโคจรรอบจุดเป้า: เมาส์ลากซ้าย = หมุน, ล้อ = ซูม · นิ้วเดียวลาก = หมุน, สองนิ้วหนีบ = ซูม
## เหตุการณ์เมาส์ที่จำลองจากนิ้ว (device == DEVICE_ID_EMULATION) ถูกข้าม ไม่งั้นนิ้วเดียวจะหมุนสองเท่า

@export var target := Vector3(0.0, 1.5, 0.0)
@export var distance := 31.0
@export var yaw := -0.35
@export var pitch := -0.38
@export var min_distance := 2.0
@export var max_distance := 120.0
@export var orbit_speed := 0.006
@export var wheel_step := 0.9

@onready var camera: Camera3D = $Camera3D

var _mouse_down := false
var _touches: Dictionary = {}   # นิ้ว index → ตำแหน่ง
var _pinch_distance := 0.0


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_distance = _current_pinch()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var d := _current_pinch()
			if _pinch_distance > 1.0 and d > 1.0:
				_zoom(_pinch_distance / d)
			_pinch_distance = d
		else:
			_orbit(drag.relative)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(wheel_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / wheel_step)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _mouse_down:
			_orbit((event as InputEventMouseMotion).relative)


func _current_pinch() -> float:
	if _touches.size() < 2:
		return 0.0
	var keys := _touches.keys()
	return (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]])


func _orbit(rel: Vector2) -> void:
	yaw -= rel.x * orbit_speed
	pitch = clampf(pitch - rel.y * orbit_speed, -1.45, -0.05)
	_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func _apply() -> void:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	camera.global_position = target + basis * Vector3(0.0, 0.0, distance)
	camera.look_at(target, Vector3.UP)
