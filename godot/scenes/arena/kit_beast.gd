class_name KitBeast
extends Node3D
## ตัวสัตว์รังเริ่มต้น (ARENA_SPEC §8.1–§8.2, สัญญาตัวละคร §9.1): ชุดโมเดล warrior (มีโครง 23 กระดูก) เล่นท่าที่อบไว้
## ใน humanoid.res ผ่าน AnimationPlayer (root_node = "..") · ท่าโพสหลังค่อมของชุด (holds) ทับหลังท่าทุกครั้งที่ท่าลงกระดูก
## น้ำหนักของ hold ค่อย ๆ เปลี่ยนใน 0.15 วิ ตอนสลับท่า จึงไม่กระตุก · ไม่ลดสะโพก ไม่มี IK ขา (รอบนี้)
## ไม่มีชุดโมเดล: "ไข่สัตว์รัง" สร้างด้วยโค้ด ท่าทำเองด้วย Animation แบบเดียวกัน · วัสดุ figure.gdshader ที่ duplicate แล้ว (ไม่มี TIME)
## ระดับ min: ยืนนิ่งท่าเดียว (AnimationPlayer หยุด) ตอนเดินเล่น idle · กะพริบตอนโดน/สีแดงตอนง้าง = วัสดุทับชั่วคราว

signal clip_event(kind: StringName)

const LIB_PATH := "res://assets/anim/humanoid.res"
const MATERIAL := "res://assets/shaders/figure_material.tres"
const BLEND := 0.15             # ผสมท่าตอนสลับ (วิ)
const BLEND_DIE := 0.3
const HOLD_EASE := 0.15         # น้ำหนัก hold เปลี่ยนเต็มใน (วิ)
const HOLD_RATE := 720.0        # แต่ส่วนที่ hold หมุนกระดูกไม่เร็วเกินนี้ (องศา/วิ)
const KIT_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "attack": ["claw_0", "claw_1", "claw_2"],
	"hit": ["flinch"], "hit_heavy": ["flinch_heavy"], "die": ["die_fwd", "die_back", "die_topple"]}
const EGG_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "attack": ["claw"], "hit": ["flinch"],
	"hit_heavy": ["flinch_heavy"], "die": ["die"]}
const LOOPS: Array[StringName] = [&"idle", &"walk", &"run"]
const BONES := {&"head": "head", &"chest": "chest", &"hand_r": "handR", &"hand_l": "handL"}
const SUN_DIR := Vector3(0.2, 1.0, 0.3)
const SUN_COLOUR := Color(0.62, 0.64, 0.68)
const AMBIENT := Color(0.34, 0.36, 0.42)
const FLASH_COLOUR := Color(1.0, 1.0, 1.0)
const TINT_COLOUR := Color(0.9, 0.08, 0.06)
const TINT_K := 0.4
const DEFAULT_HEIGHT := 2.14
const CARAPACE := Color("8a4ea2")
const BONE_WHITE := Color(0.90, 0.86, 0.76)
const EYE_AMBER := Color(1.0, 0.72, 0.22)

var level := "mid"
var _kit := ""
var _lib_name := "humanoid"
var _clips: Dictionary = KIT_CLIPS
var _model: Node3D
var _sk: Skeleton3D
var _meshes: Array[MeshInstance3D] = []
var _ap: AnimationPlayer
var _mat: ShaderMaterial
var _scale := 1.0
var _height := DEFAULT_HEIGHT
var _hold: Dictionary = {}
var _hold_f: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _variant_next := -1
var _loop: StringName = &"idle"
var _loop_rate := 1.0
var _oneshot: StringName = &""
var _dead := false
var _still := false
var _still_wait := -1.0         # รอผสมท่าจบก่อนหยุดนิ่ง (min)
var _manual := false
var _dt := 0.0
var _ev_prev := 0.0
var _flash := 0.0
var _tele := 0.0
var _overlay: StandardMaterial3D
var _anchors: Dictionary = {}
var _cur_anim: Animation
var _set_up := false


