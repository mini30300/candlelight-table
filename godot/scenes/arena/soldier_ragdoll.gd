class_name SoldierRagdoll
extends PhysicalBoneSimulator3D
## ร่างล้มตามฟิสิกส์ตอนตายของ SoldierFigure (ใหม่ 0.14 ข้อ 3, ARENA_SPEC §9.8) · hi 15 ชิ้น mid 13 ชิ้น · lo/min ไม่สร้าง
## ภาพล้วน: ตำแหน่งของเกมไม่ขยับ · ชิ้นร่างชั้น 32 ชนพื้นของร่างเอง (ชั้น 64) ผนัง (1) ของในห้อง (4) · กระสุน กล้อง ตัวละครไม่ชน
## แคปซูลวัดจากผิว body_lo (ต่อร่าง ครั้งเดียว) · ช่วงข้อสำเนาจาก tools/soldier rig.py LIMITS (นับจากท่า I)
## สร้างค้างไว้ไม่ทำงาน: active ปิด ชิ้นร่าง static ไม่ชน top_level ไม่ตามตัว = ไม่มีงานต่อเฟรม
## start: ข้อต่อใหม่จากท่า I แล้ววางชิ้นร่างตามท่าล้มตอนนั้น ใส่ความเร็วของท่า + แรงผลัก ค่อย ๆ เพิ่ม influence 0 → 1
## นิ่งหรือครบ TIMEOUT = freeze (ส่งท่าโลกของกระดูกให้ตัวละครอบลงโครง แล้วหยุดทั้งหมด) · ตกพร้อมกันไม่เกิน CAP ร่าง

const LAYER := 32
const FLOOR_LAYER := 64
const WORLD_MASK := 1 | 4         # ผนัง/เสา (1) และของในห้อง (4): ร่างไม่ทะลุ · ตัวละคร (2) สัตว์ (8) ไม่ชน
const SETS := {
	"hi": ["pelvis", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "shoulderR", "elbowR", "hipL", "kneeL",
		"ankleL", "hipR", "kneeR", "ankleR"],
	"mid": ["pelvis", "chest", "head", "shoulderL", "elbowL", "shoulderR", "elbowR", "hipL", "kneeL", "ankleL", "hipR",
		"kneeR", "ankleR"]}
const CAP := {"hi": 4, "mid": 2}
const LEAD := 0.1                # วิ: เล่นท่าล้มก่อนส่งให้ฟิสิกส์
const BLEND := 0.15              # วิ: influence 0 → 1
const SETTLE_V := 0.12           # ม./วิ: ช้ากว่านี้ทุกชิ้น = นิ่ง
const SETTLE_W := 1.0            # rad/วิ
const SETTLE_T := 0.3            # วิ: นิ่งต่อเนื่องเท่านี้ = หยุด
const TIMEOUT := 3.0             # วิหลังเริ่ม: หยุดแน่นอน
const MASS := 70.0               # กก. ทั้งร่าง แบ่งตามสัดส่วนของ Winter (ภาพล้วน: ท่าตกขึ้นกับสัดส่วน ไม่ขึ้นกับน้ำหนักรวม)
## สัดส่วนน้ำหนักของกระดูก (รวม 1) · ชิ้นได้ผลรวมของกระดูกที่ผูกกับมัน (มือ → แขนล่าง, mid: สันหลัง → เชิงกราน)
const FRACTION := {"pelvis": 0.142, "spine": 0.139, "chest": 0.216, "neck": 0.02, "head": 0.061, "shoulder": 0.028,
	"elbow": 0.016, "wrist": 0.006, "hip": 0.1, "knee": 0.0465, "ankle": 0.0145}
