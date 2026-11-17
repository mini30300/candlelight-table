class_name MissionEnemy
extends CharacterBody3D
## ศัตรูหนึ่งตัวในภารกิจ (CAMPAIGN_SPEC §5.4, track C): ตัวชนลอยที่ y = 0 ชั้น 8 ชน 1 | 4 | 2 | 8 (ผู้เล่น ของบัง เสาพิธี
## และศัตรูด้วยกัน ไม่ทับกันเป็นก้อน) · ตัวละครตามสัญญา §9.1: ชุดโมเดลของโต๊ะรบ (KitBeast = ท่ากรงเล็บ, KitFighter = ท่าคนถืออาวุธ)
## ไม่มีชุดบนเครื่อง = ไข่ของ KitBeast ย้อมสีฝ่าย · ฝ่ายฝูงเอเลี่ยนบทบาท brute ใช้ศัตรูของชุดเสริมเมื่อมี
## สมอง MissionAI · ทาง ArenaPath ตารางเดียวของโลก (โลกให้สิทธิ์คิดทางใหม่ ≤ 2 ตัวต่อเฟรมฟิสิกส์) · โลกเรียก step() ทุกเฟรม
## ฟิสิกส์ของตัวที่ยังมีชีวิต (ตัวนี้ไม่มี _physics_process ของตัวเอง) · เขตง้างบนพื้น: hi/mid/lo shader telegraph (ไม่มี TIME)
## min วัสดุแดงเรียบอันเดียวที่ใช้ร่วมกัน โชว์เฉพาะตอนง้าง · min: ไกลกล้องเกิน 25 ม. ตัวละครหยุดท่า (ยังเห็น)
## ไม่มีข้อความไทย · ตัวเลขจาก MissionRoster.stats

signal died(info: Dictionary)
signal hp_changed(hp: int, hp_max: int)

const LAYER := 8
const MASK := 1 | 4 | 2 | 8
const MASK_DEAD := 1 | 4
const FLASH := 0.08
const FLASH_GUN := 0.45
const KB_STOP := 0.02
const FRICTION := 8.0
const REPATH := 1.0              # คิดทางใหม่อย่างน้อยทุกกี่วิ (ถ้าได้สิทธิ์)
const GOAL_MOVE := 1.5           # จุดหมายขยับเกินนี้ คิดทางใหม่
const WAYPOINT_R := 0.45
const LOS_EVERY := 0.3
const FAR_STILL := 25.0          # min: ไกลกว่านี้ตัวละครหยุดท่า
const CLAW_EVENT := 0.433        # เวลากรงเล็บลงในท่า claw (วิ) ใช้ตั้งความเร็วท่าให้ลงตอนง้างครบ
const TELEGRAPH_SHADER := "res://scenes/arena/telegraph.gdshader"
const RING_SEG := 18
const RING_RIM := 0.1

static var _flat_red: StandardMaterial3D
static var _egg_mats: Dictionary = {}
static var _ring_meshes: Dictionary = {}

var level := "mid"
var world: Node3D
var index := 0
var post: Variant = null
var dead_t := 0.0
var faction := ""
var _role := "rusher"
var _kit := ""
var _style := "beast"
var _figure: Node3D
var _fighter := false
var _ai: MissionAI
var _path: ArenaPath
var _stats: Dictionary = {}
var _hp := 1
var _hp_max := 1
var _alive := true
var _kb := Vector3.ZERO
var _flash := 0.0
var _flash_peak := 1.0
var _radius := 0.45
var _height := 1.8
var _yaw := 0.0
var _pts := PackedVector2Array()
var _pi := 0
var _repath_t := 0.0
var _last_goal := Vector2(INF, INF)
var _los := true
var _los_t := 0.0
var _still_far := false
var _far_t := 0.0
var _moving := false
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _bounds := Rect2(-22, -22, 44, 44)
var _skinned := false


