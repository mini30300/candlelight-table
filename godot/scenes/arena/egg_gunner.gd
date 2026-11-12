class_name EggGunner
extends Node3D
## ตัวผู้เล่นตั้งต้นของอารีน่า (ARENA_SPEC §6.6, สัญญาตัวละคร §9.1): ไข่สีทีมของดาดฟ้า + ถุงมือบรอนซ์ลอยสองข้าง
## (MultiMesh 2 ชิ้น = 1 draw call) ถือปืนไรเฟิลหรือดาบเลื่อยที่ออกแบบเอง (เมชเดียว = 1 draw call) ตราเทียนของเราเท่านั้น
## หน้าตัวอยู่ทาง +z (yaw 0) ขวามือของตัว = −x · ท่าทางสร้างด้วยโค้ด: idle walk run fire reload punch swing hit die
## play() คืนความยาวท่า · จังหวะเกมมาจาก ArenaData ไม่ใช่ความยาวท่า · แมกที่หล่นตอนบรรจุเป็นเมชแยก โชว์เฉพาะตอนบรรจุ
## งานต่อเฟรม: _process เฉพาะตอนมีท่าครั้งเดียวกำลังเล่น ชักอาวุธ หรือโยกตัวตอนเดิน (hi/mid) แล้วปิดตัวเอง

signal clip_event(kind: StringName)

const FIGURE_API := ["setup", "metrics", "clip_names", "play", "set_move", "set_aim", "set_weapon", "set_flash",
	"set_telegraph", "muzzle", "anchor", "apply_level"]
const SIDES := {"hi": 14, "mid": 12, "lo": 10, "min": 8}
const HEIGHT := 1.75
const RADIUS := 0.35
const FIST_R := 0.11
const REST_R := Vector3(-0.42, 1.0, 0.18)
const REST_L := Vector3(0.42, 1.0, 0.18)
const GRIP_GUN := Vector3(-0.44, 1.24, 0.18)
const GRIP_SWORD := Vector3(-0.47, 1.0, 0.2)
const GUN_SUPPORT := Vector3(0.0, -0.035, 0.46)    # มือซ้ายประคองโครงลำกล้อง (พิกัดปืน)
const MAG_IN := Vector3(0.0, -0.1, 0.14)
const SWORD_TILT := -0.95                           # ดาบชี้ขึ้นหน้า
const PUNCH_OUT := 0.9
const LEAN := 0.15
const BOB_H := 0.05
const RECOIL := 0.06
## ท่าครั้งเดียว: ความยาว (วินาที)
const CLIPS := {"fire": 0.08, "reload": 1.6, "punch": 0.25, "swing": 0.25, "hit": 0.25, "die": 0.6}
const LOOPS := {"idle": 2.0, "walk": 0.8, "run": 0.55}
const BLADE := Color("8d949c")
const TEETH := Color("5d636b")
const GRIP_COL := Color("23262b")

static var _mesh_cache: Dictionary = {}

var role: StringName = &"player"
var level := "mid"
var team_colour := Color(0.28, 0.52, 0.84)
var bob := true

var egg: MeshInstance3D
var gauntlets: MultiMeshInstance3D
var weapon_root: Node3D
var weapon_mesh: MeshInstance3D
var mag: MeshInstance3D
var muzzle_node: Marker3D

var _weapon: StringName = &"none"
var _pitch := 0.0
var _speed := 0.0
var _running := false
var _phase := 0.0
var _clip := ""
var _clip_t := 0.0
var _clip_len := 0.0
var _clip_speed := 1.0
var _dead := false
var _draw_t := 1.0          # 0..1 ชักอาวุธ (ขยายจากเล็ก)
var _flash := 0.0
var _fade := 1.0
var _sides := 0
var _anchors: Dictionary = {}
var _flash_mat: StandardMaterial3D
var _fade_mat: StandardMaterial3D


func _ready() -> void:
	_build_nodes()
	set_process(false)