const LIMIT_CAP := 150.0         # องศา: ช่วงข้อเกินนี้ Jolt ไม่นิ่ง (ไหล่ 180°)
const SPREAD := 12.0             # องศา: สุ่มทิศแรงผลัก ± (seed ของตัวละคร)
const VARY := 0.15               # แรงผลัก × (1 ± ค่านี้)
const SPIN := 1.5                # rad/วิ: สุ่มบิดลำตัวรอบแกนตั้ง ±
const JITTER := 6                # ค่าสุ่ม ±1 ต่อการล้ม (seed ของตัวละคร): [ทิศ, แรง, บิด, ม้วน, ข้าง, เข่างอ]
const ROLL := Vector2(1.5, 2.5)  # rad/วิ: ม้วนลำตัวรอบแกนแรงผลัก ทางไหนตาม seed (ศพไม่นอนสมมาตร)
const KICK := Vector2(0.5, 0.8)  # ม./วิ: เตะออกข้าง (ตั้งฉากแรงผลัก) แขนข้างหนึ่ง + หน้าแข้งข้างตรงข้าม
const FOLD := Vector2(40.0, 70.0)  # องศา: เข่าข้างเดียวกับแขนที่เตะทรุดงอค้างอย่างน้อยเท่านี้ตลอดการล้มครั้งนี้
const DAMP_TRUNK := 2.0          # หน่วงการหมุน: ลำตัว คอ หัว
const DAMP_LIMB := 0.3           # แขนขา: หน่วงน้อย ห้อยตามน้ำหนัก
const BENT := 12.0               # องศา: ศอก/เข่าของร่างล้มงอค้างอย่างน้อยเท่านี้ (เฉพาะร่างล้ม rig.py ไม่เปลี่ยน)
const LIFT := 0.15               # ส่วนของแรงผลักที่ยกขึ้น
const V_MAX := 4.0               # ม./วิ: ความเร็วของท่าที่ส่งต่อสูงสุด
const FLOOR_SIZE := 6.0          # ม.: พื้นของร่าง (ขอบ) ใต้เท้าตัวละคร
const FLOOR_LIFT := 0.02         # ม.: Jolt ยอมให้จมเท่านี้ (penetration slop) จึงยกพื้นของร่างขึ้นเท่ากัน ศพนอนพอดีพื้นจริง
const DIP := 0.01                # ม.: กระแทกเร็วจมพื้นของร่างได้ไม่เกินราวนี้ต่อจังหวะ (Jolt มองการชนล่วงหน้าแค่ 2 ซม.)
## ส่วนของแรงผลักต่อชิ้น: ลำตัวไป ขาค้าง = ล้มตามทิศ
const SHARE := {"pelvis": 0.7, "spine": 0.85, "chest": 1.0, "neck": 1.0, "head": 1.0, "shoulder": 0.8, "elbow": 0.7,
	"hip": 0.45, "knee": 0.25, "ankle": 0.1}
## สำเนา rig.py LIMITS (องศา ข้างซ้าย ในกรอบกระดูกพ่อ ท่า I = 0): x งอ/เหยียด y บิด z กาง/หุบ · ข้างขวากลับเครื่องหมาย y z
const LIMITS := {
	"spine": {"x": [-25, 50], "y": [-15, 15], "z": [-25, 25]},
	"chest": {"x": [-20, 30], "y": [-35, 35], "z": [-20, 20]},
	"neck": {"x": [-50, 40], "y": [-60, 60], "z": [-35, 35]},
	"head": {"x": [-25, 20], "y": [-10, 10], "z": [-8, 8]},
	"shoulder": {"x": [-180, 50], "y": [-90, 70], "z": [-40, 180]},
	"elbow": {"x": [-145, 5], "y": [-80, 80], "z": [-5, 5]},
	"hip": {"x": [-120, 25], "y": [-40, 45], "z": [-30, 45]},
	"knee": {"x": [-5, 140], "y": [-10, 10], "z": [-3, 3]},
	"ankle": {"x": [-25, 50], "y": [-10, 10], "z": [-20, 25]}}
