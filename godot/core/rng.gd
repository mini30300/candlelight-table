class_name Rng
extends RefCounted
## ตัวสุ่ม PCG32 (ARCHITECTURE §4): สถานะ 64 บิต ผลลัพธ์ 32 บิต หนึ่งสตรีมต่อหนึ่งงาน
## สตรีม: terrain, props, objectives, armies, deploy, bot:<seat>, fallback:<seq>:<stage>
## ค่าคงที่เขียนเป็นฐานสิบมีเครื่องหมาย (ฐานสิบหกเกิน int64 แปลงไม่ได้) และ `>>` ของ GDScript เติมบิตเครื่องหมาย จึงมาสก์ทุกครั้ง

## ตัวคูณของ PCG
const MULT := 6364136223846793005
## มาสก์ 32 บิต
const M32 := 4294967295
## มาสก์หลังเลื่อนขวา 18 บิต = (1 << 46) - 1
const M46 := 70368744177663
## 2^32
const TWO32 := 4294967296

var _s: int = 0
var _inc: int = 1
## ชื่อสตรีมและ seed ที่ใช้สร้าง (ไว้ดูตอนดีบัก)
var stream: String = ""
var seed_value: int = 0
## จำนวนครั้งที่สุ่มไปแล้ว
var draws: int = 0


## สร้างสตรีมจากชื่อและ seed (pcg32_srandom_r): inc มาจากแฮชชื่อสตรีม เป็นเลขคี่เสมอ จึงเป็นอิสระจากสตรีมอื่น
static func make(stream_name: String, seed_v: int) -> Rng:
	var r := Rng.new()
	r.stream = stream_name
	r.seed_value = seed_v
	r._inc = (Hash.fnv1a64_str(stream_name) << 1) | 1
	r._s = 0
	r._step()
	r._s = r._s + seed_v
	r._step()
	return r


func _step() -> void:
	_s = _s * MULT + _inc


## เลขสุ่ม 32 บิต 0..2^32-1 (XSH-RR)
func next_u32() -> int:
	var old := _s
	_step()
	draws += 1
	var t := ((old >> 18) & M46) ^ old
	var xs := (t >> 27) & M32
	var rot := (old >> 59) & 31
	return ((xs >> rot) | (xs << ((32 - rot) & 31))) & M32


## เลขสุ่ม 0..n-1 ไม่เอนเอียง (ทิ้งค่าที่ต่ำกว่า threshold แล้วสุ่มใหม่); n ต้องอยู่ใน 1..2^32, n <= 1 ให้ 0
func bounded(n: int) -> int:
	if n <= 1:
		return 0
	var threshold := (TWO32 - n) % n
	while true:
		var r := next_u32()
		if r >= threshold:
			return r % n
	return 0


## ลูกเต๋าหกหน้า 1..6
func d6() -> int:
	return 1 + bounded(6)


## สถานะสำหรับบันทึก (int ล้วน)
func state() -> Dictionary:
	return {"s": _s, "inc": _inc, "draws": draws}


## คืนสถานะจาก state(); ผิดรูปคืน false และไม่แก้อะไร
func restore(d: Dictionary) -> bool:
	if not (d.has("s") and d.has("inc") and typeof(d["s"]) == TYPE_INT and typeof(d["inc"]) == TYPE_INT):
		return false
	if (int(d["inc"]) & 1) == 0:
		return false
	_s = int(d["s"])
	_inc = int(d["inc"])
	draws = int(d["draws"]) if d.has("draws") and typeof(d["draws"]) == TYPE_INT else 0
	return true


## สำเนาที่สุ่มต่อได้โดยไม่กระทบตัวเดิม
func copy() -> Rng:
	var r := Rng.new()
	r.stream = stream
	r.seed_value = seed_value
	r._s = _s
	r._inc = _inc
	r.draws = draws
	return r
