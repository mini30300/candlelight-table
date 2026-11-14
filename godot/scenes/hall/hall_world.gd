class_name HallWorld
extends Node3D
## ดาดฟ้ายานรบ 3 มิติ (ล็อบบี้ที่เดินได้, SHIP_LOBBY_SPEC): เมชนิ่ง 4 ชิ้น (โครงยาน เฟอร์นิเจอร์ ผ้า อวกาศ) เปลวเทียน
## ชั้นโฮโลแกรมบนโต๊ะรบ ยานไกลนอกหน้าต่าง ตัวชน ป้าย (สถานี + ป้ายชื่อสถานที่ "title") วงแหวน ตัวผู้เล่น กล้องตาม
## ข้อความบนป้ายมาจากหน้าห้องโถงผ่าน set_sign_text (ไฟล์นี้ไม่มีข้อความไทย)
## สภาพแวดล้อมตั้งบน Camera3D (โลกเดียวกับโต๊ะรบที่มี WorldEnvironment ของมันเอง) ไม่มีไฟจริง ไม่มีเงา
## งานต่อเฟรม: ไม่มีในสคริปต์นี้; ตัวผู้เล่นกับกล้องเปิดงานต่อเฟรมเองเฉพาะตอนขยับ
## การขยับบน hi/mid (เปลวไฟไหว โฮโลแกรมกะพริบ ยานลอย) อยู่ใน shader ทั้งหมด; lo/min ไม่มี shader ที่ใช้ TIME
## ตัวเดินบนดาดฟ้าเปลี่ยนได้ด้วยชุดเสริม (PACK_SPEC §4 H2: ArenaActors role "deck"); ไม่มีชุดเสริม = ไข่
## เพื่อนตอนออนไลน์ (NET_SPEC §6): ลูก Friends (HallFriends) ว่างและซ่อนตอนออฟไลน์ วงแหวนของเพื่อนอยู่ใน Rings เดียวกัน

signal station_changed(id: String)

const TEAMS_PATH := "res://data/teams.json"
const TABLE_VIEW := "res://table/table_view.gd"
const BG := Color("06070d")
const AVATAR_RING_R := 0.68
const STATION_RING_R := 0.55
const RING_ACTIVE := Color(1.0, 0.78, 0.34)
## ต่อระดับกราฟิก (SHIP_LOBBY_SPEC §6): จำนวนเปลวไฟ ไฟไหว ตัวโยก จำนวนเหลี่ยมของเสา/ไข่
## holo = โฮโลแกรมกะพริบ (shader) ไม่งั้นทึบนิ่ง, ships = ยานลอย (shader) / จอดนิ่ง / ไม่มี, stars = จำนวนดาว
## outline = ป้ายมีขอบ (ขอบป้ายละ 1 draw call: lo/min ไม่มีขอบ ให้อยู่ในงบตอนเปิดจอยบนมือถือ)
const LEVELS := {
	"hi": {"flames": 26, "flicker": true, "bob": true, "sides": 14, "holo": true, "ships": "drift", "stars": 700, "outline": true},
	"mid": {"flames": 26, "flicker": true, "bob": true, "sides": 12, "holo": true, "ships": "drift", "stars": 500, "outline": true},
	"lo": {"flames": 26, "flicker": false, "bob": false, "sides": 10, "holo": false, "ships": "parked", "stars": 320, "outline": false},
	"min": {"flames": 12, "flicker": false, "bob": false, "sides": 8, "holo": false, "ships": "none", "stars": 180, "outline": false},
}
const STATIC_NAMES: PackedStringArray = ["Shell", "Furniture", "Cloth", "Space"]
const FLAME_SHADER := "res://scenes/hall/flame.gdshader"
const HOLO_SHADER := "res://scenes/hall/holo.gdshader"
const SHIP_SHADER := "res://scenes/hall/ship_drift.gdshader"
const SIGN_FONT_SIZE := 88
const SIGN_PIXEL := 0.005
const SIGN_WIDTH := 860.0
## กล้องถูกผนังดันเข้ามาใกล้หัวกว่านี้ ไข่ตัวผู้เล่นจางลง (ไม่บังห้อง)
const FADE_NEAR := 1.4
const FADE_FAR := 2.6
const FADE_MIN := 0.35

static var _table_levels: Dictionary = {}

@onready var avatar: HallAvatar = $Avatar
@onready var camera_rig: HallCamera = $CameraRig
@onready var rings: Rings = $Rings
@onready var blockers_body: StaticBody3D = $Blockers
@onready var props_body: StaticBody3D = $PropBlockers
@onready var flames_node: MultiMeshInstance3D = $Flames
@onready var holo_node: MeshInstance3D = $Holo
@onready var ships_node: MultiMeshInstance3D = $Ships
@onready var static_root: Node3D = $Static
@onready var signs_root: Node3D = $Signs