## สัญญาตัวละคร: {"role", "level", "team_colour", "seed"}
func setup(opts: Dictionary) -> void:
	role = StringName(str(opts.get("role", "player")))
	team_colour = opts.get("team_colour", team_colour)
	_build_nodes()
	_sides = 0
	apply_level(str(opts.get("level", level)))


func metrics() -> Dictionary:
	return {"height": HEIGHT, "radius": RADIUS, "eye": 1.45, "shoulder": 1.1}


func clip_names() -> Dictionary:
	var out := {}
	for k in LOOPS:
		out[k] = PackedStringArray([k])
	for k in CLIPS:
		out[k] = PackedStringArray([k])
	return out


## เริ่มท่า logical (ท่าครั้งเดียวจบแล้วกลับท่าวน) คืนความยาวท่า (วินาที, หารด้วย speed) ไม่มีท่าคืน 0
func play(logical: StringName, speed: float = 1.0) -> float:
	var k := String(logical)
	speed = maxf(speed, 0.01)
	if LOOPS.has(k):
		if k == "idle":
			_dead = false
			_clip = ""
			_pose()
		return float(LOOPS[k]) / speed
	if not CLIPS.has(k):
		return 0.0
	if _dead and k != "die":
		return 0.0
	_clip = k
	_clip_t = 0.0
	_clip_speed = speed
	_clip_len = float(CLIPS[k])
	if k == "fire":
		clip_event.emit(&"shot")
	set_process(true)
	_pose()
	return _clip_len / speed


## ความเร็ว (ม./วิ) ตามทิศหน้า: เลือก idle/walk/run และจังหวะโยก
func set_move(speed: float, running: bool) -> void:
	_speed = maxf(speed, 0.0)
	_running = running
	if bob and _speed > 0.05:
		set_process(true)
	elif _clip == "" and _draw_t >= 1.0:
		_phase = 0.0
		_pose()


## มุมเล็ง (เรเดียน, บวก = เงย): ปืนกับมือขวาก้มเงยตาม ไข่เอนตาม ±0.15
func set_aim(pitch: float) -> void:
	_pitch = pitch
	_pose()


## อาวุธในมือ: none / gun / sword (ชักใหม่ขยายจากเล็ก 0.2 วิบน hi/mid)
func set_weapon(id: StringName) -> void:
	if id == _weapon:
		return
	var was := _weapon
	_weapon = id
	if weapon_mesh != null:
		weapon_mesh.mesh = _weapon_mesh(id, true)
		weapon_root.visible = id != &"none"
		muzzle_node.position = Vector3(0.0, 0.035, 0.82) if id == &"gun" else Vector3(0.0, 0.0, 1.24)
	if id != &"none" and bob and was != id:
		_draw_t = 0.0
		set_process(true)
	else:
		_draw_t = 1.0
	if mag != null:
		mag.visible = false
	_pose()


func weapon() -> StringName:
	return _weapon


## แสงวาบตอนโดน 0..1 (ไข่สว่างขึ้น)
func set_flash(a: float) -> void:
	_flash = clampf(a, 0.0, 1.0)
	_update_material()


## ผู้เล่นไม่มีสีเตือน
func set_telegraph(_a: float) -> void:
	pass