## opts: {"role", "level", "team_colour", "seed"} + ของเทส: "kit" (ชื่อชุด), "manual" (เดินท่าด้วย step())
func setup(opts: Dictionary) -> void:
	if _set_up:
		return
	_set_up = true
	level = str(opts.get("level", "mid"))
	_rng.seed = int(opts.get("seed", ArenaData.RANGE["seed"]))
	_manual = bool(opts.get("manual", false))
	var kit := str(opts.get("kit", ArenaData.BEAST["kit"]))
	if not _build_kit(kit):
		_build_egg()
	apply_level(level)
	play(&"idle")


func kit_key() -> String:
	return _kit


func metrics() -> Dictionary:
	if _kit == "egg":
		return {"height": 2.0, "radius": float(ArenaData.BEAST["radius"]), "eye": 1.55, "shoulder": 1.2}
	return {"height": _height, "radius": float(ArenaData.BEAST["radius"]), "eye": 1.9, "shoulder": 1.4}


func clip_names() -> Dictionary:
	var out := {}
	for k in _clips:
		out[k] = PackedStringArray(_clips[k])
	return out


## ท่าถัดไปที่มีหลายแบบใช้แบบนี้ (สัตว์รังสุ่มด้วย seed ของมันแล้วส่งมา) · ไม่อยู่ในสัญญา: ตัวละครอื่นไม่มีก็ได้
func set_variant(i: int) -> void:
	_variant_next = i


## เริ่มท่า: ท่าวนเปลี่ยนท่าวนปัจจุบัน · ท่าครั้งเดียวเล่นจากต้นแล้วกลับท่าวน (die ค้างเฟรมสุดท้าย) · คืนความยาว (วิ)
func play(logical: StringName, speed: float = 1.0) -> float:
	if _ap == null:
		return 0.0
	var names: Array = _clips.get(String(logical), [])
	if names.is_empty():
		return 0.0
	var idx := 0
	if names.size() > 1:
		idx = posmod(_variant_next, names.size()) if _variant_next >= 0 else _rng.randi_range(0, names.size() - 1)
	_variant_next = -1
	var clip := "%s/%s" % [_lib_name, names[idx]]
	if not _ap.has_animation(clip):
		return 0.0
	var anim := _ap.get_animation(clip)
	speed = maxf(speed, 0.01)
	_still = false
	_still_wait = -1.0
	if logical in LOOPS:
		_dead = false
		_oneshot = &""
		_loop = logical
		_loop_rate = speed
		_start(clip, speed, false)
	else:
		_dead = false
		_oneshot = logical
		_start(clip, speed, true)
	return anim.length / speed


## ความเร็วเดิน (ม./วิ ตามทิศหน้า): idle / walk / run และอัตราเล่นให้เท้าไม่ไถล
func set_move(speed: float, running: bool) -> void:
	if _ap == null or _dead:
		return
	var logical: StringName = &"idle" if speed < 0.05 else (&"run" if running else &"walk")
	var rate := 1.0
	if logical != &"idle":
		var anim := _ap.get_animation("%s/%s" % [_lib_name, _clips[String(logical)][0]])
		var cs := float(anim.get_meta("speed", 1.0)) * _scale
		rate = speed / maxf(cs, 0.01)
	_loop_rate = rate
	if _oneshot != &"":
		_loop = logical
		return
	if logical != _loop or (not _ap.is_playing() and not _still):
		_loop = logical
		_start("%s/%s" % [_lib_name, _clips[String(logical)][0]], rate, false)
	elif not _still:
		_ap.speed_scale = rate


func set_aim(_pitch: float) -> void:
	pass


func set_weapon(_id: StringName) -> void:
	pass


func set_flash(a: float) -> void:
	_flash = clampf(a, 0.0, 1.0)
	_update_overlay()


## สีแดงตอนง้าง (hi/mid/lo; min ใช้แค่วงแดงบนพื้นของตัวสัตว์)
func set_telegraph(a: float) -> void:
	_tele = clampf(a, 0.0, 1.0)
	_update_overlay()


func muzzle() -> Node3D:
	return null