var level := ""
var active := true
var team_colour := Color(0.28, 0.52, 0.84)
## ไข่ของเพื่อนตอนออนไลน์ (NET_SPEC §6.1): ว่างและซ่อนตอนออฟไลน์
var friends: HallFriends

var _static: Array[MeshInstance3D] = []
var _signs: Dictionary = {}            # id → Label3D (สถานี + "you" ป้ายเหนือตัวผู้เล่น)
var _outline: Dictionary = {}          # id → ขนาดขอบเดิมของป้าย (คืนค่าบน hi/mid)
var _station := ""
var _avatar_ring := -1
var _station_rings: Dictionary = {}    # id → ดัชนีวงแหวน
var _off: Dictionary = {}              # สถานีที่ปิด (id → true): ไม่มีวง ไม่นับเป็นสถานี
var _shutter: MeshInstance3D           # บานปิดทึบของประตูอารีน่า (สร้างเมื่อปิดครั้งแรก)
var _blockers := 0
var _sides := 0
var _flame_count := 0
var _flame_shader: ShaderMaterial
var _holo_shader: ShaderMaterial
var _holo_plain: StandardMaterial3D
var _ship_shader: ShaderMaterial
var _ship_count := 0
var _holo_flicker := false
var _ship_drift := false
var _env: Environment
var _fade_mat: StandardMaterial3D
var _alpha := 1.0


func _ready() -> void:
	add_to_group("gfx_level")
	var teams: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEAMS_PATH)) if FileAccess.file_exists(TEAMS_PATH) else null
	if teams is Array and not (teams as Array).is_empty() and (teams[0] as Dictionary).has("rgb"):
		var rgb: Array = teams[0]["rgb"]
		team_colour = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	for i in STATIC_NAMES.size():
		var mi := MeshInstance3D.new()
		mi.name = STATIC_NAMES[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = HallBuilder.material()
		static_root.add_child(mi)
		_static.append(mi)
	flames_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ships_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blockers = HallBuilder.build_colliders(blockers_body, props_body)
	_build_signs()
	rings.setup(ring_capacity())
	friends = HallFriends.new()
	friends.name = "Friends"
	add_child(friends)
	friends.setup(self, rings)
	_avatar_ring = rings.add_ring(HallLayout.SPAWN, Vector3.UP, AVATAR_RING_R, team_colour)
	for id in HallLayout.IDS:
		var f: Vector2 = HallLayout.STATIONS[id]["front"]
		_station_rings[id] = rings.add_kind(Rings.Kind.OBJECTIVE, Vector3(f.x, 0.0, f.y), Vector3.UP, STATION_RING_R)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color.BLACK
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera_rig.camera.environment = _env
	avatar.camera_rig = camera_rig
	avatar.egg.material_override = HallBuilder.material()
	avatar.moved.connect(_on_avatar_moved)
	var app := get_node_or_null(^"/root/App")
	level = str(app.get("gfx")) if app != null else "mid"
	set_figure(ArenaActors.make_figure("deck"))
	camera_rig.arm_settled.connect(_on_arm)
	camera_rig.set_view(HallLayout.SPAWN_YAW, camera_rig.pitch, camera_rig.arm_length)
	apply_level(level)
	place_avatar(HallLayout.SPAWN, PI)
	if active:
		camera_rig.camera.make_current()


## ใช้ระดับกราฟิก hi/mid/lo/min: ค่ารวมของแอปแบบเดียวกับ TableView.apply_level (render scale, fps, วาดตอนนิ่ง)
## แล้วเมชนิ่งตามจำนวนเหลี่ยม อวกาศ เปลวไฟ (จำนวน + ไหว/ไม่ไหว) โฮโลแกรม ยานไกล ไข่ตัวผู้เล่น การโยกตัว
func apply_level(l: String) -> void:
	if not LEVELS.has(l):
		l = "mid"
	level = l
	var cfg: Dictionary = LEVELS[l]
	var tv: Dictionary = table_levels().get(l, {})
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
		var ms := HallBuilder.meshes(sides)
		for i in ms.size():
			_static[i].mesh = ms[i]
		avatar.egg.mesh = HallBuilder.avatar_mesh(team_colour, sides)
	_static[3].mesh = HallSpace.mesh(l)
	_build_flames(int(cfg["flames"]), bool(cfg["flicker"]))
	_build_holo(l, bool(cfg["holo"]))
	_build_ships(l, str(cfg["ships"]))
	avatar.bob = bool(cfg["bob"])
	if avatar.figure != null:
		avatar.figure.call("apply_level", l)
	if friends != null:
		friends.apply_level(l)
	for id in _signs:
		(_signs[id] as Label3D).outline_size = int(_outline[id]) if bool(cfg["outline"]) else 0


## จำนวนวงแหวน: ตัวผู้เล่น + สถานี + 2 สำรอง + เพื่อน (NET_SPEC §6.2: 16)
static func ring_capacity() -> int:
	return 1 + HallLayout.IDS.size() + 2 + HallFriends.MAX


## ป้าย "คุณ" 3 มิติเหนือตัวผู้เล่น (ตอนออนไลน์มีเพื่อน FriendTags วาดแทน: ซ่อนป้ายนี้)
func set_you_tag_visible(on: bool) -> void:
	avatar.name_label.visible = on


func you_tag_visible() -> bool:
	return avatar.name_label.visible


## สีของตัวเอง (ไข่ + วงแหวน): ออนไลน์ใช้สีของช่องตัวเอง ออฟไลน์สีทีมแรก
func set_slot_colour(c: Color) -> void:
	if c == team_colour:
		return
	team_colour = c
	if _sides > 0:
		avatar.egg.mesh = HallBuilder.avatar_mesh(team_colour, _sides)
	rings.set_ring(_avatar_ring, avatar.global_position, Vector3.UP, AVATAR_RING_R, team_colour)


## จุดเหนือหัวของตัวเอง (ป้ายของ FriendTags): ยอดไข่ + 0.35 ม.
func head_point() -> Vector3:
	return avatar.global_position + Vector3(0.0, HallFriends.EGG_H + HallFriends.HEAD_UP, 0.0)


## สีของทีม/ช่อง i จาก data/teams.json (ไม่มีไฟล์ = สีน้ำเงินเดิม)
static func slot_colour(i: int) -> Color:
	var teams: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEAMS_PATH)) if FileAccess.file_exists(TEAMS_PATH) else null
	if teams is Array and i >= 0 and i < (teams as Array).size() and (teams[i] as Dictionary).has("rgb"):
		var rgb: Array = teams[i]["rgb"]
		return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	return Color(0.28, 0.52, 0.84)


