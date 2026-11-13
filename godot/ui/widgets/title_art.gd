class_name TitleArt
extends Control
## ภาพหัวของหน้าแรก วาดจากรูปทรงล้วน (ไม่มีภาพ ไม่มีตราของใคร): พื้นไล่สีอุ่น โต๊ะไม้ยาว
## เทียน 5 เล่ม เปลวซ้อน 3 ชั้น และแสงฟุ้งรอบเปลว · ตัวหนังสือชื่อเกมเป็น Label ของหน้าแรก (แปลภาษาได้)
## hi/mid: Timer ไม่เกิน 6 ครั้ง/วิ สุ่มความสูงเปลวแล้ว queue_redraw · lo/min: วาดครั้งเดียว นิ่ง ไม่มีงานต่อเฟรม

const FLICKER_EVERY := 0.18          # วินาที (≈ 5.5 ครั้ง/วิ)
const FLICKER_LEVELS: PackedStringArray = ["hi", "mid"]
## เทียนแต่ละเล่ม: ตำแหน่ง x (สัดส่วนของพื้นที่ภาพ), ความสูง, ความกว้าง, ยกขึ้น (เล่มหลังอยู่สูงกว่า)
const CANDLES := [
	[0.16, 0.50, 0.90, 10.0], [0.31, 0.82, 1.10, 4.0], [0.50, 1.00, 1.30, 0.0], [0.67, 0.68, 1.05, 6.0], [0.83, 0.42, 0.90, 12.0],
]
const WAX := Color(0.91, 0.86, 0.75)
const WAX_SHADE := Color(0.72, 0.63, 0.50)
const FLAME_OUT := Color(1.0, 0.55, 0.17, 0.88)
const FLAME_MID := Color(1.0, 0.78, 0.30, 0.95)
const FLAME_IN := Color(1.0, 0.96, 0.82, 1.0)
const GLOW := Color(1.0, 0.70, 0.36)

## พื้นที่ว่างด้านขวาสำหรับคอลัมน์ปุ่ม (หน่วย canvas); องค์ประกอบภาพอยู่ทางซ้ายของมัน
@export var reserve_right := 470.0

var level := "mid"
var active := true
var draws := 0                        # จำนวนครั้งที่วาด (เทสใช้ดูว่า lo/min วาดครั้งเดียว)

var _heights := PackedFloat32Array()  # ตัวคูณความสูงเปลวของแต่ละเล่ม
var _sway := PackedFloat32Array()     # เปลวเอียงซ้ายขวา
var _rng := RandomNumberGenerator.new()   # แค่ภาพ ไม่เกี่ยวกติกา
var _timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7
	_heights.resize(CANDLES.size())
	_sway.resize(CANDLES.size())
	for i in CANDLES.size():
		_heights[i] = 1.0
		_sway[i] = 0.0
	_timer = Timer.new()
	_timer.name = "FlickerTimer"
	_timer.wait_time = FLICKER_EVERY
	_timer.timeout.connect(_flicker)
	add_child(_timer)
	resized.connect(queue_redraw)
	_update_timer()


## ระดับกราฟิก: hi/mid เปลวไหว, lo/min นิ่ง
func set_level(l: String) -> void:
	level = l
	_update_timer()


## หน้าแรกถูกบัง/กลับมาโชว์: หยุดหรือเดิน Timer
func set_active(on: bool) -> void:
	active = on
	_update_timer()


func flickering() -> bool:
	return _timer != null and not _timer.is_stopped()


func _update_timer() -> void:
	if _timer == null:
		return
	var on := active and FLICKER_LEVELS.has(level) and is_inside_tree()
	if on and _timer.is_stopped():
		_timer.start()
	elif not on:
		_timer.stop()
		for i in _heights.size():
			_heights[i] = 1.0
			_sway[i] = 0.0
		queue_redraw()


