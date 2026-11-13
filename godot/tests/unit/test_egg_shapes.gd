extends "res://tests/testing.gd"
## Egg placeholder figures (LOBBY_SPEC §4.1, §7.4): size classes over every datasheet, the base radius against the kit
## exporter's baseR formula, the widest radius under the team ring, triangle caps per detail level, the mesh cache, and
## no NaN anywhere. Pure data + headless mesh building (runs in the exported exe and on arm64 too).

const COUNTS := {"infantry": 155, "big": 10, "cavalry": 25, "walker": 60, "vehicle": 6, "giant": 3, "titan": 15}


func test_class_counts_over_every_type() -> void:
	var got := {}
	for c in EggShapes.CLASSES:
		got[c] = 0
	var n := 0
	var unknown := []
	for t in GameData.types():
		var cls := EggShapes.class_of(str(t["k"]))
		if not EggShapes.CLASSES.has(cls):
			unknown.append(str(t["k"]))
		got[cls] = int(got.get(cls, 0)) + 1
		n += 1
	assert_eq(unknown, [], "every type gets a known class")
	assert_eq(n, 274, "all 274 datasheets")
	assert_eq(got, COUNTS, "size classes 155 / 10 / 25 / 60 / 6 / 3 / 15")
	assert_eq(EggShapes.class_of("no_such_key"), "infantry", "an unknown key is an infantry egg")


func test_base_radius_follows_the_exporter() -> void:
	var biggest := 0.0
	var bad := []
	for t in GameData.types():
		var k := str(t["k"])
		var r_mi := GameData.base_r_mi(k)
		var want := 0.62 if r_mi <= 800 else roundf(r_mi * 17.27 / 1000.0) / 20.0
		var r := EggShapes.base_r(k)
		if absf(r - want) > 0.0001:
			bad.append("%s: %s != %s" % [k, str(r), str(want)])
		biggest = maxf(biggest, r)
	assert_eq(bad, [], "base_r = 0.62 up to 0.8\", round(r x 17.27) / 20 above")
	assert_within(biggest, 6.9, 0.0001, "the largest base radius is 6.9")
	assert_within(EggShapes.base_r("no_such_key"), 0.62, 0.0001, "an unknown key gets the small base")


func test_sizes_have_no_nan() -> void:
	var bad := []
	for t in GameData.types():
		var k := str(t["k"])
		var s := EggShapes.size_of(k)
		if is_nan(s.x) or is_nan(s.y) or is_nan(s.z) or s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
			bad.append(k + " " + str(s))
	assert_eq(bad, [], "every size is a positive number")
	var inf_k := ""
	for t in GameData.types():
		if EggShapes.class_of(str(t["k"])) == "infantry":
			inf_k = str(t["k"])
			break
	assert_within(EggShapes.size_of(inf_k).y, 1.75, 0.01, "an infantry egg is about 1.75 m tall")


func test_meshes_fit_under_the_ring_and_the_caps() -> void:
	for cls in EggShapes.CLASSES:
		var sh: Array = EggShapes.SHAPE[cls]
		for simple in [true, false]:
			var m := EggShapes.mesh(cls, simple)
			var tag := "%s %s" % [cls, "simple" if simple else "full"]
			assert_true(m != null and m.get_surface_count() == 1, tag + ": one surface")
			var n := EggShapes.tris(m)
			var cap := EggShapes.SIMPLE_MAX_TRIS if simple else EggShapes.FULL_MAX_TRIS
			assert_true(n > 0 and n <= cap, "%s: %d triangles <= %d" % [tag, n, cap])
			var arr := m.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var wide := 0.0
			var reach := 0.0
			var top := 0.0
			var low := 1.0
			var nan := false
			for i in verts.size():
				var v := verts[i]
				if is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_nan(norms[i].x):
					nan = true
				wide = maxf(wide, absf(v.x))
				reach = maxf(reach, Vector2(v.x, v.z).length())
				top = maxf(top, v.y)
				low = minf(low, v.y)
			assert_false(nan, tag + ": no NaN in positions or normals")
			assert_true(wide <= 0.70 + 0.0001, "%s: widest radius %.3f R <= 0.70 R" % [tag, wide])
			assert_true(reach <= maxf(0.70, float(sh[2])) + 0.0001, "%s: reach %.3f R inside the egg's length" % [tag, reach])
			assert_within(top, float(sh[0]), 0.0001, tag + ": height in R")
			assert_within(low, 0.0, 0.0001, tag + ": stands on its base")
			assert_eq(cols.size(), verts.size(), tag + ": a colour per vertex")
			# the front nub is the only darker part at the top half (faces +z)
			var nub_z := -1.0
			for i in verts.size():
				var dc := cols[i]
				if absf(dc.r - EggShapes.NUB.r) < 0.01 and absf(dc.g - EggShapes.NUB.g) < 0.01 and absf(dc.b - EggShapes.NUB.b) < 0.01:
					nub_z = maxf(nub_z, verts[i].z)
			assert_true(nub_z > 0.5, "%s: a darker nub faces +z (%.3f)" % [tag, nub_z])