func anchor(name: StringName) -> Node3D:
	if _anchors.has(name):
		return _anchors[name]
	var n: Node3D = null
	if _sk != null and BONES.has(name) and _sk.find_bone(BONES[name]) >= 0:
		var ba := BoneAttachment3D.new()
		ba.name = "Anchor_" + String(name)
		ba.bone_name = BONES[name]
		_sk.add_child(ba)
		n = ba
	elif _kit == "egg":
		var pos := {&"head": Vector3(0, 1.55, 0.3), &"chest": Vector3(0, 1.2, 0.2), &"hand_r": Vector3(-0.55, 1.1, 0.7),
			&"hand_l": Vector3(0.55, 1.1, 0.7)}
		if pos.has(name):
			n = Marker3D.new()
			n.name = "Anchor_" + String(name)
			n.position = pos[name]
			add_child(n)
	if n != null:
		_anchors[name] = n
	return n


func apply_level(l: String) -> void:
	level = l
	if _mat != null:
		_mat.set_shader_parameter("per_vertex", l == "lo" or l == "min")
	_update_overlay()
	if _ap == null:
		return
	if l == "min":
		if _oneshot == &"" and _loop == &"idle" and not _dead:
			_go_still()
	elif _still:
		_still = false
		_start("%s/%s" % [_lib_name, _clips["idle"][0]], 1.0, false)


## เดินท่าเอง (เทส: AnimationPlayer แบบ manual)
func step(dt: float) -> void:
	if _ap != null and _manual:
		_dt = dt
		_ap.advance(dt)


func animation_player() -> AnimationPlayer:
	return _ap


func skeleton() -> Skeleton3D:
	return _sk


func playing_clip() -> String:
	return String(_ap.current_animation) if _ap != null else ""


func is_still() -> bool:
	return _still


# ---- ภายใน ----

func _start(clip: String, speed: float, from_start: bool) -> void:
	_cur_anim = _ap.get_animation(clip)
	if from_start and _ap.current_animation == clip:
		_ap.seek(0.0, true)
	# ล้มจากท่าโจมตีที่กำลังเหวี่ยง: ผสมนานกว่า ไม่ให้แขนสะบัด
	# ท่าครั้งเดียวใช้ความเร็วของท่าเอง (ท่าเดิมที่กำลังผสมออกไม่เร่งตาม) · ท่าวนใช้ speed_scale (เปลี่ยนได้ทุกเฟรม)
	if from_start:
		_ap.play(clip, BLEND_DIE if _oneshot == &"die" else BLEND, speed)
		_ap.speed_scale = 1.0
	else:
		_ap.play(clip, BLEND)
		_ap.speed_scale = speed
	_ev_prev = 0.0
	if level == "min" and clip.ends_with("/" + str(_clips["idle"][0])) and _oneshot == &"":
		_still_wait = BLEND


## หยุดนิ่งที่เฟรมแรกของ idle (min): AnimationPlayer ไม่เล่น
func _go_still() -> void:
	var clip := "%s/%s" % [_lib_name, _clips["idle"][0]]
	if _ap.current_animation != clip:
		_ap.play(clip)
	_cur_anim = _ap.get_animation(clip)
	_ap.seek(0.0, true)
	_ap.pause()
	_still = true
	_still_wait = -1.0


func _on_applied() -> void:
	var dt := _dt if _manual else get_process_delta_time()
	_dt = 0.0
	# ท่าครั้งเดียวที่จบแล้ว current_animation ว่างในการวางท่าสุดท้าย: ใช้ท่าที่เริ่มล่าสุด
	var anim: Animation = _ap.get_animation(_ap.current_animation) if _ap.current_animation != "" else _cur_anim
	if anim != null and not _hold.is_empty():
		_apply_holds(anim, dt)
	# เหตุการณ์ในท่า (shot / thud) ของท่าครั้งเดียว
	if anim != null and _oneshot != &"":
		var pos := _ap.current_animation_position
		for e in anim.get_meta("events", []):
			var t := float(e.get("t", -1.0))
			if t > _ev_prev and t <= pos:
				clip_event.emit(StringName(str(e.get("kind", ""))))
		_ev_prev = pos
	if _still_wait >= 0.0:
		_still_wait -= dt
		if _still_wait < 0.0 and level == "min" and _oneshot == &"" and _loop == &"idle" and not _dead:
			_go_still.call_deferred()


