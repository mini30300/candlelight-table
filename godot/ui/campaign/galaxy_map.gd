class_name GalaxyMap
extends Control
## แผนที่กาแล็กซีก้นหอย (CAMPAIGN_SPEC §1.5): จานมืด แกนสว่าง แขนสี่แขน ฝุ่นดาว อบลงภาพครั้งเดียว (แฮชตายตัว ไม่สุ่ม)
## ดาว 44 ดวงที่ CampaignGalaxy.position(i): วงในสีสภาพดาว วงนอกสีผู้รุกราน ดาวทองบนดาวเด่น เครื่องหมายถูกบนดาวที่ผ่านแล้ว
## จุดเล็กใต้ดาว = จำนวนเหตุการณ์ · ลาก = เลื่อน, ล้อเมาส์ / สองนิ้ว = ซูม 1×–3×, แตะ = planet_tapped
## วาดใหม่เฉพาะตอนมีการกด ขนาดเปลี่ยน หรือข้อมูลเปลี่ยน (ไม่มี _process) · ไฟล์นี้ไม่มีข้อความไทย

signal planet_tapped(id: String)
signal empty_tapped

const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
const HIT_MIN := 22.0          # รัศมีแตะอย่างน้อย (หน่วยจอ)
const TAP_SLOP := 12.0         # ลากน้อยกว่านี้ = แตะ
const PAD := 1.12              # ภาพพื้นหลังกว้างกว่ารัศมีกาแล็กซีเท่านี้
const BASE := 256              # ความละเอียดตอนคำนวณแสงของแขน (ขยายภายหลัง)
const TEX_SIZE := {"hi": 1024, "mid": 768, "lo": 512, "min": 512}
const STARS := {"hi": 2600, "mid": 1800, "lo": 1000, "min": 700}
const SALT := 0x6A1A
## สีของสภาพดาว (วงใน)
const BIOME_COL := {
	"ruin": Color("a39a8c"),
	"forest": Color("4fa35a"),
	"desert": Color("e0b46a"),
	"ice": Color("bfe3f5"),
	"volcanic": Color("e5643a"),
	"toxic": Color("b5d43c"),
}
const GOLD := Color("f2c66b")
const CHECK := Color("8dff9c")
const SELECT := Color(1.0, 0.93, 0.7)

static var _tex: Dictionary = {}         # ขนาด → ImageTexture (อบครั้งเดียวต่อขนาด)

var level := "mid"
var zoom := 1.0
var pan := Vector2.ZERO
## [{id, index, biome, faction_col: Color, featured, cleared, events: int}]
var planets: Array[Dictionary] = []
var selected := ""

var _press_pos := Vector2.ZERO
var _pressing := false
var _moved := 0.0
var _touches: Dictionary = {}           # index → ตำแหน่ง (สำหรับสองนิ้ว)
var _pinch_d := 0.0
var _draws := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


## ตั้งข้อมูลดาว (จาก GalaxyScreen) แล้ววาดใหม่
func set_planets(list: Array[Dictionary]) -> void:
	planets = list
	queue_redraw()


func set_level(l: String) -> void:
	level = l if TEX_SIZE.has(l) else "mid"
	queue_redraw()


func select(id: String) -> void:
	selected = id
	queue_redraw()


## จำนวนครั้งที่วาด (เทส: ไม่วาดซ้ำเองตอนนิ่ง)
func draws() -> int:
	return _draws


## รัศมีกาแล็กซีบนจอ (zoom 1)
func radius() -> float:
	return minf(size.x, size.y) * 0.5 / PAD


func origin() -> Vector2:
	return size * 0.5 + pan


## ตำแหน่งบนจอ (หน่วย Control) ของดาวลำดับ i
func screen_pos(index: int) -> Vector2:
	return origin() + CampaignGalaxy.position(index) * radius() * zoom


func marker_r() -> float:
	return clampf(radius() * 0.03, 7.0, 13.0) * (1.0 + (zoom - 1.0) * 0.25)


