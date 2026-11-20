extends "res://tests/testing.gd"
## The soldier's outfits (ใหม่ 0.15, scenes/arena/soldier_figure.gd): setup opts "outfit" = "" (training shorts, the bare
## body, the default) or "uniform" (field uniform). A worn outfit is one mesh, outfit_<name>_<level>.res in the body's
## folder, that replaces body_<level>.res on the same skeleton, Skin and material (still one draw call): the face shader
## on hi/mid/lo, the plain shader on min. An unknown name, or a body without all four files, falls back to "" without an
## error; outfit_shown() says what is worn. Meshes are cached like the body's. Wound spots come from the outfit's lo mesh
## (on the cloth), so a wound on a uniformed soldier cuts the cloth and shows its inner layers; min still does nothing.
## Figures (app/figures.gd) keeps the dressing room's choice (outfit / select_outfit, and in the slots) and gives it to the
## player's figure only (make_builtin); a soldier made otherwise keeps training shorts. The uniform checks run on every
## body that has the files (m2 and m3 today), so they stay valid as more bodies get them; "heavy" is a name no body has.

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const STORE := "user://test_soldier_outfit.cfg"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const BODIES: PackedStringArray = ["", "m2", "m3", "f1", "f2"]
## bodies the 0.15 release ships with the field uniform (the base body and f2 follow when their builds are imported)
const UNIFORMED: PackedStringArray = ["m2", "m3"]

var S: GDScript


func setup() -> void:
	S = load(SCRIPT)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _fig(level: String, body: String, opts := {}) -> Node3D:
	var f: Node3D = S.new()
	_tree().root.add_child(f)
	f.call("set_manual", true)
	var o := {"role": &"player", "level": level, "seed": 3, "body": body}
	o.merge(opts, true)
	f.call("setup", o)
	return f


func _mesh(f: Node3D) -> Mesh:
	return (f.call("body") as MeshInstance3D).mesh


func _mat(f: Node3D) -> ShaderMaterial:
	return (f.call("body") as MeshInstance3D).material_override as ShaderMaterial


## bodies (ids) that have all four uniform files
func _with_uniform() -> PackedStringArray:
	var out := PackedStringArray()
	for b in BODIES:
		if S.call("has_outfit", "uniform", S.call("folder", b)):
			out.append(b)
	return out