## opts: {"level", "seed", "role", "faction", "kit", "style", "stats" (MissionRoster.stats + flank_pct/aggro), "spawn": Vector3,
## "path": ArenaPath, "post": Vector2 | null, "index", "figure" (บังคับตัวละคร: เทส), "bounds": Rect2}
func setup(w: Node3D, opts: Dictionary) -> void:
	world = w
	level = str(opts.get("level", "mid"))
	_role = str(opts.get("role", "rusher"))
	faction = str(opts.get("faction", ""))
	_kit = str(opts.get("kit", ""))
	_style = str(opts.get("style", "beast"))
	_stats = (opts.get("stats", MissionRoster.ROLE_STATS["rusher"]) as Dictionary).duplicate()
	_path = opts.get("path")
	post = opts.get("post")
	index = int(opts.get("index", 0))
	_bounds = opts.get("bounds", _bounds)
	collision_layer = LAYER
	collision_mask = MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var seed_v := int(opts.get("seed", 1))
	_ai = MissionAI.new(seed_v, _role, _stats)
	_hp_max = int(_stats.get("hp", 60))
	_hp = _hp_max
	_radius = float(_stats.get("radius", 0.45))
	_figure = opts.get("figure", null)
	if _figure == null:
		_figure = _make_figure(seed_v)
	_figure.name = "Figure"
	if _figure.get_parent() == null:
		add_child(_figure)
	var m: Dictionary = _figure.call(&"metrics") if _figure.has_method(&"metrics") else {}
	_height = maxf(float(m.get("height", 1.8)), _radius * 2.0 + 0.1)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = _radius
	cap.height = _height
	cs.shape = cap
	cs.position = Vector3(0.0, _height * 0.5, 0.0)
	add_child(cs)
	var sp: Vector3 = opts.get("spawn", Vector3.ZERO)
	position = Vector3(sp.x, 0.0, sp.z)
	_yaw = float(opts.get("yaw", 0.0))
	rotation.y = _yaw
	if _fighter and _role == "gunner":
		_figure.call(&"set_weapon", &"gun")
	_build_ring()
	set_physics_process(false)


func _make_figure(seed_v: int) -> Node3D:
	var fo := {"role": &"enemy", "level": level, "team_colour": Color(0.54, 0.31, 0.64), "seed": seed_v}
	if faction == "swarm" and _role == "brute" and ArenaActors.pack_id() != "":
		var pf := ArenaActors.make_figure("enemy")
		if pf != null:
			pf.call(&"setup", fo)
			_skinned = true
			return pf
	if _kit != "" and KitLibrary.has_kit(_kit):
		var fig: Node3D
		if _style == "fighter":
			var kf := KitFighter.new()
			kf.walk_kit = _kit
			fig = kf
			_fighter = true
		else:
			fig = KitBeast.new()
			fo["kit"] = _kit
		add_child(fig)
		fig.call(&"setup", fo)
		_skinned = true
		return fig
	# ไม่มีชุดโมเดล: ไข่สัตว์รังย้อมสีฝ่าย ขนาดตามบทบาท
	var egg := KitBeast.new()
	fo["kit"] = ""
	add_child(egg)
	egg.call(&"setup", fo)
	var s := float(MissionRoster.EGG_SCALE.get(_role, 1.0))
	egg.scale = Vector3.ONE * s
	var col := _faction_colour()
	var mat := _egg_material(col)
	for c in egg.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = mat
	return egg


func apply_level(l: String) -> void:
	level = l
	if _figure != null and _figure.has_method(&"apply_level"):
		_figure.call(&"apply_level", l)
	_set_ring_material()
	if l != "min" and _still_far:
		_still_far = false
		_figure.process_mode = Node.PROCESS_MODE_INHERIT


func role() -> String:
	return _role


func kit_key() -> String:
	return _kit


func hp() -> int:
	return _hp


func hp_max() -> int:
	return _hp_max


func is_alive() -> bool:
	return _alive


func radius() -> float:
	return _radius


func height() -> float:
	return _height


func ai() -> MissionAI:
	return _ai


func figure() -> Node3D:
	return _figure


func skinned() -> bool:
	return _skinned


func telegraph_uses_shader() -> bool:
	return _ring != null and _ring.material_override is ShaderMaterial


func telegraph_visible() -> bool:
	return _ring != null and _ring.visible


## โดน: {"amount", "kind", "point", "dir", "knockback", "stagger"} → {"applied", "hp", "killed"}
func take_hit(hit: Dictionary) -> Dictionary:
	if not _alive:
		return {"applied": 0, "hp": _hp, "killed": false}
	var r := ArenaCombat.apply(_hp, int(hit.get("amount", 0)))
	var applied := int(r["applied"])
	var killed := bool(r["killed"])
	_hp = int(r["hp"])
	var kind := StringName(str(hit.get("kind", "")))
	_flash = FLASH
	_flash_peak = FLASH_GUN if kind == &"gun" else 1.0
	_fig("set_flash", [_flash_peak])
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	var kb := float(hit.get("knockback", 0.0))
	if _role == "boss":
		kb *= 0.2
	elif _role == "brute":
		kb *= 0.5
	_kb += ArenaCombat.knockback(dir, kb)
	var react := _ai.on_damage(applied, bool(hit.get("stagger", false)), killed)
	hp_changed.emit(_hp, _hp_max)
	if killed:
		_die(kind)
	elif react == &"flinch":
		_ring_show(false)
		_fig("play", [&"hit", 1.0])
	return {"applied": applied, "hp": _hp, "killed": killed}


