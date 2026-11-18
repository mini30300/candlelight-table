class_name SoldierFigure
extends Node3D
## ทหารราบ (ทดลอง): ร่างคนตามกายวิภาค (โครง → กล้าม → ผิว) จากเครื่องมือ tools/soldier · ยังไม่มีชุดและปืน
## ตัวในห้องแต่งตัว (Figures kind builtin): เดินบนดาดฟ้า เป็นตัวผู้เล่นในห้องทดลองและภารกิจ และในการ์ด "ธรรมดา"
## สัญญาตัวละคร (ARENA_SPEC §9.1): 12 เมธอด + clip_event · ดาดฟ้า (PACK_SPEC §3) + deck_speeds · H6 H8 H9 แบบ KitFighter
## ไฟล์ทั้งหมดใน assets/figures/soldier/ (tools/soldier/import_stage.sh นำเข้า) · ร่างอื่น (body_id) ใน assets/figures/soldier_<id>/
## ชุดเดียวกัน (ไม่มี blend shape ได้: hi/mid ใช้กระดูกช่วยอย่างเดียว) · S จาก motion_scale ของ rig แต่ละร่าง · ท่า: clips.res ของทหารถ้ามี
## ไม่งั้นสำเนาท่าใน humanoid.res ที่แต่งข้อมือแล้ว (ผิวต่อเนื่องบิดเกือบรอบไม่ได้) · โครง 23 กระดูกของเกม + กระดูกช่วย
## ตัวขับกระดูกช่วย/ท่าแก้ทำงานใน mixer_applied (ไม่มี _process): hi/mid = กระดูกช่วย + ท่าแก้ · lo = กระดูกช่วย ·
## min = ไม่มีงานเพิ่ม ยืนนิ่งท่าเดียว · ดาดฟ้ายืนนิ่งทั้ง lo และ min · เมช วัสดุ เก็บ static ต่อโฟลเดอร์ร่าง ท่าใช้ร่วม · ภาพล้วน
## บาดแผล (add_wound, โดน/ตายลงแผลสุ่มแบบมี seed ≤ 8 แผล ติดกระดูก ด้านที่ถูกตีถ้ารู้ set_hit_from): hi/mid = ผิวขาด
## เห็นเนื้อและกระดูก (inner_*.res ซ่อนจนแผลแรก) · lo = สีแผลบนผิว · min = ไม่มีเลย (วัสดุร่วมไม่มีโค้ดแผล) ·
## แผลตัดเฉพาะส่วนร่างกายเดียวกับกระดูกแผล · อัปเดตตามท่าเฉพาะตอนมีแผล ล้างตอน setup / ลุกขึ้นใหม่

signal clip_event(kind: StringName)

const DIR := "res://assets/figures/soldier/"
const RIG := DIR + "rig.tscn"
const SKIN := DIR + "skin.res"
const MATERIAL := DIR + "body_material.tres"
const OWN_CLIPS := DIR + "clips.res"
const LIB_PATH := "res://assets/anim/humanoid.res"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
## งบสามเหลี่ยมของผิวต่อระดับ (1 พื้นผิว 1 draw) · crowd = ระดับฝูง (ถ้าขั้นปั้นทำมา ยังไม่มีที่ใช้)
const BUDGET := {"hi": 24000, "mid": 16000, "lo": 9000, "min": 5000, "crowd": 1500}
## โครง 23 กระดูกของเกม (assets/kits/CONTRACT.md §1) ที่ท่าใน humanoid.res ขับ
const GAME_BONES: PackedStringArray = ["pelvis", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL",
	"shoulderR", "elbowR", "wristR", "handR", "hipL", "kneeL", "ankleL", "toeL", "heelL", "hipR", "kneeR", "ankleR", "toeR", "heelR"]
const PLAYER_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "fire": ["fire"],
	"punch": ["bash_0", "bash_1", "bash_2"], "swing": ["thrust_0", "thrust_1", "thrust_2"], "hit": ["flinch"],
	"hit_heavy": ["flinch_heavy"], "die": ["die_back", "die_fwd", "die_spin"]}
const ENEMY_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "attack": ["bash_0", "bash_1", "bash_2"],
	"hit": ["flinch"], "hit_heavy": ["flinch_heavy"], "die": ["die_back", "die_fwd", "die_spin"]}
const LOOPS: Array[StringName] = [&"idle", &"walk", &"run"]
const BONES := {&"head": "head", &"chest": "chest", &"hand_r": "handR", &"hand_l": "handL"}
const BLEND := 0.15
const BLEND_DIE := 0.3
const DECK_RATE := 1.4           # ความเร็วบนดาดฟ้า = ความเร็วของท่า × S × ค่านี้ (แบบ KitWalker)
const RADIUS := 0.35
## ข้อมือ: การรวมมือ+ข้อมือหมุนได้ไม่เกิน (องศา) บิดรอบแกนแขน / พับ
const WRIST_TWIST := 45.0
const WRIST_SWING := 45.0
## ท่าเล็ง (แบบ KitFighter): ท่อนบนจากท่า fire ที่นัดแรก + อกก้มเงยตามกล้อง · ยิง = สะบัด 0.16 วิ
const AIM_BONES: PackedStringArray = ["chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL", "shoulderR",
	"elbowR", "wristR", "handR"]
const AIM_PITCH_K := 0.8
const MELEE_RATE := 1.8
const RECOIL_T := 0.16
const RECOIL_SPAN := 0.08
const MUZZLE_AHEAD := 0.35
const DODGE_LEAN := 0.35
const DODGE_DIP := 0.18
const FLASH_COLOUR := Color(1.0, 1.0, 1.0)
const TINT_COLOUR := Color(0.9, 0.08, 0.06)
## ตัวขับ (ค่าของขั้น 1 ใช้เมื่อ rig.tscn ไม่มี meta "soldier_rig" จาก rig.json ของขั้นปั้น)
const DRIVERS := {"clav_elev_k": 0.12, "clav_elev_max": 15.0, "clav_prot_k": 0.12, "twist_k": 0.5}
const KEYS := {"elbow": 120.0, "knee": 120.0, "hip_flex": 100.0, "hip_ext": 25.0}
const BIND_ELBOW := 8.0
const ARM_KEYS := {"bind": [0.573576436, -0.819152044, 0.0], "down": [0.087155743, -0.996194698, 0.0],
	"front": [0.0, 0.0, 1.0], "up": [0.342020143, 0.939692621, 0.0]}
## ท่าแก้ที่ตัวขับรู้จัก (ชื่อ + L/R)
const SHAPE_KINDS: PackedStringArray = ["shoulder_down", "shoulder_front", "shoulder_up", "elbow_flex", "knee_flex",
	"hip_flex", "hip_ext"]
const SHAPE_ZERO := 0.05         # น้ำหนักต่ำกว่านี้ = 0 (ไม่เสียรอบวาดท่าแก้)
const DOWN := Vector3(0.0, -1.0, 0.0)
## บาดแผล: ชั้นในจาก tools/soldier (inner_layers.py) · ผิวตอนมีแผล (วัสดุของตัวเอง) · แผลสูงสุด (เกินแล้วทับแผลเก่าสุด)
const INNER := {"flesh": "inner_flesh.res", "bone": "inner_bone.res"}
const WOUND_SHADER := DIR + "body_wound.gdshader"
const WOUND_FILE := "body_wound.gdshader"
const MAX_WOUNDS := 8
## ส่วนร่างกาย (CUSTOM0.w ของผิว / CUSTOM0.x ของชั้นใน จาก parts.py ของ tools/soldier): แผลมีผลเฉพาะส่วนของกระดูกแผล
const PARTS: PackedStringArray = ["torso", "head", "armL", "armR", "legL", "legR"]
## ที่ลงแผลสุ่ม: กระดูก → น้ำหนักการสุ่ม (ลำตัวมากกว่าแขนขา ไม่ลงหัว มือ เท้า) · clavicle = อกบน/ไหล่ (กระดูกช่วย)
const WOUND_BONES := {&"chest": 2.2, &"clavicleL": 0.4, &"clavicleR": 0.4, &"spine": 3.0, &"pelvis": 1.0, &"shoulderL": 1.2,
	&"shoulderR": 1.2, &"elbowL": 0.8, &"elbowR": 0.8, &"hipL": 1.4, &"hipR": 1.4, &"kneeL": 0.9, &"kneeR": 0.9}