const MERGE := {"chest": "spine", "head": "neck"}   # mid: ชิ้นนี้รวมข้อของกระดูกที่ไม่มีชิ้น
## แกนข้อ (กรอบกระดูก) = [y, z, x]: แกน x ของข้อ (Jolt บิด) ตามแนวกระดูก · คู่ [แกนข้อ, แกน LIMITS]
## (6DOF ของ Jolt อ่านมุมกลับเครื่องหมาย (วัดแล้ว: ศอก/เข่างอผิดทางถ้าไม่กลับ) ช่วงที่ตั้งจึงกลับ)
const JOINT_BASIS := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
const AXES := [["x", "y"], ["y", "z"], ["z", "x"]]
const CHILD := {"neck": "head", "shoulderL": "elbowL", "elbowL": "wristL", "shoulderR": "elbowR", "elbowR": "wristR",
	"hipL": "kneeL", "kneeL": "ankleL", "hipR": "kneeR", "kneeR": "ankleR"}
const ACROSS: PackedStringArray = ["pelvis", "spine", "chest"]   # ลำตัว: แคปซูลตามแนวซ้าย-ขวา

static var _fits: Dictionary = {}     # โฟลเดอร์ร่าง|ระดับ -> [[กระดูก, รัศมี, ยาว, body_offset, มวล], ...]
static var _live: Array[int] = []     # instance id ของร่างที่กำลังตก

var level := "hi"
var _bodies: Array[PhysicalBone3D] = []
var _figure: Node3D                   # SoldierFigure เจ้าของ (รับท่าตอน freeze)
var _drive_mod: SkeletonModifier3D
var _floor: StaticBody3D
var _t := -1.0                        # วิตั้งแต่เริ่มตก (−1 = ไม่ตก)
var _still_t := 0.0
var _peak := 0.0                      # ความเร็วชิ้นร่างสูงสุดของการตกครั้งนี้ (เทส)
var _bad := false                     # เจอค่า NaN/inf (เทส)


## สร้างค้างไว้ (ไม่ทำงาน) ใต้โครง sk ของ fig · body = โฟลเดอร์ร่าง · null = ระดับนี้ไม่มีร่างฟิสิกส์ / ไม่มีผิว
static func make(fig: Node3D, sk: Skeleton3D, skin: Skin, body: String, l: String) -> SoldierRagdoll:
	if sk == null or not sk.is_inside_tree():
		return null
	var fits := fit(sk, skin, body, l)
	if fits.is_empty():
		return null
	var r := SoldierRagdoll.new()
	r.name = "Ragdoll"
	r.level = l
	r._figure = fig
	r.active = false
	r.influence = 0.0
	r.set_physics_process(false)
	for f: Array in fits:
		var pb := PhysicalBone3D.new()
		pb.name = str(f[0])
		pb.bone_name = str(f[0])
		pb.body_offset = f[3]
		pb.joint_offset = (f[3] as Transform3D).affine_inverse() * Transform3D(JOINT_BASIS, Vector3.ZERO)
		pb.mass = float(f[4])
		pb.friction = 0.8
		pb.bounce = 0.0
		pb.linear_damp = 0.05
		pb.angular_damp = DAMP_LIMB if ["shoulder", "elbow", "hip", "knee", "ankle"].has(_base(str(f[0]))) else DAMP_TRUNK
		pb.collision_layer = LAYER
		pb.collision_mask = FLOOR_LAYER | WORLD_MASK
		pb.top_level = true
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(f[1])
		cap.height = float(f[2])
		cs.shape = cap
		pb.add_child(cs)
		r.add_child(pb)
		r._bodies.append(pb)
	sk.add_child(r)
	var d := HelperDrive.new()
	d.name = "RagdollHelpers"
	d.figure = fig
	d.active = false
	sk.add_child(d)
	r._drive_mod = d
	return r