## ค่าต่อระดับของโต๊ะ (TableView.LEVELS) อ่านจากสคริปต์ตอนใช้ (แหล่งเดียวกับโต๊ะรบ)
static func table_levels() -> Dictionary:
	if _table_levels.is_empty():
		var s: Script = load(TABLE_VIEW)
		if s != null:
			_table_levels = s.get_script_constant_map().get("LEVELS", {})
	return _table_levels


## เปิด/ปิดห้องโถงทั้งห้อง: ซ่อน หยุดงาน (ตัวชนออกจากฟิสิกส์ด้วย) และคืนกล้อง; เปิดกลับครบทั้งสามอย่าง
func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not is_node_ready():
		return
	if on:
		camera_rig.camera.make_current()
	else:
		camera_rig.camera.clear_current(false)
		camera_rig.reset_input()
		avatar.halt()


## ข้อความบนป้ายของสถานี id (หรือ "you" = ป้ายเหนือตัวผู้เล่น); หน้าห้องโถงส่งข้อความที่แปลแล้วมา
func set_sign_text(id: String, text: String) -> void:
	var l: Label3D = _signs.get(id)
	if l != null:
		l.text = text


func sign_text(id: String) -> String:
	var l: Label3D = _signs.get(id)
	return l.text if l != null else ""


func labels() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for id in _signs:
		out.append(_signs[id])
	return out


func set_stick(v: Vector2) -> void:
	avatar.set_stick(v)


## สถานีที่ตัวผู้เล่นเอื้อมถึงตอนนี้ ("" = ไม่มี)
func station() -> String:
	return _station


## เปิด/ปิดสถานี id: ปิด = ไม่มีวงหน้าสถานี ไม่มีปุ่มใช้งาน (ของยังวาดเป็นฉาก) · แอปสาธารณะปิดประตูเทียบยาน
func set_station_enabled(id: String, on: bool) -> void:
	if not _station_rings.has(id) or on != _off.has(id):
		return
	if on:
		_off.erase(id)
		var f: Vector2 = HallLayout.STATIONS[id]["front"]
		_station_rings[id] = rings.add_kind(Rings.Kind.OBJECTIVE, Vector3(f.x, 0.0, f.y), Vector3.UP, STATION_RING_R)
	else:
		_off[id] = true
		rings.remove_ring(int(_station_rings[id]))
		_station_rings[id] = -1
	if id == "arena":
		_set_shut(not on)
	_update_station(avatar.global_position)


