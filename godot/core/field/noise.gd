class_name FieldNoise
extends RefCounted
## นอยส์ของพื้นสนามแบบจำนวนเต็มจุดคงที่ Q16 (ONE = 65536 คือหนึ่ง) ทุกเครื่องได้ค่าเดียวกัน
## สูตรเดียวกับหน้าเก่า (value noise + fade ของ Perlin + fbm ครึ่งแอมพลิจูด สองเท่าความถี่)
## แต่ใช้แฮชของรุ่นสิบ (Hash.ihash2) ค่าจึงไม่ตรงกับหน้าเก่าทีละจุด แต่ลักษณะพื้นเหมือนกัน

## หนึ่งในหน่วย Q16
const ONE := 65536
const HALF := 32768
const FRAC := 65535


## ค่าสุ่มของจุดกริด 0..ONE-1 (16 บิตบนของแฮช)
static func lattice(ix: int, iy: int, salt: int) -> int:
	return (Hash.ihash2(ix, iy, salt) >> 16) & FRAC


## เส้นโค้งนุ่ม t^3 (6t^2 - 15t + 10) ของ t ใน 0..ONE (Q16) คิดละเอียดแบบ Q24 แล้วปัดเศษ (เพิ่มขึ้นตาม t เสมอ)
static func fade_q(t: int) -> int:
	var p := 6 * t * t - 15 * t * ONE + 10 * ONE * ONE      # Q32 ค่าบวกเสมอเมื่อ t อยู่ใน 0..ONE
	var t3 := (t * t * t) >> 24                               # Q24
	return (t3 * (p >> 8) + (1 << 31)) >> 32


## ผสมเชิงเส้น a ไป b ด้วย u ใน 0..ONE (Q16)
static func mix_q(a: int, b: int, u: int) -> int:
	return a + (((b - a) * u + HALF) >> 16)


## value noise ที่จุด (x, y) แบบ Q16 คืนค่า -ONE..ONE
static func vnoise(x: int, y: int, salt: int) -> int:
	var ix := x >> 16
	var iy := y >> 16
	var u := fade_q(x & FRAC)
	var v := fade_q(y & FRAC)
	var top := mix_q(lattice(ix, iy, salt), lattice(ix + 1, iy, salt), u)
	var bottom := mix_q(lattice(ix, iy + 1, salt), lattice(ix + 1, iy + 1, salt), u)
	return mix_q(top, bottom, v) * 2 - ONE


## fbm: รวม oct ชั้น ชั้นถัดไปความถี่สองเท่า แอมพลิจูดครึ่งหนึ่ง แล้วหารด้วยผลรวมแอมพลิจูด คืนค่า -ONE..ONE
static func fbm(x: int, y: int, oct: int, salt: int) -> int:
	var s := 0
	var n := 0
	var a := ONE
	for i: int in oct:
		s += (a * vnoise(x << i, y << i, salt) + HALF) >> 16
		n += a
		a >>= 1
	return Fx.idiv(s * ONE, n) if n > 0 else 0


## สันเขา (1 - |fbm|) ยกกำลังสอง แบบหน้าเก่าในภูมิประเทศภูเขา คืนค่า 0..ONE
static func ridge(x: int, y: int, oct: int, salt: int) -> int:
	var f := fbm(x, y, oct, salt)
	var r := ONE - (f if f >= 0 else -f)
	return (r * r) >> 16


## พิกัด MI -> พิกัดนอยส์ Q16 ของ x / สเกล + ออฟเซ็ต (สเกลเป็น MI เช่น 4500 = 4 นิ้วครึ่ง, ออฟเซ็ตเป็นส่วนพัน)
static func at(mi: int, scale_mi: int, offset_milli: int) -> int:
	return Fx.idiv((mi * 1000 + offset_milli * scale_mi) * ONE, scale_mi * 1000)


## พิกัดนิ้วแบบ MI -> พิกัดนอยส์ Q16 ที่สเกล 1/scale_in (เช่น scale_in 34 = x/34 ของหน้าเก่า) บวกออฟเซ็ตเป็น MI
static func at_mi(mi: int, scale_in: int, offset_mi: int) -> int:
	return Fx.idiv((mi + offset_mi * scale_in) * ONE, scale_in * Fx.MI)