## แคปซูลของแต่ละชิ้นจากผิว body_lo: จุดผิวที่กระดูกนั้น (หรือลูกที่ไม่มีชิ้น) ถือน้ำหนักมากสุด ในกรอบกระดูกตอนผูก
## แกน: ลำตัวซ้าย-ขวา หัวตั้ง ที่เหลือตามกระดูกไปหาลูก · รัศมี = มัธยฐานระยะจากแกน · ยาว = ช่วง 3–97 % ตามแกน
static func fit(sk: Skeleton3D, skin: Skin, body: String, l: String) -> Array:
	var key := body + "|" + l
	if _fits.has(key):
		return _fits[key]
	var mesh := SoldierFigure.body_mesh("lo", body)
	if mesh == null or skin == null or not SETS.has(l):
		return []
	var names: Array = SETS[l]
	var a := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bs.size() / maxi(vs.size(), 1)
	var to := PackedInt32Array()
	var binds: Dictionary = {}
	for i in skin.get_bind_count():
		var bi := skin.get_bind_bone(i)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(i))
		binds[bi] = i
		var k := -1
		while bi >= 0 and k < 0:
			k = names.find(sk.get_bone_name(bi))
			bi = sk.get_bone_parent(bi)
		to.append(k)
	var kg: Array = []
	for n: String in names:
		kg.append(0.0)
	for bi in sk.get_bone_count():
		var f := float(FRACTION.get(_base(sk.get_bone_name(bi)), 0.0))
		var b := bi
		var k := -1
		while b >= 0 and k < 0:
			k = names.find(sk.get_bone_name(b))
			b = sk.get_bone_parent(b)
		if k >= 0:
			kg[k] = float(kg[k]) + f * MASS
	var pts: Array = []
	var inv: Array = []
	for n: String in names:
		pts.append([])
		inv.append(skin.get_bind_pose(int(binds.get(sk.find_bone(n), 0))))
	for v in vs.size():
		var best := 0
		var bw := -1.0
		for j in per:
			if ws[v * per + j] > bw:
				bw = ws[v * per + j]
				best = bs[v * per + j]
		var k := to[best] if best < to.size() else -1
		if k >= 0:
			(pts[k] as Array).append((inv[k] as Transform3D) * vs[v])
	var out := []
	for k in names.size():
		var n: String = names[k]
		var ax := Vector3.RIGHT if ACROSS.has(n) else Vector3.UP
		if n.begins_with("ankle"):
			ax = Vector3.BACK        # เท้า: ตามแนวหน้า-หลัง (ฝ่าเท้าราบ ไม่ทิ่มพื้นตอนยืน)
		elif CHILD.has(n):
			ax = sk.get_bone_rest(sk.find_bone(CHILD[n])).origin.normalized()
		if ax.y < 0.0:
			ax = -ax                 # แคปซูลสมมาตร: ชี้ขึ้นเสมอ (ไม่หมุนรอบ 180°)
		var p: Array = pts[k]
		var c := Vector3.ZERO
		for q: Vector3 in p:
			c += q
		c /= maxf(p.size(), 1.0)
		var ts := PackedFloat32Array()
		var rs := PackedFloat32Array()
		for q: Vector3 in p:
			var dq := q - c
			var t := dq.dot(ax)
			ts.append(t)
			rs.append((dq - ax * t).length())
		var r := 0.05
		var t0 := -0.1
		var t1 := 0.1
		if p.size() >= 8:
			ts.sort()
			rs.sort()
			t0 = ts[int(0.03 * (ts.size() - 1))]
			t1 = ts[int(0.97 * (ts.size() - 1))]
			r = clampf(rs[int(0.5 * (rs.size() - 1))], 0.03, 0.2)
		var h := maxf(t1 - t0, 2.0 * r + 0.01)
		var off := Transform3D(Basis(Quaternion(Vector3.UP, ax)), c + ax * (t0 + t1) * 0.5)
		out.append([n, r, h, off, maxf(float(kg[k]), 0.5)])
	_fits[key] = out
	return out


