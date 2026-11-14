class_name PackRoomWorld
extends Node3D
## ห้องเสริม 3 มิติหลังประตูบนดาดฟ้า (PACK_SPEC §9): ภาพทั้งหมดมาจากสคริปต์ของชุดเสริม (ลูกของ Room)
## ไฟล์นี้ทำส่วนสาธารณะจาก room.json: ตัวชน (เปลือกห้อง + รอยเท้าสถานี + ของจากสคริปต์) วงแหวน ป้าย ตัวผู้เล่น กล้อง เพื่อน
## หน้าตาและพฤติกรรมเหมือน HallWorld (ไม่มีไฟจริง ไม่มีเงา) · ข้อความบนป้ายมาจาก room.json ผ่าน PackRooms.text
## งานต่อเฟรม: ไม่มีในสคริปต์นี้ (ตัวผู้เล่น กล้อง เพื่อน เปิดเองเฉพาะตอนขยับ เหมือนดาดฟ้า)

signal station_changed(id: String)

const STATION_RING_R := HallWorld.STATION_RING_R
const AVATAR_RING_R := HallWorld.AVATAR_RING_R
const MAX_STATIONS := 8

@onready var avatar: HallAvatar = $Avatar
@onready var camera_rig: HallCamera = $CameraRig
@onready var rings: Rings = $Rings
@onready var blockers_body: StaticBody3D = $Blockers
@onready var props_body: StaticBody3D = $PropBlockers
@onready var room_root: Node3D = $Room
@onready var signs_root: Node3D = $Signs

var level := ""
var active := true
var team_colour := Color(0.28, 0.52, 0.84)
var friends: HallFriends
var layout: RoomLayout
var room: Dictionary = {}
## โหนดจากสคริปต์ของชุดเสริม (null = ยังไม่เปิด / เปิดไม่ได้)
var script_node: Node3D

var _station := ""
var _avatar_ring := -1
var _station_rings: Dictionary = {}
var _signs: Dictionary = {}
var _outline: Dictionary = {}
var _blockers := 0
var _sides := 0
var _env: Environment
var _fade_mat: StandardMaterial3D
var _alpha := 1.0


func _ready() -> void:
	add_to_group("gfx_level")
	team_colour = HallWorld.slot_colour(0)
	rings.setup(1 + MAX_STATIONS + 2 + HallFriends.MAX)
	friends = HallFriends.new()
	friends.name = "Friends"
	add_child(friends)
	friends.setup(self, rings)
	_avatar_ring = rings.add_ring(Vector3.ZERO, Vector3.UP, AVATAR_RING_R, team_colour)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = HallWorld.BG
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color.BLACK
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera_rig.camera.environment = _env
	avatar.camera_rig = camera_rig
	avatar.egg.material_override = HallBuilder.material()
	avatar.moved.connect(_on_avatar_moved)
	camera_rig.arm_settled.connect(_on_arm)
	var app := get_node_or_null(^"/root/App")
	level = str(app.get("gfx")) if app != null else "mid"
	_signs["you"] = avatar.name_label
	_outline["you"] = avatar.name_label.outline_size


