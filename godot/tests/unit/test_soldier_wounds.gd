extends "res://tests/testing.gd"
## Wounds on the infantry soldier (scenes/arena/soldier_figure.gd): add_wound(bone, local_offset, radius) on a bone,
## at most 8 (the oldest is replaced), seeded random wounds on hit (one small) and die (two or three larger) that repeat
## with the same seed, cleared on setup and when a dead figure gets up again. Levels: hi/mid cut the skin (the figure's
## own material on body_wound.gdshader, wound_mode 2) and show the inner flesh and bone layers, which do not exist or
## stay hidden until the first wound; lo tints the skin only (wound_mode 1, per vertex, no inner layers); min does
## nothing at all (no wound, no material copy, no per-frame update) and its shared material runs body.gdshader, which
## has no wound code and no discard. Every random draw happens on every level, so the level does not change where later
## wounds go. Body parts: every skin and inner vertex carries its part (CUSTOM0.w / CUSTOM0.x: torso, head, arms, legs,
## from the dominant bone) and a wound cuts only its own bone's part. Wound spots come from body_lo and carry the
## largest radius that keeps the cut off the part seams and, on the forearm and shin, within the limb (0.55 x the
## distance to the bone axis). set_hit_from(dir) puts the next hit's wounds on the side that faces the attacker.
## Assets: inner_bone.res is bound rigidly (one weight of 1 per vertex) and inner_flesh.res is skinned, both to binds of
## skin.res, one surface each within their budgets, drawn after the skin (render_priority 1), every vertex at least
## 1 mm (flesh) / 2 mm (bone) under the hi and mid skin; the wound code lives once, in wound.gdshaderinc.
## The other bodies (assets/figures/soldier_<id>/): each has its own inner layers that pass the same asset checks
## against its own skin, and a figure of that body takes wounds from its own spots and shows its own layers; its
## IMPORTED.txt records the posed bone check (inner_posed.py) with the chest front and hips within the base body + 0.5 mm.

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DIR := "res://assets/figures/soldier/"
const DT := 1.0 / 30.0
## triangle budgets of the inner layers (tools/soldier/generator/src/py/inner_layers.py: about 5k and 7k)
const INNER_BUDGET := {"bone": 6000, "flesh": 8000}
## least depth under the hi and mid skin (tools/soldier/generator/src/py/inner_layers.py FLESH_MIN / BONE_MIN_D)
const DEPTH_MM := {"flesh": 1.0, "bone": 2.0}
## ร่างอื่น (Figures.BUILTINS ที่มี body)
const BODIES: PackedStringArray = ["m2", "m3", "f1", "f2"]

var S: GDScript


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _new_fig(level: String, seed_v := 7, role := &"player", body := "") -> Node3D:
	S = load(SCRIPT)
	var f: Node3D = S.new()
	_tree().root.add_child(f)
	f.call("set_manual", true)
	f.call("setup", {"role": role, "level": level, "team_colour": Color.BLUE, "seed": seed_v, "body": body})
	return f


func _steps(f: Node3D, n: int) -> void:
	for i in n:
		f.call("step", DT)


func _skin_mat(f: Node3D) -> ShaderMaterial:
	return (f.call("body") as MeshInstance3D).material_override as ShaderMaterial


func _visible_inner(f: Node3D) -> int:
	var n := 0
	for mi: MeshInstance3D in f.call("inner_layers"):
		if mi.visible:
			n += 1
	return n


func _chest_spot() -> Vector3:
	var s: Array = (load(SCRIPT) as GDScript).call("wound_spot", &"chest", Vector3(0, 0, 1), 0.05)
	return (s[0] as Vector3) - (s[1] as Vector3) * 0.015 if s.size() >= 2 else Vector3(0, 0.1, 0.1)


## the spot a random wound was placed on (its centre is the spot moved WOUND_DEPTH x radius inward)
func _spot_of(w: Dictionary) -> Array:
	var depth: float = S.get("WOUND_DEPTH")
	for s: Array in (S.call("wound_spots") as Dictionary).get(w["bone"], []):
		var c := (s[0] as Vector3) - (s[1] as Vector3) * float(w["radius"]) * depth
		if c.distance_to(w["offset"]) < 0.0001:
			return s
	return []


## the wound's spot normal in the world, in the figure's current pose
func _posed_normal(f: Node3D, w: Dictionary) -> Vector3:
	var s := _spot_of(w)
	var sk: Skeleton3D = f.call("skeleton")
	if s.is_empty():
		return Vector3.ZERO
	return (sk.global_basis * sk.get_bone_global_pose(sk.find_bone(String(w["bone"]))).basis * (s[1] as Vector3)).normalized()


