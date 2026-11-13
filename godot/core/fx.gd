class_name Fx
extends RefCounted
## เลขคณิตจำนวนเต็มของกติกา (ARCHITECTURE §4): หน่วย MI = หนึ่งในพันนิ้ว, ไม่มีทศนิยม ไม่มีตรีโกณ
## ทุกฟังก์ชันเป็น static และให้ผลเท่ากันทุกเครื่อง (int64 ล้วน)

## 1 นิ้ว = 1000 MI
const MI := 1000
## ขอบเขตที่ to_fixed_* รับประกันว่าตรงกับ JavaScript (|mi| < 2^53)
const TO_FIXED_MAX := 9007199254740992
## ขอบล่างของ mantissa 53 บิต คูณ 1000 (= 1000 << 52) ใช้จำลองการปัดของ double ใน _double_dir
const _DBL_LO := 4503599627370496000


## หารปัดลง (floor) ต่างจาก `/` ของ GDScript ที่ตัดเข้าหาศูนย์; b == 0 ให้ 0
static func idiv(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := a / b
	if a % b != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


## หารปัดขึ้น (ceil) = -idiv(-a, b); b == 0 ให้ 0
static func cdiv(a: int, b: int) -> int:
	return -idiv(-a, b)


## เศษจากการหารที่มีเครื่องหมายตามตัวหาร (b > 0 ให้ผล 0..b-1); b == 0 ให้ 0
static func imod(a: int, b: int) -> int:
	if b == 0:
		return 0
	var r := a % b
	if r != 0 and ((r < 0) != (b < 0)):
		r += b
	return r


## รากที่สองจำนวนเต็ม ⌊√n⌋ แบบนิวตัน ตรงเป๊ะทุกค่า 0..2^63-1; n < 0 ให้ 0
static func isqrt(n: int) -> int:
	if n < 2:
		return 0 if n < 0 else n
	# เริ่มจากกำลังสองที่ไม่ต่ำกว่าราก แล้วลดลงจนนิ่ง
	var bits := 0
	var t := n
	while t > 0:
		t >>= 1
		bits += 1
	var x: int = 1 << ((bits + 1) >> 1)
	while true:
		var y := (x + n / x) >> 1
		if y >= x:
			return x
		x = y
	return x


## รากที่สองปัดขึ้น ⌈√n⌉ ตรงเป๊ะทุกค่า 0..2^63-1; n < 0 ให้ 0
static func isqrt_ceil(n: int) -> int:
	var r := isqrt(n)
	return r + 1 if r * r < n else r


## ระยะกำลังสอง (MI^2) ระหว่างสองจุด
static func dist2(ax: int, az: int, bx: int, bz: int) -> int:
	var dx := bx - ax
	var dz := bz - az
	return dx * dx + dz * dz


## ระยะ (MI) ระหว่างสองจุด = isqrt ของ dist2
static func dist(ax: int, az: int, bx: int, bz: int) -> int:
	return isqrt(dist2(ax, az, bx, bz))


## ผลคูณจุด
static func dot(ax: int, az: int, bx: int, bz: int) -> int:
	return ax * bx + az * bz


## ผลคูณไขว้ (บวก = b อยู่ทางซ้ายของ a เมื่อมองจากบน x→z)
static func cross(ax: int, az: int, bx: int, bz: int) -> int:
	return ax * bz - az * bx


## เวกเตอร์ทิศทางยาว 1000 (ปัดแบบ js_round ทีละแกน); เวกเตอร์ศูนย์ให้ [0, 0] ผู้เรียกเลือกทิศตั้งต้นเอง
static func norm1000(dx: int, dz: int) -> PackedInt64Array:
	var len := isqrt(dx * dx + dz * dz)
	if len == 0:
		return PackedInt64Array([0, 0])
	return PackedInt64Array([js_round(dx * 1000, len), js_round(dz * 1000, len)])


## Math.round ของ JavaScript บนเศษส่วน num/den: ครึ่งปัดไปทาง +∞ (js_round(-5, 2) == -2, js_round(5, 2) == 3)
## den ต้องเป็นบวก (den <= 0 ให้ 0)
static func js_round(num: int, den: int) -> int:
	if den <= 0:
		return 0
	return idiv(2 * num + den, 2 * den)


## (mi/1000).toFixed(1) ของ JavaScript เป๊ะทุกค่า |mi| < 2^53 (mi ติดลบที่ปัดเป็นศูนย์ยังมีเครื่องหมายลบ เหมือน JS)
static func to_fixed_1(mi: int) -> String:
	return _to_fixed(mi, 1)


## (mi/1000).toFixed(2) ของ JavaScript เป๊ะทุกค่า |mi| < 2^53
static func to_fixed_2(mi: int) -> String:
	return _to_fixed(mi, 2)


## กติกาของ toFixed: ปัดขนาด (ไม่รวมเครื่องหมาย) ไปหา n ที่ใกล้ค่า double ที่สุด ถ้าเสมอกันเลือก n ที่มากกว่า
## ค่า double ของ mi/1000 ไม่ตรงทศนิยมพอดี จึงต้องดูว่ามันตกเหนือหรือใต้ครึ่งด้วย _double_dir
static func _to_fixed(mi: int, f: int) -> String:
	var neg := mi < 0
	var a := -mi if neg else mi
	var unit := 100 if f == 1 else 10
	var q := a / unit
	var r := a % unit
	var half := unit / 2
	if r > half or (r == half and _double_dir(a) >= 0):
		q += 1
	var scale := 10 if f == 1 else 100
	var ip := q / scale
	var fp := q % scale
	var s := str(ip) + "." + str(fp).lpad(f, "0")
	return "-" + s if neg else s


## ทิศของ double ที่ใกล้ a/1000 ที่สุดเทียบกับค่าจริง: 1 = สูงกว่า, -1 = ต่ำกว่า, 0 = เท่ากันพอดี (0 < a < 2^53)
static func _double_dir(a: int) -> int:
	var x := a
	while x < _DBL_LO:
		x = x * 2
	var rem := x % 1000
	if rem == 0:
		return 0
	if rem * 2 > 1000:
		return 1
	if rem * 2 < 1000:
		return -1
	# ครึ่งพอดี: double ปัดไปเลขคู่
	return 1 if ((x / 1000) & 1) == 1 else -1


## เรียงแบบเสถียร (merge sort): สมาชิกที่เท่ากันคงลำดับเดิม; คืนอาร์เรย์ใหม่ ไม่แก้ของเดิม
## less(a, b) -> bool ต้องเป็น strict weak ordering
static func stable_sort(arr: Array, less: Callable) -> Array:
	var n := arr.size()
	var src := arr.duplicate()
	if n < 2:
		return src
	var dst := arr.duplicate()
	var width := 1
	while width < n:
		var i := 0
		while i < n:
			_merge(src, dst, i, mini(i + width, n), mini(i + 2 * width, n), less)
			i += 2 * width
		var tmp := src
		src = dst
		dst = tmp
		width *= 2
	return src


static func _merge(src: Array, dst: Array, lo: int, mid: int, hi: int, less: Callable) -> void:
	var i := lo
	var j := mid
	var k := lo
	while k < hi:
		if i < mid and (j >= hi or not bool(less.call(src[j], src[i]))):
			dst[k] = src[i]
			i += 1
		else:
			dst[k] = src[j]
			j += 1
		k += 1


## จำกัดค่าในช่วง [lo, hi]
static func clampi(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## เครื่องหมาย: -1, 0, 1
static func sign(v: int) -> int:
	if v < 0:
		return -1
	return 1 if v > 0 else 0


## ไซน์แบบจำนวนเต็ม: มุมเป็นเรเดียนแบบ Q16 (65536 = 1 เรเดียน) คืนค่า Q16 (-65536..65536)
## พับมุมเข้าช่วง -pi/2..pi/2 แล้วใช้อนุกรมเทย์เลอร์ถึงพจน์กำลังเก้า (คลาดไม่เกินราวสี่หน่วย Q16)
const PI_Q16 := 205887
const HALF_PI_Q16 := 102944
static func isin_q16(theta: int) -> int:
	var x := imod(theta + PI_Q16, 2 * PI_Q16) - PI_Q16
	if x > HALF_PI_Q16:
		x = PI_Q16 - x
	elif x < -HALF_PI_Q16:
		x = -PI_Q16 - x
	var x2 := (x * x) >> 16
	var t := 65536 - idiv(x2, 72)
	t = 65536 - idiv((x2 * t) >> 16, 42)
	t = 65536 - idiv((x2 * t) >> 16, 20)
	t = 65536 - idiv((x2 * t) >> 16, 6)
	return (x * t) >> 16