## เปิดห้อง room (ห้องที่ผ่าน PackRooms.validate แล้ว): สร้างโหนดของสคริปต์ เรียก setup แล้วสร้างส่วนสาธารณะ
## คืน false เมื่อสคริปต์ใช้ไม่ได้ หรือตัวกันของสคริปต์ทับจุดเกิด/หน้าสถานี (ไม่มีอะไรค้างในห้อง)
func open(r: Dictionary) -> bool:
	var dir := str(r.get("dir", ""))
	var path := dir.path_join(str(r.get("script", "")))
	var sc := load(path) as Script if ResourceLoader.exists(path) else null
	var node: Object = sc.new() if sc != null and sc.can_instantiate() else null
	if not node is Node3D or not PackRooms.missing_api(node).is_empty():
		push_warning("pack room %s: the script %s is not a usable room" % [dir, path])
		if node != null and not node is RefCounted:
			node.free()
		return false
	room = r
	script_node = node
	script_node.name = "PackRoom"
	room_root.add_child(script_node)
	var lang := get_node_or_null(^"/root/I18n")
	script_node.call("setup", {"data": r, "dir": dir, "level": level, "english": lang != null and bool(lang.get("english")),
		"team_colour": team_colour})
	var extra: Variant = script_node.call("blockers")
	var list: Array = extra if extra is Array else []
	var bad := RoomLayout.extra_problems(_v2(r.get("half")), list)
	if not bad.is_empty():
		push_warning("pack room %s: blockers ignored: %s" % [dir, "; ".join(bad)])
	var lay := RoomLayout.new(r, list)
	# ตัวกันของสคริปต์ทับจุดเกิดหรือวงแหวนหน้าสถานี: ไม่เปิดห้อง (ผู้เล่นจะติด) ล้างโหนดสคริปต์ทิ้ง
	var stuck := lay.clear_problems()
	if not stuck.is_empty():
		push_warning("pack room %s: refused: %s" % [dir, "; ".join(stuck)])
		room_root.remove_child(script_node)
		script_node.free()
		script_node = null
		room = {}
		return false
	layout = lay
	camera_rig.layout = layout
	_blockers = HallBuilder.build_colliders(blockers_body, props_body, layout.blockers())
	for id in layout.ids:
		var f: Vector2 = layout.stations[id]["front"]
		_station_rings[id] = rings.add_kind(Rings.Kind.OBJECTIVE, Vector3(f.x, 0.0, f.y), Vector3.UP, STATION_RING_R)
	_build_signs()
	if r.has("bg"):
		_env.background_color = Color("#" + str(r["bg"]))
	refresh_figure()
	var app := get_node_or_null(^"/root/App")
	if app != null and app.has_signal("figure_changed") and not app.is_connected("figure_changed", refresh_figure):
		app.connect("figure_changed", refresh_figure)
	apply_level(level)
	refresh_text()
	place_avatar(layout.spawn, layout.spawn_yaw + PI)
	camera_rig.set_view(layout.spawn_yaw, -0.45, 6.5)
	if active:
		camera_rig.camera.make_current()
	return true


## ตัวที่เลือกในห้องแต่งตัว (Figures; ไข่ = null) ทาชุดสี (H10) แล้วใช้ความจางปัจจุบัน · เรียกซ้ำเมื่อ App.figure_changed
func refresh_figure() -> void:
	var sel := Figures.selected()
	var l := level if HallWorld.LEVELS.has(level) else "mid"
	avatar.set_figure(Figures.make(StringName(sel["figure"]), StringName(l)), {"level": l, "team_colour": team_colour, "seed": 0})
	Figures.dress(avatar.figure, str(sel["scheme"]))
	_apply_alpha()


## ระดับกราฟิก: ค่ารวมของแอปแบบ HallWorld แล้วไข่/ตัวละคร เพื่อน ขอบป้าย และสคริปต์ของห้อง
func apply_level(l: String) -> void:
	if not HallWorld.LEVELS.has(l):
		l = "mid"
	level = l
	var cfg: Dictionary = HallWorld.LEVELS[l]
	var tv: Dictionary = HallWorld.table_levels().get(l, {})
	var vp := get_viewport()
	if vp != null and not tv.is_empty():
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(tv["scale"])
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if not tv.is_empty():
		Engine.max_fps = int(tv["fps"])
		OS.low_processor_usage_mode = bool(tv["idle"])
	var sides := int(cfg["sides"])
	if sides != _sides:
		_sides = sides
		avatar.egg.mesh = HallBuilder.avatar_mesh(team_colour, sides)
	avatar.bob = bool(cfg["bob"])
	if avatar.figure != null:
		avatar.figure.call("apply_level", l)
	if friends != null:
		friends.apply_level(l)
	for id in _signs:
		(_signs[id] as Label3D).outline_size = int(_outline[id]) if bool(cfg["outline"]) else 0
	if script_node != null:
		script_node.call("apply_level", l)


## ข้อความบนป้ายสถานีจาก room.json ตามภาษาที่ใช้อยู่ (และบอกสคริปต์ถ้ามันวาดข้อความเอง)
func refresh_text() -> void:
	if layout == null:
		return
	for id in layout.ids:
		var l: Label3D = _signs.get(id)
		if l != null:
			l.text = PackRooms.text((layout.stations[id]["data"] as Dictionary).get("name"))
	if script_node != null and script_node.has_method("set_english"):
		var lang := get_node_or_null(^"/root/I18n")
		script_node.call("set_english", lang != null and bool(lang.get("english")))


func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if script_node != null and script_node.has_method("set_active"):
		script_node.call("set_active", on)
	if not is_node_ready():
		return
	if on:
		camera_rig.camera.make_current()
	else:
		camera_rig.camera.clear_current(false)
		camera_rig.reset_input()
		avatar.halt()


func set_you_tag_visible(on: bool) -> void:
	avatar.name_label.visible = on


func you_tag_visible() -> bool:
	return avatar.name_label.visible


func set_you_text(text: String) -> void:
	avatar.name_label.text = text