## กล้องถูกบีบเข้าใกล้: ไข่จางลง (ส่วนเสริม ไม่อยู่ในสัญญา; ผู้เล่นเรียกถ้ามี)
func set_fade(a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	if absf(a - _fade) < 0.01:
		return
	_fade = a
	_update_material()


func fade() -> float:
	return _fade


func muzzle() -> Node3D:
	return muzzle_node


func anchor(n: StringName) -> Node3D:
	return _anchors.get(n)


## ระดับกราฟิก: จำนวนเหลี่ยมของไข่ โยกตัวและชักอาวุธแบบนุ่มบน hi/mid
func apply_level(l: String) -> void:
	if not SIDES.has(l):
		l = "mid"
	level = l
	bob = l == "hi" or l == "mid"
	var sides := int(SIDES[l])
	if sides != _sides and egg != null:
		_sides = sides
		egg.mesh = _egg_mesh(team_colour, sides)
	if not bob:
		_draw_t = 1.0
		_phase = 0.0
	_pose()


## ท่าที่กำลังเล่น ("" = ท่าวน)
func clip() -> String:
	return _clip


func busy() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	var active := false
	if _clip != "":
		_clip_t += delta * _clip_speed
		if _clip_t >= _clip_len:
			if _clip == "die":
				_dead = true
				_clip_t = _clip_len
				clip_event.emit(&"thud")
			_clip = ""
		else:
			active = true
	if _draw_t < 1.0:
		_draw_t = minf(_draw_t + delta / 0.2, 1.0)
		active = active or _draw_t < 1.0
	if bob and _speed > 0.05 and not _dead:
		_phase += delta * _speed * (3.2 if _running else 2.8)
		active = true
	else:
		_phase = 0.0
	_pose()
	if not active:
		set_process(false)


# ---- ท่าทาง ----

func _pose() -> void:
	if egg == null:
		return
	var t := _clip_t
	var lean := clampf(-_pitch * 0.25, -LEAN, LEAN)
	var tip := 0.0
	var bob_y := 0.0
	if bob and _phase > 0.0:
		bob_y = absf(sin(_phase)) * BOB_H * minf(_speed / 3.0, 1.0)
		lean += 0.08 * minf(_speed / 5.0, 1.0)
	var aim_fwd := Vector3(0.0, sin(_pitch), cos(_pitch))
	# อาวุธและมือขวา
	var grip := GRIP_GUN if _weapon == &"gun" else GRIP_SWORD
	var rot := Vector3(-_pitch, 0.0, 0.0)
	if _weapon == &"sword":
		rot = Vector3(SWORD_TILT - _pitch * 0.5, -0.12, 0.0)
	var recoil := 0.0
	var mag_pos := MAG_IN
	var mag_on := false
	var left := REST_L
	var right := REST_R
	var punch := 0.0
	if _dead or _clip == "die":
		var s := 1.0 if _dead else smoothstep(0.0, 1.0, t / CLIPS["die"])
		tip = 1.45 * s
		bob_y = 0.0
	match _clip:
		"fire":
			recoil = RECOIL * (1.0 - t / CLIPS["fire"])
		"reload":
			var e := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(1.35, 1.6, t))
			rot.x += 0.45 * e
			if t > 0.15 and t < 1.35:
				mag_on = true
				if t < 0.5:
					mag_pos = MAG_IN + Vector3(0.0, -0.38 * smoothstep(0.15, 0.5, t), 0.0)
				elif t < 0.9:
					mag_pos = MAG_IN + Vector3(0.0, -0.38, 0.0)
				else:
					mag_pos = MAG_IN + Vector3(0.0, -0.38 * (1.0 - smoothstep(0.9, 1.3, t)), 0.0)
		"punch":
			punch = sin(PI * clampf(t / CLIPS["punch"], 0.0, 1.0))
			lean += LEAN * punch
		"swing":
			var s := smoothstep(0.0, 1.0, t / CLIPS["swing"])
			grip = Vector3(-0.45, 1.25, 0.15).lerp(Vector3(-0.05, 0.85, 0.38), s)
			rot = Vector3(lerpf(-1.15, 0.55, s), lerpf(-0.9, 0.8, s), lerpf(-0.4, 0.5, s))
		"hit":
			lean -= 0.22 * sin(PI * clampf(t / CLIPS["hit"], 0.0, 1.0))
	var wb := Basis.from_euler(rot)
	var scale_k := 0.05 + 0.95 * smoothstep(0.0, 1.0, _draw_t)
	var wpos := grip + Vector3(0.0, bob_y, 0.0) - wb.z * recoil
	if tip > 0.0:
		wpos = wpos.lerp(Vector3(grip.x * 1.4, 0.2, grip.z), tip / 1.45)
	weapon_root.transform = Transform3D(wb.scaled(Vector3.ONE * scale_k), wpos)
	if _weapon != &"none":
		right = wpos
	if _weapon == &"gun" and punch <= 0.0:
		var sup := weapon_root.transform * GUN_SUPPORT
		left = sup
		if mag_on and t > 0.7:
			left = weapon_root.transform * (mag_pos + Vector3(0.0, -0.05, 0.0))
	left += Vector3(0.0, bob_y, 0.0)
	if _weapon == &"none":
		right += Vector3(0.0, bob_y, 0.0)
	if punch > 0.0:
		left = REST_L.lerp(Vector3(0.12, 1.05, 0.25), punch) + aim_fwd * PUNCH_OUT * punch
	if tip > 0.0:
		var k := tip / 1.45
		left = left.lerp(Vector3(0.55, 0.15, 0.1), k)
		right = right.lerp(Vector3(-0.55, 0.15, 0.1), k)
	egg.position = Vector3(0.0, bob_y, 0.0)
	egg.rotation = Vector3(lean, 0.0, tip)
	var mm := gauntlets.multimesh
	mm.set_instance_transform(0, Transform3D(Basis.from_euler(Vector3(-_pitch if _weapon == &"gun" else 0.0, 0.0, 0.0)), right))
	mm.set_instance_transform(1, Transform3D(Basis.from_euler(Vector3(-_pitch * punch, 0.0, 0.0)), left))
	weapon_mesh.mesh = _weapon_mesh(_weapon, not mag_on)
	mag.visible = mag_on and _weapon == &"gun"
	if mag.visible:
		mag.position = mag_pos
	(_anchors[&"hand_r"] as Node3D).position = right
	(_anchors[&"hand_l"] as Node3D).position = left