func test_api_and_cap() -> void:
	var f := _new_fig("hi")
	for m in ["add_wound", "clear_wounds", "wound_count", "wounds", "wound_point", "inner_layers", "wound_updates",
			"set_hit_from"]:
		assert_true(f.has_method(m), "SoldierFigure." + m)
	var shared := _skin_mat(f)
	assert_true(shared != null and shared.shader.resource_path == DIR + "body.gdshader", "unwounded: the shared material on body.gdshader")
	assert_eq(int(f.call("wound_count")), 0, "set up: no wounds")
	assert_eq(_visible_inner(f), 0, "set up: no inner layer is visible")
	assert_true((f.call("inner_layers") as Array).is_empty(), "…none is even made before the first wound")
	_steps(f, 4)
	assert_eq(int(f.call("wound_updates")), 0, "no wounds: nothing is updated per frame")
	assert_false(bool(f.call("add_wound", &"tail", Vector3.ZERO, 0.05)), "an unknown bone takes no wound")
	assert_false(bool(f.call("add_wound", &"chest", Vector3.ZERO, 0.0)), "a zero radius takes no wound")
	var spot := _chest_spot()
	assert_true(bool(f.call("add_wound", &"chest", spot, 0.05)), "add_wound on the chest")
	assert_eq(int(f.call("wound_count")), 1, "one wound")
	assert_eq(_visible_inner(f), 2, "hi: the flesh and bone layers show after the first wound")
	var mat := _skin_mat(f)
	assert_true(mat != shared, "the wounded figure gets its own skin material")
	assert_true(mat.shader != null and mat.shader.resource_path == DIR + "body_wound.gdshader", "…on the wound shader")
	assert_true(shared.shader.resource_path == DIR + "body.gdshader", "…while the shared material keeps body.gdshader")
	assert_eq(int(mat.get_shader_parameter("wound_count")), 1, "its wound_count is 1")
	assert_eq(int(mat.get_shader_parameter("wound_mode")), 2, "hi: wound_mode 2 (cut the skin)")
	var c: PackedVector4Array = mat.get_shader_parameter("wounds")
	var p: Vector3 = f.call("wound_point", 0)
	var local := (f.call("skeleton") as Skeleton3D).global_transform.affine_inverse() * p
	assert_true(c.size() == 8 and Vector3(c[0].x, c[0].y, c[0].z).distance_to(local) < 0.001 and is_equal_approx(c[0].w, 0.05),
		"the shader gets the centre (skeleton frame) and radius", str(c[0]))
	var pt: PackedFloat32Array = mat.get_shader_parameter("wound_part")
	assert_true(pt.size() == 8 and int(pt[0]) == 0 and int((f.call("wounds") as Array)[0]["part"]) == 0, "…and the wound's body part (chest: torso, 0)", str(pt))
	for mi: MeshInstance3D in f.call("inner_layers"):
		var im := mi.material_override as ShaderMaterial
		assert_eq(int(im.get_shader_parameter("wound_count")), 1, "%s: the inner layer knows the wound" % mi.name)
		assert_true((im.get_shader_parameter("wound_part") as PackedFloat32Array).size() == 8, "%s: …and its body part" % mi.name)
		assert_true(im.render_priority > 0, "%s: drawn after the skin (render_priority %d > 0)" % [mi.name, im.render_priority])
		assert_true(mi.skin == (f.call("body") as MeshInstance3D).skin and mi.get_parent() == f.call("skeleton"),
			"%s: on the same skeleton and skin as the body" % mi.name)
	var other := _new_fig("hi")
	var wc: Variant = shared.get_shader_parameter("wound_count")
	assert_true(_skin_mat(other) == shared and wc == null, "another soldier keeps the shared, unwounded material")
	other.free()
	var u0 := int(f.call("wound_updates"))
	f.call("play", &"walk", 1.0)
	_steps(f, 5)
	assert_true(int(f.call("wound_updates")) >= u0 + 5, "wounded: the centres follow the pose every frame (%d)" % (int(f.call("wound_updates")) - u0))
	# bone-attached: the wound moves with its bone ; the forearm is an arm part (2 = left)
	var before: Vector3 = f.call("wound_point", 0)
	f.call("add_wound", &"elbowL", Vector3(0, -0.1, 0.02), 0.03)
	assert_eq(int((f.call("wounds") as Array)[1]["part"]), 2, "a wound on the left forearm cuts the left arm only (part 2)")
	var sk: Skeleton3D = f.call("skeleton")
	var e0: Vector3 = f.call("wound_point", 1)
	sk.set_bone_pose_rotation(sk.find_bone("shoulderL"), Quaternion(Vector3.RIGHT, -1.2))
	var e1: Vector3 = f.call("wound_point", 1)
	assert_true(e0.distance_to(e1) > 0.05 and (f.call("wound_point", 0) as Vector3).distance_to(before) < 0.001,
		"a wound on the forearm moves with the arm, the chest wound stays")
	# the cap: at most 8, the oldest is replaced
	f.call("clear_wounds")
	for i in 12:
		f.call("add_wound", &"spine", Vector3(0, 0.01 * i, 0.1), 0.02 + 0.001 * i)
	assert_eq(int(f.call("wound_count")), 8, "at most 8 wounds")
	var ws: Array = f.call("wounds")
	assert_true(is_equal_approx(float(ws[0]["radius"]), 0.028) and is_equal_approx(float(ws[3]["radius"]), 0.031)
		and is_equal_approx(float(ws[4]["radius"]), 0.024), "the 9th to 12th replaced the four oldest", str(ws.map(func(w: Dictionary) -> float: return w["radius"])))
	f.call("clear_wounds")
	assert_eq(int(f.call("wound_count")), 0, "clear_wounds empties the list")
	assert_eq(_visible_inner(f), 0, "…and hides the inner layers")
	assert_true(_skin_mat(f) == shared, "…and the skin returns to the shared material")
	var u1 := int(f.call("wound_updates"))
	_steps(f, 5)
	assert_eq(int(f.call("wound_updates")), u1, "no wounds again: no per-frame updates")
	f.free()


