extends "res://tests/testing.gd"
## The R1-V5 gothic ruin sample (tools/ruin_kit.gd + tools/ruin_sample.gd), built headless: both LOD meshes stay
## inside their triangle budgets, are one surface each (one draw call), fit the rules footprint of a 'building'
## (FieldProps.bld_size at s = 1000, h = 45000, field seed 30) plus the 0.6 m levelled pad, are about 9 m tall,
## come out the same on every run, and the committed assets/props/ruin/*.res match the generator. The renders are
## made by the tool itself under xvfb (see its header).

const Sample := preload("res://tools/ruin_sample.gd")
const Kit := preload("res://tools/ruin_kit.gd")
const RES := ["res://assets/props/ruin/sample_building_hi.res", "res://assets/props/ruin/sample_building_lo.res"]

var built: Array[Dictionary] = []


func setup() -> void:
	built = [Sample.build_mesh(0), Sample.build_mesh(1)]


func test_footprint_is_the_rules_building() -> void:
	var foot := Sample.footprint()
	assert_within(foot.x, 9.806, 0.0005, "width from FieldProps.bld_size (9806 MI)")
	assert_within(foot.y, 8.038, 0.0005, "depth from FieldProps.bld_size (8038 MI)")


func test_triangle_budgets() -> void:
	var hi: int = built[0]["tris"]
	var lo: int = built[1]["tris"]
	assert_true(hi <= Sample.HI_BUDGET, "hi within %d triangles" % Sample.HI_BUDGET, str(hi))
	assert_true(lo <= Sample.LO_BUDGET, "lo within %d triangles" % Sample.LO_BUDGET, str(lo))
	assert_true(hi >= 3000, "hi carries the detail (cut-out windows, fluted pillars)", str(hi))
	assert_true(lo * 2 < hi, "lo is far lighter than hi", "%d vs %d" % [lo, hi])


func test_one_surface_per_lod() -> void:
	for i in 2:
		var m: ArrayMesh = built[i]["mesh"]
		assert_eq(m.get_surface_count(), 1, "LOD %d is one surface (one draw call)" % i)
		assert_true(m.surface_get_material(0) is StandardMaterial3D, "LOD %d carries its vertex-colour material" % i)


func test_inside_the_footprint_and_about_nine_metres() -> void:
	var foot := Sample.footprint()
	for i in 2:
		var box: AABB = built[i]["aabb"]
		assert_true(Sample.fits(box, foot), "LOD %d inside the footprint + %.1f m pad" % [i, Sample.PAD], str(box))
		assert_within(box.end.y, 9.0, 0.6, "LOD %d is about 9 m tall" % i)
		assert_true(box.position.y >= -0.45, "LOD %d sinks at most 0.45 m into the ground" % i, str(box.position.y))
	assert_true(built[0]["aabb"].is_equal_approx(built[1]["aabb"]), "hi and lo share the outline")


func test_same_mesh_every_run() -> void:
	var again := Sample.build_mesh(0)
	assert_eq(int(again["tris"]), int(built[0]["tris"]), "same triangle count on a second build")
	assert_true((again["aabb"] as AABB).is_equal_approx(built[0]["aabb"]), "same bounds on a second build")


func test_committed_meshes_match_the_generator() -> void:
	for i in 2:
		assert_true(ResourceLoader.exists(RES[i]), RES[i] + " is committed (run tools/ruin_sample.gd)")
		var m := load(RES[i]) as ArrayMesh
		assert_true(m != null and m.get_surface_count() == 1, RES[i] + " loads as one surface")
		if m == null:
			continue
		var a := m.get_aabb()
		var b: AABB = built[i]["aabb"]
		assert_true(a.position.distance_to(b.position) < 0.002 and a.end.distance_to(b.end) < 0.002,
			RES[i] + " matches the generator's bounds (re-run tools/ruin_sample.gd after a change)", "%s vs %s" % [a, b])
		assert_eq(m.surface_get_array_index_len(0) / 3, int(built[i]["tris"]),
			RES[i] + " has the generator's triangle count")


func test_pointed_arch_and_steps() -> void:
	var k: Kit = Kit.new(0)
	var hole := k.arch_hole(0.0, 1.0, 0.0, 2.0, 1.0)
	assert_true(Kit.area2(hole) > 0.0, "arch hole winds counter-clockwise")
	assert_within(Kit.rect_of(hole).end.y, 2.0 + sqrt(0.75), 0.001, "equilateral arch apex at spring + w*sin(60)")
	k.seed_piece(3)
	var top := PackedVector2Array([Vector2(0.0, 5.0)])
	top.append_array(k.steps(Vector2(0.0, 5.0), Vector2(4.0, 3.0), 4))
	assert_eq(top[top.size() - 1], Vector2(4.0, 3.0), "a broken top ends where asked")
	for i in top.size() - 1:
		assert_true(top[i + 1].x >= top[i].x - 1e-6, "broken top runs left to right (%d)" % i)


func test_caption_strings_have_english() -> void:
	assert_eq(Array(I18n.missing(Sample.CAPTIONS)), [], "every caption on the sample PNGs has an English entry")