func _update_material() -> void:
	if egg == null:
		return
	if _flash <= 0.001 and _fade >= 0.999:
		egg.material_override = HallBuilder.material()
		return
	if _flash > 0.001:
		if _flash_mat == null:
			_flash_mat = HallBuilder.material().duplicate() as StandardMaterial3D
			_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var k := 1.0 + 2.2 * _flash
		_flash_mat.albedo_color = Color(k, k, k, _fade)
		egg.material_override = _flash_mat
		return
	if _fade_mat == null:
		_fade_mat = HallBuilder.material().duplicate() as StandardMaterial3D
		_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.albedo_color = Color(1.0, 1.0, 1.0, _fade)
	egg.material_override = _fade_mat


# ---- โหนดและเมช ----

func _build_nodes() -> void:
	if egg != null:
		return
	egg = MeshInstance3D.new()
	egg.name = "Egg"
	egg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	egg.material_override = HallBuilder.material()
	add_child(egg)
	gauntlets = MultiMeshInstance3D.new()
	gauntlets.name = "Gauntlets"
	gauntlets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gauntlets.material_override = HallBuilder.material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fist_mesh()
	mm.instance_count = 2
	gauntlets.multimesh = mm
	add_child(gauntlets)
	weapon_root = Node3D.new()
	weapon_root.name = "Weapon"
	add_child(weapon_root)
	weapon_mesh = MeshInstance3D.new()
	weapon_mesh.name = "WeaponMesh"
	weapon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon_mesh.material_override = HallBuilder.material()
	weapon_root.add_child(weapon_mesh)
	mag = MeshInstance3D.new()
	mag.name = "Mag"
	mag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mag.material_override = HallBuilder.material()
	mag.mesh = mag_mesh()
	mag.visible = false
	weapon_root.add_child(mag)
	muzzle_node = Marker3D.new()
	muzzle_node.name = "Muzzle"
	muzzle_node.position = Vector3(0.0, 0.035, 0.82)
	weapon_root.add_child(muzzle_node)
	weapon_root.visible = false
	for a in [[&"head", Vector3(0.0, 1.6, 0.0)], [&"chest", Vector3(0.0, 1.1, 0.0)], [&"hand_r", REST_R], [&"hand_l", REST_L]]:
		var m := Marker3D.new()
		m.name = "Anchor_" + String(a[0])
		m.position = a[1]
		add_child(m)
		_anchors[a[0]] = m
	egg.mesh = _egg_mesh(team_colour, int(SIDES.get(level, 12)))