func set_slot_colour(c: Color) -> void:
	if c == team_colour:
		return
	team_colour = c
	if _sides > 0:
		avatar.egg.mesh = HallBuilder.avatar_mesh(team_colour, _sides)
	rings.set_ring(_avatar_ring, avatar.global_position, Vector3.UP, AVATAR_RING_R, team_colour)


func head_point() -> Vector3:
	return avatar.global_position + Vector3(0.0, HallFriends.EGG_H + HallFriends.HEAD_UP, 0.0)


func set_stick(v: Vector2) -> void:
	avatar.set_stick(v)


func station() -> String:
	return _station


## ข้อมูลสถานี id จาก room.json ({} = ไม่มี)
func station_data(id: String) -> Dictionary:
	if layout == null or not layout.stations.has(id):
		return {}
	return layout.stations[id]["data"]


func place_avatar(p: Vector3, yaw: float = PI) -> void:
	camera_rig.snap(Vector3(p.x, 0.0, p.z))
	avatar.place(p, yaw)


func labels() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for id in _signs:
		out.append(_signs[id])
	return out


func avatar_alpha() -> float:
	return _alpha


func counts() -> Dictionary:
	var c := {"blockers": _blockers, "signs": _signs.size() - 1, "level": level, "rings": rings.count(), "sides": _sides}
	var pack: Dictionary = {}
	if script_node != null and script_node.has_method("counts"):
		var v: Variant = script_node.call("counts")
		if v is Dictionary:
			pack = v
	c["static_meshes"] = int(pack.get("static_meshes", 0))
	c["static_tris"] = int(pack.get("static_tris", 0))
	c["anim_parts"] = int(pack.get("anim_parts", 0))
	c["shaders"] = int(pack.get("shaders", 0))
	return c


# ---- ภายใน ----

func _on_avatar_moved(pos: Vector3) -> void:
	rings.set_ring(_avatar_ring, pos, Vector3.UP, AVATAR_RING_R, team_colour)
	camera_rig.follow(pos)
	if layout == null:
		return
	var s := layout.station_at(Vector2(pos.x, pos.z))
	if s == _station:
		return
	if _station != "":
		rings.set_colour(_station_rings[_station], Rings.KIND_COLOUR[Rings.Kind.OBJECTIVE])
	if s != "":
		rings.set_colour(_station_rings[s], HallWorld.RING_ACTIVE)
	_station = s
	if script_node != null and script_node.has_method("station_near"):
		script_node.call("station_near", s)
	station_changed.emit(s)


## เหมือน HallWorld._on_arm: แขนกล้องสั้นลงเพราะชนผนัง ตัวผู้เล่นจางลง
func _on_arm(length: float) -> void:
	var a := clampf(HallWorld.FADE_MIN + (1.0 - HallWorld.FADE_MIN) * (length - HallWorld.FADE_NEAR) / (HallWorld.FADE_FAR - HallWorld.FADE_NEAR),
		HallWorld.FADE_MIN, 1.0)
	if absf(a - _alpha) < 0.04 and not (a == 1.0 and _alpha != 1.0):
		return
	_alpha = a
	_apply_alpha()


func _apply_alpha() -> void:
	var a := _alpha
	if avatar.figure != null:
		if avatar.figure.has_method("set_fade"):
			avatar.figure.call("set_fade", a)
		return
	if a >= 1.0:
		avatar.egg.material_override = HallBuilder.material()
		return
	if _fade_mat == null:
		_fade_mat = HallBuilder.material().duplicate() as StandardMaterial3D
		_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.albedo_color = Color(1.0, 1.0, 1.0, a)
	avatar.egg.material_override = _fade_mat


## ป้าย 3 มิติของสถานีที่มี sign (ตั้งค่าเดียวกับป้ายของ HallWorld)
func _build_signs() -> void:
	for id in layout.ids:
		var s: Dictionary = layout.stations[id]
		if s["sign"] == null:
			continue
		var l := Label3D.new()
		l.name = "Sign_" + id
		l.font_size = HallWorld.SIGN_FONT_SIZE
		l.pixel_size = HallWorld.SIGN_PIXEL
		l.outline_size = 16
		l.modulate = Color(1.0, 0.92, 0.76)
		l.outline_modulate = Color(0.12, 0.06, 0.02)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.position = s["sign"]
		l.rotation.y = float(s["face"])
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.double_sided = false
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = HallWorld.SIGN_WIDTH
		signs_root.add_child(l)
		_signs[id] = l
		_outline[id] = l.outline_size


static func _v2(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO
