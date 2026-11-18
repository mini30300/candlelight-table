extends "res://tests/testing.gd"
## Wounds on the infantry soldier (scenes/arena/soldier_figure.gd): add_wound(bone, local_offset, radius) on a bone,
## at most 8 (the oldest is replaced), seeded random wounds on hit (one small) and die (two or three larger) that repeat
## with the same seed, cleared on setup and when a dead figure gets up again. Levels: hi/mid cut the skin (the figure's
## own material, wound_mode 2) and show the inner flesh and bone layers, which do not exist or stay hidden until the first
## wound; lo tints the skin only (wound_mode 1, per vertex, no inner layers); min does nothing at all (no wound, no
## material copy, no per-frame update). Positions follow the pose only while wounds exist. Assets: inner_bone.res is bound
## rigidly (one weight of 1 per vertex) and inner_flesh.res is skinned, both to binds of skin.res; one surface each within
## their budgets; the skin and inner shaders are unshaded, use no TIME, and the skin only discards behind wound_count > 0.

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DIR := "res://assets/figures/soldier/"
const DT := 1.0 / 30.0
## triangle budgets of the inner layers (tools/soldier/generator/src/py/inner_layers.py: about 5k and 7k)
const INNER_BUDGET := {"bone": 6000, "flesh": 8000}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _new_fig(level: String, seed_v := 7, role := &"player") -> Node3D:
	var f: Node3D = (load(SCRIPT) as GDScript).new()
	_tree().root.add_child(f)
	f.call("set_manual", true)
	f.call("setup", {"role": role, "level": level, "team_colour": Color.BLUE, "seed": seed_v})
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
	var s: Array = (load(SCRIPT) as GDScript).call("wound_spot", &"chest", Vector3(0, 0, 1))
	return (s[0] as Vector3) - (s[1] as Vector3) * 0.015 if s.size() == 2 else Vector3(0, 0.1, 0.1)


func test_api_and_cap() -> void:
	var f := _new_fig("hi")
	for m in ["add_wound", "clear_wounds", "wound_count", "wounds", "wound_point", "inner_layers", "wound_updates"]:
		assert_true(f.has_method(m), "SoldierFigure." + m)
	var shared := _skin_mat(f)
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
	assert_eq(int(mat.get_shader_parameter("wound_count")), 1, "its wound_count is 1")
	assert_eq(int(mat.get_shader_parameter("wound_mode")), 2, "hi: wound_mode 2 (cut the skin)")
	var c: PackedVector4Array = mat.get_shader_parameter("wounds")
	var p: Vector3 = f.call("wound_point", 0)
	var local := (f.call("skeleton") as Skeleton3D).global_transform.affine_inverse() * p
	assert_true(c.size() == 8 and Vector3(c[0].x, c[0].y, c[0].z).distance_to(local) < 0.001 and is_equal_approx(c[0].w, 0.05),
		"the shader gets the centre (skeleton frame) and radius", str(c[0]))
	for mi: MeshInstance3D in f.call("inner_layers"):
		var im := mi.material_override as ShaderMaterial
		assert_eq(int(im.get_shader_parameter("wound_count")), 1, "%s: the inner layer knows the wound" % mi.name)
		assert_true(mi.skin == (f.call("body") as MeshInstance3D).skin and mi.get_parent() == f.call("skeleton"),
			"%s: on the same skeleton and skin as the body" % mi.name)
	var other := _new_fig("hi")
	var wc: Variant = shared.get_shader_parameter("wound_count")
	assert_true(_skin_mat(other) == shared and (wc == null or int(wc) == 0), "another soldier keeps the shared, unwounded material")
	other.free()
	var u0 := int(f.call("wound_updates"))
	f.call("play", &"walk", 1.0)
	_steps(f, 5)
	assert_true(int(f.call("wound_updates")) >= u0 + 5, "wounded: the centres follow the pose every frame (%d)" % (int(f.call("wound_updates")) - u0))
	# bone-attached: the wound moves with its bone
	var before: Vector3 = f.call("wound_point", 0)
	f.call("add_wound", &"elbowL", Vector3(0, -0.1, 0.02), 0.03)
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