static func _egg_mesh(team: Color, sides: int) -> ArrayMesh:
	var key := "egg|%s|%d" % [team.to_html(false), sides]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = HallBuilder.avatar_mesh(team, sides)
	return _mesh_cache[key]


static func _weapon_mesh(id: StringName, with_mag: bool) -> ArrayMesh:
	match id:
		&"gun":
			return rifle_mesh(with_mag)
		&"sword":
			return sword_mesh()
	return null


## แสงอบง่าย ๆ ทิศเดียวจากบนหน้า (วัสดุไม่รับแสง)
static func _shade(g: PropsLayer.Geo) -> void:
	var l := Vector3(0.35, 0.85, 0.4).normalized()
	var cols := g.c
	for i in cols.size():
		var f := 0.6 + 0.4 * clampf(g.n[i].dot(l) * 0.5 + 0.5, 0.0, 1.0)
		var c := cols[i]
		cols[i] = Color(c.r * f, c.g * f, c.b * f, 1.0)
	g.c = cols


## ท่อ 8 เหลี่ยมตามแกน z (มีฝา) ศูนย์กลาง (x, y) จาก z0 ถึง z1
static func _zprism(g: PropsLayer.Geo, x: float, y: float, z0: float, z1: float, r: float, sides: int, col: Color, caps := true) -> void:
	var a0: Array[Vector3] = []
	var a1: Array[Vector3] = []
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		a0.append(Vector3(x + cos(a) * r, y + sin(a) * r, z0))
		a1.append(Vector3(x + cos(a) * r, y + sin(a) * r, z1))
	for i in sides:
		var k := (i + 1) % sides
		var mid := (a0[i] + a0[k]) * 0.5 - Vector3(x, y, z0)
		g.poly([a0[i], a0[k], a1[k], a1[i]], col, mid)
	if caps:
		g.poly(a0, col * 0.8, Vector3.FORWARD)
		g.poly(a1, col * 0.9, Vector3.BACK)


## กำปั้นถุงมือบรอนซ์ 8 เหลี่ยม r 0.11 (หน้า +z) ข้อนิ้วทองเหลือง ข้อมือเหล็ก
static func fist_mesh() -> ArrayMesh:
	if _mesh_cache.has("fist"):
		return _mesh_cache["fist"]
	var g := PropsLayer.Geo.new()
	_zprism(g, 0.0, 0.0, -0.08, 0.07, FIST_R, 8, HallBuilder.BRONZE)
	for i in 4:
		var x := -0.06 + i * 0.04
		g.box(Vector3(x, 0.035, 0.085), Vector3(0.016, 0.03, 0.02), HallBuilder.BRASS)
	_zprism(g, 0.0, 0.0, -0.15, -0.08, 0.075, 8, HallBuilder.STEEL_DARK)
	g.box(Vector3(0.0, 0.0, -0.115), Vector3(0.085, 0.022, 0.012), HallBuilder.BRASS)
	_shade(g)
	var m := g.mesh()
	_mesh_cache["fist"] = m
	return m