func test_body_parts() -> void:
	S = load(SCRIPT)
	var skin := load(DIR + "skin.res") as Skin
	var names: PackedStringArray = S.get("PARTS")
	assert_eq(names.size(), 6, "six body parts")
	for b in ["pelvis", "spine", "chest", "clavicleL", "neck", "head", "shoulderL", "uparm_twistR", "elbow_halfL", "handR",
			"hipL", "hip_halfR", "knee_halfL", "toeR"]:
		var want := {"pelvis": 0, "spine": 0, "chest": 0, "clavicleL": 0, "neck": 1, "head": 1, "shoulderL": 2,
			"uparm_twistR": 3, "elbow_halfL": 2, "handR": 3, "hipL": 4, "hip_halfR": 5, "knee_halfL": 4, "toeR": 5}
		assert_eq(int(S.call("body_part", b)), int(want[b]), "body part of %s" % b)
	# every vertex of every level and of the inner layers carries the part of its dominant bone (the generator's rule)
	var sets := [["hi", 3], ["mid", 3], ["lo", 3], ["min", 3]]
	for e: Array in sets:
		var m: ArrayMesh = S.call("body_mesh", e[0])
		_check_parts(m, int(e[1]), 4, skin, "body_" + str(e[0]))
	for l in ["flesh", "bone"]:
		_check_parts(S.call("inner_mesh", l), 0, 1, skin, "inner_" + l)


func _check_parts(m: ArrayMesh, comp: int, width: int, skin: Skin, label: String) -> void:
	if m == null:
		assert_true(false, label + " loads")
		return
	var arr := m.surface_get_arrays(0)
	var cus: Variant = arr[Mesh.ARRAY_CUSTOM0]
	var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_true(cus is PackedFloat32Array and (cus as PackedFloat32Array).size() == nv * width,
		"%s: CUSTOM0 holds the body part (%d floats per vertex)" % [label, width])
	if not cus is PackedFloat32Array or (cus as PackedFloat32Array).size() != nv * width:
		return
	var cf: PackedFloat32Array = cus
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / nv
	var bad := 0
	var first := ""
	var seen := {}
	for v in nv:
		var tb := bones[v * per]
		var tw := wts[v * per]
		for k in range(1, per):
			if wts[v * per + k] > tw:
				tw = wts[v * per + k]
				tb = bones[v * per + k]
		var want := int(S.call("body_part", String(skin.get_bind_name(tb))))
		var got := cf[v * width + comp]
		seen[int(got)] = true
		if absf(got - float(want)) > 0.001:
			bad += 1
			if first == "":
				first = "vertex %d: %s -> %d, stored %.2f" % [v, skin.get_bind_name(tb), want, got]
	assert_eq(bad, 0, "%s: every vertex's part is its dominant bone's part %s" % [label, first])
	assert_eq(seen.size(), 6, "%s: all six parts appear" % label)


func test_seeded_hits_and_death() -> void:
	var a := _new_fig("hi", 7)
	var b := _new_fig("hi", 7)
	var c := _new_fig("hi", 8)
	var bones: Dictionary = S.get("WOUND_BONES")
	var trunk: Array = S.get("TRUNK_BONES")
	var hit: Vector2 = S.get("WOUND_HIT")
	var room_k: float = S.get("WOUND_ROOM")
	for f in [a, b, c]:
		for i in 3:
			f.call("play", &"hit", 1.0)
			_steps(f, 2)
	var wa: Array = a.call("wounds")
	assert_eq(wa.size(), 3, "three hits, three wounds")
	assert_eq(str(wa), str(b.call("wounds")), "the same seed places the same wounds")
	assert_true(str(wa) != str(c.call("wounds")), "another seed places them elsewhere")
	for w: Dictionary in wa:
		var s := _spot_of(w)
		assert_true(bones.has(w["bone"]) and not s.is_empty() and float(w["radius"]) <= hit.y + 0.0001
			and float(w["radius"]) >= hit.x * room_k - 0.0001 and float(w["radius"]) <= float(s[2]) + 0.0001,
			"a hit: a small wound on a wound spot of the torso or a limb, within the spot's room (%s, %.3f m)" % [w["bone"], float(w["radius"])])
	var die: Vector2 = S.get("WOUND_DIE")
	var die_limb: Vector2 = S.get("WOUND_DIE_LIMB")
	for f in [a, b]:
		f.call("play", &"die", 1.0)
		_steps(f, 3)
	var da: Array = a.call("wounds")
	assert_true(da.size() >= 5 and da.size() <= 6, "die adds two or three wounds (%d)" % (da.size() - 3))
	assert_eq(str(da), str(b.call("wounds")), "…placed the same way with the same seed")
	for i in range(3, da.size()):
		var w: Dictionary = da[i]
		var rr: Vector2 = die if trunk.has(w["bone"]) else die_limb
		var s := _spot_of(w)
		assert_true(not s.is_empty() and float(w["radius"]) >= rr.x * room_k - 0.0001 and float(w["radius"]) <= rr.y + 0.0001
			and float(w["radius"]) <= float(s[2]) + 0.0001, "a death wound: the death range, within its spot's room (%s, %.3f m)" % [w["bone"], float(w["radius"])])
	# many seeds: death wounds are larger than hit wounds where there is room (torso), never larger than the spot allows
	var big := 0
	for sd in range(20, 40):
		var f := _new_fig("hi", sd)
		f.call("play", &"die", 1.0)
		for w: Dictionary in f.call("wounds"):
			var s := _spot_of(w)
			if s.is_empty() or float(w["radius"]) > float(s[2]) + 0.0001:
				big = -1000
			elif float(w["radius"]) > hit.y:
				big += 1
		f.free()
	assert_true(big >= 20, "over 20 deaths, many wounds larger than any hit and none past its spot's room (%d)" % big)
	# the arena revives the same figure with play(idle): wounds go
	_steps(a, 60)
	a.call("play", &"idle", 1.0)
	assert_eq(int(a.call("wound_count")), 0, "getting up again (respawn with the same figure) clears the wounds")
	assert_eq(_visible_inner(a), 0, "…and hides the inner layers")
	b.call("setup", {"role": &"player", "level": "hi", "seed": 7})
	assert_eq(int(b.call("wound_count")), 0, "setup on a reused figure clears the wounds")
	for f in [a, b, c]:
		f.free()