## หนึ่งก้าวของโลก: targets ของ MissionAI · can_repath = ได้สิทธิ์คิดทางใหม่เฟรมนี้ · คืน true เมื่อใช้สิทธิ์
func step(dt: float, targets: Array, can_repath: bool, cam_pos: Vector3) -> bool:
	if _flash > 0.0:
		_flash = maxf(_flash - dt, 0.0)
		_fig("set_flash", [_flash_peak * _flash / FLASH])
	if not _alive:
		dead_t += dt
		return false
	var pos := Vector2(position.x, position.z)
	var used := false
	if _role == "gunner":
		_los_t -= dt
		if _los_t <= 0.0:
			_los_t = LOS_EVERY
			_los = _line_of_sight(targets)
	var way: Variant = null
	if _pi < _pts.size():
		if pos.distance_to(_pts[_pi]) < WAYPOINT_R:
			_pi += 1
		if _pi < _pts.size():
			way = _pts[_pi]
	var me := {"pos": pos, "yaw": _yaw, "alive": true, "way": way, "post": post, "los": _los}
	var r := _ai.tick(dt, me, targets)
	var goal: Vector2 = r["goal"]
	_repath_t -= dt
	if can_repath and _path != null and _ai.state == MissionAI.CHASE and (_repath_t <= 0.0 or goal.distance_to(_last_goal) > GOAL_MOVE):
		_pts = _path.find(pos, goal)
		_pi = 1
		_repath_t = REPATH
		_last_goal = goal
		used = true
	_yaw = float(r["face"])
	rotation.y = _yaw
	var ev: StringName = r["event"]
	if ev != &"":
		_on_event(ev, targets, int(r["target"]))
	var mv: Vector2 = r["move"]
	var v := Vector3(mv.x, 0.0, mv.y) + _kb
	var moving := v.length_squared() > 0.0004
	if moving:
		velocity = v
		move_and_slide()
		position.y = 0.0
		position.x = clampf(position.x, _bounds.position.x + _radius, _bounds.end.x - _radius)
		position.z = clampf(position.z, _bounds.position.y + _radius, _bounds.end.y - _radius)
	_kb = ArenaCombat.decay(_kb, FRICTION, dt)
	if _kb.length() < KB_STOP:
		_kb = Vector3.ZERO
	if not _ai.busy():
		var spd := mv.length()
		if (spd > 0.05) != _moving or spd > 0.05:
			_fig("set_move", [spd, spd > 2.2])
		_moving = spd > 0.05
	if _ring != null and _ring.visible:
		var t := _ai.telegraph()
		if _ring_mat != null and _ring.material_override == _ring_mat:
			_ring_mat.set_shader_parameter(&"fill", t)
	if level == "min":
		_far_t -= dt
		if _far_t <= 0.0:
			_far_t = 0.25
			var far := Vector2(cam_pos.x, cam_pos.z).distance_to(pos) > FAR_STILL
			if far != _still_far:
				_still_far = far
				_figure.process_mode = Node.PROCESS_MODE_DISABLED if far else Node.PROCESS_MODE_INHERIT
	return used


## หยุดชั่วคราว: ตัวละครหยุดท่า (โลกหยุดเรียก step เอง)
func set_paused(on: bool) -> void:
	if _figure != null:
		_figure.process_mode = Node.PROCESS_MODE_DISABLED if on or _still_far else Node.PROCESS_MODE_INHERIT


func chest() -> Vector3:
	return global_position + Vector3(0.0, _height * 0.62, 0.0)


# ---- ภายใน ----