## ปืนไรเฟิลของเรา (พิกัดปืน: ด้ามที่จุดกำเนิด ลำกล้องไป +z): โครงทองเหลือง 0.5 × 0.12 × 0.09 ลำกล้องเหล็ก 0.45 ม.
## ในปลอกระบายความร้อนเจาะร่อง แมกกล่องสั้น พานท้ายโครงโปร่งมีตราเปลวเทียนทองเหลือง
static func rifle_mesh(with_mag: bool = true) -> ArrayMesh:
	var key := "rifle|%s" % with_mag
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var g := PropsLayer.Geo.new()
	var brass := HallBuilder.BRASS
	var steel := HallBuilder.STEEL
	var dark := HallBuilder.STEEL_DARK
	# ด้ามจับ เอียงไปหลังนิดหนึ่ง
	g.poly([Vector3(-0.022, -0.02, 0.03), Vector3(0.022, -0.02, 0.03), Vector3(0.022, -0.14, -0.02), Vector3(-0.022, -0.14, -0.02)], GRIP_COL, Vector3.BACK)
	g.poly([Vector3(-0.022, -0.02, -0.03), Vector3(0.022, -0.02, -0.03), Vector3(0.022, -0.14, -0.07), Vector3(-0.022, -0.14, -0.07)], GRIP_COL, Vector3.FORWARD)
	g.poly([Vector3(-0.022, -0.02, 0.03), Vector3(-0.022, -0.02, -0.03), Vector3(-0.022, -0.14, -0.07), Vector3(-0.022, -0.14, -0.02)], GRIP_COL * 0.9, Vector3.LEFT)
	g.poly([Vector3(0.022, -0.02, 0.03), Vector3(0.022, -0.02, -0.03), Vector3(0.022, -0.14, -0.07), Vector3(0.022, -0.14, -0.02)], GRIP_COL * 0.9, Vector3.RIGHT)
	# โครงปืน (receiver) และราง
	g.box(Vector3(0.0, 0.03, 0.08), Vector3(0.045, 0.06, 0.25), brass, 0.0, true)
	g.box(Vector3(0.0, 0.096, 0.08), Vector3(0.016, 0.008, 0.21), dark)
	g.box(Vector3(0.0, 0.03, 0.08), Vector3(0.047, 0.012, 0.18), HallBuilder.BRONZE)
	# ศูนย์หน้า/หลัง
	g.box(Vector3(0.0, 0.115, -0.08), Vector3(0.012, 0.014, 0.012), dark)
	g.box(Vector3(0.0, 0.112, 0.3), Vector3(0.006, 0.014, 0.008), dark)
	# ปลอกระบายความร้อนเจาะร่อง + ลำกล้อง + ปากลำกล้อง
	_zprism(g, 0.0, 0.035, 0.33, 0.63, 0.046, 8, steel)
	for side in [-1.0, 1.0]:
		for i in 4:
			var z := 0.37 + i * 0.065
			g.box(Vector3(side * 0.043, 0.035, z), Vector3(0.006, 0.018, 0.022), Color("101114"))
	_zprism(g, 0.0, 0.035, 0.63, 0.78, 0.025, 8, dark)
	_zprism(g, 0.0, 0.035, 0.76, 0.82, 0.034, 8, brass)
	# แมกกล่องสั้น
	if with_mag:
		_mag_geo(g, MAG_IN)
	# พานท้ายโครงโปร่ง + แผ่นท้าย + ตราเทียน
	g.box(Vector3(0.0, 0.06, -0.33), Vector3(0.014, 0.012, 0.16), dark)
	HallBuilder.tube(g, Vector3(0.0, -0.03, -0.17), Vector3(0.0, -0.065, -0.49), 0.012, 6, dark)
	g.box(Vector3(0.0, 0.0, -0.5), Vector3(0.026, 0.075, 0.016), brass)
	for side in [-1.0, 1.0]:
		HallBuilder.emblem(g, Vector3(side * 0.016, 0.005, -0.32), Vector3(0.0, 0.0, 1.0), Vector3(side, 0.0, 0.0), 0.042,
			brass, HallBuilder.WAX, HallBuilder.LAMP_AMBER, 12)
	_shade(g)
	var m := g.mesh()
	_mesh_cache[key] = m
	return m


static func _mag_geo(g: PropsLayer.Geo, at: Vector3) -> void:
	g.box(at + Vector3(0.0, -0.01, 0.0), Vector3(0.03, 0.07, 0.04), HallBuilder.STEEL_DARK, 0.0, true)
	g.box(at + Vector3(0.0, -0.01, 0.0), Vector3(0.032, 0.012, 0.042), HallBuilder.BRASS)


## แมกที่หล่นตอนบรรจุ (เมชแยก พิกัดแมกอยู่ที่จุดกำเนิด)
static func mag_mesh() -> ArrayMesh:
	if _mesh_cache.has("mag"):
		return _mesh_cache["mag"]
	var g := PropsLayer.Geo.new()
	_mag_geo(g, Vector3.ZERO)
	_shade(g)
	var m := g.mesh()
	_mesh_cache["mag"] = m
	return m