func station_enabled(id: String) -> bool:
	return _station_rings.has(id) and not _off.has(id)


## ประตูอารีน่าปิดทึบ (อารีน่าอยู่ในห้องเสริม): โชว์บานปิด · เมชนิ่ง ไม่มีงานต่อเฟรม
func _set_shut(on: bool) -> void:
	if on and _shutter == null:
		_shutter = MeshInstance3D.new()
		_shutter.name = "ArenaShutter"
		_shutter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shutter.material_override = HallBuilder.material()
		_shutter.mesh = HallBuilder.arena_shutter_mesh()
		static_root.add_child(_shutter)
	if _shutter != null:
		_shutter.visible = on


func arena_shut() -> bool:
	return _shutter != null and _shutter.visible


## ตัวละครชุดเสริมแทนไข่ (null = ไข่): ส่งระดับกราฟิก สีทีม แล้วใช้ความจางปัจจุบัน
func set_figure(fig: Node3D) -> void:
	avatar.set_figure(fig, {"level": level if LEVELS.has(level) else "mid", "team_colour": team_colour, "seed": 0})
	_apply_alpha()


## วางตัวผู้เล่นที่ p หันไป yaw แล้วกล้องตามทันที
func place_avatar(p: Vector3, yaw: float = PI) -> void:
	camera_rig.snap(Vector3(p.x, 0.0, p.z))
	avatar.place(p, yaw)


func counts() -> Dictionary:
	var tris := 0
	for mi in _static:
		if mi.mesh != null:
			tris += HallBuilder.tris(mi.mesh as ArrayMesh)
	var space := HallBuilder.tris(_static[3].mesh as ArrayMesh) if _static.size() > 3 and _static[3].mesh != null else 0
	return {"flames": _flame_count, "blockers": _blockers, "signs": _signs.size(), "level": level,
		"static_meshes": _static.size(), "static_tris": tris, "rings": rings.count(), "sides": _sides,
		"stars": int(HallSpace.STARS.get(level, 0)), "ships": _ship_count, "ship_drift": _ship_drift,
		"holo_flicker": _holo_flicker, "space_tris": space}


# ---- ภายใน ----

func _on_avatar_moved(pos: Vector3) -> void:
	rings.set_ring(_avatar_ring, pos, Vector3.UP, AVATAR_RING_R, team_colour)
	camera_rig.follow(pos)
	_update_station(pos)


func _update_station(pos: Vector3) -> void:
	var s := HallLayout.station_at(Vector2(pos.x, pos.z), _off)
	if s == _station:
		return
	if _station != "":
		rings.set_colour(_station_rings[_station], Rings.KIND_COLOUR[Rings.Kind.OBJECTIVE])
	if s != "":
		rings.set_colour(_station_rings[s], RING_ACTIVE)
	_station = s
	station_changed.emit(s)


## แขนกล้องสั้นลงเพราะชนผนัง: ไข่จางลงตามระยะ (สลับวัสดุเฉพาะตอนค่าเปลี่ยน ไม่มีงานตอนนิ่ง)
func _on_arm(length: float) -> void:
	var a := clampf(FADE_MIN + (1.0 - FADE_MIN) * (length - FADE_NEAR) / (FADE_FAR - FADE_NEAR), FADE_MIN, 1.0)
	if absf(a - _alpha) < 0.04 and not (a == 1.0 and _alpha != 1.0):
		return
	_alpha = a
	_apply_alpha()


## ความจางปัจจุบัน: ตัวละครชุดเสริมใช้ set_fade ของมันเอง (ถ้ามี) ไม่งั้นสลับวัสดุไข่
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


func avatar_alpha() -> float:
	return _alpha


## เปลวไฟทั้งหมดใน MultiMesh เดียว: hi/mid ใช้ shader ไหว (TIME + เฟสต่อดวง), lo/min วัสดุธรรมดา
func _build_flames(n: int, flicker: bool) -> void:
	var pts := HallLayout.flames(n <= HallLayout.MAX_FLAMES_MIN)
	n = mini(n, pts.size())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = HallBuilder.flame_mesh()
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 2601
	for i in n:
		var big := 1.5 if pts[i].is_equal_approx(HallLayout.CONSOLE_FLAME) else 1.0
		var s := big * rng.randf_range(0.9, 1.12)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pts[i]))
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 0.0))
	flames_node.multimesh = mm
	if flicker:
		if _flame_shader == null:
			_flame_shader = ShaderMaterial.new()
			_flame_shader.shader = load(FLAME_SHADER)
		flames_node.material_override = _flame_shader
	else:
		flames_node.material_override = HallBuilder.flame_plain_material()
	_flame_count = n