const TRUNK_BONES: Array[StringName] = [&"chest", &"clavicleL", &"clavicleR", &"spine", &"pelvis"]
## รัศมีแผล (ม. ต่ำ-สูง): โดน / ตายที่ลำตัว / ตายที่แขนขา
const WOUND_HIT := Vector2(0.032, 0.045)
const WOUND_DIE := Vector2(0.06, 0.085)
const WOUND_DIE_LIMB := Vector2(0.045, 0.06)
const WOUND_DEPTH := 0.3         # ศูนย์กลางแผลอยู่ใต้ผิว (เท่าของรัศมี)
const WOUND_SPOT_W := 0.8        # จุดลงแผล: จุดผิวที่กระดูกนั้นถือน้ำหนักอย่างน้อยเท่านี้ (ไม่ลงตรงข้อพับ)
## จุดลงแผลมาจากผิว lo (น้ำหนักชุดเดียวกับ hi/mid: รอยต่อส่วนร่างกายตรงกับที่เชดเดอร์ตัด) ทุกระดับใช้ชุดเดียวกัน
const SPOT_MESH := "body_lo.res"
## แขนขา: รัศมี ≤ ค่านี้ × ระยะจุดผิวถึงแกนกระดูก (ท่าผูก) ปลายแขน/หน้าแข้งไม่ทะลุเป็นหน้าต่าง
const WOUND_AXIS := {&"shoulderL": &"elbowL", &"elbowL": &"wristL", &"shoulderR": &"elbowR", &"elbowR": &"wristR",
	&"hipL": &"kneeL", &"kneeL": &"ankleL", &"hipR": &"kneeR", &"kneeR": &"ankleR"}
const WOUND_AXIS_K := 0.55
## รัศมี ≤ (ระยะถึงรอยต่อกับส่วนอื่นบนผิวเดียวกัน − WOUND_SEAM_PAD) / ค่านี้: ขอบแผลไม่จบเป็นเส้นตรงตรงรอยต่อ
const WOUND_SEAM_K := 1.35
const WOUND_SEAM_PAD := 0.01
const WOUND_ROOM := 0.6          # จุดที่รัศมีลงได้ < ค่านี้ × รัศมีต่ำสุดของช่วง ไม่ใช้
const WOUND_FACING := 0.25       # set_hit_from: ลงแผลเฉพาะจุดที่นอร์มอลตามท่า · ทิศหาผู้ตี > ค่านี้ (ไม่มีจุดเลย = ทุกจุด)

static var _bodies: Dictionary = {}       # โฟลเดอร์ร่าง -> {rig, skin, mat, mat_pv, drv, scale, rules, rules_ready}
static var _mesh_cache: Dictionary = {}   # โฟลเดอร์ร่าง + ระดับ -> ผิว
static var _lib: AnimationLibrary
static var _lib_from := ""
static var _baked: Dictionary = {}
static var _inner_cache: Dictionary = {}   # โฟลเดอร์ร่าง + ชั้น -> เมช
static var _spots: Dictionary = {}         # โฟลเดอร์ร่าง -> จุดลงแผล
static var _wound_shs: Dictionary = {}     # โฟลเดอร์ร่าง -> เชดเดอร์ผิวมีแผล (null = ไม่มี)

## ร่าง: "" = ร่างหลัก (assets/figures/soldier/) · อื่น = assets/figures/soldier_<id>/ · Figures ตั้งก่อน setup (หรือ opts "body")
var body_id := ""
var role: StringName = &"player"
var level := "mid"
var weapon: StringName = &"none"
## ตัวขับ (ทำภาพ/เทส): ปิดกระดูกช่วยหรือท่าแก้ได้
var helpers_on := true
var correctives_on := true
var _built := false
var _model: Node3D
var _sk: Skeleton3D
var _mi: MeshInstance3D
var _ap: AnimationPlayer
var _clips: Dictionary = PLAYER_CLIPS
var _loop: StringName = &"idle"
var _loop_rate := 1.0
var _oneshot: StringName = &""
var _variant_next := -1
var _dead := false
var _still := false
var _still_wait := -1.0
var _still_due := false
var _manual := false
var _dt := 0.0
var _ev_prev := 0.0
var _cur_anim: Animation
var _rng := RandomNumberGenerator.new()
var _anchors: Dictionary = {}
var _muzzle: Marker3D
var _overlay: StandardMaterial3D
var _flash := 0.0
var _tele := 0.0
var _height := 1.78
var _idx: Dictionary = {}
var _shape_slots: Array = []     # [ดัชนี blend shape, ชนิด, ข้าง 0/1]
var _own_mat: ShaderMaterial     # ไฟของฉากโชว์ (set_light): วัสดุของตัวนี้เอง
var _own_pp := false
var _pitch := 0.0
var _fire_anim: Animation
var _aim_t := 0.26
var _aim_tracks: Dictionary = {}
var _recoil := -1.0
var _back := false
var _rest := Transform3D.IDENTITY
var _tw: Tween
var _last_dodge := Vector2.ZERO
var _own_lit := false            # _own_mat มาจาก set_light (ไม่ใช่เพื่อแผลอย่างเดียว)
var _wounds: Array = []          # [ชื่อกระดูก, ดัชนีกระดูก, ศูนย์กลางในกรอบกระดูก, รัศมี, ส่วนร่างกาย] เก่า → ใหม่
var _wound_next := 0             # ช่องที่ทับเมื่อครบ MAX_WOUNDS (เก่าสุด)
var _wrng := RandomNumberGenerator.new()
var _inner: Array = []           # [เนื้อ, กระดูก] MeshInstance3D (สร้างตอนแผลแรกบน hi/mid)
var _inner_mats: Array = []      # วัสดุชั้นในของตัวนี้เอง (ค่าแผล)
var _wound_updates := 0          # ครั้งที่ส่งตำแหน่งแผลให้เชดเดอร์ (เทส)
var _hit_from := Vector3.ZERO    # ทิศ (โลก) ไปหาผู้ตีของแผลครั้งถัดไป (set_hit_from) · ศูนย์ = ไม่รู้
var _body := DIR                 # โฟลเดอร์ร่างของตัวนี้ (ทุกอย่างของร่างแยกตามโฟลเดอร์)
## ของร่างนี้ (จาก _bodies ตอน _use_body): ทุกตัวที่ใช้ร่างเดียวกันใช้ชุดเดียวกัน
var _rig: PackedScene
var _skin: Skin
var _mat: ShaderMaterial
var _mat_pv: ShaderMaterial
var _drv: Dictionary = {}
var _scale := 1.0
var _rules: Array = []           # [ดัชนี, ชนิด, ต้นทาง, ต้นทาง 2, ข้าง ±1] ของกระดูกช่วยที่ต้องขับ
var _wound_sh: Shader


# ================= สัญญาตัวละคร =================

## opts: {"role" &"player"|&"enemy"|&"deck"|อื่น ๆ = ผู้เล่น, "level", "team_colour" (ไม่ใช้: สีผิวของตัวเอง), "seed"}
## + "manual" (เดินท่าด้วย step() ของฉาก เช่นการ์ดฮีโร่) + "body" (แทน body_id; ร่างเลือกได้ก่อนสร้างครั้งแรกเท่านั้น)
func setup(opts: Dictionary) -> void:
	if bool(opts.get("manual", false)):
		_manual = true
	if opts.has("body"):
		body_id = str(opts["body"])
	if not _built:
		_body = folder(body_id)
		if _body != DIR and not ResourceLoader.exists(_body + "rig.tscn"):
			push_warning("soldier: no body %s, using the base body" % body_id)
			_body = DIR
	role = StringName(str(opts.get("role", "player")))
	_clips = ENEMY_CLIPS if role == &"enemy" else PLAYER_CLIPS
	_rng.seed = int(opts.get("seed", 1))
	_wrng.seed = int(opts.get("seed", 1)) * 7919 + 104729
	level = str(opts.get("level", level))
	if not LEVELS.has(level):
		level = "mid"
	_build()
	_wounds.clear()
	_wound_next = 0
	apply_level(level)
	play(&"idle")


func metrics() -> Dictionary:
	return {"height": _height, "radius": RADIUS, "eye": _height * 0.934, "shoulder": _height * 0.812}


func clip_names() -> Dictionary:
	var out := {}
	for k in _clips:
		out[k] = PackedStringArray(_clips[k])
	return out