func test_spot_room() -> void:
	S = load(SCRIPT)
	var spots: Dictionary = S.call("wound_spots")
	var skin := load(DIR + "skin.res") as Skin
	var axis_k: float = S.get("WOUND_AXIS_K")
	var axes: Dictionary = S.get("WOUND_AXIS")
	for b in S.get("WOUND_BONES"):
		assert_true(spots.has(b) and (spots[b] as Array).size() >= 8, "wound spots on %s (%d)" % [b, (spots.get(b, []) as Array).size()])
	# forearm and shin: the room keeps the sphere within the limb (0.55 x the distance to the bone axis, bind pose)
	for b: StringName in [&"elbowL", &"elbowR", &"kneeL", &"kneeR", &"shoulderL", &"hipR"]:
		var bi := -1
		var ci := -1
		for i in skin.get_bind_count():
			if skin.get_bind_name(i) == b:
				bi = i
			if skin.get_bind_name(i) == axes[b]:
				ci = i
		var tip := skin.get_bind_pose(bi) * skin.get_bind_pose(ci).affine_inverse().origin
		var worst := 0.0
		var most := 0.0
		for s: Array in spots[b]:
			var lp: Vector3 = s[0]
			var axis := Geometry3D.get_closest_point_to_segment(lp, Vector3.ZERO, tip).distance_to(lp)
			worst = maxf(worst, float(s[2]) - axis * axis_k)
			most = maxf(most, float(s[2]))
		assert_true(worst <= 0.0001, "%s: no spot's room exceeds 0.55 x its distance to the bone axis (most %.1f cm)" % [b, most * 100.0])
		if b in [&"elbowL", &"elbowR"]:
			assert_true(most <= 0.03, "%s: forearm wounds stay at most 3 cm (%.1f cm), no window through the limb" % [b, most * 100.0])
	# seams: no spot's room lets the cut reach a vertex of another part on the same surface of body_lo
	var lo: ArrayMesh = S.call("body_mesh", "lo")
	var arr := lo.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cus: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var tri: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var seam := PackedVector3Array()
	var seam_part := PackedInt32Array()
	for t in range(0, tri.size(), 3):
		var pa := int(cus[tri[t] * 4 + 3])
		var pb := int(cus[tri[t + 1] * 4 + 3])
		var pc := int(cus[tri[t + 2] * 4 + 3])
		if pa != pb or pb != pc:
			for v in [tri[t], tri[t + 1], tri[t + 2]]:
				seam.append(pos[v])
				seam_part.append(int(cus[v * 4 + 3]))
	var reach: float = 1.0 / 0.79           # the ragged edge reaches at most 1.27 radii (wound_dist noise +-21 %)
	var hits := 0
	var checked := 0
	for b: StringName in spots:
		var bi := -1
		for i in skin.get_bind_count():
			if skin.get_bind_name(i) == b:
				bi = i
		var inv := skin.get_bind_pose(bi).affine_inverse()
		var part := int(S.call("body_part", String(b)))
		for s: Array in spots[b]:
			var p: Vector3 = inv * (s[0] as Vector3)
			var r := float(s[2])
			checked += 1
			for k in seam.size():
				if seam_part[k] != part and p.distance_to(seam[k]) < r * reach:
					hits += 1
					break
	assert_eq(hits, 0, "no wound spot's largest cut reaches a seam vertex of another part (%d spots)" % checked)


func test_hit_from() -> void:
	S = load(SCRIPT)
	var facing: float = S.get("WOUND_FACING")
	for side: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0)]:
		var bad := 0
		var n := 0
		for sd in range(1, 13):
			var f := _new_fig("hi", sd)
			f.rotation.y = 0.7 * sd
			_steps(f, 1)
			var world := f.global_basis * side
			f.call("set_hit_from", world * 3.0)
			f.call("play", &"hit", 1.0)
			f.call("set_hit_from", world)
			f.call("play", &"die", 1.0)
			for w: Dictionary in f.call("wounds"):
				n += 1
				if _posed_normal(f, w).dot(world) <= facing:
					bad += 1
			f.free()
		assert_true(n >= 36 and bad == 0, "hits and deaths from the figure's %s land on spots facing the attacker (%d wounds, %d not facing)" % [side, n, bad])
	# without a direction (and after one hit: it is used once) wounds land on every side
	var away := 0
	for sd in range(1, 13):
		var f := _new_fig("hi", sd)
		_steps(f, 1)
		f.call("set_hit_from", Vector3(0, 0, 1))
		f.call("play", &"hit", 1.0)
		f.call("play", &"die", 1.0)
		var ws: Array = f.call("wounds")
		for i in range(1, ws.size()):
			if _posed_normal(f, ws[i]).dot(Vector3(0, 0, 1)) < 0.0:
				away += 1
		f.free()
	assert_true(away >= 5, "no direction: some death wounds face away from the last attacker (%d)" % away)


func test_draws_do_not_depend_on_level() -> void:
	var a := _new_fig("hi", 11)
	var b := _new_fig("min", 11)
	for f in [a, b]:
		f.call("play", &"hit", 1.0)
		_steps(f, 2)
		f.call("play", &"die", 1.0)
		_steps(f, 2)
		f.call("play", &"idle", 1.0)
	assert_eq(int(b.call("wound_count")), 0, "min: no wounds kept")
	b.call("apply_level", "hi")
	a.call("clear_wounds")
	for f in [a, b]:
		f.call("play", &"hit", 1.0)
		_steps(f, 2)
	assert_eq(str(a.call("wounds")), str(b.call("wounds")), "after the same events on min and on hi, the next wound lands in the same place")
	a.free()
	b.free()


