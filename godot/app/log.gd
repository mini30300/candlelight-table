extends Node
## Log (autoload): เก็บล็อก 500 บรรทัดล่าสุดไว้ในแอป (ปุ่ม "คัดลอกล็อก" ในตั้งค่าอ่านจาก dump())
## info/warn/error ใส่บัฟเฟอร์วงกลมและพิมพ์ออก console ด้วยเมื่อ echo เป็น true (เทสปิดได้)

const CAPACITY := 500

var echo: bool = true

var _buf: PackedStringArray = PackedStringArray()   # ขนาด CAPACITY ใช้วน
var _head: int = 0      # ช่องที่จะเขียนถัดไป
var _count: int = 0     # จำนวนบรรทัดที่เก็บอยู่ (≤ CAPACITY)


func _init() -> void:
	_buf.resize(CAPACITY)


func info(msg: String) -> void:
	_add("I", msg)
	if echo:
		print(msg)


func warn(msg: String) -> void:
	_add("W", msg)
	if echo:
		push_warning(msg)


func error(msg: String) -> void:
	_add("E", msg)
	if echo:
		push_error(msg)


## บรรทัดทั้งหมดจากเก่าไปใหม่
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	var start := (_head - _count + CAPACITY) % CAPACITY
	for i in _count:
		out.append(_buf[(start + i) % CAPACITY])
	return out


## ล็อกทั้งก้อนเป็นข้อความเดียว (สำหรับคัดลอก)
func dump() -> String:
	return "\n".join(lines())


func size() -> int:
	return _count


func clear() -> void:
	_head = 0
	_count = 0


func _add(level: String, msg: String) -> void:
	_buf[_head] = "%s %d %s" % [level, Time.get_ticks_msec(), msg]
	_head = (_head + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