## ช่วงข้อของชิ้น bone (องศา {x, y, z} ตามแกน LIMITS): ข้างขวากลับ y z · mid รวมข้อที่ไม่มีชิ้น · ไม่เกิน ±LIMIT_CAP
static func limits_for(bone: String, l: String) -> Dictionary:
	var base := _base(bone)
	var out := {}
	if not LIMITS.has(base):
		return out
	for ax: String in ["x", "y", "z"]:
		var rg: Array = (LIMITS[base] as Dictionary)[ax]
		var lo := float(rg[0])
		var hi := float(rg[1])
		if l == "mid" and MERGE.has(base):
			var m: Array = (LIMITS[MERGE[base]] as Dictionary)[ax]
			lo += float(m[0])
			hi += float(m[1])
		if bone.ends_with("R") and ax != "x":
			var t := lo
			lo = -hi
			hi = -t
		if ax == "x" and base == "elbow":
			hi = minf(hi, -BENT)       # ศอกงอเป็นลบ: ปลายเหยียดไม่ถึงตรง
		elif ax == "x" and base == "knee":
			lo = maxf(lo, BENT)        # เข่างอเป็นบวก
		out[ax] = [clampf(lo, -LIMIT_CAP, LIMIT_CAP), clampf(hi, -LIMIT_CAP, LIMIT_CAP)]
	return out


## ร่างที่กำลังตกตอนนี้ (ทุกตัวละคร)
static func live_count() -> int:
	var keep: Array[int] = []
	for id in _live:
		if is_instance_id_valid(id):
			keep.append(id)
	_live = keep
	return _live.size()


static func _base(bone: String) -> String:
	return bone.trim_suffix("L").trim_suffix("R")


## เริ่มตก: vel = ความเร็วโลกของท่าต่อดัชนีกระดูก · push = แรงผลักโลก (ม./วิ ที่อก) · jitter = สุ่ม JITTER ค่า ละ ±1
## (ทิศ แรง บิดรอบแกนตั้ง ม้วนรอบแกนแรงผลัก เตะแขน/ขาข้างไหน เข่างอค้างเท่าไร) · คืน false = ตกพร้อมกันครบ CAP แล้ว (ตัวละครเล่นท่าล้มต่อ)
func start(vel: Dictionary, push: Vector3, jitter: PackedFloat32Array) -> bool:
	if _t >= 0.0 or _bodies.is_empty() or not is_inside_tree():
		return false
	if live_count() >= int(CAP.get(level, 0)):
		return false
	var sk := get_skeleton()
	_rejoint(sk)
	active = true
	influence = 0.0
	physical_bones_start_simulation()
	var jt := jitter.duplicate()
	jt.resize(JITTER)
	var p := push.rotated(Vector3.UP, deg_to_rad(SPREAD * jt[0])) * (1.0 + VARY * jt[1])
	p.y += p.length() * LIFT
	# ข้างเดียว (ไม่สมมาตร): ลำตัวม้วนรอบแกนแรงผลัก + แขนข้างหนึ่งกับหน้าแข้งข้างตรงข้ามเตะออกข้าง
	var flat := Vector3(p.x, 0.0, p.z)
	if flat.length() < 0.01:
		flat = sk.global_transform.basis.z
	flat = Vector3(flat.x, 0.0, flat.z).normalized()
	var roll := flat * (1.0 if jt[3] >= 0.0 else -1.0) * lerpf(ROLL.x, ROLL.y, absf(jt[3]))
	var side := Vector3.UP.cross(flat).normalized()
	if side.dot(sk.global_transform.basis.x) < 0.0:
		side = -side                 # ชี้ไปทางซ้ายของตัว
	var arm_l := jt[4] >= 0.0
	var kick := lerpf(KICK.x, KICK.y, absf(jt[4]))
	var fold := lerpf(FOLD.x, FOLD.y, 0.5 + 0.5 * jt[5])
	for pb in _bodies:
		var bi := pb.get_bone_id()
		pb.global_transform = sk.global_transform * sk.get_bone_global_pose(bi) * pb.body_offset
		var bn := String(pb.bone_name)
		var base := _base(bn)
		var share := float(SHARE.get(base, 0.5))
		var v := (vel.get(bi, Vector3.ZERO) as Vector3).limit_length(V_MAX) + p * share
		var is_l := bn.ends_with("L")
		if ((base == "shoulder" or base == "elbow") and is_l == arm_l) or (base == "knee" and is_l != arm_l):
			v += side * kick * (1.0 if is_l else -1.0)
		elif base == "knee":
			pb.set("joint_constraints/z/angular_limit_upper", -fold)   # แกน z ของข้อ = งอเข่า (กลับเครื่องหมาย)
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
		PhysicsServer3D.body_set_enable_continuous_collision_detection(pb.get_rid(), true)   # กระแทกพื้นเร็วไม่จม
		var w := roll if ACROSS.has(bn) else Vector3.ZERO
		if share >= 0.85:
			w += Vector3.UP * SPIN * jt[2]
		if w != Vector3.ZERO:
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)
	_make_floor()
	_drive_mod.active = true
	_live.append(get_instance_id())
	_t = 0.0
	_still_t = 0.0
	_peak = 0.0
	_bad = false
	set_physics_process(true)
	return true