func test_levels() -> void:
	S = load(SCRIPT)
	# lo: a red tint on the skin only
	var lo := _new_fig("lo")
	var shared_pv := _skin_mat(lo)
	assert_true(bool(lo.call("add_wound", &"chest", _chest_spot(), 0.05)), "lo: the wound is kept")
	var m := _skin_mat(lo)
	assert_true(m != shared_pv and bool(m.get_shader_parameter("per_vertex")), "lo: its own per-vertex skin material")
	assert_true(m.shader.resource_path == DIR + "body_wound.gdshader", "lo: on the wound shader")
	assert_eq(int(m.get_shader_parameter("wound_mode")), 1, "lo: wound_mode 1 (tint, no cut)")
	assert_eq(int(m.get_shader_parameter("wound_count")), 1, "lo: the tint knows the wound")
	assert_true((lo.call("inner_layers") as Array).is_empty(), "lo: no inner layers")
	lo.free()
	# min: nothing at all, and the shared material has no wound code
	var mn := _new_fig("min")
	var shared_min := _skin_mat(mn)
	assert_false(bool(mn.call("add_wound", &"chest", _chest_spot(), 0.05)), "min: add_wound does nothing")
	mn.call("play", &"hit", 1.0)
	_steps(mn, 3)
	mn.call("play", &"die", 1.0)
	_steps(mn, 10)
	assert_eq(int(mn.call("wound_count")), 0, "min: hit and die leave no wound")
	assert_true(_skin_mat(mn) == shared_min, "min: the shared material, no copy")
	_assert_plain_shader(shared_min.shader, "min: the shared material's shader")
	assert_true((mn.call("inner_layers") as Array).is_empty(), "min: no inner layers")
	assert_eq(int(mn.call("wound_updates")), 0, "min: no wound work per frame")
	assert_false(mn.is_processing() or mn.is_physics_processing(), "min: no _process on the figure")
	mn.free()
	# switching levels keeps the wounds but shows them per level
	var f := _new_fig("hi")
	var shared := _skin_mat(f)
	f.call("add_wound", &"chest", _chest_spot(), 0.05)
	f.call("apply_level", "min")
	assert_true(_skin_mat(f) == shared_min, "to min: the shared per-vertex material (no wound shown)")
	_assert_plain_shader(_skin_mat(f).shader, "to min: the material's shader")
	assert_eq(_visible_inner(f), 0, "to min: the inner layers hide")
	var u := int(f.call("wound_updates"))
	f.call("play", &"walk", 1.0)
	_steps(f, 5)
	assert_eq(int(f.call("wound_updates")), u, "on min: no per-frame wound updates")
	f.call("apply_level", "mid")
	assert_eq(_visible_inner(f), 2, "back to mid: the wound shows again with flesh and bone")
	assert_eq(int(_skin_mat(f).get_shader_parameter("wound_mode")), 2, "mid: wound_mode 2")
	f.call("apply_level", "lo")
	assert_eq(_visible_inner(f), 0, "to lo: tint only, the inner layers hide")
	assert_eq(int(_skin_mat(f).get_shader_parameter("wound_mode")), 1, "lo: wound_mode 1")
	f.call("clear_wounds")
	f.call("apply_level", "hi")
	assert_true(_skin_mat(f) == shared, "cleared: back on the shared material")
	f.free()
	for mat: ShaderMaterial in [load(DIR + "body_material.tres")]:
		_assert_plain_shader(mat.shader, "body_material.tres")


func _assert_plain_shader(sh: Shader, label: String) -> void:
	assert_true(sh != null and sh.resource_path == DIR + "body.gdshader", label + " is body.gdshader")
	if sh == null:
		return
	var bare := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/").sub(sh.code, "", true)
	assert_false(bare.contains("discard"), label + ": no discard (early depth and hidden-surface removal stay on)")
	assert_false(bare.contains("wound") or bare.contains("#include"), label + ": no wound uniforms or code")
	var names := (sh.get_shader_uniform_list() as Array).map(func(u: Dictionary) -> String: return u["name"])
	assert_false(names.any(func(n: String) -> bool: return n.begins_with("wound")), label + ": no wound_ uniforms", str(names))


func test_no_inner_layers() -> void:
	S = load(SCRIPT)
	var cache: Dictionary = S.get("_inner_cache")
	var saved := cache.duplicate()
	cache[DIR + "flesh"] = null
	cache[DIR + "bone"] = null
	var f := _new_fig("hi")
	assert_true(bool(f.call("add_wound", &"chest", _chest_spot(), 0.05)), "no inner layers: the wound is still kept")
	assert_true((f.call("inner_layers") as Array).is_empty(), "…no inner layer is made")
	assert_eq(int(_skin_mat(f).get_shader_parameter("wound_mode")), 1, "…and hi tints instead of cutting (no hole onto the background)")
	f.free()
	cache.clear()
	cache.merge(saved)


func test_flash_on_wounded() -> void:
	var f := _new_fig("hi")
	var body: MeshInstance3D = f.call("body")
	f.call("set_flash", 1.0)
	assert_true(body.material_overlay != null, "unwounded: the hit flash is an overlay on the shared material")
	f.call("set_flash", 0.0)
	f.call("add_wound", &"chest", _chest_spot(), 0.05)
	f.call("set_flash", 1.0)
	var m := _skin_mat(f)
	assert_true(body.material_overlay == null and is_equal_approx(float(m.get_shader_parameter("flash")), 1.0),
		"wounded: the flash is the skin's own uniform, no overlay washes over the hole")
	f.call("set_telegraph", 0.5)
	assert_true(body.material_overlay == null and is_equal_approx(float(m.get_shader_parameter("telegraph")), 0.5), "…and so is the telegraph tint")
	f.call("set_flash", 0.0)
	f.call("set_telegraph", 0.0)
	assert_true(is_equal_approx(float(m.get_shader_parameter("flash")), 0.0), "flash off: the uniform goes back to 0")
	f.call("set_flash", 1.0)
	f.call("clear_wounds")
	assert_true(body.material_overlay != null, "cleared while flashing: back to the overlay on the shared material")
	f.call("set_flash", 0.0)
	assert_true(body.material_overlay == null, "flash off: no overlay")
	f.free()


