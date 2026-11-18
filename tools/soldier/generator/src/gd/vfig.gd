extends Node3D
## (สำเนาสำหรับทำภาพร่างหลากหลาย: FIG_DIR = โฟลเดอร์ทรัพยากร ; วัสดุสร้างจากเชดเดอร์ของขั้นปั้น)
## ทหาร ขั้นที่ 1 (ร่างกายวิภาคเปลือย ยังไม่มีชุด/ปืน): โครง 23 กระดูกของเกม + กระดูกช่วย 10 + ผิว 1 พื้นผิวต่อระดับ
## สัญญาตัวละคร (ARENA_SPEC §9.1): 12 เมธอด + สัญญาณ clip_event ; ท่าจาก humanoid.res ตรง ๆ (ไม่ต้อง retarget)
## ตัวขับใน mixer_applied (ไม่มี _process): hi/mid = กระดูกช่วย + ท่าแก้ (blend shape 14) ; lo = กระดูกช่วย ; min = ไม่มีเลย
## min: ยืนนิ่งท่าแรกของ idle ภายในไม่กี่เฟรมหลัง set_move(0) ; เมช/วัสดุ/คลิปเก็บใน static (ใช้ร่วมทุกตัว)

signal clip_event(kind: StringName)

static var DIR := "res://out/godot/"
const LIB_PATH := "res://ref/humanoid.res"
const HEIGHT := 1.78
const S := 1.78 / 1.6
const BLEND := 0.15
const MIN_STILL := 0.04       # min: หยุดนิ่งเร็ว (ไม่รอผสมท่าเต็ม)
const LEVELS := ["hi", "mid", "lo", "min"]
const BONES := {&"head": "head", &"chest": "chest", &"hand_r": "handR", &"hand_l": "handL"}
const PLAYER_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "fire": ["fire"], "punch": ["bash_0", "bash_1", "bash_2"],
	"swing": ["thrust_0", "thrust_1", "thrust_2"], "hit": ["flinch"], "die": ["die_back", "die_fwd", "die_spin"]}
const ENEMY_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "attack": ["fire"], "hit": ["flinch"],
	"hit_heavy": ["flinch_heavy"], "die": ["die_back", "die_fwd", "die_spin"]}
const LOOPS := [&"idle", &"walk", &"run"]
# ---- ตัวขับ (สูตรเดียวกับ src/py/rig.py + correctives.py) ----
const CLAV_ELEV_K := 0.12
const CLAV_ELEV_MAX := 15.0
const CLAV_PROT_K := 0.12
const TWIST_K := 0.5
const BIND_ELBOW := 8.0
const ELBOW_KEY := 120.0
const KNEE_KEY := 120.0
const HIP_FLEX_KEY := 100.0
const HIP_EXT_KEY := 25.0
const DOWN := Vector3(0, -1, 0)

static var _mesh_cache: Dictionary = {}
static var _mat: ShaderMaterial
static var _lib: AnimationLibrary
static var _rig: PackedScene
static var _skin: Skin
static var _arm_keys: Dictionary = {}

var role: StringName = &"player"
var level := "hi"
var weapon: StringName = &"none"
var helpers_on := true          # ทดสอบ/ทำภาพ: ปิดกระดูกช่วยหรือท่าแก้ได้
var correctives_on := true
var _sk: Skeleton3D
var _mi: MeshInstance3D
var _ap: AnimationPlayer
var _clips: Dictionary = PLAYER_CLIPS
var _loop: StringName = &"idle"
var _loop_rate := 1.0
var _oneshot: StringName = &""
var _dead := false
var _still := false
var _still_wait := -1.0
var _ev_prev := 0.0
var _aim := 0.0
var _anchors: Dictionary = {}
var _muzzle: Marker3D
var _overlay: StandardMaterial3D
var _flash := 0.0
var _tele := 0.0
var _rng := RandomNumberGenerator.new()
var _bs_idx: Dictionary = {}
var _hb: Dictionary = {}         # ชื่อกระดูก -> ดัชนี
var last_weights: Dictionary = {}
var deform_us := 0.0             # เวลาตัวขับครั้งล่าสุด (ไมโครวินาที)