func _on_event(ev: StringName, targets: Array, ti: int) -> void:
	var t: Dictionary = targets[ti] if ti >= 0 and ti < targets.size() else {}
	match ev:
		&"windup":
			var w := maxf(float(_stats.get("windup", 0.5)), 0.05)
			if _fighter:
				_fig("play", [&"swing", clampf(0.5 / w, 0.4, 2.0)])
			else:
				_fig("play", [&"attack", clampf(CLAW_EVENT / w, 0.4, 2.5)])
			_ring_show(true)
			if world != null and world.has_method(&"enemy_event"):
				world.call(&"enemy_event", self, &"windup", t)
		&"strike":
			_ring_show(false)
			var landed := false
			if not t.is_empty() and bool(t.get("alive", true)):
				landed = _ai.strike_hits(Vector2(position.x, position.z), _yaw, t.get("pos", Vector2.ZERO), float(t.get("r", 0.35)))
			if world != null and world.has_method(&"enemy_strike"):
				world.call(&"enemy_strike", self, t, int(_stats.get("dmg", 8)) if landed else 0)
		&"aim":
			if not _fighter:
				_fig("play", [&"attack", 0.8])
		&"fire":
			if _fighter:
				_fig("play", [&"fire", 1.0])
			if world != null and world.has_method(&"enemy_fire") and not t.is_empty():
				world.call(&"enemy_fire", self, t)


func _die(kind: StringName) -> void:
	_alive = false
	collision_layer = 0
	collision_mask = MASK_DEAD
	velocity = Vector3.ZERO
	_ring_show(false)
	if _figure != null and _still_far:
		_figure.process_mode = Node.PROCESS_MODE_INHERIT
	_fig("play", [&"die", 1.0])
	died.emit({"role": _role, "kit": _kit, "faction": faction, "by": kind})


func _line_of_sight(targets: Array) -> bool:
	if targets.is_empty() or not is_inside_tree():
		return true
	var ti := _ai.target
	var t: Dictionary = targets[ti] if ti >= 0 and ti < targets.size() else targets[0]
	var tp: Vector2 = t.get("pos", Vector2.ZERO)
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var a := chest()
	var q := PhysicsRayQueryParameters3D.create(a, Vector3(tp.x, 1.3, tp.y), 1)
	return space.intersect_ray(q).is_empty()


func _fig(method: StringName, args: Array) -> void:
	if _figure != null and _figure.has_method(method):
		_figure.callv(method, args)


func _faction_colour() -> Color:
	for f: Dictionary in CampaignGalaxy.FACTIONS:
		if str(f["id"]) == faction:
			return Color(str(f["col"]))
	return Color(0.54, 0.31, 0.64)


static func _egg_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html(false)
	if not _egg_mats.has(key):
		var m := HallBuilder.material().duplicate() as StandardMaterial3D
		m.albedo_color = col.lerp(Color.WHITE, 0.35)
		_egg_mats[key] = m
	return _egg_mats[key]


## เขตง้าง: พัดตามระยะฟาดจริง ±MissionAI.STRIKE_CONE (หนึ่ง draw ตอนโชว์)
func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Telegraph"
	_ring.mesh = _ring_mesh(float(_stats.get("reach", 1.8)) + _radius)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.03, 0.0)
	_ring.visible = false
	add_child(_ring)
	_set_ring_material()


func _set_ring_material() -> void:
	if _ring == null:
		return
	if level == "min":
		if _flat_red == null:
			_flat_red = StandardMaterial3D.new()
			_flat_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_flat_red.albedo_color = Color(0.85, 0.1, 0.06)
			_flat_red.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring.material_override = _flat_red
	else:
		if _ring_mat == null:
			_ring_mat = ShaderMaterial.new()
			_ring_mat.shader = load(TELEGRAPH_SHADER)
		_ring.material_override = _ring_mat


func _ring_show(on: bool) -> void:
	if _ring == null or _role == "gunner":
		return
	_ring.visible = on
	if on and _ring_mat != null and _ring.material_override == _ring_mat:
		_ring_mat.set_shader_parameter(&"fill", 0.0)


static func _ring_mesh(reach: float) -> ArrayMesh:
	var key := snappedf(reach, 0.1)
	if _ring_meshes.has(key):
		return _ring_meshes[key]
	var half := deg_to_rad(MissionAI.STRIKE_CONE)
	var inner := reach - RING_RIM
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in RING_SEG:
		var a0 := -half + 2.0 * half * i / RING_SEG
		var a1 := -half + 2.0 * half * (i + 1) / RING_SEG
		var d0 := Vector3(sin(a0), 0.0, cos(a0))
		var d1 := Vector3(sin(a1), 0.0, cos(a1))
		for v: Array in [[Vector3.ZERO, 0.0], [d0 * inner, 1.0], [d1 * inner, 1.0]]:
			st.set_uv(Vector2(float(v[1]), 0.0))
			st.add_vertex(v[0])
		for v: Vector3 in [d0 * inner, d0 * reach, d1 * reach, d0 * inner, d1 * reach, d1 * inner]:
			st.set_uv(Vector2(1.0, 1.0))
			st.add_vertex(v)
	var m := st.commit()
	_ring_meshes[key] = m
	return m