func test_shaders() -> void:
	var strip := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/")
	var src := {}
	for name in ["body.gdshader", "body_wound.gdshader", "inner.gdshader", "wound.gdshaderinc"]:
		var code := FileAccess.get_file_as_string(DIR + name)
		src[name] = strip.sub(code, "", true)
		assert_true((src[name] as String).length() > 100, name + " is there")
		assert_true(RegEx.create_from_string("\\bTIME\\b").search(src[name]) == null, name + ": no TIME (comments aside)")
	for name in ["body.gdshader", "body_wound.gdshader", "inner.gdshader"]:
		assert_true(RegEx.create_from_string("render_mode[^;]*\\bunshaded\\b").search(src[name]) != null, name + ": unshaded (computes its own light)")
	# the plain skin (shared, min): no wound code at all
	_assert_plain_shader(load(DIR + "body.gdshader") as Shader, "body.gdshader")
	# the wound code lives once, in wound.gdshaderinc, which the wound skin and the inner layers include
	var inc: String = src["wound.gdshaderinc"]
	for k in ["uniform int wound_count", "uniform vec4 wounds[8]", "uniform vec4 wound_rot[8]", "uniform float wound_part[8]",
			"float wound_dist(", "float wound_near("]:
		assert_true(inc.contains(k), "wound.gdshaderinc: " + k)
	assert_true(inc.contains("wound_part[i]"), "wound.gdshaderinc: a wound skips vertices of other body parts")
	for name in ["body_wound.gdshader", "inner.gdshader"]:
		var s: String = src[name]
		assert_true(s.contains("#include \"wound.gdshaderinc\""), name + ": includes wound.gdshaderinc")
		assert_false(s.contains("float w_noise(") or s.contains("float wound_dist(") or s.contains("uniform vec4 wounds["),
			name + ": does not define its own copy of the wound code")
		assert_true(RegEx.create_from_string("varying\\s+flat\\s+float\\s+v_part").search(s) != null, name + ": the body part as a flat varying")
	assert_true((src["body_wound.gdshader"] as String).contains("CUSTOM0.w"), "body_wound.gdshader: the part from CUSTOM0.w")
	assert_true((src["inner.gdshader"] as String).contains("CUSTOM0.x"), "inner.gdshader: the part from CUSTOM0.x")
	var body: String = src["body_wound.gdshader"]
	var frag := body.substr(body.find("void fragment()"))
	assert_true(frag.find("if (wound_count > 0)") >= 0 and frag.find("if (wound_count > 0)") < frag.find("discard"),
		"the wound skin discards only behind wound_count > 0")
	assert_eq(body.count("discard"), 1, "…and nowhere else")
	# the wound skin lights exactly like the plain skin: same uniforms and the same skin_light()
	var plain: String = src["body.gdshader"]
	for line in plain.split("\n"):
		if line.strip_edges().begins_with("uniform "):
			assert_true(body.contains(line.strip_edges()), "body_wound.gdshader has the same " + line.strip_edges().get_slice(";", 0))
	var f0 := plain.find("vec3 skin_light(")
	var f1 := body.find("vec3 skin_light(")
	var fn := plain.substr(f0, plain.find("\n}", f0) - f0)
	assert_true(f0 >= 0 and f1 >= 0 and body.substr(f1, fn.length()) == fn, "…and the same skin_light()")
	for name in ["body_wound.gdshader", "inner.gdshader"]:
		var sh := load(DIR + name) as Shader
		var names := (sh.get_shader_uniform_list() as Array).map(func(u: Dictionary) -> String: return u["name"])
		assert_true(names.has("wound_count") and names.has("wound_part"), name + " loads with the included wound uniforms", str(names))


func test_inner_assets() -> void:
	S = load(SCRIPT)
	_inner_assets(DIR, "base")
	for body in BODIES:
		_inner_assets(str(S.call("folder", body)), body)


## ร่างอื่น: IMPORTED.txt บันทึกกระดูกที่โผล่พ้นผิว hi ตามท่าของเกม (inner_posed.py) และอกหน้า/สะโพกไม่เกินร่างหลัก
## (0.917 / 6.432 มม. ชั้นในขั้น 1c) + 0.5 มม. · ในแอปที่ส่งออกไม่มี IMPORTED.txt
func test_posed_bone_record() -> void:
	if OS.has_feature("template"):
		print("skip  IMPORTED.txt is not inside the exported self-test")
		return
	S = load(SCRIPT)
	var re := RegEx.create_from_string("posed bone above the hi skin[^:]*: chest front ([0-9.]+) mm, hips ([0-9.]+) mm, worst ([0-9.]+) mm")
	for body in BODIES:
		var m := re.search(FileAccess.get_file_as_string(str(S.call("folder", body)) + "IMPORTED.txt"))
		assert_true(m != null, "%s: IMPORTED.txt records the posed bone check" % body)
		if m == null:
			continue
		var chest := float(m.get_string(1))
		var hips := float(m.get_string(2))
		assert_true(chest <= 0.917 + 0.5 and hips <= 6.432 + 0.5,
			"%s: posed bone at the chest front %.2f mm and the hips %.2f mm, within the base body + 0.5 mm" % [body, chest, hips])