func test_meshes_are_cached() -> void:
	assert_true(EggShapes.mesh("infantry", true) == EggShapes.mesh("infantry", true), "the simple mesh is cached")
	assert_true(EggShapes.mesh("titan", false) == EggShapes.mesh("titan", false), "the full mesh is cached")
	assert_true(EggShapes.mesh("titan", false) != EggShapes.mesh("titan", true), "simple and full are different meshes")
	assert_true(EggShapes.mesh("nope", true) == EggShapes.mesh("infantry", true), "an unknown class uses the infantry egg")


func test_profile_lookup() -> void:
	assert_within(EggShapes.profile_at(0.0), 0.55, 0.0001, "profile at the base")
	assert_within(EggShapes.profile_at(0.32), 1.0, 0.0001, "profile at the widest point")
	assert_within(EggShapes.profile_at(1.0), 0.0, 0.0001, "profile at the tip")
	assert_within(EggShapes.profile_at(0.41), 0.975, 0.0001, "profile between two points")


## FigurePool's egg switch, built headless (no tree): one MultiMesh per size class with the shared figure material,
## every figure drawn, nothing skinned, the style in counts(); stress mode adds 500 eggs from non-hidden types.
## (Instance data is not read back: the headless renderer keeps none.)
func test_figure_pool_egg_switch() -> void:
	var pool := FigurePool.new()
	assert_eq(pool.style, "kit", "FigurePool starts in kit style (the kit path is unchanged)")
	pool.set_style("nope")
	assert_eq(pool.style, "kit", "an unknown style is ignored")
	pool.set_style("egg")
	var list: Array[FigurePool.Figure] = []
	var per_class := {}
	for t in GameData.types():
		var k := str(t["k"])
		if GameData.is_hidden(k):
			continue
		var cls := EggShapes.class_of(k)
		if int(per_class.get(cls, 0)) >= 3:
			continue
		per_class[cls] = int(per_class.get(cls, 0)) + 1
		list.append(FigurePool.make(k, list.size() % 4, Vector3(list.size(), 0.0, 0.0), 0.3, EggShapes.base_r(k)))
	pool.set_figures(list)
	for lv in ["hi", "min"]:
		pool.build(lv, Vector3(0, 30, 30))
		var c := pool.counts()
		assert_eq(str(c["style"]), "egg", lv + ": counts() says egg")
		assert_eq(int(c["figures"]), list.size(), lv + ": every figure is counted")
		assert_eq(int(c["skinned"]), 0, lv + ": no skinned figure")
		assert_eq(int(c["kits"]), per_class.size(), lv + ": one MultiMesh per size class present (%d)" % per_class.size())
		var drawn := 0
		var names := []
		var shared := true
		for n in pool.get_children():
			if n is MultiMeshInstance3D and not n.is_queued_for_deletion():
				var mmi := n as MultiMeshInstance3D
				drawn += mmi.multimesh.instance_count
				names.append(String(mmi.name))
				shared = shared and mmi.material_override == pool._figure_material() and mmi.multimesh.use_colors and mmi.multimesh.use_custom_data
				var simple: bool = lv == "min"
				assert_true(mmi.multimesh.mesh == EggShapes.mesh(String(mmi.name).trim_prefix("Egg_"), simple), "%s %s: the class mesh for this level" % [lv, mmi.name])
		assert_eq(drawn, list.size(), lv + ": every figure is an instance")
		assert_true(shared, lv + ": shared figure material, instance colours and custom data on")
		names.sort()
		assert_true(names.size() > 0 and String(names[0]).begins_with("Egg_"), lv + ": nodes are named Egg_<class> " + str(names))
	pool.set_stress(true, Vector3(0, 30, 30))
	assert_eq(int(pool.counts()["figures"]), list.size() + FigurePool.STRESS_RIGID + FigurePool.STRESS_SKINNED, "stress adds 500 eggs")
	assert_eq(int(pool.counts()["skinned"]), 0, "stress eggs are never skinned")
	pool.set_stress(false, Vector3(0, 30, 30))
	assert_eq(int(pool.counts()["figures"]), list.size(), "stress off restores the list")
	pool.free()