func _flicker() -> void:
	for i in _heights.size():
		_heights[i] = clampf(lerpf(_heights[i], _rng.randf_range(0.82, 1.14), 0.7), 0.8, 1.16)
		_sway[i] = clampf(lerpf(_sway[i], _rng.randf_range(-1.0, 1.0), 0.6), -1.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draws += 1
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	var area := Rect2(0.0, 0.0, maxf(s.x - reserve_right, s.x * 0.45), s.y)
	var u := minf(area.size.x / 800.0, s.y / 720.0)   # หน่วยย่อขยายของภาพ
	_draw_background(s, area)
	var table_y := s.y * 0.72
	_draw_table(area, table_y, u)
	var flames: Array[Vector2] = []
	for i in CANDLES.size():
		flames.append(_candle_top(area, table_y, u, i))
	for i in CANDLES.size():
		_draw_halo(flames[i], u * float(CANDLES[i][2]))
	for i in CANDLES.size():
		_draw_candle(area, table_y, u, i)
	for i in CANDLES.size():
		_draw_flame(flames[i], u * float(CANDLES[i][2]), _heights[i], _sway[i])
	_draw_right_shade(s)


## พื้นไล่สีจากบนมืดลงล่างอุ่น + แสงฟุ้งใหญ่กลางภาพ
func _draw_background(s: Vector2, area: Rect2) -> void:
	var top := Color("0c0705")
	var mid := Color("21130a")
	var bottom := Color("120a06")
	var my := s.y * 0.62
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, my), Vector2(0, my)]),
		PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, my), Vector2(s.x, my), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([mid, mid, bottom, bottom]))
	_glow(Vector2(area.position.x + area.size.x * 0.5, s.y * 0.55), area.size.x * 0.66, Color(GLOW, 0.24))


## โต๊ะไม้ยาว: หน้าโต๊ะสี่เหลี่ยมคางหมู ขอบหน้า แผ่นไม้ ขาโต๊ะ
func _draw_table(area: Rect2, table_y: float, u: float) -> void:
	var x0 := area.position.x + 24.0 * u
	var x1 := area.end.x - 24.0 * u
	var yb := table_y - 34.0 * u
	var yf := table_y + 16.0 * u
	var top_back := Color("5a3519")
	var top_front := Color("6e4220")
	draw_polygon(PackedVector2Array([Vector2(x0 + 40.0 * u, yb), Vector2(x1 - 40.0 * u, yb), Vector2(x1, yf), Vector2(x0, yf)]),
		PackedColorArray([top_back, top_back, top_front, top_front]))
	for k in range(1, 4):   # รอยต่อแผ่นไม้
		var t := k / 4.0
		var y := lerpf(yb, yf, t)
		var a := lerpf(x0 + 40.0 * u, x0, t)
		var b := lerpf(x1 - 40.0 * u, x1, t)
		draw_line(Vector2(a, y), Vector2(b, y), Color(0.0, 0.0, 0.0, 0.18), maxf(1.0, 1.5 * u))
	var band := 28.0 * u
	draw_rect(Rect2(x0, yf, x1 - x0, band), Color("3a2210"))
	draw_line(Vector2(x0, yf), Vector2(x1, yf), Color(1.0, 0.75, 0.45, 0.25), maxf(1.0, 2.0 * u))
	var leg := 30.0 * u
	var floor_y := area.end.y
	for lx in [x0 + 40.0 * u, x1 - 40.0 * u - leg]:
		draw_rect(Rect2(lx, yf + band, leg, floor_y - yf - band), Color("27160b"))
	# แสงเทียนตกบนโต๊ะ
	for i in CANDLES.size():
		var cx: float = area.position.x + area.size.x * float(CANDLES[i][0])
		var rr := 92.0 * u * float(CANDLES[i][2])
		_glow(Vector2(cx, table_y - 6.0 * u), rr, Color(GLOW, 0.26), 0.28)


func _candle_rect(area: Rect2, table_y: float, u: float, i: int) -> Rect2:
	var c: Array = CANDLES[i]
	var w := 26.0 * u * float(c[2])
	var h := 190.0 * u * float(c[1])
	var cx: float = area.position.x + area.size.x * float(c[0])
	var base := table_y - 8.0 * u - float(c[3]) * u
	return Rect2(cx - w * 0.5, base - h, w, h)


## จุดโคนเปลว (ปลายไส้เทียน)
func _candle_top(area: Rect2, table_y: float, u: float, i: int) -> Vector2:
	var r := _candle_rect(area, table_y, u, i)
	return Vector2(r.get_center().x, r.position.y - 9.0 * u * float(CANDLES[i][2]))