## เริ่มท่า: ท่าวนเปลี่ยนท่าวน · ท่าครั้งเดียวเล่นจากต้นแล้วกลับท่าวน (die ค้าง) · ยิง = สะบัดในท่าเล็ง · คืนความยาว (วิ)
func play(logical: StringName, speed: float = 1.0) -> float:
	match logical:
		&"fire":
			if _fire_anim == null:
				return 0.0
			if not _paused():
				_recoil = 0.0
			return RECOIL_T
		&"reload":
			return 0.0
		&"punch", &"swing":
			speed *= MELEE_RATE
	if _ap == null:
		return 0.0
	var names: Array = _clips.get(String(logical), [])
	if names.is_empty():
		return 0.0
	var idx := 0
	if names.size() > 1:
		idx = posmod(_variant_next, names.size()) if _variant_next >= 0 else _rng.randi_range(0, names.size() - 1)
	_variant_next = -1
	var clip := "humanoid/" + str(names[idx])
	if not _ap.has_animation(clip):
		return 0.0
	var anim := _ap.get_animation(clip)
	speed = maxf(speed, 0.01)
	if logical in LOOPS and (_dead or _oneshot == &"die"):
		clear_wounds()           # ลุกขึ้นใหม่ด้วยตัวเดิม (เกิดใหม่): แผลหาย
	_still = false
	_still_wait = -1.0
	_dead = false
	if logical in LOOPS:
		_oneshot = &""
		_loop = logical
		_loop_rate = speed
		_start(clip, speed, false)
	else:
		_oneshot = logical
		_start(clip, speed, true)
	match logical:
		&"hit", &"hit_heavy":
			_random_wound(WOUND_HIT * (1.25 if logical == &"hit_heavy" else 1.0), WOUND_HIT)
			_hit_from = Vector3.ZERO
		&"die":
			for i in 2 + (1 if _wrng.randf() < 0.5 else 0):      # สุ่มทุกระดับ (min ด้วย): ลำดับสุ่มไม่ขึ้นกับระดับ
				_random_wound(WOUND_DIE, WOUND_DIE_LIMB)
			_hit_from = Vector3.ZERO
	return anim.length / speed


## ความเร็ว (ม./วิ ตามทิศหน้า): idle / walk / run และอัตราเล่น = ความเร็ว / (ความเร็วของท่า × S) เท้าจึงไม่ไถล
## set_move ตรง ๆ = เดินหน้าเสมอ (PACK_SPEC H6: ทิศกลับเป็น (0, 1))
func set_move(speed: float, running: bool) -> void:
	_back = false
	_move(speed, running)


func _move(speed: float, running: bool) -> void:
	if _ap == null or _dead:
		return
	var logical: StringName = &"idle" if speed < 0.05 else (&"run" if running else &"walk")
	var rate := 1.0
	if logical != &"idle":
		var clip := "humanoid/" + str(_clips[String(logical)][0])
		if _ap.has_animation(clip):
			rate = speed / maxf(float(_ap.get_animation(clip).get_meta("speed", 1.0)) * _scale, 0.01)
	_loop_rate = rate
	if _oneshot != &"":
		_loop = logical
		return
	if logical != _loop or (not _ap.is_playing() and not _still):
		_loop = logical
		_start("humanoid/" + str(_clips[String(logical)][0]), rate, false)
	elif not _still:
		_ap.speed_scale = rate
	if _back and _ap.is_playing() and logical != &"idle":
		_ap.speed_scale = -absf(_ap.speed_scale)
		_loop_rate = -absf(_loop_rate)


func set_aim(pitch: float) -> void:
	_pitch = pitch
	_refresh_still()


func set_weapon(id: StringName) -> void:
	weapon = id
	_refresh_still()


func set_flash(a: float) -> void:
	_flash = clampf(a, 0.0, 1.0)
	_update_overlay()


## สีแดงตอนง้าง (hi/mid/lo; min ไม่มี)
func set_telegraph(a: float) -> void:
	_tele = clampf(a, 0.0, 1.0)
	_update_overlay()


## จุดปากกระบอก: มือที่อยู่หน้าสุด + MUZZLE_AHEAD ไปทางหน้าตัว (วางตอนถาม ไม่มีงานต่อเฟรม) · ศัตรูไม่มี
func muzzle() -> Node3D:
	if role == &"enemy" or _sk == null:
		return null
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		add_child(_muzzle)
	var hr := anchor(&"hand_r")
	var hl := anchor(&"hand_l")
	if hr == null or not hr.is_inside_tree():
		_muzzle.position = Vector3(0.0, _height * 0.72, 0.5)
		return _muzzle
	var fwd := global_basis.z.normalized()
	var h := hr
	if hl != null and hl.is_inside_tree() and (hl.global_position - hr.global_position).dot(fwd) > 0.0:
		h = hl
	_muzzle.global_position = h.global_position + fwd * MUZZLE_AHEAD
	return _muzzle


func anchor(name: StringName) -> Node3D:
	if _anchors.has(name):
		return _anchors[name]
	if _sk == null or not BONES.has(name) or _sk.find_bone(BONES[name]) < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Anchor_" + String(name)
	ba.bone_name = BONES[name]
	_sk.add_child(ba)
	_anchors[name] = ba
	return ba


func apply_level(l: String) -> void:
	level = l if LEVELS.has(l) else "mid"
	if not _built:
		return
	_set_mesh(level)
	_show_wounds()
	_update_overlay()
	if level == "min":
		_reset_helpers()
	if _ap == null:
		return
	if _still_level():
		if _oneshot == &"" and _loop == &"idle" and not _dead:
			_go_still()
	elif _still:
		_still = false
		_start("humanoid/" + str(_clips["idle"][0]), 1.0, false)


# ================= ตะขอเสริม (ไม่อยู่ใน FIGURE_API) =================

## (เดิน, วิ่ง) ม./วิ บนดาดฟ้าที่ท่าไม่ไถล (HallAvatar ใช้แทน 3 / 6)
func deck_speeds() -> Vector2:
	var lib := clip_library()
	if lib == null or not lib.has_animation(&"walk") or not lib.has_animation(&"run"):
		return Vector2(HallAvatar.WALK, HallAvatar.RUN)
	_use_body()
	return Vector2(float(lib.get_animation(&"walk").get_meta("speed", 1.0)) * _scale * DECK_RATE,
		float(lib.get_animation(&"run").get_meta("speed", 2.0)) * _scale * DECK_RATE)


## H9: ไม่เดินเยื้อง (A/D หมุนตัว) เพราะไม่มีท่าก้าวข้าง
func uses_strafe() -> bool:
	return false


## H6: ขาเดินหน้า (y ≥ −0.5) หรือถอยหลัง (walk เล่นกลับ ไม่วิ่งถอยหลัง)
func set_move_dir(local_dir: Vector2, speed: float, running: bool) -> void:
	_back = local_dir.y < -0.5 and speed >= 0.05
	_move(speed, running and not _back)


## H8: เอนไปทางที่พุ่ง ย่อลงแล้วตั้งตัวกลับใน duration วิ (Tween มีเฉพาะตอนพุ่ง)
func begin_dodge(local_dir: Vector2, duration: float) -> void:
	_last_dodge = local_dir
	if _model == null or not is_inside_tree():
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	var lean := DODGE_LEAN * (-1.0 if local_dir.y < 0.0 else 1.0)
	_tw = create_tween()
	_tw.tween_method(_dodge_pose.bind(lean), 0.0, 1.0, duration * 0.3).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_dodge_pose.bind(lean), 1.0, 0.0, duration * 0.7).set_ease(Tween.EASE_IN_OUT)


## ไฟของฉากโชว์ (HeroLight): วัสดุของตัวนี้เอง ไม่แตะวัสดุที่ใช้ร่วม · per_pixel = คิดแสงต่อพิกเซลทุกระดับ
func set_light(sun_dir: Vector3, sun: Color, ambient: Color, per_pixel := true) -> void:
	_use_body()
	if _own_mat == null:
		_own_mat = _mat.duplicate() as ShaderMaterial
	_own_mat.set_shader_parameter("sun_dir", sun_dir)
	_own_mat.set_shader_parameter("sun_colour", Vector3(sun.r, sun.g, sun.b))
	_own_mat.set_shader_parameter("ambient_colour", Vector3(ambient.r, ambient.g, ambient.b))
	_own_pp = per_pixel
	_own_lit = true
	_sync_inner_light()
	if _built:
		_mi.material_override = _material_for(level)


## เทส/เครื่องมือ: เดินท่าเองด้วย step() แทนทุกเฟรม
func set_manual(on: bool) -> void:
	_manual = on
	if _ap != null:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if on \
			else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


func step(dt: float) -> void:
	if _ap != null and _manual:
		_dt = dt
		_ap.advance(dt)
		if _still_due:
			_still_due = false
			_go_still()


## ท่าถัดไปที่มีหลายแบบใช้แบบนี้ (ไม่อยู่ในสัญญา)
func set_variant(i: int) -> void:
	_variant_next = i


func skeleton() -> Skeleton3D:
	return _sk