## ชั้นโฮโลแกรมเหนือโต๊ะรบ: hi/mid shader กะพริบ (บวกสี ไม่เขียนความลึก), lo/min วัสดุทึบธรรมดา 0.8 เท่า ไม่มี TIME
func _build_holo(l: String, flicker: bool) -> void:
	holo_node.mesh = HallBuilder.holo_mesh(l)
	if flicker:
		if _holo_shader == null:
			_holo_shader = ShaderMaterial.new()
			_holo_shader.shader = load(HOLO_SHADER)
		holo_node.material_override = _holo_shader
	else:
		if _holo_plain == null:
			_holo_plain = StandardMaterial3D.new()
			_holo_plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_holo_plain.vertex_color_use_as_albedo = true
			_holo_plain.vertex_color_is_srgb = true
			_holo_plain.albedo_color = Color(0.8, 0.8, 0.8)
			_holo_plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		holo_node.material_override = _holo_plain
	_holo_flicker = flicker


## ยานไกลใน MultiMesh เดียว: drift = shader ลอย (ตำแหน่ง instance = กลางช่วงลอย), parked = จอดที่ตำแหน่งเฟส
## วัสดุธรรมดา, none = ไม่มียาน ซ่อนโหนด (ไม่มี draw call)
func _build_ships(l: String, mode: String) -> void:
	var list: Array[Dictionary] = []
	if mode != "none":
		list = HallSpace.ship_instances(l)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = mode == "drift"
	mm.mesh = HallSpace.ship_mesh()
	mm.instance_count = list.size()
	for i in list.size():
		var d: Dictionary = list[i]
		var p := HallSpace.ship_pos(d, float(d["span"]) * 0.5) if mode == "drift" else HallSpace.ship_pos(d, float(d["phase"]))
		mm.set_instance_transform(i, HallSpace.ship_transform(d, p))
		if mode == "drift":
			mm.set_instance_custom_data(i, Color(float(d["speed"]), float(d["phase"]), float(d["span"]), float(d["len"])))
	ships_node.multimesh = mm
	ships_node.visible = mode != "none"
	# ยานลอยไปไกลจากตำแหน่ง instance (shader): กล่องตัดภาพครอบทั้งโดม ไม่งั้นยานหายตอนกล่องเดิมหลุดจอ
	if mode == "drift":
		var r := Vector3.ONE * HallSpace.DOME_R
		ships_node.custom_aabb = AABB(HallSpace.DOME_C - r, Vector3(2.0 * r.x, 2.0 * r.y, r.z))
	else:
		ships_node.custom_aabb = AABB()
	if mode == "drift":
		if _ship_shader == null:
			_ship_shader = ShaderMaterial.new()
			_ship_shader.shader = load(SHIP_SHADER)
		ships_node.material_override = _ship_shader
	else:
		ships_node.material_override = HallBuilder.material()
	_ship_count = list.size()
	_ship_drift = mode == "drift" and _ship_count > 0


func _build_signs() -> void:
	for id in HallLayout.IDS:
		var s: Dictionary = HallLayout.STATIONS[id]
		var l := _make_label("Sign_" + id)
		l.position = s["sign"]
		l.rotation.y = float(s["face"])
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.double_sided = false
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = SIGN_WIDTH
		signs_root.add_child(l)
		_signs[id] = l
	# ป้ายชื่อสถานที่บนแผ่นบรอนซ์ใต้หน้าต่างกลาง (ไม่ใช่สถานี)
	var t := _make_label("Sign_title")
	t.position = HallLayout.TITLE_SIGN
	t.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	t.double_sided = false
	# ขนาดบนจอเท่าตัวอักษร 72 แต่ใช้ขนาด 88 ของป้ายสถานี (ใช้แคชตัวอักษรชุดเดิม ไม่จองหน่วยความจำเพิ่ม ~4 MB)
	t.pixel_size = SIGN_PIXEL * 72.0 / SIGN_FONT_SIZE
	t.modulate = Color(1.0, 0.86, 0.55)
	signs_root.add_child(t)
	_signs["title"] = t
	_signs["you"] = avatar.name_label
	for id in _signs:
		_outline[id] = (_signs[id] as Label3D).outline_size


func _make_label(n: String) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.font_size = SIGN_FONT_SIZE
	l.pixel_size = SIGN_PIXEL
	l.outline_size = 16
	l.modulate = Color(1.0, 0.92, 0.76)
	l.outline_modulate = Color(0.12, 0.06, 0.02)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l