## ท่าโพสของชุดทับท่า (test_anim_footslide.apply_holds) น้ำหนักต่อกระดูกเลื่อนเข้าหาเป้าใน HOLD_EASE วิ
func _apply_holds(anim: Animation, dt: float) -> void:
	var mode := String(anim.get_meta("hold_mode", "all"))
	var drives: PackedStringArray = anim.get_meta("drives", PackedStringArray())
	var joints: Dictionary = _hold.get("joints", {})
	# dt 0 (ท่าถูกตั้งใหม่กลางเฟรม) ไม่ขยับน้ำหนัก ไม่งั้นกระโดดทีเดียว
	var step_f := maxf(dt, 0.0) / HOLD_EASE
	for j in joints:
		var v: Variant = joints[j]
		if not (v is Dictionary):
			continue
		var b := _sk.find_bone(String(j))
		if b < 0:
			continue
		var want := 0.0
		if mode == "all" or (mode == "undriven" and not drives.has(String(j))):
			want = 1.0
		var q := _sk.get_bone_pose_rotation(b)
		var qh := q
		if v.has("C"):
			qh = q.slerp(v["C"], float(v["w"]))
		elif v.has("mul"):
			qh = q * (v["mul"] as Quaternion)
		elif v.has("pre"):
			qh = (v["pre"] as Quaternion) * q
		# ท่าโพสห่างท่าดิบมาก (เช่น แขนตอนเริ่มล้ม): จำกัดความเร็วหมุนไม่เกิน HOLD_RATE องศา/วิ
		var ang := rad_to_deg(q.angle_to(qh))
		var lim := step_f if ang <= 0.001 else minf(step_f, HOLD_RATE * maxf(dt, 0.0) / ang)
		var f := float(_hold_f.get(j, want))
		f = move_toward(f, want, lim)
		_hold_f[j] = f
		if f <= 0.0:
			continue
		q = q.slerp(qh, f)
		_sk.set_bone_pose_rotation(b, q.normalized())


func _on_finished(anim_name: StringName) -> void:
	if _oneshot == &"":
		return
	if _oneshot == &"die":
		_dead = true
		return
	_oneshot = &""
	var clip := "%s/%s" % [_lib_name, _clips[String(_loop)][0]]
	_start(clip, _loop_rate if _loop != &"idle" else 1.0, false)


func _update_overlay() -> void:
	if _meshes.is_empty():
		return
	var tint := _tele if level != "min" else 0.0
	var mat: StandardMaterial3D = null
	if _flash > 0.0 or tint > 0.0:
		if _overlay == null:
			_overlay = StandardMaterial3D.new()
			_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if _flash > 0.0:
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_overlay.albedo_color = Color(FLASH_COLOUR, 0.85 * _flash)
		else:
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			_overlay.albedo_color = Color(TINT_COLOUR, TINT_K * tint)
		mat = _overlay
	for m in _meshes:
		m.material_overlay = mat


## ชุดโมเดล: <kit> > Skeleton3D > <kit>_mesh · motion_scale = scale ใน kits.json
func _build_kit(kit: String) -> bool:
	if not KitLibrary.has_kit(kit) or not ResourceLoader.exists(LIB_PATH):
		return false
	var ps := load(KitLibrary.kit_path(kit)) as PackedScene
	var lib := load(LIB_PATH) as AnimationLibrary
	if ps == null or lib == null:
		return false
	var node := ps.instantiate() as Node3D
	if node == null:
		return false
	var sk := node.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk == null:
		node.free()
		return false
	_model = node
	_model.name = "Model"
	add_child(_model)
	_sk = sk
	var man := _manifest()
	var entry: Dictionary = man.get(kit, {})
	_scale = float(entry.get("scale", 1.0))
	_sk.motion_scale = _scale
	var bb := KitLibrary.bounds(man, kit)
	if bb.size.y > 0.0:
		_height = bb.size.y
	var base := load(MATERIAL) as ShaderMaterial
	if base != null:
		_mat = base.duplicate() as ShaderMaterial
		_mat.set_shader_parameter("sun_dir", SUN_DIR)
		_mat.set_shader_parameter("sun_colour", Vector3(SUN_COLOUR.r, SUN_COLOUR.g, SUN_COLOUR.b))
		_mat.set_shader_parameter("ambient_colour", Vector3(AMBIENT.r, AMBIENT.g, AMBIENT.b))
	for c in _sk.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if _mat != null:
				mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_meshes.append(mi)
	_hold = (lib.get_meta("holds", {}) as Dictionary).get(kit, {})
	_ap = AnimationPlayer.new()
	_ap.name = "AnimationPlayer"
	_model.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.add_animation_library("humanoid", lib)
	if _manual:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.mixer_applied.connect(_on_applied)
	_ap.animation_finished.connect(_on_finished)
	_kit = kit
	_lib_name = "humanoid"
	_clips = KIT_CLIPS
	return true


