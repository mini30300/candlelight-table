extends Node
## Clock (autoload): แหล่งเวลาเดียวของตัวจับเวลาฝั่งภาพ หน่วยมิลลิวินาที
## ปกติเดินตาม Time.get_ticks_msec(); เทสสั่ง frozen = true แล้ว step(ms) เอง (เหมือน BT.clock(false)/BT.tick ของหน้าเก่า)
## ไม่มี signal และไม่มีงานต่อเฟรม: now_ms() คำนวณตอนถูกเรียก · กติกาไม่ใช้เวลานี้ (เวลาในกติกามากับ act)

var frozen: bool = false: set = set_frozen

var _offset: int = 0   # หักจาก ticks ตอนเดิน (เริ่มที่ 0 และรองรับ step ตอนเดิน)
var _held: int = 0     # ค่าเวลาตอนหยุด


func _init() -> void:
	_offset = Time.get_ticks_msec()


## เวลาปัจจุบัน (ms) นับจากเปิดแอป; ค่าคงที่ตอนหยุด
func now_ms() -> int:
	return _held if frozen else Time.get_ticks_msec() - _offset


## เลื่อนเวลาไปข้างหน้า ms (ใช้ได้ทั้งตอนหยุดและตอนเดิน)
func step(ms: int) -> void:
	if frozen:
		_held += ms
	else:
		_offset -= ms


func set_frozen(v: bool) -> void:
	if v == frozen:
		return
	if v:
		_held = now_ms()
	else:
		_offset = Time.get_ticks_msec() - _held
	frozen = v