func test_outfit_option() -> void:
	assert_eq(Array(S.get("OUTFITS")), ["", "uniform"], "two outfits: training shorts and the field uniform")
	var have := _with_uniform()
	for b in UNIFORMED:
		assert_true(have.has(b), "%s ships with the field uniform (all four levels)" % b, str(have))
	assert_false(have.has("f1"), "f1 has no uniform in this release (it keeps training shorts)")
	for b in have:
		var dir: String = S.call("folder", b)
		for lv in LEVELS:
			var bare := _fig(lv, b)
			var f := _fig(lv, b, {"outfit": "uniform"})
			var m: ArrayMesh = S.call("outfit_mesh", "uniform", lv, dir)
			var tag := "%s %s" % [b if b != "" else "base", lv]
			assert_eq(str(bare.call("outfit_shown")), "", tag + ": the default is training shorts")
			assert_eq(_mesh(bare), S.call("body_mesh", lv, dir), tag + ": the default still draws body_%s.res" % lv)
			assert_eq(str(f.call("outfit_shown")), "uniform", tag + ": the uniform is worn")
			assert_true(m != null and _mesh(f) == m and m != S.call("body_mesh", lv, dir), tag + ": the outfit mesh replaces the body")
			assert_true(m == S.call("outfit_mesh", "uniform", lv, dir), tag + ": the outfit mesh is cached")
			assert_eq(m.get_surface_count(), 1, tag + ": one surface (one draw call)")
			assert_eq(m.get_blend_shape_count(), 0, tag + ": no blend shapes")
			var fmt := m.surface_get_format(0)
			assert_true((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, tag + ": CUSTOM0 (class, region, flesh, part)")
			assert_eq((fmt & Mesh.ARRAY_FORMAT_CUSTOM1) != 0, lv != "min", tag + ": face data (CUSTOM1) on hi/mid/lo only")
			var mi: MeshInstance3D = f.call("body")
			assert_true(mi.skin == (bare.call("body") as MeshInstance3D).skin and mi.skin != null, tag + ": the same Skin as the body")
			assert_eq(_mat(f), _mat(bare), tag + ": the same shared material as the bare body")
			var sp := _mat(f).shader.resource_path.get_file()
			assert_eq(sp, "body.gdshader" if lv == "min" else "body_face.gdshader", tag + ": the shader of the level")
			var face: Object = f.call("face")
			assert_eq(bool(face.call("active")), lv != "min", tag + ": the face (blink, moods, mouth) works on hi/mid/lo, not min")
			f.free()
			bare.free()


func test_fallback() -> void:
	for b in BODIES:
		var dir: String = S.call("folder", b)
		var tag := b if b != "" else "base"
		assert_false(bool(S.call("has_outfit", "heavy", dir)), tag + ": no body has a \"heavy\" outfit")
		assert_true(bool(S.call("has_outfit", "", dir)), tag + ": training shorts always fit")
		var f := _fig("mid", b, {"outfit": "heavy"})
		assert_eq(str(f.call("outfit_shown")), "", tag + ": an unbuilt outfit falls back to training shorts")
		assert_eq(_mesh(f), S.call("body_mesh", "mid", dir), tag + ": and draws the body")
		f.free()
		if not bool(S.call("has_outfit", "uniform", dir)):
			var g := _fig("hi", b, {"outfit": "uniform"})
			assert_eq(str(g.call("outfit_shown")), "", tag + ": no uniform files: training shorts")
			assert_eq(_mesh(g), S.call("body_mesh", "hi", dir), tag + ": no uniform files: the body mesh")
			g.free()
	assert_eq(S.call("outfit_mesh", "heavy", "hi", S.call("folder", "m2")), null, "no file: no outfit mesh")
	assert_eq(S.call("outfit_mesh", "", "hi", S.call("folder", "m2")), null, "\"\" is the body, not an outfit mesh")


func test_getter_and_resetup() -> void:
	var b := _with_uniform()[0] if not _with_uniform().is_empty() else ""
	if b == "" and not bool(S.call("has_outfit", "uniform", S.call("folder", ""))):
		assert_true(false, "a body with the uniform to test on")
		return
	var dir: String = S.call("folder", b)
	var f := _fig("hi", b, {"outfit": "uniform"})
	assert_eq(str(f.get("outfit")), "uniform", "the asked outfit is kept on the figure")
	f.call("setup", {"role": &"player", "level": "hi", "seed": 3})
	assert_eq(str(f.call("outfit_shown")), "uniform", "setup again without \"outfit\" keeps it")
	f.call("setup", {"role": &"player", "level": "hi", "seed": 3, "outfit": ""})
	assert_eq(str(f.call("outfit_shown")), "", "setup with \"\" takes it off")
	assert_eq(_mesh(f), S.call("body_mesh", "hi", dir), "and the body mesh is back")
	f.call("apply_level", "min")
	assert_eq(_mesh(f), S.call("body_mesh", "min", dir), "levels follow the bare body")
	f.free()
	var g: Node3D = S.new()
	g.set("body_id", b)
	g.set("outfit", "uniform")
	_tree().root.add_child(g)
	g.call("setup", {"role": &"deck", "level": "lo", "seed": 0})
	assert_eq(str(g.call("outfit_shown")), "uniform", "the outfit set before setup (as Figures does) is worn")
	g.call("apply_level", "mid")
	assert_eq(_mesh(g), S.call("outfit_mesh", "uniform", "mid", dir), "a level change keeps the outfit")
	g.free()


func test_wounds_on_cloth() -> void:
	for b in _with_uniform():
		var dir: String = S.call("folder", b)
		var tag := b if b != "" else "base"
		var cloth: Dictionary = S.call("wound_spots", dir, "uniform")
		var bare: Dictionary = S.call("wound_spots", dir)
		assert_true(cloth.has(&"chest") and cloth.has(&"spine") and cloth.has(&"pelvis"), tag + ": wound spots on the uniform's trunk")
		assert_false(is_same(cloth, bare), tag + ": the uniform has its own spots (not the skin's)")
		var sc: Array = S.call("wound_spot", &"chest", Vector3(0, 0, 1), 0.03, dir, "uniform")
		var sb: Array = S.call("wound_spot", &"chest", Vector3(0, 0, 1), 0.03, dir)
		assert_true(sc.size() == 3 and sb.size() == 3, tag + ": a front chest spot on the cloth and on the skin")
		if sc.size() == 3 and sb.size() == 3:
			var skin: Skin = (load(dir + "skin.res") as Skin)
			var bi := -1
			for i in skin.get_bind_count():
				if skin.get_bind_name(i) == &"chest":
					bi = i
			var inv := skin.get_bind_pose(bi).affine_inverse()
			# จุดบนชุด: ส่วนใหญ่เป็นผ้า/สายรัด (ชนิด ≥ 1 ใน outfit_uniform_lo) · คอเสื้อเปิด = ผิว (ชนิด 0)
			var oa := (S.call("outfit_mesh", "uniform", "lo", dir) as ArrayMesh).surface_get_arrays(0)
			var ov: PackedVector3Array = oa[Mesh.ARRAY_VERTEX]
			var oc: PackedFloat32Array = oa[Mesh.ARRAY_CUSTOM0]
			var list: Array = cloth[&"chest"]
			var on_cloth := 0
			var tried := 0
			for k in range(0, list.size(), maxi(1, list.size() / 40)):
				tried += 1
				var pc := inv * (list[k][0] as Vector3)
				var cls := -1
				for i in ov.size():
					if ov[i].distance_squared_to(pc) < 1e-8:
						cls = int(round(oc[i * 4]))
						break
				if cls >= 1:
					on_cloth += 1
			assert_true(on_cloth * 2 >= tried, tag + ": most chest spots are on the uniform, not on skin (%d of %d)" % [on_cloth, tried])
		for lv in ["hi", "mid", "lo"]:
			var f := _fig(lv, b, {"outfit": "uniform"})
			var mat0 := _mat(f)
			f.call("play", &"hit")
			assert_eq(int(f.call("wound_count")), 1, "%s %s: a hit wounds the uniformed soldier" % [tag, lv])
			var m := _mat(f)
			assert_true(m != mat0 and m.shader == S.call("wound_shader", dir), "%s %s: its own material on the wound shader" % [tag, lv])
			assert_eq(int(m.get_shader_parameter("wound_mode")), 2 if lv != "lo" else 1, "%s %s: hi/mid cut the cloth, lo tints it" % [tag, lv])
			var shown := 0
			for mi: MeshInstance3D in f.call("inner_layers"):
				shown += 1 if mi.visible else 0
			assert_eq(shown, 2 if lv != "lo" else 0, "%s %s: the flesh and bone layers show under the cloth on hi/mid" % [tag, lv])
			f.free()
		var mn := _fig("min", b, {"outfit": "uniform"})
		var mm := _mat(mn)
		mn.call("play", &"hit")
		assert_eq(int(mn.call("wound_count")), 0, tag + " min: no wound on the uniform either")
		assert_true(_mat(mn) == mm and not mn.has_method("_process"), tag + " min: shared material, nothing per frame")
		mn.free()


func test_figures_choice() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = STORE
	assert_eq(Figures.outfit(), "", "nothing saved: training shorts")
	Figures.select_outfit("uniform")
	assert_eq(Figures.outfit(), "uniform", "the field uniform is saved")
	Figures.select_outfit("heavy")
	assert_eq(Figures.outfit(), "", "an unknown outfit is saved as training shorts")
	Figures.select_outfit("uniform")
	var p: Node3D = Figures.make_builtin("soldier_m2")
	assert_true(p != null and str(p.get("outfit")) == "uniform", "the player's figure (make_builtin) gets the saved outfit")
	if p != null:
		p.free()
	var other: Node3D = S.new()
	assert_eq(str(other.get("outfit")), "", "a soldier made otherwise (other soldiers, bots) keeps training shorts")
	other.free()
	Figures.save_slot(0, "soldier_m2", "original", "uniform")
	Figures.save_slot(1, "soldier_m3", "original")
	var sl: Array = Figures.slots()
	assert_eq(sl[0], {"figure": "soldier_m2", "scheme": "original", "outfit": "uniform"}, "a slot keeps the outfit")
	assert_eq(sl[1], {"figure": "soldier_m3", "scheme": "original"}, "training shorts leave the slot as before")
	assert_eq(Figures.selected().keys(), ["figure", "scheme"], "the selection keeps its two keys")
	Figures.store_path = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