## the inner layers of the body in folder d: the same rules for every body, against that body's own skin
func _inner_assets(d: String, tag: String) -> void:
	var skin := load(d + "skin.res") as Skin
	assert_true(skin != null, "%s: skin.res loads" % tag)
	if skin == null:
		return
	var game: PackedStringArray = S.get("GAME_BONES")
	var known := {}
	for i in skin.get_bind_count():
		known[String(skin.get_bind_name(i))] = true
	for l in ["bone", "flesh"]:
		var m: ArrayMesh = S.call("inner_mesh", l, d)
		assert_true(m != null, "%s: inner_%s.res loads" % [tag, l])
		if m == null:
			continue
		assert_eq(m.get_surface_count(), 1, "%s %s: one surface (one draw)" % [tag, l])
		var arr := m.surface_get_arrays(0)
		var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_true(tris >= 3000 and tris <= int(INNER_BUDGET[l]), "%s %s: %d triangles within %d" % [tag, l, tris, int(INNER_BUDGET[l])])
		var mat := m.surface_get_material(0) as ShaderMaterial
		assert_true(mat != null and mat.shader != null and mat.shader.resource_path == d + "inner.gdshader", "%s %s: the inner shader" % [tag, l])
		assert_true(mat != null and mat.render_priority == 1, "%s %s: render_priority 1 (drawn after the skin, which hides most of it first)" % [tag, l])
		for dep in ResourceLoader.get_dependencies(d + "inner_%s.res" % l):
			var path := dep.get_slice("::", dep.get_slice_count("::") - 1)
			assert_true(path.begins_with(d), "%s: inner_%s.res depends only on its own folder" % [tag, l], dep)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / nv
		var unknown := {}
		var rigid := true
		var used := {}
		for v in nv:
			var nz := 0
			for k in per:
				var w := wts[v * per + k]
				if w > 0.0001:
					nz += 1
					var bi := bones[v * per + k]
					var bn := String(skin.get_bind_name(bi)) if bi >= 0 and bi < skin.get_bind_count() else "#%d" % bi
					used[bn] = true
					if not known.has(bn):
						unknown[bn] = true
					if l == "bone" and absf(w - 1.0) > 0.001:
						rigid = false
			if l == "bone" and nz != 1:
				rigid = false
		assert_true(unknown.is_empty(), "%s %s: skinned to binds of its skin.res only" % [tag, l], str(unknown.keys()))
		if l == "bone":
			assert_true(rigid, "%s bone: every vertex bound rigidly (one weight of 1)" % tag)
			for b in ["pelvis", "spine", "chest", "head", "shoulderL", "elbowR", "hipL", "kneeR"]:
				assert_true(used.has(b), "%s bone: a part rides %s" % [tag, b])
		else:
			var main := 0
			for b in game:
				if used.has(b):
					main += 1
			assert_true(main >= 20, "%s flesh: weighted over the body (%d game bones)" % [tag, main])
		# the generator's per-vertex check (inner_layers.py) travels with the mesh
		var dm: Dictionary = m.get_meta("depth_mm", {})
		for lv in ["hi", "mid"]:
			assert_true(dm.has(lv) and float(dm[lv]) >= float(DEPTH_MM[l]),
				"%s %s: the generator measured every vertex at least %.0f mm under the %s skin (%s mm)" % [tag, l, float(DEPTH_MM[l]), lv, str(dm.get(lv, "?"))])
	# …and here every vertex again, against the hi and mid skin as the game draws them (bind pose)
	for lv in ["hi", "mid"]:
		var skin_mesh: ArrayMesh = S.call("body_mesh", lv, d)
		var depth := _SkinDepth.new(skin_mesh)
		for l in ["bone", "flesh"]:
			var m: ArrayMesh = S.call("inner_mesh", l, d)
			if m == null:
				continue
			var pos: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var least := INF
			var worst := -1
			for v in pos.size():
				var dd := depth.depth(pos[v])
				if dd < least:
					least = dd
					worst = v
			assert_true(least * 1000.0 >= float(DEPTH_MM[l]) - 0.01, "%s %s: every one of %d vertices at least %.0f mm under the %s skin (least %.2f mm, vertex %d)"
				% [tag, l, pos.size(), float(DEPTH_MM[l]), lv, least * 1000.0, worst])


