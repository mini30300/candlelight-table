class_name FriendTags
extends Control
## ป้ายชื่อบนดาดฟ้าตอนออนไลน์ (NET_SPEC §6.2): ชื่อเพื่อนทุกคน ป้าย "คุณ" ของตัวเอง และบรรทัดสถานะห้อง
## วาดใน _draw() ครั้งเดียว ฟอนต์เดียว ขนาดเดียว (22) ไม่มีขอบ: อ่านง่ายด้วยเงาเข้ม 1 px จากตัวอักษรชุดเดียวกัน
## (texture เดียวกัน = draw call เดียว) · ตำแหน่งจาก camera.unproject_position ของจุดเหนือหัว อยู่หลังกล้องก็ข้าม
## วาดใหม่เฉพาะตอนมีเหตุ (เพื่อนขยับ ตัวเองขยับ กล้องเปลี่ยน รายชื่อเปลี่ยน จอเปลี่ยนขนาด) ไม่มี _process
## ไม่รับการแตะ (mouse_filter IGNORE) · ข้อความที่ส่งมาแปลแล้ว (ชื่อผู้เล่นไม่แปล) ไฟล์นี้ไม่มีข้อความไทย
## อักขระที่ฟอนต์ไม่มี (อีโมจิ ตัวจีน) ไม่วาด: ฟอนต์สำรองของระบบเป็น texture อื่น draw call จะแตกต่อชื่อ (งบ min บนมือถือ)

const FONT_SIZE := 22
const SHADOW := Color(0.04, 0.02, 0.01, 0.9)
const NAME_COLOUR := Color(1.0, 0.92, 0.76)
const STATUS_COLOUR := Color(0.91, 0.72, 0.38)
const PAD := 16.0

## จุดบนสุดของบรรทัดสถานะ (หน้าห้องโถงตั้งให้ ไม่ทับปุ่มบนสุด)
var status_y := PAD
## บรรทัดคำแนะนำ (§6.3 ทางสำรองบน min) วาดตรงกลางที่ y นี้
var hint_y := 96.0

var _world: Node3D
var _status := ""
var _you := ""
var _hint := ""
var _drawn: Array[Dictionary] = []
var _placed: Array[Rect2] = []       # กรอบป้ายที่วางแล้วในรอบวาดนี้ (ป้ายที่ทับกันขยับขึ้น)
var _font: Font
var _clean: Dictionary = {}           # ข้อความ → ข้อความที่ฟอนต์วาดได้ (แคช ไม่คิดซ้ำทุกรอบวาด)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = CandleStyle.BOLD
	resized.connect(refresh)


## ห้องที่อ่านหัวของเพื่อน (world.friends.heads()), หัวของตัวเอง (world.head_point()) และกล้อง (world.camera_rig.camera)
func bind(world: Node3D) -> void:
	_world = world


func set_status(text: String) -> void:
	if text != _status:
		_status = text
		refresh()


## ป้ายของตัวเอง ("" = ไม่วาด ใช้ป้าย 3 มิติเดิมของห้อง)
func set_you(text: String) -> void:
	if text != _you:
		_you = text
		refresh()


func set_hint(text: String) -> void:
	if text != _hint:
		_hint = text
		refresh()


func status_text() -> String:
	return _status


func you_text() -> String:
	return _you


func hint_text() -> String:
	return _hint


## มีอะไรต้องวาดไหม (ไม่มี = ซ่อนทั้งโหนด ไม่มี draw call)
func has_content() -> bool:
	if _status != "" or _you != "" or _hint != "":
		return true
	var friends: Node = _friends()
	return friends != null and int(friends.call("friend_count")) > 0


func refresh() -> void:
	visible = has_content()
	if visible:
		queue_redraw()
	else:
		_drawn.clear()


## ข้อความที่วาดไปครั้งล่าสุด [{text, pos}] (เทส)
func drawn() -> Array[Dictionary]:
	return _drawn


func _draw() -> void:
	_drawn.clear()
	_placed.clear()
	if _font == null:
		_font = CandleStyle.BOLD
	var cam := _camera()
	if cam != null and cam.is_inside_tree():
		# ใกล้กล้องก่อนได้ที่ของตัวเอง ป้ายที่อยู่ไกลกว่าและทับกันขยับขึ้น
		var heads: Array[Dictionary] = []
		var friends: Node = _friends()
		if friends != null:
			for h: Dictionary in friends.call("heads"):
				heads.append({"pos": h["pos"], "text": str(h["nm"])})
		if _you != "" and _world.has_method("head_point"):
			heads.append({"pos": _world.call("head_point"), "text": _you})
		var eye := cam.global_position
		heads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return eye.distance_squared_to(a["pos"]) < eye.distance_squared_to(b["pos"]))
		for h in heads:
			_tag(cam, h["pos"], str(h["text"]), NAME_COLOUR)
	if _status != "":
		_line(_status, status_y, STATUS_COLOUR)
	if _hint != "":
		_line(_hint, hint_y, NAME_COLOUR)


# ---- ภายใน ----

func _tag(cam: Camera3D, head: Vector3, raw: String, colour: Color) -> void:
	var text := _drawable(raw)
	if text == "" or cam.is_position_behind(head):
		return
	var p := get_global_transform_with_canvas().affine_inverse() * cam.unproject_position(head)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := Vector2(p.x - w * 0.5, p.y)
	if at.x > size.x or at.x + w < 0.0 or at.y < 0.0 or at.y > size.y + FONT_SIZE:
		return
	var line := float(FONT_SIZE) + 4.0
	var box := Rect2(at - Vector2(0.0, FONT_SIZE), Vector2(w, line))
	for i in 4:
		var hit := false
		for r in _placed:
			if r.intersects(box):
				hit = true
				break
		if not hit:
			break
		box.position.y -= line
	_placed.append(box)
	_text(Vector2(at.x, box.position.y + FONT_SIZE), text, colour)


func _line(raw: String, y: float, colour: Color) -> void:
	var text := _drawable(raw)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	_text(Vector2((size.x - w) * 0.5, y + _font.get_ascent(FONT_SIZE)), text, colour)


func _text(at: Vector2, text: String, colour: Color) -> void:
	draw_string(_font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SHADOW)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
	_drawn.append({"text": text, "pos": at})


## ข้อความที่เหลือเฉพาะอักขระที่ฟอนต์ของป้ายมี (ช่องว่างเก็บไว้ ช่องว่างซ้อน/หัวท้ายตัดทิ้ง)
func _drawable(text: String) -> String:
	if _clean.has(text):
		return _clean[text]
	var out := ""
	for i: int in text.length():
		var c := text.unicode_at(i)
		if c == 32 or _font.has_char(c):
			out += String.chr(c)
	out = " ".join(out.split(" ", false))
	if _clean.size() > 64:
		_clean.clear()
	_clean[text] = out
	return out


func _camera() -> Camera3D:
	if _world == null or not is_instance_valid(_world):
		return null
	var rig: Variant = _world.get("camera_rig")
	if rig == null:
		return null
	return (rig as Node).get("camera") as Camera3D


func _friends() -> Node:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.get("friends") as Node
