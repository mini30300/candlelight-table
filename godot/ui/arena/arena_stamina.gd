class_name ArenaStamina
extends RefCounted
## ความเหนื่อยแบบซ่อน (ไม่มีหลอดบนจอ, 0.14 ข้อ 1b): ความเร็ววิกฤต cs + แรงสำรอง dprime (ม. ที่วิ่งเกิน cs ได้)
## เร็วกว่า cs ใช้แรง (v − cs)·dt · ช้ากว่า cs ฟื้นแบบเอกซ์โพเนนเชียล ช่วงเวลา dprime / (cs − v) (ยืนฟื้นเร็วสุด)
## สำรองต่ำกว่า knee ความเร็วสูงสุดลดนุ่ม ๆ หา cs · ตัวเลขทั้งหมดจาก ArenaData · ติ๊กคงที่ ไม่สุ่ม ไม่อ่านเวลาเครื่อง

var cls := "human"
var walk := 0.0
var jog := 0.0
var back := 0.0
var vmax := 0.0
var accel := 0.0
var sprint_accel := 0.0
var cs := 0.0                # 0 = ไม่เหนื่อย (เครื่องจักร)
var dprime := 0.0
var knee := 0.0
var bal := 0.0               # แรงสำรองที่เหลือ (ม.)


func _init(move_class: String = "human") -> void:
	setup(move_class)


## ค่าจาก ArenaData.PLAYER ทับด้วย MOVE_CLASS[ชั้น] (ชั้นที่ไม่รู้จัก = human) แล้วเติมแรงเต็ม
func setup(move_class: String) -> void:
	cls = move_class if ArenaData.MOVE_CLASS.has(move_class) else "human"
	var d: Dictionary = ArenaData.PLAYER.merged(ArenaData.MOVE_CLASS[cls], true)
	walk = float(d["walk"])
	jog = float(d["jog"])
	back = float(d["back"])
	vmax = float(d["run"])
	accel = float(d["accel"])
	sprint_accel = float(d["sprint_accel"])
	cs = float(d["cs"])
	dprime = float(d["dprime"])
	knee = float(d["knee"])
	refill()


## เติมแรงเต็ม (วางตัวใหม่ ฟื้นจากล้ม)
func refill() -> void:
	bal = dprime


func tires() -> bool:
	return cs > 0.0


## แรงสำรอง 0..1 (เครื่องจักร = 1 เสมอ)
func reserve() -> float:
	return bal / dprime if tires() else 1.0


## แรงเหนื่อย e = 1 − สำรอง ใช้ขับเสียงหอบ
func effort() -> float:
	return 1.0 - reserve()


## ความเร็ววิ่งสูงสุดตอนนี้: vmax เต็มเมื่อสำรอง ≥ knee แล้วลดนุ่ม ๆ (smoothstep) หา cs ไม่ต่ำกว่า cs
func top() -> float:
	if not tires():
		return vmax
	var x := clampf(reserve() / knee, 0.0, 1.0)
	return cs + (vmax - cs) * x * x * (3.0 - 2.0 * x)


## อัตราเร่ง (/วิ): กำลังเร่งขึ้นเป็นวิ่งเร็ว (เป้าเร็วกว่าตอนนี้และเกิน jog) ใช้ sprint_accel นอกนั้น accel
func accel_to(want: float, now: float) -> float:
	return sprint_accel if want > now and want > jog else accel


## หนึ่งติ๊ก · v = ความเร็วจริงบนพื้น (ม./วิ) หลังชนกำแพงแล้ว
func tick(v: float, dt: float) -> void:
	if not tires():
		return
	if v > cs:
		bal = maxf(bal - (v - cs) * dt, 0.0)
	elif bal < dprime:      # เต็มแล้วข้าม exp(): สูตรให้ dprime พอดีอยู่แล้ว ค่าเท่าเดิมทุกบิต
		bal = dprime - (dprime - bal) * exp(-(cs - v) * dt / dprime)


## ยืนพัก sec วิ ในครั้งเดียว (สูตรปิดของ v = 0 ต่อกันได้พอดี เท่ากับติ๊กทีละก้าว)
func rest(sec: float) -> void:
	if sec > 0.0:
		tick(0.0, sec)


## หอบอยู่ไหม (กันติด ๆ ดับ ๆ ด้วย was_on) · เครื่องจักรไม่หอบ
func breathing(was_on: bool) -> bool:
	return tires() and breath_on(effort(), was_on)


## ความดังหอบตอนนี้ตามชั้น · เกราะเสริมกำลังเบาลง · เครื่องจักรเงียบ
func breath_volume() -> float:
	if not tires():
		return 0.0
	var g := breath_gain(effort())
	return g * float(ArenaData.BREATH["armour_gain"]) if cls == "armoured" else g


func breath_pitch() -> float:
	return float(ArenaData.BREATH["armour_pitch"]) if cls == "armoured" else 1.0


## ความดังฝีเท้าที่ความเร็ว v: เดิน → วิ่งเหยาะ → วิ่งเร็ว (STEPS walk / jog / run) × (1 + tired·e) เหนื่อยแล้วเท้าลงหนัก
func step_gain(v: float) -> float:
	var s := ArenaData.STEPS
	var g := lerpf(float(s["walk"]), float(s["jog"]), clampf((v - walk) / (jog - walk), 0.0, 1.0)) if v < jog \
		else lerpf(float(s["jog"]), float(s["run"]), clampf((v - jog) / (vmax - jog), 0.0, 1.0))
	return g * (1.0 + float(s["tired"]) * effort())


## หอบเปิดเมื่อ e ≥ on ปิดเมื่อ e < off
static func breath_on(e: float, was_on: bool) -> bool:
	var b := ArenaData.BREATH
	return e >= float(b["off"] if was_on else b["on"])


## จังหวะหายใจ (ครั้ง/นาที)
static func breath_rate(e: float) -> float:
	var b := ArenaData.BREATH
	return float(b["rate0"]) + float(b["rate1"]) * clampf(e, 0.0, 1.0)


## ความดังตาม e (ก่อนคูณชั้น): gain0 ที่ e = on ขึ้นนุ่ม ๆ ถึง gain1 ที่ gain_full
static func breath_gain(e: float) -> float:
	var b := ArenaData.BREATH
	var x := clampf((e - float(b["on"])) / (float(b["gain_full"]) - float(b["on"])), 0.0, 1.0)
	return float(b["gain0"]) + (float(b["gain1"]) - float(b["gain0"])) * x * x * (3.0 - 2.0 * x)


## ชุดหอบแรงเมื่อ e ≥ hard ลงเมื่อ e < hard_off
static func breath_hard(e: float, was_hard: bool) -> bool:
	var b := ArenaData.BREATH
	return e >= float(b["hard_off"] if was_hard else b["hard"])


## ก้าว/นาที ที่ความเร็ว v (ม./วิ) ของวงล้อก้าว · ต่อจุดเป็นเส้นตรง เกินจุดท้ายคงที่
static func cadence(v: float) -> float:
	var pts: Array = ArenaData.STEPS["cadence"]
	var a: Vector2 = pts[0]
	if v <= a.x:
		return a.y
	for i in range(1, pts.size()):
		var b: Vector2 = pts[i]
		if v <= b.x:
			return lerpf(a.y, b.y, (v - a.x) / (b.x - a.x))
		a = b
	return a.y