func test_seeded_hits_and_death() -> void:
	var a := _new_fig("hi", 7)
	var b := _new_fig("hi", 7)
	var c := _new_fig("hi", 8)
	var S: GDScript = load(SCRIPT)
	var bones: Dictionary = S.get("WOUND_BONES")
	var hit: Vector2 = S.get("WOUND_HIT")
	for f in [a, b, c]:
		for i in 3:
			f.call("play", &"hit", 1.0)
			_steps(f, 2)
	var wa: Array = a.call("wounds")
	assert_eq(wa.size(), 3, "three hits, three wounds")
	assert_eq(str(wa), str(b.call("wounds")), "the same seed places the same wounds")
	assert_true(str(wa) != str(c.call("wounds")), "another seed places them elsewhere")
	for w: Dictionary in wa:
		assert_true(bones.has(w["bone"]) and float(w["radius"]) >= hit.x - 0.0001 and float(w["radius"]) <= hit.y + 0.0001,
			"a hit: a small wound on the torso or a limb (%s, %.3f m)" % [w["bone"], float(w["radius"])])
	var die: Vector2 = S.get("WOUND_DIE_LIMB")
	for f in [a, b]:
		f.call("play", &"die", 1.0)
		_steps(f, 3)
	var da: Array = a.call("wounds")
	assert_true(da.size() >= 5 and da.size() <= 6, "die adds two or three wounds (%d)" % (da.size() - 3))
	assert_eq(str(da), str(b.call("wounds")), "…placed the same way with the same seed")
	for i in range(3, da.size()):
		assert_true(float(da[i]["radius"]) >= die.x - 0.0001, "a death wound is larger (%.3f m)" % float(da[i]["radius"]))
	# the arena revives the same figure with play(idle): wounds go
	_steps(a, 60)
	a.call("play", &"idle", 1.0)
	assert_eq(int(a.call("wound_count")), 0, "getting up again (respawn with the same figure) clears the wounds")
	assert_eq(_visible_inner(a), 0, "…and hides the inner layers")
	b.call("setup", {"role": &"player", "level": "hi", "seed": 7})
	assert_eq(int(b.call("wound_count")), 0, "setup on a reused figure clears the wounds")
	for f in [a, b, c]:
		f.free()


func test_levels() -> void:
	var S: GDScript = load(SCRIPT)
	# lo: a red tint on the skin only
	var lo := _new_fig("lo")
	var shared_pv := _skin_mat(lo)
	assert_true(bool(lo.call("add_wound", &"chest", _chest_spot(), 0.05)), "lo: the wound is kept")
	var m := _skin_mat(lo)
	assert_true(m != shared_pv and bool(m.get_shader_parameter("per_vertex")), "lo: its own per-vertex skin material")
	assert_eq(int(m.get_shader_parameter("wound_mode")), 1, "lo: wound_mode 1 (tint, no cut)")
	assert_eq(int(m.get_shader_parameter("wound_count")), 1, "lo: the tint knows the wound")
	assert_true((lo.call("inner_layers") as Array).is_empty(), "lo: no inner layers")
	lo.free()
	# min: nothing at all
	var mn := _new_fig("min")
	var shared_min := _skin_mat(mn)
	assert_false(bool(mn.call("add_wound", &"chest", _chest_spot(), 0.05)), "min: add_wound does nothing")
	mn.call("play", &"hit", 1.0)
	_steps(mn, 3)
	mn.call("play", &"die", 1.0)
	_steps(mn, 10)
	assert_eq(int(mn.call("wound_count")), 0, "min: hit and die leave no wound")
	assert_true(_skin_mat(mn) == shared_min, "min: the shared material, no copy")
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