## ดาบเลื่อยของเรา (พิกัดดาบ: ด้ามที่จุดกำเนิด ใบไป +z): ใบเหล็ก 1.0 ม. ฟัน 18 ซี่ตามสันบน (ไม่ขยับ)
## ห้องมอเตอร์ทรงกล่อง ช่องระบายทองเหลือง ตราเทียนของเรา ด้ามจับ
static func sword_mesh() -> ArrayMesh:
	if _mesh_cache.has("sword"):
		return _mesh_cache["sword"]
	var g := PropsLayer.Geo.new()
	var brass := HallBuilder.BRASS
	HallBuilder.tube(g, Vector3(0.0, 0.0, -0.13), Vector3(0.0, 0.0, 0.03), 0.022, 8, GRIP_COL)
	g.box(Vector3(0.0, 0.0, -0.145), Vector3(0.03, 0.03, 0.02), brass, 0.0, true)
	# ห้องมอเตอร์
	g.box(Vector3(0.0, 0.0, 0.12), Vector3(0.05, 0.075, 0.09), HallBuilder.STEEL, 0.0, true)
	for side in [-1.0, 1.0]:
		for i in 3:
			g.box(Vector3(side * 0.052, 0.035 - i * 0.03, 0.15), Vector3(0.004, 0.008, 0.045), brass)
		HallBuilder.emblem(g, Vector3(side * 0.053, -0.035, 0.08), Vector3(0.0, 0.0, 1.0), Vector3(side, 0.0, 0.0), 0.03,
			brass, HallBuilder.WAX, HallBuilder.LAMP_AMBER, 10)
	# กระบัง
	g.box(Vector3(0.0, 0.0, 0.22), Vector3(0.065, 0.095, 0.014), HallBuilder.BRONZE, 0.0, true)
	# ใบดาบ (ปลายเฉียง)
	var z0 := 0.23
	var z1 := 1.23
	var h := 0.045
	var w := 0.01
	for side in [-1.0, 1.0]:
		g.poly([Vector3(side * w, -h, z0), Vector3(side * w, h, z0), Vector3(side * w, h, z1 - 0.06), Vector3(side * w, -h * 0.2, z1),
			Vector3(side * w, -h, z1 - 0.02)], BLADE, Vector3(side, 0.0, 0.0))
	g.poly([Vector3(-w, -h, z0), Vector3(w, -h, z0), Vector3(w, -h, z1 - 0.02), Vector3(-w, -h, z1 - 0.02)], BLADE * 0.8, Vector3.DOWN)
	g.poly([Vector3(-w, h, z0), Vector3(w, h, z0), Vector3(w, h, z1 - 0.06), Vector3(-w, h, z1 - 0.06)], TEETH, Vector3.UP)
	# ฟัน 18 ซี่ตามสันบน
	var n := 18
	var span := (z1 - 0.06 - z0) / n
	for i in n:
		var a := z0 + i * span
		var tip := Vector3(0.0, h + 0.032, a + span * 0.75)
		for side in [-1.0, 1.0]:
			g.poly([Vector3(side * w * 0.8, h, a), Vector3(side * w * 0.8, h, a + span), tip + Vector3(side * w * 0.3, 0.0, 0.0)],
				TEETH, Vector3(side, 0.2, 0.0))
	# แถบโซ่ใบเลื่อยสีเข้มตามสัน
	for side in [-1.0, 1.0]:
		g.poly([Vector3(side * (w + 0.001), h - 0.012, z0), Vector3(side * (w + 0.001), h, z0), Vector3(side * (w + 0.001), h, z1 - 0.06),
			Vector3(side * (w + 0.001), h - 0.012, z1 - 0.06)], TEETH * 0.7, Vector3(side, 0.0, 0.0))
	_shade(g)
	var m := g.mesh()
	_mesh_cache["sword"] = m
	return m