## ดาวที่จุด p (หน่วย Control) แตะโดน ("" = ไม่มี) · ใกล้สุดชนะ
func planet_at(p: Vector2) -> String:
	var best := ""
	var best_d := maxf(HIT_MIN, marker_r() + 6.0)
	for pl in planets:
		var d := p.distance_to(screen_pos(int(pl["index"])))
		if d <= best_d:
			best_d = d
			best = str(pl["id"])
	return best


func set_zoom(z: float, around := Vector2(-1, -1)) -> void:
	var nz := clampf(z, ZOOM_MIN, ZOOM_MAX)
	if around.x < 0.0:
		around = size * 0.5
	# จุดใต้นิ้ว/เมาส์อยู่ที่เดิมหลังซูม
	var o := origin()
	var k := nz / zoom
	var new_o := around + (o - around) * k
	zoom = nz
	pan = new_o - size * 0.5
	_clamp_pan()
	queue_redraw()


func pan_by(d: Vector2) -> void:
	pan += d
	_clamp_pan()
	queue_redraw()


func _clamp_pan() -> void:
	var lim := radius() * zoom * 0.9
	if zoom <= 1.0:
		lim = radius() * 0.25
	pan = pan.clamp(Vector2(-lim, -lim), Vector2(lim, lim))


# ---- การกด ----

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		_pinch_d = _touch_span()
		if _touches.size() >= 2:
			_pressing = false
		accept_event()
	elif event is InputEventScreenDrag:
		var g := event as InputEventScreenDrag
		_touches[g.index] = g.position
		if _touches.size() >= 2:
			var span := _touch_span()
			if _pinch_d > 1.0 and span > 1.0:
				set_zoom(zoom * span / _pinch_d, _touch_mid())
			_pinch_d = span
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(zoom * 1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(zoom / 1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_moved = 0.0
				_press_pos = mb.position
			elif _pressing:
				_pressing = false
				if _moved < TAP_SLOP and _touches.size() < 2:
					tap(mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _touches.size() < 2:
			_moved += mm.relative.length()
			if _moved >= TAP_SLOP:
				pan_by(mm.relative)
			accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		set_zoom(zoom * mg.factor, mg.position)
		accept_event()
	elif event is InputEventPanGesture:
		pan_by(-(event as InputEventPanGesture).delta * 8.0)
		accept_event()


## แตะที่จุด p: ดาว → planet_tapped, ที่ว่าง → empty_tapped (เทสเรียกตรงได้)
func tap(p: Vector2) -> void:
	var id := planet_at(p)
	if id != "":
		planet_tapped.emit(id)
	else:
		empty_tapped.emit()


func _touch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1] as Vector2)


func _touch_mid() -> Vector2:
	var v: Array = _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5


# ---- วาด ----

## ตัวรวมสามเหลี่ยม 2 มิติ: วงกลม วงแหวน เส้น รูปหลายเหลี่ยม → คำสั่งวาดเดียว (draw call เดียว)
class Pen:
	extends RefCounted
	var v := PackedVector2Array()
	var c := PackedColorArray()

	func tri(a: Vector2, b: Vector2, d: Vector2, col: Color) -> void:
		v.append_array([a, b, d])
		c.append_array([col, col, col])

	func circle(o: Vector2, r: float, col: Color, seg := 20) -> void:
		var prev := o + Vector2(r, 0.0)
		for i in range(1, seg + 1):
			var a := TAU * i / seg
			var q := o + Vector2(cos(a), sin(a)) * r
			tri(o, prev, q, col)
			prev = q

	func ring(o: Vector2, r: float, w: float, col: Color, seg := 24, a0 := 0.0, a1 := TAU) -> void:
		var ri := r - w * 0.5
		var ro := r + w * 0.5
		for i in seg:
			var t0 := a0 + (a1 - a0) * i / seg
			var t1 := a0 + (a1 - a0) * (i + 1) / seg
			var d0 := Vector2(cos(t0), sin(t0))
			var d1 := Vector2(cos(t1), sin(t1))
			tri(o + d0 * ri, o + d0 * ro, o + d1 * ro, col)
			tri(o + d0 * ri, o + d1 * ro, o + d1 * ri, col)

	func line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
		var n := (b - a).orthogonal().normalized() * w * 0.5
		tri(a - n, a + n, b + n, col)
		tri(a - n, b + n, b - n, col)

	func poly(pts: PackedVector2Array, col: Color) -> void:
		var idx := Geometry2D.triangulate_polygon(pts)
		for i in range(0, idx.size(), 3):
			tri(pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]], col)

	func star(o: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			pts.append(o + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		poly(pts, col)

	## วาดสามเหลี่ยมทั้งหมดลงใน ci เป็นคำสั่งเดียว (ต้องเรียกใน _draw ของ ci)
	func draw(ci: CanvasItem) -> void:
		if v.is_empty():
			return
		var idx := PackedInt32Array()
		idx.resize(v.size())
		for i in v.size():
			idx[i] = i
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, v, c)


func _draw() -> void:
	_draws += 1
	# พื้นมืดมาจากหน้า (ColorRect ข้างหลัง) ไม่วาดซ้ำ
	var tex := texture_for(level)
	var half := radius() * zoom * PAD
	var o := origin()
	draw_texture_rect(tex, Rect2(o - Vector2(half, half), Vector2(half, half) * 2.0), false)
	var pen := Pen.new()
	var mr := marker_r()
	var seg := 14 if level == "min" or level == "lo" else 20
	for pl in planets:
		var p := screen_pos(int(pl["index"]))
		if p.x < -40.0 or p.y < -40.0 or p.x > size.x + 40.0 or p.y > size.y + 40.0:
			continue
		var fc: Color = pl["faction_col"]
		if str(pl["id"]) == selected:
			pen.circle(p, mr + 10.0, Color(SELECT, 0.2), seg)
			pen.ring(p, mr + 7.5, 2.5, SELECT, seg + 6)
		pen.circle(p, mr + 3.5, fc, seg)
		pen.circle(p, mr, Color(0.02, 0.02, 0.04), seg)
		pen.circle(p, mr - 2.0, BIOME_COL.get(str(pl["biome"]), Color.GRAY), seg)
		# จุดจำนวนเหตุการณ์ใต้ดาว
		var n := int(pl["events"])
		for k in n:
			var dx := (float(k) - float(n - 1) * 0.5) * 7.0
			pen.circle(p + Vector2(dx, mr + 9.0), 2.4, Color(1.0, 0.85, 0.55), 8)
		if bool(pl["featured"]):
			pen.star(p + Vector2(mr * 0.95, -mr * 0.95), mr * 0.75, GOLD)
		if bool(pl["cleared"]):
			var c := p + Vector2(-mr * 0.95, -mr * 0.95)
			pen.circle(c, mr * 0.55, Color(0.02, 0.1, 0.04), 12)
			pen.line(c + Vector2(-mr * 0.3, 0.0), c + Vector2(-mr * 0.05, mr * 0.28), 2.5, CHECK)
			pen.line(c + Vector2(-mr * 0.05, mr * 0.28), c + Vector2(mr * 0.35, -mr * 0.3), 2.5, CHECK)
	pen.draw(self)


# ---- ภาพพื้นหลัง (อบครั้งเดียว) ----

## ภาพกาแล็กซีขนาดตามระดับกราฟิก (จำไว้ต่อขนาด)
static func texture_for(l: String) -> ImageTexture:
	var n := int(TEX_SIZE.get(l, 768))
	if _tex.has(n):
		return _tex[n]
	var t := ImageTexture.create_from_image(bake(n, int(STARS.get(l, 1800))))
	_tex[n] = t
	return t


## แสงของกาแล็กซีที่จุด p (หน่วยรัศมี): แกนอุ่น แขนสี่แขนตามสูตรตำแหน่งดาว ฝุ่นมืดตามขอบแขน
static func glow_at(p: Vector2) -> Color:
	var r := p.length()
	if r > PAD:
		return Color(0, 0, 0)
	var th := atan2(p.y, p.x)
	var arm_ang := 0.35 + (r - 0.18) * (0.42 / 0.074)
	var per := TAU / CampaignGalaxy.ARMS
	var d := fposmod(th - arm_ang + per * 0.5, per) - per * 0.5
	var width := 0.22 + 0.25 * r
	var arm := exp(-(d / width) * (d / width)) * clampf(1.15 - r, 0.0, 1.0)
	# ฝุ่นมืดเลื่อนจากแนวแขนนิดหน่อย
	var lane := exp(-pow((d + width * 0.55) / (width * 0.3), 2.0)) * 0.55 * clampf(r * 3.0, 0.0, 1.0)
	var core := exp(-(r / 0.13) * (r / 0.13)) * 1.6 + exp(-(r / 0.32) * (r / 0.32)) * 0.35
	var halo := exp(-r * 2.6) * 0.22
	var a := maxf(arm * (1.0 - lane), 0.0)
	var col := Color(0.012, 0.012, 0.03)
	col += Color(0.32, 0.42, 0.95) * a * 0.75
	col += Color(0.75, 0.45, 0.85) * a * a * 0.35
	col += Color(0.30, 0.30, 0.55) * halo
	col += Color(1.0, 0.82, 0.55) * core
	var edge := clampf((PAD - r) / 0.12, 0.0, 1.0)
	return Color(minf(col.r, 1.0) * edge, minf(col.g, 1.0) * edge, minf(col.b, 1.0) * edge)


## สร้างภาพ n × n: แสงแขนคำนวณที่ BASE แล้วขยายแบบนุ่ม ตามด้วยดาวทีละจุด (แฮชตายตัว)
static func bake(n: int, stars: int) -> Image:
	var b := Image.create(BASE, BASE, false, Image.FORMAT_RGB8)
	for y in BASE:
		for x in BASE:
			var p := Vector2((float(x) + 0.5) / BASE * 2.0 - 1.0, (float(y) + 0.5) / BASE * 2.0 - 1.0) * PAD
			b.set_pixel(x, y, glow_at(p))
	b.resize(n, n, Image.INTERPOLATE_CUBIC)
	for i in stars:
		var h1 := Hash.ihash2(i, 1, SALT)
		var h2 := Hash.ihash2(i, 2, SALT)
		var h3 := Hash.ihash2(i, 3, SALT)
		var p: Vector2
		if i % 3 == 0:
			# ดาวทั่วจาน
			p = Vector2(float(h1 % 10000) / 5000.0 - 1.0, float(h2 % 10000) / 5000.0 - 1.0) * PAD
		else:
			# ดาวตามแขน: รัศมีแล้วมุมใกล้แนวแขน
			var r := pow(float(h1 % 10000) / 10000.0, 0.8) * 1.0
			var arm := int(h3 % CampaignGalaxy.ARMS)
			var off := (float(h2 % 10000) / 10000.0 - 0.5) * (0.5 + 0.4 * r)
			var ang := arm * TAU / CampaignGalaxy.ARMS + 0.35 + (r - 0.18) * (0.42 / 0.074) + off
			p = Vector2(cos(ang), sin(ang)) * r
		var px := int((p.x / PAD * 0.5 + 0.5) * n)
		var py := int((p.y / PAD * 0.5 + 0.5) * n)
		if px < 1 or py < 1 or px >= n - 1 or py >= n - 1:
			continue
		var br := 0.25 + float(h3 % 1000) / 1000.0 * 0.75
		var tint: Color = [Color(1.0, 1.0, 1.0), Color(0.75, 0.85, 1.0), Color(1.0, 0.85, 0.65), Color(0.9, 0.8, 1.0)][(h1 >> 12) % 4]
		_add(b, px, py, tint * br)
		if br > 0.9 and n >= 768:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_add(b, px + o.x, py + o.y, tint * br * 0.35)
	return b


static func _add(img: Image, x: int, y: int, c: Color) -> void:
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(minf(o.r + c.r, 1.0), minf(o.g + c.g, 1.0), minf(o.b + c.b, 1.0)))