## a figure of another body: wounds from its own spots, its own inner layers bound to its own skin, the same seeded
## draws, min does nothing
func test_variant_wounds() -> void:
	S = load(SCRIPT)
	for body in BODIES:
		var d: String = S.call("folder", body)
		var spots: Dictionary = S.call("wound_spots", d)
		var base_spots: Dictionary = S.call("wound_spots")
		assert_true(spots.has(&"chest") and spots.has(&"spine") and spots.has(&"hipL"), "%s: wound spots on its own body" % body, str(spots.keys()))
		assert_true(spots != base_spots and (spots[&"chest"] as Array).size() != (base_spots[&"chest"] as Array).size()
			or (spots[&"chest"][0][0] as Vector3) != (base_spots[&"chest"][0][0] as Vector3), "%s: not the base body's spots" % body)
		var f := _new_fig("hi", 7, &"player", body)
		var s: Array = S.call("wound_spot", &"chest", Vector3(0, 0, 1), 0.03, d)
		assert_true(s.size() == 3, "%s: a chest spot with room for 3 cm" % body)
		if s.size() != 3:
			f.free()
			continue
		assert_true(bool(f.call("add_wound", &"chest", (s[0] as Vector3) - (s[1] as Vector3) * 0.01, 0.03)), "%s hi: add_wound takes a chest wound" % body)
		var inner: Array = f.call("inner_layers")
		assert_eq(inner.size(), 2, "%s hi: the inner layers exist after the first wound" % body)
		var skin := load(d + "skin.res") as Skin
		for mi: MeshInstance3D in inner:
			assert_true(mi.visible and (mi.mesh == S.call("inner_mesh", "flesh", d) or mi.mesh == S.call("inner_mesh", "bone", d)),
				"%s: %s is its own body's layer" % [body, mi.name])
			assert_true(mi.skin == skin, "%s: %s is bound to its own skin" % [body, mi.name])
		var mat := (f.call("body") as MeshInstance3D).material_override as ShaderMaterial
		assert_true(mat != null and mat.shader != null and mat.shader.resource_path == d + "body_wound.gdshader", "%s hi: the skin on its wound shader" % body)
		# seeded hits: the same seed repeats, the spots are its own
		f.call("clear_wounds")
		f.call("play", &"hit", 1.0)
		var w1: Array = f.call("wounds")
		f.free()
		var g := _new_fig("hi", 7, &"player", body)
		g.call("play", &"hit", 1.0)
		var w2: Array = g.call("wounds")
		assert_true(w1.size() == 1 and str(w1) == str(w2), "%s: a hit leaves one seeded wound, the same with the same seed" % body, "%s / %s" % [w1, w2])
		if w1.size() == 1:
			var hit: Dictionary = w1[0]
			var found := false
			for sp: Array in spots.get(hit["bone"], []):
				if ((sp[0] as Vector3) - (sp[1] as Vector3) * float(hit["radius"]) * 0.3).distance_to(hit["offset"]) < 0.0001:
					found = true
					break
			assert_true(found, "%s: the hit wound sits on one of its own spots (%s)" % [body, hit["bone"]])
		g.free()
		var mn := _new_fig("min", 7, &"player", body)
		assert_false(bool(mn.call("add_wound", &"chest", Vector3(0, 0.1, 0.1), 0.03)), "%s min: add_wound does nothing" % body)
		mn.free()


## depth of a point under a closed skin mesh (bind pose): distance to the closest triangle, negative outside (the sign
## from the vertex normals interpolated at the closest point, as inner_layers.py does). Exact: the closest vertex bounds
## the distance to the surface, and every triangle whose box meets that ball is tested (a grid of triangle boxes)
class _SkinDepth:
	const CELL := 0.03
	var pos: PackedVector3Array
	var nrm: PackedVector3Array
	var tri: PackedInt32Array
	var vgrid := {}
	var tgrid := {}

	func _init(m: ArrayMesh) -> void:
		var arr := m.surface_get_arrays(0)
		pos = arr[Mesh.ARRAY_VERTEX]
		nrm = arr[Mesh.ARRAY_NORMAL]
		tri = arr[Mesh.ARRAY_INDEX]
		for v in pos.size():
			var k := _key(pos[v])
			var at: PackedInt32Array = vgrid.get(k, PackedInt32Array())
			at.append(v)
			vgrid[k] = at
		for t in tri.size() / 3:
			var a := pos[tri[3 * t]]
			var b := pos[tri[3 * t + 1]]
			var c := pos[tri[3 * t + 2]]
			var lo := _key(Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z))))
			var hi := _key(Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z))))
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var k := Vector3i(x, y, z)
						var at: PackedInt32Array = tgrid.get(k, PackedInt32Array())
						at.append(t)
						tgrid[k] = at

	func _key(p: Vector3) -> Vector3i:
		return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))

	func depth(p: Vector3) -> float:
		var k := _key(p)
		var dn := INF
		var r := 0
		while r <= 64 and float(r - 1) * CELL <= dn:
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					for dz in range(-r, r + 1):
						if maxi(absi(dx), maxi(absi(dy), absi(dz))) == r:
							for v: int in vgrid.get(k + Vector3i(dx, dy, dz), PackedInt32Array()):
								dn = minf(dn, p.distance_to(pos[v]))
			r += 1
		var lo := _key(p - Vector3.ONE * (dn + 0.0001))
		var hi := _key(p + Vector3.ONE * (dn + 0.0001))
		var best := INF
		var sgn := 1.0
		var seen := {}
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					for t: int in tgrid.get(Vector3i(x, y, z), PackedInt32Array()):
						if seen.has(t):
							continue
						seen[t] = true
						var a := pos[tri[3 * t]]
						var b := pos[tri[3 * t + 1]]
						var c := pos[tri[3 * t + 2]]
						var q := _closest(p, a, b, c)
						var d := p.distance_to(q)
						if d < best:
							best = d
							var w := Geometry3D.get_triangle_barycentric_coords(q, a, b, c)
							var n := nrm[tri[3 * t]] * w.x + nrm[tri[3 * t + 1]] * w.y + nrm[tri[3 * t + 2]] * w.z
							sgn = -1.0 if (p - q).dot(n) > 0.0 else 1.0
		return best * sgn

	static func _closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var ab := b - a
		var ac := c - a
		var ap := p - a
		var d1 := ab.dot(ap)
		var d2 := ac.dot(ap)
		if d1 <= 0.0 and d2 <= 0.0:
			return a
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0.0 and d4 <= d3:
			return b
		var vc := d1 * d4 - d3 * d2
		if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
			return a + ab * (d1 / (d1 - d3))
		var cp := p - c
		var d5 := ab.dot(cp)
		var d6 := ac.dot(cp)
		if d6 >= 0.0 and d5 <= d6:
			return c
		var vb := d5 * d2 - d1 * d6
		if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
			return a + ac * (d2 / (d2 - d6))
		var va := d3 * d6 - d5 * d4
		if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
			return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
		var den := 1.0 / (va + vb + vc)
		return a + ab * (vb * den) + ac * (vc * den)