static var _man_cache: Dictionary = {}


static func _manifest() -> Dictionary:
	if _man_cache.is_empty():
		_man_cache = KitLibrary.load_manifest()
	return _man_cache


# ---- ไข่สัตว์รัง (ไม่มีชุดโมเดล) ----

func _build_egg() -> void:
	_kit = "egg"
	_lib_name = "egg"
	_clips = EGG_CLIPS
	_scale = 1.0
	_height = 2.0
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _egg_body_mesh()
	body.material_override = HallBuilder.material()
	_model.add_child(body)
	_meshes.append(body)
	for side in [1.0, -1.0]:
		var arm := MeshInstance3D.new()
		arm.name = "ClawL" if side > 0.0 else "ClawR"
		arm.mesh = _egg_claw_mesh()
		arm.material_override = HallBuilder.material()
		arm.position = Vector3(0.5 * side, 1.15, 0.2)
		_model.add_child(arm)
		_meshes.append(arm)
	_ap = AnimationPlayer.new()
	_ap.name = "AnimationPlayer"
	_model.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.add_animation_library("egg", _egg_library())
	if _manual:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.mixer_applied.connect(_on_applied)
	_ap.animation_finished.connect(_on_finished)


static func _egg_body_mesh() -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	HallBuilder.lathe(g, Vector3.ZERO, 2.0, 0.55, 10, CARAPACE, 0.9, 0.25)
	# หงอนกระดูกตามหลัง
	for i in 5:
		var y := 1.05 + i * 0.2
		var z := -0.42 + i * 0.06
		g.prism(0.0, y, z - 0.02 * i, 0.07, 0.28 - i * 0.03, 4, BONE_WHITE, 0.0)
	# ตาสีอำพัน
	for sx in [-0.15, 0.15]:
		g.box(Vector3(sx, 1.58, 0.47), Vector3(0.06, 0.035, 0.03), EYE_AMBER)
	return g.mesh()


## กรงเล็บ: แขนสั้นกับใบกระดูกสามใบชี้ไปหน้า (+z) จากข้อที่จุดกำเนิด
static func _egg_claw_mesh() -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	g.box(Vector3(0, 0, 0.12), Vector3(0.07, 0.07, 0.14), CARAPACE * 0.85)
	for k in 3:
		var x := (k - 1) * 0.05
		var a := Vector3(x - 0.025, 0.0, 0.24)
		var b := Vector3(x + 0.025, 0.0, 0.24)
		var c := Vector3(x, 0.05, 0.24)
		var tip := Vector3(x, -0.12, 0.75)
		g.poly([a, b, tip], BONE_WHITE, Vector3.DOWN)
		g.poly([b, c, tip], BONE_WHITE * 0.92, Vector3(1, 1, 0))
		g.poly([c, a, tip], BONE_WHITE * 0.86, Vector3(-1, 1, 0))
	return g.mesh()