## หยุดแล้วอบท่า: ท่าโลก (กรอบโครง) ของกระดูกที่มีชิ้น → ตัวละคร _rag_frozen (ท่าหลักหยุดไม่ทับ)
func freeze() -> void:
	if _t < 0.0:
		return
	var sk := get_skeleton()
	var inv := sk.global_transform.affine_inverse()
	var g := {}
	for pb in _bodies:
		var x := inv * pb.global_transform * pb.body_offset.affine_inverse()
		if not x.is_finite():
			g.clear()                # ค่าเสีย: ไม่อบ (คงท่าล้ม)
			_bad = true
			break
		g[pb.get_bone_id()] = x.orthonormalized()
	stop()
	if _figure != null and _figure.has_method("_rag_frozen"):
		_figure.call("_rag_frozen", g)


## หยุดไม่อบท่า (ลุกขึ้นใหม่ / เปลี่ยนระดับ): ชิ้นร่างกลับไปพัก ไม่มีงานต่อเฟรม
func stop() -> void:
	if _t < 0.0:
		return
	_t = -1.0
	set_physics_process(false)
	physical_bones_stop_simulation()
	active = false
	influence = 0.0
	if _drive_mod != null:
		_drive_mod.active = false
	for pb in _bodies:
		pb.top_level = true
	if _floor != null:
		_floor.queue_free()
		_floor = null
	_live.erase(get_instance_id())


## ทิ้งทั้งชุด (ระดับใหม่ไม่มีร่างฟิสิกส์ / ชุดชิ้นต่างกัน)
func discard() -> void:
	stop()
	if _drive_mod != null:
		_drive_mod.queue_free()
		_drive_mod = null
	queue_free()


func is_falling() -> bool:
	return _t >= 0.0


func bodies() -> Array[PhysicalBone3D]:
	return _bodies


func peak_speed() -> float:
	return _peak


func went_bad() -> bool:
	return _bad


## จุดกลางชิ้นร่าง (โลก) ตามท่าโครงตอนนี้ ต่อดัชนีกระดูก (ความเร็วของท่าตอนส่งต่อ)
func centres() -> Dictionary:
	var sk := get_skeleton()
	var out := {}
	for pb in _bodies:
		var bi := pb.get_bone_id()
		out[bi] = sk.global_transform * (sk.get_bone_global_pose(bi) * pb.body_offset.origin)
	return out


func _physics_process(delta: float) -> void:
	if _t < 0.0:
		set_physics_process(false)
		return
	_t += delta
	influence = minf(1.0, _t / BLEND)
	var fast := false
	var top := _floor.global_position.y + 0.2 if _floor != null else -INF
	for pb in _bodies:
		var v: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var w: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if not (v.is_finite() and w.is_finite()):
			_bad = true
			freeze()
			return
		# ตกเร็วใกล้พื้น: ความเร็วลงไม่เกินระยะถึงพื้นของจังหวะนี้ + DIP (ไม่จมลึกแล้วเด้ง)
		if v.y < 0.0 and delta > 0.0:
			var cap := (pb.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
			var low := pb.global_position.y - absf(pb.global_transform.basis.y.normalized().y) * (cap.height * 0.5 - cap.radius) - cap.radius
			var most := (maxf(low - top, 0.0) + DIP) / delta
			if -v.y > most:
				v.y = -most
				PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
		_peak = maxf(_peak, v.length())
		if v.length() > SETTLE_V or w.length() > SETTLE_W:
			fast = true
	_still_t = 0.0 if fast else _still_t + delta
	if (_still_t >= SETTLE_T and _t >= BLEND + SETTLE_T) or _t >= TIMEOUT:
		freeze()


func _ready() -> void:
	set_physics_process(false)       # มี _physics_process: Godot เปิดให้เองตอนพร้อม · เปิดเฉพาะตอนตก


func _exit_tree() -> void:
	if _t >= 0.0:
		_t = -1.0
		set_physics_process(false)
		_live.erase(get_instance_id())


## ข้อต่อใหม่จากท่า I (หมุน 0 ทุกกระดูก: ช่วงข้อนับแบบ LIMITS) ทุกครั้งก่อนตก · เข้า tree ใหม่ข้อถูกสร้างจากท่าที่ค้างอยู่
func _rejoint(sk: Skeleton3D) -> void:
	for pb in _bodies:
		var o := Vector3.ZERO
		var bi := pb.get_bone_id()
		while bi >= 0:
			o += sk.get_bone_rest(bi).origin
			bi = sk.get_bone_parent(bi)
		pb.global_transform = sk.global_transform * Transform3D(Basis(), o) * pb.body_offset
	for pb in _bodies:
		if sk.get_bone_parent(pb.get_bone_id()) < 0:
			continue
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
		var lim := limits_for(String(pb.bone_name), level)
		for pr: Array in AXES:
			var rg: Array = lim[pr[1]]
			pb.set("joint_constraints/%s/angular_limit_enabled" % pr[0], true)
			pb.set("joint_constraints/%s/angular_limit_lower" % pr[0], -float(rg[1]))
			pb.set("joint_constraints/%s/angular_limit_upper" % pr[0], -float(rg[0]))


## พื้นของร่าง (ชั้น 64) ที่ระดับเท้าตัวละคร: ร่างไม่ตกทะลุไม่ว่าฉากจะมีพื้นชนได้หรือไม่
func _make_floor() -> void:
	_floor = StaticBody3D.new()
	_floor.name = "RagdollFloor"
	_floor.collision_layer = FLOOR_LAYER
	_floor.collision_mask = 0
	_floor.top_level = true
	var m := PhysicsMaterial.new()
	m.friction = 0.9
	_floor.physics_material_override = m
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FLOOR_SIZE, 0.4, FLOOR_SIZE)
	cs.shape = box
	_floor.add_child(cs)
	add_child(_floor)
	var g := _figure.global_position if _figure != null else get_skeleton().global_position
	_floor.global_transform = Transform3D(Basis(), g + Vector3(0.0, FLOOR_LIFT - 0.2, 0.0))


## กระดูกช่วย (ไหปลาร้า บิดแขน ครึ่งข้อ) ตามท่าฟิสิกส์: ต่อจากตัวจำลองในชั้นปรับโครง · ทำงานเฉพาะตอนตก
class HelperDrive extends SkeletonModifier3D:
	var figure: Node

	func _process_modification_with_delta(_delta: float) -> void:
		if figure != null:
			figure.call("_drive")