func test_shaders() -> void:
	var strip := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/")
	for name in ["body.gdshader", "inner.gdshader"]:
		var code := FileAccess.get_file_as_string(DIR + name)
		var bare := strip.sub(code, "", true)
		assert_true(bare.length() > 100, name + " is there")
		assert_true(RegEx.create_from_string("render_mode[^;]*\\bunshaded\\b").search(bare) != null, name + ": unshaded (computes its own light)")
		assert_true(RegEx.create_from_string("\\bTIME\\b").search(bare) == null, name + ": no TIME (comments aside)")
		assert_true(bare.contains("uniform int wound_count") and bare.contains("uniform vec4 wounds[8]"), name + ": up to 8 wounds as uniforms")
	var body := strip.sub(FileAccess.get_file_as_string(DIR + "body.gdshader"), "", true)
	var frag := body.substr(body.find("void fragment()"))
	assert_true(frag.find("if (wound_count > 0)") >= 0 and frag.find("if (wound_count > 0)") < frag.find("discard"),
		"the skin discards only behind wound_count > 0")
	assert_eq(body.count("discard"), 1, "…and nowhere else")
	# the wound function is the same text in both shaders (the edges line up)
	var a := FileAccess.get_file_as_string(DIR + "body.gdshader")
	var b := FileAccess.get_file_as_string(DIR + "inner.gdshader")
	var k0 := "// ---- แผล"
	var k1 := "// ---- จบส่วนแผล ----"
	assert_true(a.find(k0) >= 0 and b.find(k0) >= 0 and a.find(k1) > a.find(k0) and b.find(k1) > b.find(k0),
		"both shaders mark their wound section")
	var sa := a.substr(a.find("\n", a.find(k0)), a.find(k1) - a.find("\n", a.find(k0)))
	var sb := b.substr(b.find("\n", b.find(k0)), b.find(k1) - b.find("\n", b.find(k0)))
	assert_true(sa == sb and sa.length() > 200, "…and it is the same code in both (the edges line up)")


func test_inner_assets() -> void:
	var S: GDScript = load(SCRIPT)
	var skin := load(DIR + "skin.res") as Skin
	var game: PackedStringArray = S.get("GAME_BONES")
	var known := {}
	for i in skin.get_bind_count():
		known[String(skin.get_bind_name(i))] = true
	for l in ["bone", "flesh"]:
		var m: ArrayMesh = S.call("inner_mesh", l)
		assert_true(m != null, "inner_%s.res loads" % l)
		if m == null:
			continue
		assert_eq(m.get_surface_count(), 1, "%s: one surface (one draw)" % l)
		var arr := m.surface_get_arrays(0)
		var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_true(tris >= 3000 and tris <= int(INNER_BUDGET[l]), "%s: %d triangles within %d" % [l, tris, int(INNER_BUDGET[l])])
		var mat := m.surface_get_material(0) as ShaderMaterial
		assert_true(mat != null and mat.shader != null and mat.shader.resource_path == DIR + "inner.gdshader", "%s: the inner shader" % l)
		for d in ResourceLoader.get_dependencies(DIR + "inner_%s.res" % l):
			var path := d.get_slice("::", d.get_slice_count("::") - 1)
			assert_true(path.begins_with(DIR), "inner_%s.res depends only on the soldier folder" % l, d)
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
		assert_true(unknown.is_empty(), "%s: skinned to binds of skin.res only" % l, str(unknown.keys()))
		if l == "bone":
			assert_true(rigid, "bone: every vertex bound rigidly (one weight of 1)")
			for b in ["pelvis", "spine", "chest", "head", "shoulderL", "elbowR", "hipL", "kneeR"]:
				assert_true(used.has(b), "bone: a part rides " + b)
		else:
			var main := 0
			for b in game:
				if used.has(b):
					main += 1
			assert_true(main >= 20, "flesh: weighted over the body (%d game bones)" % main)
	var spots: Dictionary = S.call("wound_spots")
	for b in S.get("WOUND_BONES"):
		assert_true(spots.has(b) and (spots[b] as Array).size() >= 8, "wound spots on %s (%d)" % [b, (spots.get(b, []) as Array).size()])
	var hi: ArrayMesh = S.call("body_mesh", "hi")
	if hi != null:
		var box := hi.get_aabb()
		for l in ["bone", "flesh"]:
			var m: ArrayMesh = S.call("inner_mesh", l)
			if m != null:
				var ib := m.get_aabb()
				assert_true(box.grow(0.002).encloses(ib), "%s: inside the skin's bounds in the bind pose" % l, "%s in %s" % [ib, box])