## ท่าของไข่: ท่าวน (หายใจ เดิน วิ่ง) และท่าครั้งเดียว (ง้างตะปบ สะดุ้ง ล้ม) แบบเดียวกับท่าที่อบ (meta speed / events)
static func _egg_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var claw_l := Vector3(0.5, 1.15, 0.2)
	var claw_r := Vector3(-0.5, 1.15, 0.2)
	# [เวลา, ตัว y, ตัว z, ตัวเอน, กรงเล็บยก (rad รอบ x; ลบ = ง้างขึ้น), กรงเล็บ z]
	var specs := {
		"idle": {"loop": true, "len": 2.0, "speed": 0.0, "keys": [[0.0, 0.0, 0.0, 0.05, 0.0, 0.0], [1.0, 0.03, 0.0, 0.07, -0.08, 0.0], [2.0, 0.0, 0.0, 0.05, 0.0, 0.0]]},
		"walk": {"loop": true, "len": 0.8, "speed": 1.5, "keys": [[0.0, 0.0, 0.0, 0.12, 0.1, 0.0], [0.2, 0.05, 0.0, 0.14, -0.1, 0.0], [0.4, 0.0, 0.0, 0.12, 0.1, 0.0], [0.6, 0.05, 0.0, 0.14, -0.1, 0.0], [0.8, 0.0, 0.0, 0.12, 0.1, 0.0]]},
		"run": {"loop": true, "len": 0.5, "speed": 3.7, "keys": [[0.0, 0.0, 0.0, 0.32, 0.35, 0.0], [0.125, 0.08, 0.0, 0.36, -0.2, 0.0], [0.25, 0.0, 0.0, 0.32, 0.35, 0.0], [0.375, 0.08, 0.0, 0.36, -0.2, 0.0], [0.5, 0.0, 0.0, 0.32, 0.35, 0.0]]},
		"claw": {"loop": false, "len": 0.966667, "speed": 0.0, "events": [{"t": 0.433333, "kind": "shot"}],
			"keys": [[0.0, 0.0, 0.0, 0.05, 0.0, 0.0], [0.3, 0.06, -0.05, -0.18, -1.5, -0.15], [0.433333, 0.0, 0.12, 0.38, 0.9, 0.2], [0.65, 0.0, 0.08, 0.3, 0.6, 0.1], [0.966667, 0.0, 0.0, 0.05, 0.0, 0.0]]},
		"flinch": {"loop": false, "len": 0.5, "speed": 0.0, "keys": [[0.0, 0.0, 0.0, 0.05, 0.0, 0.0], [0.12, -0.04, -0.15, -0.28, -0.5, -0.1], [0.5, 0.0, 0.0, 0.05, 0.0, 0.0]]},
		"flinch_heavy": {"loop": false, "len": 1.033333, "speed": 0.0, "keys": [[0.0, 0.0, 0.0, 0.05, 0.0, 0.0], [0.18, -0.1, -0.35, -0.5, -0.9, -0.15], [0.6, -0.05, -0.2, -0.2, -0.4, 0.0], [1.033333, 0.0, 0.0, 0.05, 0.0, 0.0]]},
		"die": {"loop": false, "len": 1.2, "speed": 0.0, "events": [{"t": 0.8, "kind": "thud"}],
			"keys": [[0.0, 0.0, 0.0, 0.05, 0.0, 0.0], [0.3, 0.05, -0.1, -0.35, -0.8, 0.0], [0.8, 0.25, -0.6, -1.5, 0.6, 0.0], [1.2, 0.25, -0.65, -1.5, 0.7, 0.0]]},
	}
	for nm in specs:
		var sp: Dictionary = specs[nm]
		var a := Animation.new()
		a.length = float(sp["len"])
		a.loop_mode = Animation.LOOP_LINEAR if bool(sp["loop"]) else Animation.LOOP_NONE
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, "Body")
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, "Body")
		var tl := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tl, "ClawL")
		var trr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(trr, "ClawR")
		var tlp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tlp, "ClawL")
		var trp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(trp, "ClawR")
		for k in sp["keys"]:
			var t := float(k[0])
			a.position_track_insert_key(tp, t, Vector3(0.0, float(k[1]), float(k[2])))
			a.rotation_track_insert_key(tr, t, Quaternion(Vector3.RIGHT, float(k[3])))
			var lift := Quaternion(Vector3.RIGHT, float(k[4]))
			a.rotation_track_insert_key(tl, t, lift)
			a.rotation_track_insert_key(trr, t, lift)
			a.position_track_insert_key(tlp, t, claw_l + Vector3(0.0, float(k[1]), float(k[2]) + float(k[5])))
			a.position_track_insert_key(trp, t, claw_r + Vector3(0.0, float(k[1]), float(k[2]) + float(k[5])))
		a.set_meta("speed", float(sp["speed"]))
		a.set_meta("events", sp.get("events", []))
		a.set_meta("hold_mode", "none")
		lib.add_animation(nm, a)
	return lib