func _draw_candle(area: Rect2, table_y: float, u: float, i: int) -> void:
	var r := _candle_rect(area, table_y, u, i)
	var k := float(CANDLES[i][2])
	draw_rect(r, WAX)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x * 0.28, r.size.y), WAX_SHADE)
	draw_rect(Rect2(r.end.x - r.size.x * 0.18, r.position.y, r.size.x * 0.18, r.size.y), Color(WAX_SHADE, 0.6))
	_ellipse(Vector2(r.get_center().x, r.position.y), Vector2(r.size.x * 0.5, 4.0 * u * k), Color(1.0, 0.95, 0.85))
	# น้ำตาเทียนไหลลงหนึ่งหยด
	var dx := r.position.x + r.size.x * 0.62
	draw_rect(Rect2(dx, r.position.y, 5.0 * u * k, 28.0 * u * k), Color(1.0, 0.96, 0.88))
	draw_circle(Vector2(dx + 2.5 * u * k, r.position.y + 28.0 * u * k), 3.2 * u * k, Color(1.0, 0.96, 0.88))
	# ฐานรองเทียนโลหะเก่า
	_ellipse(Vector2(r.get_center().x, r.end.y), Vector2(r.size.x * 0.95, 6.0 * u * k), Color("6b4a2a"))
	draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.position.y - 9.0 * u * k), Color("2a1a10"), maxf(1.0, 2.2 * u))


func _draw_halo(p: Vector2, k: float) -> void:
	_glow(p + Vector2(0, -16.0 * k), 150.0 * k, Color(GLOW, 0.30))


## เปลวรูปหยดน้ำ 3 ชั้น (นอกส้ม กลางเหลือง ในขาว)
func _draw_flame(p: Vector2, k: float, h: float, sway: float) -> void:
	_teardrop(p, 15.0 * k, 52.0 * k * h, sway * 4.0 * k, FLAME_OUT)
	_teardrop(p + Vector2(0, -1.0 * k), 10.5 * k, 37.0 * k * h, sway * 3.0 * k, FLAME_MID)
	_teardrop(p + Vector2(0, -2.0 * k), 5.5 * k, 20.0 * k * h, sway * 1.5 * k, FLAME_IN)


func _teardrop(base: Vector2, w: float, h: float, lean: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var r := w * 0.5
	var c := base + Vector2(0, -r)
	for j in 9:   # ครึ่งวงกลมด้านล่าง
		var a := PI * j / 8.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r))
	pts.append(c + Vector2(-r * 0.75, -h * 0.35))
	pts.append(base + Vector2(lean, -h))
	pts.append(c + Vector2(r * 0.75, -h * 0.35))
	pts.reverse()
	draw_colored_polygon(pts, col)


## เงาเข้มด้านขวาให้ปุ่มอ่านง่าย
func _draw_right_shade(s: Vector2) -> void:
	var x := s.x - reserve_right - 60.0
	var clear := Color(0, 0, 0, 0)
	var dark := Color(0, 0, 0, 0.42)
	draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(x, s.y)]),
		PackedColorArray([clear, dark, dark, clear]))


## แสงฟุ้งไล่สีเนียนจากกลางออกขอบ (พัดสามเหลี่ยม 3 วง) squash = ย่อแนวตั้งเป็นวงรี
func _glow(c: Vector2, r: float, col: Color, squash := 1.0) -> void:
	const N := 40
	const RINGS := [0.0, 0.3, 0.62, 1.0]
	const FADE := [1.0, 0.5, 0.16, 0.0]
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.append(c)
	cols.append(col)
	for ri in range(1, RINGS.size()):
		for j in N:
			var a := TAU * j / N
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * squash) * float(RINGS[ri]))
			cols.append(Color(col, col.a * float(FADE[ri])))
	var idx := PackedInt32Array()
	for j in N:   # วงในสุด: พัดจากจุดกลาง
		idx.append_array([0, 1 + j, 1 + (j + 1) % N])
	for ri in range(1, RINGS.size() - 1):
		var a0 := 1 + (ri - 1) * N
		var b0 := 1 + ri * N
		for j in N:
			var j1 := (j + 1) % N
			idx.append_array([a0 + j, b0 + j, b0 + j1, a0 + j, b0 + j1, a0 + j1])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for j in 20:
		var a := TAU * j / 20.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