func body() -> MeshInstance3D:
	return _mi


func animation_player() -> AnimationPlayer:
	return _ap


func is_still() -> bool:
	return _still


func playing_clip() -> String:
	return String(_ap.current_animation) if _ap != null else ""


func weapon_clip() -> String:
	return "fire" if _fire_anim != null else ""


func aiming() -> bool:
	return _aim_on()


func moving_back() -> bool:
	return _back and _ap != null and _ap.speed_scale < 0.0


func dodging() -> bool:
	return _tw != null and _tw.is_valid() and _tw.is_running()


func last_dodge() -> Vector2:
	return _last_dodge


## ชื่อท่าแก้ของเมชระดับนี้ที่ตัวขับรู้จัก / ไม่รู้จัก (เทสตรวจหลังนำเข้าขั้นปั้นใหม่)
func shape_names() -> PackedStringArray:
	var out := PackedStringArray()
	if _mi != null and _mi.mesh != null:
		for i in _mi.mesh.get_blend_shape_count():
			out.append(String(_mi.mesh.get_blend_shape_name(i)))
	return out


func active_shapes() -> int:
	var n := 0
	if _mi != null and _mi.mesh != null:
		for i in _mi.mesh.get_blend_shape_count():
			if _mi.get_blend_shape_value(i) > 0.0:
				n += 1
	return n


# ================= บาดแผล (ภาพล้วน ไม่เกี่ยวกับกติกา) =================

## แผลที่กระดูก bone (ชื่อกระดูกในโครง) ศูนย์กลาง local_offset ในกรอบกระดูก รัศมี radius ม. · คืน true = ลงแผลแล้ว
## ติดกระดูก (ตามท่าทุกเฟรมตอนมีแผล) · ตัดเฉพาะส่วนร่างกายของ bone · ครบ MAX_WOUNDS แล้วทับแผลเก่าสุด ·
## min ไม่มีแผลเลย (ไม่เก็บ ไม่มีงานต่อเฟรม) · ไม่มีเชดเดอร์แผลในโฟลเดอร์ = ไม่มีแผล
func add_wound(bone: StringName, local_offset: Vector3, radius: float) -> bool:
	if not _built or level == "min" or radius <= 0.0 or wound_shader(_body) == null:
		return false
	var bi := int(_idx.get(String(bone), -1))
	if bi < 0:
		return false
	var w := [bone, bi, local_offset, radius, body_part(String(bone))]
	if _wounds.size() < MAX_WOUNDS:
		_wounds.append(w)
	else:
		_wounds[_wound_next] = w
		_wound_next = (_wound_next + 1) % MAX_WOUNDS
	_show_wounds()
	return true


func clear_wounds() -> void:
	_wounds.clear()
	_wound_next = 0
	_show_wounds()


func wound_count() -> int:
	return _wounds.size()


## แผลทั้งหมด [{bone, offset, radius, part}] (เทส: seed เดิมได้ตำแหน่งเดิม)
func wounds() -> Array:
	var out := []
	for w: Array in _wounds:
		out.append({"bone": w[0], "offset": w[2], "radius": w[3], "part": w[4]})
	return out


## ทิศ (โลก) จากตัวนี้ไปหาผู้ตี สำหรับแผลของ play(&"hit"/&"hit_heavy"/&"die") ครั้งถัดไป: ลงแผลด้านที่หันหาผู้ตี
## (ใช้ครั้งเดียวแล้วลืม · ไม่เรียก = สุ่มทุกด้าน) · นอกสัญญาตัวละคร (ตัวอื่นไม่มี: ผู้เรียกเช็ก has_method)
func set_hit_from(world_dir: Vector3) -> void:
	_hit_from = world_dir.normalized() if world_dir.length() > 0.0001 else Vector3.ZERO


## ศูนย์กลางแผล i ในพิกัดโลกตามท่าปัจจุบัน
func wound_point(i: int) -> Vector3:
	if i < 0 or i >= _wounds.size() or _sk == null:
		return Vector3.ZERO
	var w: Array = _wounds[i]
	return _sk.global_transform * (_sk.get_bone_global_pose(int(w[1])) * (w[2] as Vector3))


## ชั้นในที่สร้างแล้ว [เนื้อ, กระดูก] (ว่าง = ยังไม่เคยมีแผลบน hi/mid)
func inner_layers() -> Array:
	return _inner.duplicate()


func wound_updates() -> int:
	return _wound_updates


## จุดผิวที่ลงแผลได้ของกระดูก bone ที่หันไปทาง dir (กรอบโครงตอนผูก) มากสุด เฉพาะจุดที่รัศมีลงได้ ≥ min_room (เทส/ภาพ)
## [ศูนย์กลางในกรอบกระดูก, นอร์มอลในกรอบกระดูก, รัศมีที่ลงได้สูงสุด] · body = โฟลเดอร์ร่าง
static func wound_spot(bone: StringName, dir: Vector3, min_room := 0.0, body := DIR) -> Array:
	var list: Array = wound_spots(body).get(bone, [])
	var skin := _skin_of(body)
	var best := []
	var score := -INF
	var bp := skin.get_bind_pose(_bind_index(bone, skin)) if skin != null else Transform3D.IDENTITY
	for s: Array in list:
		if float(s[2]) < min_room:
			continue
		var d := (bp.basis.inverse() * (s[1] as Vector3)).dot(dir.normalized())
		if d > score:
			score = d
			best = s
	return best


## ส่วนร่างกายของกระดูก (ตามชื่อ เหมือน parts.py ของ tools/soldier): 0 ลำตัว 1 หัว 2/3 แขนซ้าย/ขวา 4/5 ขาซ้าย/ขวา
static func body_part(bone: String) -> int:
	if bone.begins_with("neck") or bone.begins_with("head"):
		return 1
	var side := 0 if bone.ends_with("L") else 1
	for a in ["shoulder", "uparm", "elbow", "wrist", "hand"]:
		if bone.begins_with(a):
			return 2 + side
	for a in ["hip", "knee", "ankle", "toe", "heel"]:
		if bone.begins_with(a):
			return 4 + side
	return 0


## เชดเดอร์ผิวตอนมีแผลของร่างในโฟลเดอร์ body (โหลดตอนแผลแรก) · null = โฟลเดอร์ไม่มี (ไม่มีแผล)
static func wound_shader(body := DIR) -> Shader:
	if not _wound_shs.has(body):
		var p := body + WOUND_FILE
		_wound_shs[body] = load(p) as Shader if ResourceLoader.exists(p) else null
	return _wound_shs[body]


## โฟลเดอร์ไฟล์ของร่าง id ("" = ร่างหลัก DIR)
static func folder(id: String) -> String:
	return DIR if id == "" else "res://assets/figures/soldier_%s/" % id


# ================= ข้อมูลร่วม (static) =================

## ผิวของระดับ l (hi/mid/lo/min หรือ crowd) ของร่างในโฟลเดอร์ body · null = ไม่มีไฟล์
static func body_mesh(l: String, body := DIR) -> ArrayMesh:
	var key := body + l
	if not _mesh_cache.has(key):
		var p := body + "body_%s.res" % l
		_mesh_cache[key] = load(p) as ArrayMesh if ResourceLoader.exists(p) else null
	return _mesh_cache[key]


## ชั้นในของแผล "flesh" / "bone" ของร่างในโฟลเดอร์ body (โหลดตอนแผลแรกบน hi/mid) · null = ไม่มีไฟล์
static func inner_mesh(l: String, body := DIR) -> ArrayMesh:
	var key := body + l
	if not _inner_cache.has(key):
		var p: String = body + str(INNER[l]) if INNER.has(l) else ""
		_inner_cache[key] = load(p) as ArrayMesh if p != "" and ResourceLoader.exists(p) else null
	return _inner_cache[key]


## จุดลงแผลต่อกระดูกใน WOUND_BONES ของร่างในโฟลเดอร์ body (คิดครั้งเดียวต่อร่าง ตามลำดับจุดยอด กำหนดแน่นอน):
## จุดยอดของ SPOT_MESH ที่กระดูกนั้นถือน้ำหนัก ≥ WOUND_SPOT_W · {กระดูก: [[จุดในกรอบกระดูก, นอร์มอลในกรอบกระดูก,
## รัศมีสูงสุด], ...]} · รัศมีสูงสุด = ระยะถึงรอยต่อส่วนร่างกาย (ท่าผูก) และแขนขา: ระยะถึงแกนกระดูก (WOUND_AXIS_K)
static func wound_spots(body := DIR) -> Dictionary:
	if _spots.has(body):
		return _spots[body]
	var out := {}
	_spots[body] = out
	var skin := _skin_of(body)
	var m := load(body + SPOT_MESH) as ArrayMesh if ResourceLoader.exists(body + SPOT_MESH) else null
	if m == null or skin == null:
		return out
	var arr := m.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var tri: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var cus: Variant = arr[Mesh.ARRAY_CUSTOM0]
	var nv := pos.size()
	var per := bones.size() / maxi(nv, 1)
	var top := PackedInt32Array()
	var topw := PackedFloat32Array()
	var part := PackedInt32Array()
	top.resize(nv)
	topw.resize(nv)
	part.resize(nv)
	for v in nv:
		var tb := -1
		var tw := -1.0
		for k in per:
			if wts[v * per + k] > tw:
				tw = wts[v * per + k]
				tb = bones[v * per + k]
		top[v] = tb
		topw[v] = tw
		# ส่วนร่างกาย: ค่าที่อบไว้ใน CUSTOM0.w (ที่เชดเดอร์ใช้) ไม่มีก็คิดจากกระดูกหลัก
		if cus is PackedFloat32Array and (cus as PackedFloat32Array).size() == nv * 4:
			part[v] = int(round((cus as PackedFloat32Array)[v * 4 + 3]))
		else:
			part[v] = body_part(String(skin.get_bind_name(tb))) if tb >= 0 and tb < skin.get_bind_count() else 0
	# รอยต่อ: จุดยอดที่อยู่สามเหลี่ยมเดียวกับจุดของอีกส่วน -> ตาราง (ช่องละ cell ม.) แยกตามส่วน
	var cell := WOUND_DIE.y * WOUND_SEAM_K + WOUND_SEAM_PAD
	var edge := PackedByteArray()
	edge.resize(nv)
	for t in range(0, tri.size(), 3):
		if part[tri[t]] != part[tri[t + 1]] or part[tri[t + 1]] != part[tri[t + 2]]:
			edge[tri[t]] = 1
			edge[tri[t + 1]] = 1
			edge[tri[t + 2]] = 1
	var seam := {}
	for v in nv:
		if edge[v] == 1:
			var key := Vector4i(part[v], floori(pos[v].x / cell), floori(pos[v].y / cell), floori(pos[v].z / cell))
			var at: PackedVector3Array = seam.get(key, PackedVector3Array())
			at.append(pos[v])
			seam[key] = at
	for v in nv:
		var tb := top[v]
		if topw[v] < WOUND_SPOT_W or tb < 0 or tb >= skin.get_bind_count():
			continue
		var name := StringName(skin.get_bind_name(tb))
		if not WOUND_BONES.has(name):
			continue
		var p := pos[v]
		var clear := cell
		var ci := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var key := Vector4i(part[v], ci.x + dx, ci.y + dy, ci.z + dz)
					if seam.has(key):
						for q: Vector3 in seam[key]:
							clear = minf(clear, p.distance_to(q))
		var room := maxf(clear - WOUND_SEAM_PAD, 0.0) / WOUND_SEAM_K
		var bp := skin.get_bind_pose(tb)
		var lp := bp * p
		if WOUND_AXIS.has(name):
			var ch := _bind_index(WOUND_AXIS[name], skin)
			if ch >= 0:
				var tip := bp * skin.get_bind_pose(ch).affine_inverse().origin
				var axis := Geometry3D.get_closest_point_to_segment(lp, Vector3.ZERO, tip).distance_to(lp)
				room = minf(room, axis * WOUND_AXIS_K)
		if not out.has(name):
			out[name] = []
		out[name].append([lp, (bp.basis * nrm[v]).normalized(), room])
	return out


static func _skin_of(body: String) -> Skin:
	return _load_static(body)["skin"]


static func _bind_index(bone: StringName, skin: Skin = null) -> int:
	var sk: Skin = skin if skin != null else _skin_of(DIR)
	if sk != null:
		for i in sk.get_bind_count():
			if sk.get_bind_name(i) == bone:
				return i
	return -1


## ท่าของทหาร (ใช้ร่วมทุกตัว): clips.res ของขั้นปั้นถ้ามี ไม่งั้นสำเนาท่าที่ใช้จาก humanoid.res แต่งข้อมือ (ease_wrists)
## humanoid.res เองไม่ถูกแตะ (ชุดโมเดลอื่นใช้ร่วม) · ไม่มีทั้งสองไฟล์ = null (ยืนท่าพักของโครง)
static func clip_library() -> AnimationLibrary:
	if _lib != null:
		return _lib
	if ResourceLoader.exists(OWN_CLIPS):
		_lib = load(OWN_CLIPS) as AnimationLibrary
		_lib_from = OWN_CLIPS
	elif ResourceLoader.exists(LIB_PATH):
		var src := load(LIB_PATH) as AnimationLibrary
		if src != null:
			var lib := AnimationLibrary.new()
			var used := {}
			for m in [PLAYER_CLIPS, ENEMY_CLIPS]:
				for k in m:
					for n in m[k]:
						used[n] = true
			for n in used:
				if src.has_animation(n):
					var a := (src.get_animation(n) as Animation).duplicate(true) as Animation
					ease_wrists(a)
					lib.add_animation(n, a)
			_lib = lib
			_lib_from = LIB_PATH
	_baked.clear()
	if _lib != null:
		for n in _lib.get_animation_list():
			var a := _lib.get_animation(n)
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_BLEND_SHAPE:
					_baked["@shapes"] = true
				else:
					var p := String(a.track_get_path(t))
					if p.begins_with("Skeleton3D:"):
						_baked[p.substr(11)] = true
	return _lib


static func clip_source() -> String:
	clip_library()
	return _lib_from


## ข้อมือของผิวต่อเนื่อง: ท่าที่ปรับอาวุธของชุดโมเดลแข็งหมุนมือ/ข้อมือเกือบรอบ (ผิวบิดเป็นหนาม)
## รวม wrist·hand ไว้ที่ wrist แล้วจำกัดการบิดรอบแกนแขนและการพับ · hand ไม่หมุน · ตัดแทร็กตำแหน่งมือ/ข้อมือ (ตำแหน่งพัก)
static func ease_wrists(a: Animation) -> void:
	for sd in ["L", "R"]:
		var tw := a.find_track(NodePath("Skeleton3D:wrist" + sd), Animation.TYPE_ROTATION_3D)
		var th := a.find_track(NodePath("Skeleton3D:hand" + sd), Animation.TYPE_ROTATION_3D)
		if tw >= 0:
			for k in a.track_get_key_count(tw):
				var qw: Quaternion = a.track_get_key_value(tw, k)
				var qh := a.rotation_track_interpolate(th, a.track_get_key_time(tw, k)) if th >= 0 else Quaternion.IDENTITY
				a.track_set_key_value(tw, k, limit_turn((qw * qh).normalized(), WRIST_TWIST, WRIST_SWING))
		if th >= 0:
			for k in a.track_get_key_count(th):
				a.track_set_key_value(th, k, Quaternion.IDENTITY)
		for b in ["wrist" + sd, "hand" + sd]:
			var tp := a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_POSITION_3D)
			if tp >= 0:
				a.remove_track(tp)


## แยก q เป็นพับ (swing) × บิดรอบแกน Y ของกระดูก (twist) แล้วจำกัดแต่ละส่วนไม่เกินองศาที่ให้
static func limit_turn(q: Quaternion, twist_max: float, swing_max: float) -> Quaternion:
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
	var sw := q * tw.inverse()
	return (_clamp_turn(sw, swing_max) * _clamp_turn(tw, twist_max)).normalized()


## มุมหมุนของ q (องศา, 0..180)
static func turn_deg(q: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(q.w), 0.0, 1.0)))


## ส่วนบิดรอบแกน Y ของ q (องศา, −180..180)
static func twist_deg(q: Quaternion) -> float:
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	if tw.length_squared() < 1e-12:
		return 0.0
	tw = tw.normalized()
	return wrapf(rad_to_deg(2.0 * atan2(tw.y, tw.w)), -180.0, 180.0)


## กฎของกระดูกช่วยชื่อ name (พ่อ parent): [ชนิด, กระดูกต้นทาง, ต้นทาง 2] · ชนิด "" = ไม่รู้จัก (คงท่าพัก)
## half = ครึ่งมุมของข้อ · upper_twist = หมุนกลับครึ่งหนึ่งของการบิดต้นแขน · fore_twist = รับการบิดข้อมือ+มือส่วนหนึ่ง
## clavicle = ไหล่ยก/ยื่นตามทิศต้นแขน
static func helper_rule(name: String, parent: String) -> Array:
	var side := name.right(1)
	if side != "L" and side != "R":
		return ["", "", ""]
	if name.begins_with("clavicle"):
		return ["clavicle", "shoulder" + side, ""]
	var h := name.find("_half")
	if h > 0:
		return ["half", name.substr(0, h) + side, ""]
	if name.contains("twist"):
		if parent.begins_with("shoulder"):
			return ["upper_twist", parent, ""]
		if parent.begins_with("elbow"):
			return ["fore_twist", "wrist" + side, "hand" + side]
	return ["", "", ""]


## กระดูกช่วยทั้งหมดของโครงของร่างในโฟลเดอร์ body กับกฎ [{bone, parent, kind, src, src2}] (เทสตรวจว่ารู้จักครบ)
static func helper_rules(body := DIR) -> Array:
	var out := []
	var rig: PackedScene = _load_static(body)["rig"]
	if rig == null:
		return out
	var root := rig.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk != null:
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if GAME_BONES.has(n):
				continue
			var par := sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else ""
			var r := helper_rule(n, par)
			out.append({"bone": n, "parent": par, "kind": r[0], "src": r[1], "src2": r[2]})
	root.free()
	return out


## ท่าแก้ชื่อ s ตัวขับรู้จักไหม (ชนิดใน SHAPE_KINDS + L/R)
static func shape_known(s: String) -> bool:
	return SHAPE_KINDS.has(s.left(s.length() - 1)) and (s.ends_with("L") or s.ends_with("R"))


## น้ำหนักท่าแก้จากท่าข้อ (สูตรเดียวกับ tools/soldier/py/correctives.py): rot = ชื่อกระดูก → Quaternion
## คืน {ชื่อท่าแก้: น้ำหนัก 0..1} · ค่าคงที่ตัวขับของร่างในโฟลเดอร์ body
static func shape_weights(rot: Dictionary, body := DIR) -> Dictionary:
	var drv: Dictionary = _load_static(body)["drv"]
	var out := {}
	var keys: Dictionary = drv["arm_keys"]
	for sd in ["L", "R"]:
		var sx := 1.0 if sd == "L" else -1.0
		var d: Vector3 = (rot["shoulder" + sd] as Quaternion) * DOWN
		d.x *= sx
		for k in ["down", "front", "up"]:
			var r := _ang(keys["bind"], keys[k])
			out["shoulder_%s%s" % [k, sd]] = _ease(1.0 - _ang(d, keys[k]) / r)
		var th := _ang((rot["elbow" + sd] as Quaternion) * DOWN, DOWN)
		out["elbow_flex" + sd] = clampf((th - float(drv["bind_elbow"])) / (float(drv["elbow"]) - float(drv["bind_elbow"])), 0.0, 1.0)
		out["knee_flex" + sd] = clampf(_ang((rot["knee" + sd] as Quaternion) * DOWN, DOWN) / float(drv["knee"]), 0.0, 1.0)
		var t: Vector3 = (rot["hip" + sd] as Quaternion) * DOWN
		var phi := rad_to_deg(atan2(t.z, -t.y))
		out["hip_flex" + sd] = clampf(phi / float(drv["hip_flex"]), 0.0, 1.0)
		out["hip_ext" + sd] = clampf(-phi / float(drv["hip_ext"]), 0.0, 1.0)
	return out


static func _ang(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _clamp_turn(q: Quaternion, max_deg: float) -> Quaternion:
	if q.w < 0.0:
		q = -q
	var a := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	if a <= deg_to_rad(max_deg) or a < 1e-6:
		return q
	return Quaternion.IDENTITY.slerp(q, deg_to_rad(max_deg) / a)


## ข้อมูลร่วมของร่างในโฟลเดอร์ body (โหลดครั้งเดียวต่อร่าง): {rig, skin, mat, mat_pv, drv, scale, rules, rules_ready}
## วัสดุ: body_material.tres ของโฟลเดอร์นั้น ไม่มีก็ของร่างหลัก · S = motion_scale ของ rig.tscn ของร่างนั้น
static func _load_static(body := DIR) -> Dictionary:
	if _bodies.has(body):
		return _bodies[body]
	var d := {"rig": null, "skin": null, "mat": null, "mat_pv": null, "drv": {}, "scale": 1.0, "rules": [], "rules_ready": false}
	_bodies[body] = d
	if ResourceLoader.exists(body + "rig.tscn"):
		d["rig"] = load(body + "rig.tscn") as PackedScene
	if ResourceLoader.exists(body + "skin.res"):
		d["skin"] = load(body + "skin.res") as Skin
	var mp := body + "body_material.tres" if ResourceLoader.exists(body + "body_material.tres") else MATERIAL
	var mat := load(mp) as ShaderMaterial if ResourceLoader.exists(mp) else null
	if mat != null:
		d["mat"] = mat
		var pv := mat.duplicate() as ShaderMaterial
		pv.set_shader_parameter("per_vertex", true)
		d["mat_pv"] = pv
	# ค่าคงที่ของตัวขับ: meta ของราก rig.tscn (rig.json ของขั้นปั้น) ทับค่าของขั้น 1
	var drv := DRIVERS.duplicate()
	drv["arm_keys"] = {}
	for k in ARM_KEYS:
		drv["arm_keys"][k] = _vec(ARM_KEYS[k])
	drv.merge(KEYS)
	drv["bind_elbow"] = BIND_ELBOW
	d["drv"] = drv
	if d["rig"] == null:
		return d
	var root := (d["rig"] as PackedScene).instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk != null:
		d["scale"] = sk.motion_scale
	var m: Variant = root.get_meta("soldier_rig", {})
	if m is Dictionary:
		var md: Dictionary = m
		for k in (md.get("drivers", {}) as Dictionary):
			drv[k] = float(md["drivers"][k])
		for k in (md.get("keys", {}) as Dictionary):
			drv[k] = float(md["keys"][k])
		if (md.get("bind_angles", {}) as Dictionary).has("elbow_flexion"):
			drv["bind_elbow"] = float(md["bind_angles"]["elbow_flexion"])
		for k in (md.get("arm_keys", {}) as Dictionary):
			drv["arm_keys"][k] = _vec(md["arm_keys"][k])
	root.free()
	return d


## ชี้ข้อมูลของร่างนี้ (โฟลเดอร์ _body) ลงตัวแปรของตัว (ครั้งแรกที่ใช้)
func _use_body() -> void:
	if not _drv.is_empty():
		return
	var d := _load_static(_body)
	_rig = d["rig"]
	_skin = d["skin"]
	_mat = d["mat"]
	_mat_pv = d["mat_pv"]
	_drv = d["drv"]
	_scale = float(d["scale"])
	_wound_sh = wound_shader(_body)


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else Vector3.ZERO


# ================= ภายใน =================

func _build() -> void:
	if _built:
		return
	_use_body()
	if _rig == null:
		return
	_model = _rig.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	_sk = _model.get_node("Skeleton3D") as Skeleton3D
	for i in _sk.get_bone_count():
		_idx[_sk.get_bone_name(i)] = i
	_mi = MeshInstance3D.new()
	_mi.name = "Body"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sk.add_child(_mi)
	_mi.skeleton = NodePath("..")
	_mi.skin = _skin
	_rest = _model.transform
	_built = true
	var lib := clip_library()
	_ready_rules()
	if lib == null:
		_set_mesh(level)
		return
	_ap = AnimationPlayer.new()
	_ap.name = "AnimationPlayer"
	_model.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.add_animation_library("humanoid", lib)
	if _manual:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.mixer_applied.connect(_on_applied)
	_ap.animation_finished.connect(_on_finished)
	var fire := "humanoid/fire"
	_fire_anim = _ap.get_animation(fire) if _ap.has_animation(fire) else null
	_aim_tracks.clear()
	if _fire_anim != null:
		var ev: Array = _fire_anim.get_meta("events", [])
		_aim_t = maxf(float(ev[0].get("t", 0.28)) - 0.02, 0.0) if not ev.is_empty() else _fire_anim.length * 0.3
		for b in AIM_BONES:
			var bi := _sk.find_bone(b)
			var tr := _fire_anim.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D)
			if bi >= 0 and tr >= 0:
				_aim_tracks[bi] = tr
	_set_mesh(level)


## กฎกระดูกช่วยที่ต้องขับ (ครั้งเดียวต่อร่าง หลังโหลดท่า: กระดูกที่ชุดท่ามีแทร็กเองแล้วไม่ต้องขับ)
func _ready_rules() -> void:
	var d := _load_static(_body)
	if not bool(d["rules_ready"]):
		d["rules_ready"] = true
		var rules := []
		for r in helper_rules(_body):
			var b := int(_idx.get(r["bone"], -1))
			var s := int(_idx.get(r["src"], -1))
			if b >= 0 and s >= 0 and str(r["kind"]) != "" and not _baked.has(r["bone"]):
				rules.append([b, str(r["kind"]), s, int(_idx.get(r["src2"], -1)), 1.0 if str(r["bone"]).ends_with("L") else -1.0])
		d["rules"] = rules
	_rules = d["rules"]


func _set_mesh(l: String) -> void:
	var m := body_mesh(l, _body)
	_mi.mesh = m
	_mi.material_override = _material_for(l)
	_shape_slots.clear()
	if m == null:
		return
	_height = maxf(m.get_aabb().end.y, 1.0)
	for i in m.get_blend_shape_count():
		_mi.set_blend_shape_value(i, 0.0)
		var nm := String(m.get_blend_shape_name(i))
		if shape_known(nm):
			_shape_slots.append([i, nm.left(nm.length() - 1), 0 if nm.ends_with("L") else 1])


func _material_for(l: String) -> ShaderMaterial:
	var pv := l == "lo" or l == "min"
	if _own_mat != null and (_own_lit or l != "min"):
		_own_mat.set_shader_parameter("per_vertex", pv and not _own_pp)
		return _own_mat
	return _mat_pv if pv else _mat


## ระดับที่ยืนนิ่งท่าเดียว: min ทุกบทบาท · ดาดฟ้า lo ด้วย (PACK_SPEC §3.2)
func _still_level() -> bool:
	return level == "min" or (role == &"deck" and level == "lo")


func _paused() -> bool:
	return _still and _ap != null and not _ap.is_playing()


func _aim_on() -> bool:
	return weapon == &"gun" and _fire_anim != null and not _dead and _oneshot == &"" and not _aim_tracks.is_empty()


## ยืนนิ่งอยู่แล้วท่าเล็งเปลี่ยน: วางท่าใหม่ครั้งเดียว (seek ลงกระดูก → _on_applied)
func _refresh_still() -> void:
	if _paused():
		_ap.seek(0.0, true)


func _start(clip: String, speed: float, from_start: bool) -> void:
	_cur_anim = _ap.get_animation(clip)
	_still = false
	if from_start and _ap.current_animation == clip:
		_ap.seek(0.0, true)
	if from_start:
		_ap.play(clip, BLEND_DIE if _oneshot == &"die" else BLEND, speed)
		_ap.speed_scale = 1.0
	else:
		_ap.play(clip, BLEND)
		_ap.speed_scale = speed
	_ev_prev = 0.0
	if _still_level() and clip.ends_with("/" + str(_clips["idle"][0])) and _oneshot == &"":
		_still_wait = BLEND


## หยุดนิ่งที่เฟรมแรกของ idle: AnimationPlayer ไม่เล่น
func _go_still() -> void:
	var clip := "humanoid/" + str(_clips["idle"][0])
	if not _ap.has_animation(clip):
		return
	if _ap.current_animation != clip:
		_ap.play(clip)
	_cur_anim = _ap.get_animation(clip)
	_still = true
	_still_wait = -1.0
	_ap.seek(0.0, true)
	_ap.pause()


func _on_applied() -> void:
	var dt := _dt if _manual else get_process_delta_time()
	_dt = 0.0
	if _aim_on():
		_aim_pose(dt)
	var anim: Animation = _ap.get_animation(_ap.current_animation) if _ap.current_animation != "" else _cur_anim
	if anim != null and _oneshot != &"":
		var pos := _ap.current_animation_position
		for e in anim.get_meta("events", []):
			var t := float(e.get("t", -1.0))
			if t > _ev_prev and t <= pos:
				clip_event.emit(StringName(str(e.get("kind", ""))))
		_ev_prev = pos
	if level != "min":
		_drive()
		if not _wounds.is_empty():
			_update_wounds()
	if _still_wait >= 0.0:
		_still_wait -= dt
		if _still_wait < 0.0 and _still_level() and _oneshot == &"" and _loop == &"idle" and not _dead:
			# หยุดนิ่งนอกการวางท่า (ไม่เรียก seek ซ้อนใน mixer_applied): manual = ท้าย step() · ปกติ = deferred
			if _manual:
				_still_due = true
			else:
				_go_still.call_deferred()


func _on_finished(_anim_name: StringName) -> void:
	if _oneshot == &"":
		return
	if _oneshot == &"die":
		_dead = true
		return
	_oneshot = &""
	_start("humanoid/" + str(_clips[String(_loop)][0]), _loop_rate if _loop != &"idle" else 1.0, false)


## ท่าเล็ง: ท่อนบนจากท่า fire (สะบัดตอนยิง) แล้วอกก้มเงยตามกล้อง
func _aim_pose(dt: float) -> void:
	var t := _aim_t
	if _recoil >= 0.0:
		_recoil += dt
		if _recoil >= RECOIL_T:
			_recoil = -1.0
		else:
			t += RECOIL_SPAN * sin(PI * _recoil / RECOIL_T)
	for bi: int in _aim_tracks:
		_sk.set_bone_pose_rotation(bi, _fire_anim.rotation_track_interpolate(_aim_tracks[bi], t))
	var c := _sk.find_bone("chest")
	if c < 0 or absf(_pitch) < 0.001:
		return
	var par := _sk.get_bone_parent(c)
	var pq := _sk.get_bone_global_pose(par).basis.get_rotation_quaternion() if par >= 0 else Quaternion.IDENTITY
	var r := Quaternion(Vector3.RIGHT, -_pitch * AIM_PITCH_K)
	_sk.set_bone_pose_rotation(c, (pq.inverse() * r * pq * _sk.get_bone_pose_rotation(c)).normalized())


## ตัวขับ: กระดูกช่วย (hi/mid/lo) แล้วท่าแก้ (hi/mid ที่เมชมี blend shape) จากท่าข้อที่วางเสร็จแล้ว
func _drive() -> void:
	if helpers_on:
		for r: Array in _rules:
			var q := _sk.get_bone_pose_rotation(int(r[2]))
			var out := Quaternion.IDENTITY
			match str(r[1]):
				"half":
					out = Quaternion.IDENTITY.slerp(q, 0.5)
				"upper_twist":
					var tw := Quaternion(0.0, q.y, 0.0, q.w)
					tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
					out = Quaternion.IDENTITY.slerp(tw.inverse(), float(_drv["twist_k"]))
				"fore_twist":
					var qc := q * (_sk.get_bone_pose_rotation(int(r[3])) if int(r[3]) >= 0 else Quaternion.IDENTITY)
					var tw := Quaternion(0.0, qc.y, 0.0, qc.w)
					tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
					out = Quaternion.IDENTITY.slerp(tw, float(_drv["twist_k"]))
				"clavicle":
					var sx := float(r[4])
					var d := q * DOWN
					var elev := rad_to_deg(acos(clampf(-d.y, -1.0, 1.0)))
					var a := minf(float(_drv["clav_elev_max"]), float(_drv["clav_elev_k"]) * maxf(0.0, elev - 30.0))
					var b := float(_drv["clav_prot_k"]) * rad_to_deg(asin(clampf(d.z, -1.0, 1.0)))
					out = Quaternion(Vector3.UP, deg_to_rad(-sx * b)) * Quaternion(Vector3.BACK, deg_to_rad(sx * a))
			_sk.set_bone_pose_rotation(int(r[0]), out)
	if not correctives_on or _shape_slots.is_empty() or _baked.has("@shapes") or level == "lo":
		return
	var rot := {}
	for b in ["shoulderL", "shoulderR", "elbowL", "elbowR", "hipL", "hipR", "kneeL", "kneeR"]:
		rot[b] = _sk.get_bone_pose_rotation(int(_idx[b]))
	var w := shape_weights(rot, _body)
	for s: Array in _shape_slots:
		var v := float(w.get(str(s[1]) + ("L" if int(s[2]) == 0 else "R"), 0.0))
		if v < SHAPE_ZERO:
			v = 0.0
		if absf(_mi.get_blend_shape_value(int(s[0])) - v) > 0.002 or (v == 0.0 and _mi.get_blend_shape_value(int(s[0])) != 0.0):
			_mi.set_blend_shape_value(int(s[0]), v)


func _reset_helpers() -> void:
	if _sk == null:
		return
	for r: Array in _rules:
		_sk.set_bone_pose_rotation(int(r[0]), Quaternion.IDENTITY)
	if _mi != null and _mi.mesh != null:
		for i in _mi.mesh.get_blend_shape_count():
			_mi.set_blend_shape_value(i, 0.0)


func _update_overlay() -> void:
	if _mi == null:
		return
	var tint := _tele if level != "min" else 0.0
	if _own_mat != null and _mi.material_override == _own_mat:
		# วัสดุของตัวเอง (มีแผล/ไฟฉากโชว์): แสงวาบ/สีเตือนผ่าน uniform ของผิว ไม่มีชั้นทับ (ไม่ทับรูแผล ไม่เพิ่ม draw)
		_own_mat.set_shader_parameter("flash", _flash)
		_own_mat.set_shader_parameter("telegraph", tint)
		_mi.material_overlay = null
		return
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
			_overlay.albedo_color = Color(TINT_COLOUR, 0.4 * tint)
		mat = _overlay
	_mi.material_overlay = mat


func _dodge_pose(f: float, lean: float) -> void:
	if _model == null:
		return
	_model.transform = Transform3D(Basis(Vector3.RIGHT, lean * f), Vector3(0.0, -DODGE_DIP * f, 0.0)) * _rest


## แผลสุ่มแบบมี seed (_wrng): สุ่ม 3 ค่าต่อแผลทุกระดับ (min ด้วย ลำดับสุ่มจึงไม่ขึ้นกับระดับ) แล้ว min ไม่ลงแผล
## กระดูกตามน้ำหนัก WOUND_BONES × สัดส่วนจุดที่ใช้ได้ แล้วจุดผิวของกระดูกนั้น: เฉพาะจุดที่รัศมีลงได้พอ และ (set_hit_from)
## หันหาผู้ตี (ไม่มีจุดหันหาเลย = ทุกด้าน) · รัศมีไม่เกินที่จุดนั้นลงได้ · ศูนย์กลางลึกใต้ผิว WOUND_DEPTH
## trunk = ช่วงรัศมีที่ลำตัว · limb = ที่แขนขา
func _random_wound(trunk: Vector2, limb: Vector2) -> bool:
	var r_bone := _wrng.randf()
	var r_spot := _wrng.randf()
	var r_rad := _wrng.randf()
	if not _built or level == "min" or wound_shader(_body) == null:
		return false
	var spots := wound_spots(_body)
	var cand := {}
	for facing in [_hit_from != Vector3.ZERO, false]:
		cand = _wound_candidates(spots, trunk, limb, facing)
		if not cand.is_empty() or not facing:
			break
	# น้ำหนักกระดูก × สัดส่วนจุดที่ใช้ได้ (พื้นที่ที่ลงได้/หันหาผู้ตี)
	var wt := {}
	var total := 0.0
	for b: StringName in WOUND_BONES:
		if cand.has(b):
			wt[b] = float(WOUND_BONES[b]) * float((cand[b] as Array).size()) / float((spots[b] as Array).size())
			total += float(wt[b])
	if total <= 0.0:
		return false
	var x := r_bone * total
	var pick: StringName = &""
	for b: StringName in WOUND_BONES:
		if not cand.has(b):
			continue
		pick = b
		x -= float(wt[b])
		if x <= 0.0:
			break
	var list: Array = cand[pick]
	var s: Array = list[mini(int(r_spot * list.size()), list.size() - 1)]
	var rr := trunk if TRUNK_BONES.has(pick) else limb
	var rad := minf(lerpf(rr.x, rr.y, r_rad), float(s[2]))
	return add_wound(pick, (s[0] as Vector3) - (s[1] as Vector3) * rad * WOUND_DEPTH, rad)


## จุดที่ลงแผลได้ต่อกระดูก: รัศมีที่ลงได้ ≥ WOUND_ROOM × ต่ำสุดของช่วง · facing = นอร์มอลตามท่าหันหา _hit_from
func _wound_candidates(spots: Dictionary, trunk: Vector2, limb: Vector2, facing: bool) -> Dictionary:
	var out := {}
	for b: StringName in WOUND_BONES:
		if not spots.has(b):
			continue
		var rr := trunk if TRUNK_BONES.has(b) else limb
		var d := Vector3.ZERO
		if facing:
			var bi := int(_idx.get(String(b), -1))
			if bi < 0:
				continue
			var gb := _sk.global_basis if _sk.is_inside_tree() else _sk.basis
			d = ((gb * _sk.get_bone_global_pose(bi).basis).inverse() * _hit_from).normalized()
		var list := []
		for s: Array in spots[b]:
			if float(s[2]) >= rr.x * WOUND_ROOM and (not facing or (s[1] as Vector3).dot(d) > WOUND_FACING):
				list.append(s)
		if not list.is_empty():
			out[b] = list
	return out


## สภาพแผลตามระดับ: hi/mid = วัสดุของตัวเองบนเชดเดอร์แผล (ทิ้งผิวในแผล) + ชั้นในเห็น · lo = สีแผลบนผิว ไม่มีชั้นใน
## min หรือไม่มีแผล = เชดเดอร์ผิวปกติ (ไม่มีโค้ดแผล) วัสดุร่วม ชั้นในซ่อน (visible = false ไม่มีต้นทุน)
func _show_wounds() -> void:
	if not _built or _mat == null:
		return
	var on := not _wounds.is_empty() and level != "min"
	var cut := on and (level == "hi" or level == "mid")
	if on and _own_mat == null:
		_own_mat = _mat.duplicate() as ShaderMaterial
	elif _wounds.is_empty() and _own_mat != null and not _own_lit:
		_own_mat = null
	if _own_mat != null:
		var sh: Shader = _wound_sh if on else _mat.shader
		if sh != null and _own_mat.shader != sh:
			_own_mat.shader = sh
	if cut and _inner.is_empty():
		_make_inner()
	for mi: MeshInstance3D in _inner:
		mi.visible = cut
	_mi.material_override = _material_for(level)
	_update_wounds()
	_update_overlay()


## ส่งศูนย์กลาง (กรอบโครง) + การหมุนของกระดูก + ส่วนร่างกายของแต่ละแผลให้เชดเดอร์ (ทุกเฟรมเฉพาะตอนมีแผล · min ไม่มี)
## wound_mode 2 (ตัดผิว) เฉพาะ hi/mid ที่มีชั้นใน ไม่งั้น 1 (สีแผล: ไม่เห็นพื้นหลังผ่านรู)
func _update_wounds() -> void:
	var n := _wounds.size() if level != "min" else 0
	var c := PackedVector4Array()
	var q := PackedVector4Array()
	var pt := PackedFloat32Array()
	c.resize(MAX_WOUNDS)
	q.resize(MAX_WOUNDS)
	pt.resize(MAX_WOUNDS)
	for i in n:
		var w: Array = _wounds[i]
		var g := _sk.get_bone_global_pose(int(w[1]))
		var p := g * (w[2] as Vector3)
		var r := g.basis.get_rotation_quaternion()
		c[i] = Vector4(p.x, p.y, p.z, float(w[3]))
		q[i] = Vector4(r.x, r.y, r.z, r.w)
		pt[i] = float(w[4])
	var mats: Array = []
	if _own_mat != null and _own_mat.shader == _wound_sh:
		mats.append(_own_mat)
	if level == "hi" or level == "mid":
		mats.append_array(_inner_mats)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("wound_count", n)
		m.set_shader_parameter("wounds", c)
		m.set_shader_parameter("wound_rot", q)
		m.set_shader_parameter("wound_part", pt)
	if _own_mat != null and _own_mat.shader == _wound_sh:
		_own_mat.set_shader_parameter("wound_mode", 2 if (level == "hi" or level == "mid") and not _inner.is_empty() else 1)
	if n > 0:
		_wound_updates += 1


## ชั้นในของตัวนี้ (ผูกโครงและ Skin เดียวกับผิว) วัสดุของตัวเอง · สร้างครั้งเดียวตอนแผลแรกบน hi/mid
func _make_inner() -> void:
	for l in ["flesh", "bone"]:
		var m := inner_mesh(l, _body)
		var base := m.surface_get_material(0) as ShaderMaterial if m != null else null
		if base == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Inner_" + l
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.mesh = m
		var mat := base.duplicate() as ShaderMaterial
		mi.material_override = mat
		_sk.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = _skin
		_inner.append(mi)
		_inner_mats.append(mat)
	_sync_inner_light()


## ไฟของชั้นใน = ไฟของผิว (ไฟเริ่มของวัสดุร่วม หรือไฟฉากโชว์จาก set_light)
func _sync_inner_light() -> void:
	var src := _own_mat if _own_mat != null else _mat
	if src == null:
		return
	for k in ["sun_dir", "sun_colour", "ambient_colour"]:
		var v: Variant = src.get_shader_parameter(k)
		if v != null:
			for m: ShaderMaterial in _inner_mats:
				m.set_shader_parameter(k, v)