func _init() -> void:
	_load_static()
	var root := _rig.instantiate() as Node3D
	_sk = root.get_node("Skeleton3D") as Skeleton3D
	root.remove_child(_sk)
	_sk.owner = null
	root.free()
	add_child(_sk)
	for i in _sk.get_bone_count():
		_hb[_sk.get_bone_name(i)] = i
	_mi = MeshInstance3D.new()
	_mi.name = "Body"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sk.add_child(_mi)
	_mi.skeleton = NodePath("..")
	_mi.skin = _skin
	_ap = AnimationPlayer.new()
	_ap.name = "AnimationPlayer"
	add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.add_animation_library("humanoid", _lib)
	_ap.mixer_applied.connect(_on_applied)
	_ap.animation_finished.connect(_on_finished)
	_set_mesh("hi")


static func _load_static() -> void:
	if _rig != null:
		return
	var e := OS.get_environment("FIG_DIR")
	if e != "":
		DIR = e
	_rig = load(DIR + "rig.tscn") as PackedScene
	_skin = load(DIR + "skin.res") as Skin
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/gd/soldier_skin.gdshader") as Shader
	_lib = load(LIB_PATH) as AnimationLibrary
	var s35 := deg_to_rad(35.0)
	_arm_keys = {"bind": Vector3(sin(s35), -cos(s35), 0), "down": Vector3(sin(deg_to_rad(5)), -cos(deg_to_rad(5)), 0),
		"front": Vector3(0, 0, 1), "up": Vector3(sin(deg_to_rad(160)), -cos(deg_to_rad(160)), 0)}


static func body_mesh(l: String) -> ArrayMesh:
	if not _mesh_cache.has(l):
		_mesh_cache[l] = load(DIR + "body_%s.res" % l)
	return _mesh_cache[l]


# ================= สัญญาตัวละคร =================

func setup(opts: Dictionary) -> void:
	role = StringName(str(opts.get("role", "player")))
	_clips = ENEMY_CLIPS if role == &"enemy" else PLAYER_CLIPS
	_rng.seed = int(opts.get("seed", 1))
	apply_level(str(opts.get("level", level)))
	play(&"idle")


func metrics() -> Dictionary:
	return {"height": HEIGHT, "radius": 0.35, "eye": 1.663, "shoulder": 1.446}


func clip_names() -> Dictionary:
	return _clips.duplicate(true)


func play(logical: StringName, speed: float = 1.0) -> float:
	var names: Array = _clips.get(String(logical), [])
	if names.is_empty():
		return 0.0
	var clip := "humanoid/" + str(names[_rng.randi_range(0, names.size() - 1)] if names.size() > 1 else names[0])
	if not _ap.has_animation(clip):
		return 0.0
	speed = maxf(speed, 0.01)
	_still = false
	_still_wait = -1.0
	_dead = false
	if logical in LOOPS:
		_oneshot = &""
		_loop = logical
		_loop_rate = speed
		_ap.play(clip, BLEND)
		_ap.speed_scale = speed
	else:
		_oneshot = logical
		if _ap.current_animation == clip:
			_ap.seek(0.0, true)
		_ap.play(clip, BLEND, speed)
		_ap.speed_scale = 1.0
	_ev_prev = 0.0
	if level == "min" and logical == &"idle":
		_still_wait = MIN_STILL
	return _ap.get_animation(clip).length / speed


func set_move(speed: float, running: bool) -> void:
	if _dead:
		return
	var logical: StringName = &"idle" if speed < 0.05 else (&"run" if running else &"walk")
	var rate := 1.0
	if logical != &"idle":
		var anim := _ap.get_animation("humanoid/" + str(_clips[String(logical)][0]))
		rate = speed / maxf(float(anim.get_meta("speed", 1.0)) * S, 0.01)
	if _oneshot != &"":
		_loop = logical
		_loop_rate = rate
		return
	if logical != _loop or (not _ap.is_playing() and not _still):
		play(logical, rate)
	elif not _still:
		_ap.speed_scale = rate


func set_aim(pitch: float) -> void:
	_aim = clampf(pitch, -0.9, 0.6)


func set_weapon(id: StringName) -> void:
	weapon = id


func set_flash(a: float) -> void:
	_flash = clampf(a, 0.0, 1.0)
	_update_overlay()


func set_telegraph(a: float) -> void:
	_tele = clampf(a, 0.0, 1.0) if level != "min" else 0.0
	_update_overlay()


func muzzle() -> Node3D:
	if role == &"enemy":
		return null
	if _muzzle == null:
		var ba := anchor(&"hand_r")
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		_muzzle.position = Vector3(0, -0.05, 0.45)
		ba.add_child(_muzzle)
	return _muzzle


func anchor(name: StringName) -> Node3D:
	if _anchors.has(name):
		return _anchors[name]
	if not BONES.has(name):
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Anchor_" + String(name)
	ba.bone_name = BONES[name]
	_sk.add_child(ba)
	_anchors[name] = ba
	return ba


func apply_level(l: String) -> void:
	if not l in LEVELS:
		l = "mid"
	level = l
	_set_mesh(l)
	if l == "min":
		_reset_helpers()
		if _oneshot == &"" and _loop == &"idle" and not _dead:
			_go_still()
	elif _still:
		_still = false
		play(&"idle")


# ================= ใช้ในเครื่องมือทำภาพ/ทดสอบ =================

func skeleton() -> Skeleton3D:
	return _sk


func body() -> MeshInstance3D:
	return _mi


func animation_player() -> AnimationPlayer:
	return _ap


func is_still() -> bool:
	return _still


## วางท่าตรง ๆ (หยุดคลิป): local = ชื่อกระดูก -> Quaternion ; pelvis = ตำแหน่งเชิงกราน
func set_pose(local: Dictionary, pelvis: Vector3) -> void:
	_ap.stop()
	for b in local:
		_sk.set_bone_pose_rotation(_hb[b], local[b])
	_sk.set_bone_pose_position(_hb["pelvis"], pelvis)
	deform()


func use_mesh(l: String) -> void:
	_set_mesh(l)


# ================= ตัวขับกระดูกช่วย + ท่าแก้ =================

func deform() -> void:
	if level == "min" and _aim == 0.0:
		deform_us = 0.0
		return                                   # min: ไม่มีงานเพิ่มต่อเฟรม (ผิวไม่ใช้กระดูกช่วย/ท่าแก้)
	var t0 := Time.get_ticks_usec()
	var L := {}
	for b in ["shoulderL", "shoulderR", "elbowL", "elbowR", "hipL", "hipR", "kneeL", "kneeR"]:
		L[b] = _sk.get_bone_pose_rotation(_hb[b])
	if _aim != 0.0:
		var c: int = _hb["chest"]
		_sk.set_bone_pose_rotation(c, Quaternion(Vector3(1, 0, 0), -_aim) * _sk.get_bone_pose_rotation(c))
	var use_h := helpers_on and level != "min"
	if use_h:
		for sd in ["L", "R"]:
			var sx := 1.0 if sd == "L" else -1.0
			_sk.set_bone_pose_rotation(_hb["elbow_half" + sd], Quaternion.IDENTITY.slerp(L["elbow" + sd], 0.5))
			_sk.set_bone_pose_rotation(_hb["knee_half" + sd], Quaternion.IDENTITY.slerp(L["knee" + sd], 0.5))
			_sk.set_bone_pose_rotation(_hb["hip_half" + sd], Quaternion.IDENTITY.slerp(L["hip" + sd], 0.5))
			var qs: Quaternion = L["shoulder" + sd]
			var tw := Quaternion(0, qs.y, 0, qs.w)
			tw = Quaternion.IDENTITY if tw.length() < 1e-9 else tw.normalized()
			_sk.set_bone_pose_rotation(_hb["uparm_twist" + sd], Quaternion.IDENTITY.slerp(tw.inverse(), TWIST_K))
			var d := qs * DOWN
			var elev := rad_to_deg(acos(clampf(-d.y, -1, 1)))
			var a := minf(CLAV_ELEV_MAX, CLAV_ELEV_K * maxf(0.0, elev - 30.0))
			var b := CLAV_PROT_K * rad_to_deg(asin(clampf(d.z, -1, 1)))
			_sk.set_bone_pose_rotation(_hb["clavicle" + sd],
				Quaternion(Vector3(0, 1, 0), deg_to_rad(-sx * b)) * Quaternion(Vector3(0, 0, 1), deg_to_rad(sx * a)))
	if correctives_on and use_h and _mi.mesh != null and _mi.mesh.get_blend_shape_count() > 0:
		var w := corrective_weights(L)
		last_weights = w
		for k in w:
			var i: int = _bs_idx.get(k, -1)
			if i >= 0:
				var v: float = w[k]
				if absf(_mi.get_blend_shape_value(i) - v) > 0.002:
					_mi.set_blend_shape_value(i, v if v > 0.01 else 0.0)
	deform_us = float(Time.get_ticks_usec() - t0)


static func _ang(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func corrective_weights(L: Dictionary) -> Dictionary:
	var out := {}
	for sd in ["L", "R"]:
		var sx := 1.0 if sd == "L" else -1.0
		var d: Vector3 = (L["shoulder" + sd] as Quaternion) * DOWN
		d.x *= sx
		for k in ["down", "front", "up"]:
			var r := _ang(_arm_keys["bind"], _arm_keys[k])
			out["shoulder_%s%s" % [k, sd]] = _ease(1.0 - _ang(d, _arm_keys[k]) / r)
		var th := _ang((L["elbow" + sd] as Quaternion) * DOWN, DOWN)
		out["elbow_flex" + sd] = clampf((th - BIND_ELBOW) / (ELBOW_KEY - BIND_ELBOW), 0.0, 1.0)
		out["knee_flex" + sd] = clampf(_ang((L["knee" + sd] as Quaternion) * DOWN, DOWN) / KNEE_KEY, 0.0, 1.0)
		var t: Vector3 = (L["hip" + sd] as Quaternion) * DOWN
		var phi := rad_to_deg(atan2(t.z, -t.y))
		out["hip_flex" + sd] = clampf(phi / HIP_FLEX_KEY, 0.0, 1.0)
		out["hip_ext" + sd] = clampf(-phi / HIP_EXT_KEY, 0.0, 1.0)
	return out


# ================= ภายใน =================

func _set_mesh(l: String) -> void:
	_mi.mesh = body_mesh(l)
	_mat.set_shader_parameter("per_vertex", false)
	var m := _mat
	if l == "lo" or l == "min":
		m = _shared_pv()
	_mi.material_override = m
	_bs_idx.clear()
	for i in _mi.mesh.get_blend_shape_count():
		_bs_idx[String(_mi.mesh.get_blend_shape_name(i))] = i
		_mi.set_blend_shape_value(i, 0.0)


static var _pv_mat: ShaderMaterial


static func _shared_pv() -> ShaderMaterial:
	if _pv_mat == null:
		_pv_mat = _mat.duplicate() as ShaderMaterial
		_pv_mat.set_shader_parameter("per_vertex", true)
	return _pv_mat


func _reset_helpers() -> void:
	for n in _hb:
		if n.begins_with("clavicle") or n.begins_with("uparm_twist") or n.ends_with("_halfL") or n.ends_with("_halfR"):
			_sk.set_bone_pose_rotation(_hb[n], Quaternion.IDENTITY)


func _go_still() -> void:
	var clip := "humanoid/idle"
	if _ap.current_animation != clip:
		_ap.play(clip)
	_ap.seek(0.0, true)
	_ap.pause()
	_still = true
	_still_wait = -1.0


func _on_applied() -> void:
	var dt := get_process_delta_time()
	deform()
	var anim: Animation = _ap.get_animation(_ap.current_animation) if _ap.current_animation != "" else null
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


func _on_finished(_n: StringName) -> void:
	if _oneshot == &"":
		return
	if _oneshot == &"die":
		_dead = true
		return
	_oneshot = &""
	play(_loop, _loop_rate if _loop != &"idle" else 1.0)


func _update_overlay() -> void:
	var mat: StandardMaterial3D = null
	if _flash > 0.0 or _tele > 0.0:
		if _overlay == null:
			_overlay = StandardMaterial3D.new()
			_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if _flash > 0.0:
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_overlay.albedo_color = Color(1, 1, 1, 0.85 * _flash)
		else:
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			_overlay.albedo_color = Color(0.9, 0.08, 0.06, 0.4 * _tele)
		mat = _overlay
	_mi.material_overlay = mat
