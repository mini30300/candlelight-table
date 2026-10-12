extends SceneTree
## Render test for the kit pipeline (R0-D). Needs GL (xvfb + Mesa is enough):
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_lineup.gd
## Run `<godot> --headless --path godot --import` first. Checks every kit of kits.json after kit_post_import.gd
## (one surface, the shared figure material, COLOR + float CUSTOM0 matching the palette, 23 bones on skinned kits,
## scale), renders one line-up per army to tests/out/lineup_<army>.png asserting draw calls <= figures +
## LINEUP_EXTRA_DRAWS, and proves the paint-job override (paint_row and INSTANCE_CUSTOM.x) changes a figure's pixels.
## Prints ok/FAIL lines like tests/testing.gd and quits with exit code 1 on any failure.

const KITS_DIR := "res://assets/kits/"
const MANIFEST := KITS_DIR + "kits.json"
const MATERIAL_PATH := "res://assets/shaders/figure_material.tres"
const SHADER_PATH := "res://assets/shaders/figure.gdshader"
const OUT_DIR := "res://tests/out"
const JOINTS := 23
const LINEUP_EXTRA_DRAWS := 4      # draw calls allowed beyond one per figure (nothing else is in the scene)
const ROW_MAX := 12                # figures per row in a line-up
const GAP := 0.5                   # metres between bases in a row
const ROW_DEPTH := 1.3             # extra metres between rows
const PITCH_DEG := 25.0            # camera elevation for the line-ups
const PAINT_KIT := "heavy"
const CLEAR := Color(0.56, 0.60, 0.66)
const PAINT_A := Color(1.0, 0.0, 1.0, 1.0)   # paint row 0, slot 0: magenta
const PAINT_B := Color(0.0, 1.0, 1.0, 1.0)   # paint row 1, slot 0: cyan

var passed := 0
var failed := 0
var _manifest: Dictionary = {}
var _natural: Dictionary = {}
var _kits := PackedStringArray()
var _scenes: Dictionary = {}       # kit -> PackedScene
var _aabbs: Dictionary = {}        # kit -> AABB (root space)


func _initialize() -> void:
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	RenderingServer.set_default_clear_color(CLEAR)
	if not _load_manifest():
		_finish()
		return
	_check_all_kits()
	_render_all()


func _finish() -> void:
	print("%s  %d passed, %d failed (test_lineup)" % ["PASS " if failed == 0 else "FAIL ", passed, failed])
	quit(1 if failed > 0 else 0)


func _ok(cond: bool, msg: String, detail: Variant = null) -> void:
	if cond:
		passed += 1
		print("ok    " + msg)
	else:
		failed += 1
		print("FAIL  " + msg + ("" if detail == null else " " + str(detail).left(1500)))


# ---------- part 1: every kit after import ----------

func _load_manifest() -> bool:
	if not FileAccess.file_exists(MANIFEST):
		_ok(false, "kits.json exists (run node godot/tools/export_kits.js and the import first)")
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (data is Dictionary) or not (data.get("kits") is Dictionary):
		_ok(false, "kits.json parses")
		return false
	_manifest = data["kits"]
	for n in data.get("natural", []):
		_natural[String(n)] = true
	for k in _manifest.keys():
		_kits.append(String(k))
	_kits.sort()
	_ok(_kits.size() >= 300, "kits.json lists the full set: %d kits" % _kits.size())
	return true


func _check_all_kits() -> void:
	var bad_load := PackedStringArray()
	var bad_shape := PackedStringArray()
	var bad_material := PackedStringArray()
	var bad_format := PackedStringArray()
	var bad_palette := PackedStringArray()
	var bad_vertex := PackedStringArray()
	var bad_bones := PackedStringArray()
	var bad_scale := PackedStringArray()
	var skinned_count := 0
	var mount_rigs := 0
	var verts := 0
	var tris := 0
	for kit in _kits:
		var entry: Dictionary = _manifest[kit]
		var ps: PackedScene = load(KITS_DIR + kit + ".glb")
		if ps == null:
			bad_load.append(kit)
			continue
		_scenes[kit] = ps
		var inst := ps.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect(inst, meshes)
		var skeletons: Array[Skeleton3D] = []
		_collect_skeletons(inst, skeletons)
		if meshes.size() != 1 or inst.name != kit or not inst.has_meta("kit"):
			bad_shape.append("%s (meshes %d, root %s, meta %s)" % [kit, meshes.size(), inst.name, str(inst.has_meta("kit"))])
			inst.free()
			continue
		var mi := meshes[0]
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() != 1:
			bad_shape.append("%s (surfaces %d)" % [kit, mesh.get_surface_count() if mesh else -1])
			inst.free()
			continue
		var mat := mesh.surface_get_material(0)
		var sm := mat as ShaderMaterial
		if sm == null or sm.resource_path != MATERIAL_PATH or sm.shader == null or sm.shader.resource_path != SHADER_PATH or mi.material_override != null:
			bad_material.append(kit)
		var fmt := mesh.surface_get_format(0)
		var custom_type: int = (fmt >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) & Mesh.ARRAY_FORMAT_CUSTOM_MASK
		if not (fmt & Mesh.ARRAY_FORMAT_COLOR) or not (fmt & Mesh.ARRAY_FORMAT_CUSTOM0) or custom_type != Mesh.ARRAY_CUSTOM_RGBA_FLOAT or not (fmt & Mesh.ARRAY_FORMAT_INDEX):
			bad_format.append("%s (format %d)" % [kit, fmt])
		# palette: meta == kits.json materials, flags == NATURAL
		var meta: Dictionary = inst.get_meta("kit")
		var palette: Array = meta.get("palette", [])
		var mats: Array = entry.get("materials", [])
		var pal_ok := palette.size() == mats.size() and palette.size() > 0
		if pal_ok:
			for i in mats.size():
				var want: Dictionary = mats[i]
				var got: Dictionary = palette[i]
				if String(got["key"]) != String(want["key"]) or bool(got["tint"]) != bool(want["tint"]) or bool(got["tint"]) == _natural.has(String(want["key"])):
					pal_ok = false
				var rgb_w: Array = want["rgb"]
				var rgb_g: Array = got["rgb"]
				for c in 3:
					if int(rgb_w[c]) != int(rgb_g[c]):
						pal_ok = false
		if not pal_ok:
			bad_palette.append(kit)
		# vertex data: every vertex colour and CUSTOM0 match its palette slot
		var arrays := mesh.surface_get_arrays(0)
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		var nv: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var vtx_bad := 0
		if colours.size() != nv or custom.size() != nv * 4:
			vtx_bad = nv
		elif pal_ok:
			for i in nv:
				var slot := int(custom[i * 4 + 1] + 0.5)
				var flag := custom[i * 4]
				if slot < 0 or slot >= palette.size():
					vtx_bad += 1
					continue
				var p: Dictionary = palette[slot]
				var rgb: Array = p["rgb"]
				var c := colours[i]
				if (flag != 1.0 and flag != 0.0) or (flag == 1.0) != bool(p["tint"]) or absi(c.r8 - int(rgb[0])) > 1 or absi(c.g8 - int(rgb[1])) > 1 or absi(c.b8 - int(rgb[2])) > 1:
					vtx_bad += 1
		if vtx_bad > 0:
			bad_vertex.append("%s (%d of %d vertices)" % [kit, vtx_bad, nv])
		verts += nv
		tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		# bones
		var skinned := bool(entry.get("skinned", false))
		if skinned:
			skinned_count += 1
			var sk: Skeleton3D = skeletons[0] if skeletons.size() == 1 else null
			# พาหนะ: กระดูกของตัวพาหนะต่อท้าย 23 ข้อ ตามลำดับใน kits.json mountRig
			var mount_bones: Array = (entry.get("mountRig", {}) as Dictionary).get("bones", []) if entry.get("mountRig") is Dictionary else []
			var want_bones := JOINTS + mount_bones.size()
			var order_ok := sk != null and sk.get_bone_count() == want_bones
			if order_ok:
				for bi in mount_bones.size():
					if sk.get_bone_name(JOINTS + bi) != String(mount_bones[bi]["name"]):
						order_ok = false
			if sk == null or not order_ok or sk.get_bone_name(0) != "pelvis" or mi.skin == null or mi.skin.get_bind_count() != want_bones or int(entry.get("joints", 0)) != want_bones \
					or not (fmt & Mesh.ARRAY_FORMAT_BONES) or not (fmt & Mesh.ARRAY_FORMAT_WEIGHTS) or mi.get_node_or_null(mi.skeleton) != sk:
				bad_bones.append("%s (skeletons %d, bones %d, binds %d, want %d)" % [kit, skeletons.size(), sk.get_bone_count() if sk else -1, mi.skin.get_bind_count() if mi.skin else -1, want_bones])
			if not mount_bones.is_empty():
				mount_rigs += 1
		elif skeletons.size() != 0 or mi.skin != null or (fmt & Mesh.ARRAY_FORMAT_BONES):
			bad_bones.append("%s (rigid kit with a skeleton or bones)" % kit)
		# scale: AABB == exporter bbox, height in band
		var aabb: AABB = _xform_to(mi, inst) * mesh.get_aabb()
		_aabbs[kit] = aabb
		var bb: Array = entry["bbox"]
		var bb_min := Vector3(bb[0][0], bb[0][1], bb[0][2])
		var bb_max := Vector3(bb[1][0], bb[1][1], bb[1][2])
		var want_h: float = float(entry.get("h", 1.75)) * float(entry.get("scale", 1.0))
		var loose: bool = entry.get("mount") != null or bool(entry.get("creature", false)) or entry.has("fly")
		var ratio := aabb.size.y / want_h if want_h > 0.0 else 0.0
		var lo := 0.3 if loose else 0.5
		var hi := 2.0 if loose else 1.5
		if not aabb.position.is_equal_approx(bb_min) and (aabb.position - bb_min).length() > 0.01 \
				or not aabb.end.is_equal_approx(bb_max) and (aabb.end - bb_max).length() > 0.01 or ratio < lo or ratio > hi:
			bad_scale.append("%s (aabb %s..%s vs bbox %s..%s, height %.2f of %.2f)" % [kit, aabb.position, aabb.end, bb_min, bb_max, aabb.size.y, want_h])
		inst.free()
	var n := _kits.size()
	_ok(bad_load.is_empty(), "%d kits load as scenes" % n, bad_load)
	_ok(bad_shape.is_empty(), "every kit: root named after the kit with meta 'kit', exactly one MeshInstance3D with one surface", bad_shape)
	_ok(bad_material.is_empty(), "every kit: the one surface uses the shared " + MATERIAL_PATH + " (figure.gdshader)", bad_material)
	_ok(bad_format.is_empty(), "every kit: indexed surface with COLOR and RGBA_FLOAT CUSTOM0", bad_format)
	_ok(bad_palette.is_empty(), "every kit: meta palette == kits.json materials (keys, colours, paintable flags == not NATURAL)", bad_palette)
	_ok(bad_vertex.is_empty(), "every vertex: COLOR == its slot's colour, CUSTOM0 == (paintable flag, slot) — %d vertices, %d triangles" % [verts, tris], bad_vertex)
	_ok(bad_bones.is_empty(), "%d skinned kits have a Skeleton3D with %d bones and a %d-bind skin (%d mounts with their own bones after them, in mountRig order); rigid kits have none" % [skinned_count, JOINTS, JOINTS, mount_rigs], bad_bones)
	_ok(bad_scale.is_empty(), "every kit: AABB equals the exporter's bbox and the height is within band of h x scale", bad_scale)


# ---------- part 2: one line-up per army, then the paint-job check ----------

func _render_all() -> void:
	await process_frame                       # the root viewport is not ready inside _initialize
	await RenderingServer.frame_post_draw
	var armies: Dictionary = {}
	for kit in _kits:
		if not _scenes.has(kit) or not _aabbs.has(kit):
			continue
		var t: Variant = _manifest[kit].get("type")
		var fac := "misc"
		if t is Dictionary and String(t.get("fac", "")) != "" and String(t.get("fac", "")) != "*":
			fac = String(t["fac"])
		if not armies.has(fac):
			armies[fac] = PackedStringArray()
		armies[fac].append(kit)
	var names := PackedStringArray(armies.keys())
	names.sort()
	_ok(names.size() >= 15, "kits group into %d armies: %s" % [names.size(), ", ".join(names)])
	for fac in names:
		await _render_army(fac, armies[fac])
	await _render_paint_check()
	_finish()


## Rows of ROW_MAX figures, shortest in front, spaced by max(baseR, half width); orthographic camera from the front.
func _render_army(fac: String, kits: PackedStringArray) -> void:
	var sorted := Array(kits)
	sorted.sort_custom(func(a: String, b: String) -> bool: return _aabbs[a].size.y < _aabbs[b].size.y)
	var scene := Node3D.new()
	root.add_child(scene)
	var total := AABB()
	var count := 0
	var z := 0.0
	var row_start := 0
	while row_start < sorted.size():
		var row: Array = sorted.slice(row_start, row_start + ROW_MAX)
		var radii := PackedFloat32Array()
		var depth := 0.0
		for kit in row:
			var e: Dictionary = _manifest[kit]
			var a: AABB = _aabbs[kit]
			radii.append(maxf(float(e.get("baseR", 0.62)) if e.get("baseR") != null else 0.62, a.size.x * 0.5))
			depth = maxf(depth, a.size.z)
		var xs := _row_positions(radii)
		z -= depth * 0.5
		for i in row.size():
			var kit: String = row[i]
			var inst: Node3D = _scenes[kit].instantiate()
			inst.position = Vector3(xs[i], 0.0, z)
			scene.add_child(inst)
			var a: AABB = _aabbs[kit]
			a.position += inst.position
			total = a if count == 0 else total.merge(a)
			count += 1
		z -= depth * 0.5 + ROW_DEPTH
		row_start += ROW_MAX
	var cam := _frame_camera(scene, total)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var img := root.get_viewport().get_texture().get_image()
	var drawn := _count_non_background(img)
	var file := "lineup_%s.png" % fac
	var err := img.save_png(OUT_DIR + "/" + file)
	_ok(err == OK and draws <= count + LINEUP_EXTRA_DRAWS and drawn >= count * 30,
		"army %s: %d figures in %d draw calls (<= figures + %d), %d coloured pixels -> %s" % [fac, count, draws, LINEUP_EXTRA_DRAWS, drawn, file])
	if cam != null:
		cam.free()
	root.remove_child(scene)
	scene.free()


## The same kit three times: unpainted, paint_row 0 on a duplicated material (magenta slot 0), and a MultiMesh whose
## INSTANCE_CUSTOM.x selects row 1 (cyan slot 0); row -1 on a second MultiMesh instance stays unpainted.
func _render_paint_check() -> void:
	if not _scenes.has(PAINT_KIT):
		_ok(false, "paint check needs kit " + PAINT_KIT)
		return
	var ps: PackedScene = _scenes[PAINT_KIT]
	var aabb: AABB = _aabbs[PAINT_KIT]
	var scene := Node3D.new()
	root.add_child(scene)
	var paint := Image.create(16, 2, false, Image.FORMAT_RGBA8)
	paint.fill(Color(0, 0, 0, 0))
	paint.set_pixel(0, 0, PAINT_A)
	paint.set_pixel(0, 1, PAINT_B)
	var tex := ImageTexture.create_from_image(paint)
	var base: ShaderMaterial = load(MATERIAL_PATH)
	var plain: Node3D = ps.instantiate()
	plain.position = Vector3(-3.0, 0.0, 0.0)
	scene.add_child(plain)
	var painted: Node3D = ps.instantiate()
	painted.position = Vector3(-1.0, 0.0, 0.0)
	scene.add_child(painted)
	var meshes: Array[MeshInstance3D] = []
	_collect(painted, meshes)
	var row_mat: ShaderMaterial = base.duplicate()
	row_mat.set_shader_parameter("paint_tex", tex)
	row_mat.set_shader_parameter("paint_row", 0)
	for mi in meshes:
		mi.material_override = row_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true           # Compatibility multiplies COLOR by the instance colour (zero when colours are off)
	mm.use_custom_data = true
	mm.mesh = meshes[0].mesh
	mm.instance_count = 2
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)))
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, Color(1.0, 0.0, 0.0, 0.0))
	mm.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, 0.0)))
	mm.set_instance_color(1, Color.WHITE)
	mm.set_instance_custom_data(1, Color(-1.0, 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mm_mat: ShaderMaterial = base.duplicate()
	mm_mat.set_shader_parameter("paint_tex", tex)
	mm_mat.set_shader_parameter("use_instance_custom", true)
	mmi.material_override = mm_mat
	scene.add_child(mmi)
	var total := AABB(aabb.position + Vector3(-3.0, 0.0, 0.0), aabb.size + Vector3(6.0, 0.0, 0.0))
	var cam := _frame_camera(scene, total)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/lineup_paint.png")
	var r_plain := _figure_rect(cam, aabb, Vector3(-3.0, 0.0, 0.0))
	var r_row := _figure_rect(cam, aabb, Vector3(-1.0, 0.0, 0.0))
	var r_mm := _figure_rect(cam, aabb, Vector3(1.0, 0.0, 0.0))
	var r_mm_off := _figure_rect(cam, aabb, Vector3(3.0, 0.0, 0.0))
	var magenta_plain := _count_hue(img, r_plain, PAINT_A)
	var magenta_row := _count_hue(img, r_row, PAINT_A)
	var cyan_mm := _count_hue(img, r_mm, PAINT_B)
	var cyan_mm_off := _count_hue(img, r_mm_off, PAINT_B)
	var differ := _count_differing(img, r_plain, r_row)
	var magenta_off := _count_hue(img, r_mm_off, PAINT_A)
	var mean_plain := _mean_colour(img, r_plain)
	var mean_off := _mean_colour(img, r_mm_off)
	var drift := maxf(maxf(absf(mean_plain.r - mean_off.r), absf(mean_plain.g - mean_off.g)), absf(mean_plain.b - mean_off.b))
	_ok(draws <= 3 + LINEUP_EXTRA_DRAWS, "paint scene: 2 figures + 1 MultiMesh in %d draw calls" % draws)
	_ok(magenta_plain == 0 and magenta_row > 20 and differ > 20,
		"paint_row 0 recolours slot 0 (%s) of %s: %d magenta pixels (unpainted copy %d), %d pixels differ -> lineup_paint.png" % [_manifest[PAINT_KIT]["materials"][0]["key"], PAINT_KIT, magenta_row, magenta_plain, differ])
	_ok(cyan_mm > 20 and cyan_mm_off == 0 and magenta_off == 0 and drift < 0.02,
		"INSTANCE_CUSTOM.x selects the paint row on a MultiMesh: row 1 gives %d cyan pixels, row -1 gives %d cyan / %d magenta and a mean colour within %.3f of the unpainted figure" % [cyan_mm, cyan_mm_off, magenta_off, drift])
	if cam != null:
		cam.free()
	root.remove_child(scene)
	scene.free()


# ---------- helpers ----------

func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _collect_skeletons(n: Node, out: Array[Skeleton3D]) -> void:
	if n is Skeleton3D:
		out.append(n)
	for c in n.get_children():
		_collect_skeletons(c, out)


func _xform_to(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _row_positions(radii: PackedFloat32Array) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var x := 0.0
	for i in radii.size():
		if i > 0:
			x += radii[i - 1] + GAP + radii[i]
		xs.append(x)
	for i in xs.size():
		xs[i] -= x * 0.5
	return xs


## Orthographic camera in front of and above the box, sized so the whole box fits with a margin.
func _frame_camera(parent: Node, box: AABB) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var vp := Vector2(root.size)
	var aspect := vp.x / vp.y
	var pitch := deg_to_rad(PITCH_DEG)
	var vertical := box.size.y * cos(pitch) + box.size.z * sin(pitch)
	cam.size = maxf(vertical, box.size.x / aspect) * 1.1
	var dist := box.size.length() * 2.0 + 10.0
	cam.near = 0.05
	cam.far = dist * 2.0
	var centre := box.get_center()
	parent.add_child(cam)
	cam.look_at_from_position(centre + Vector3(0.0, sin(pitch), cos(pitch)) * dist, centre, Vector3.UP)
	cam.make_current()
	return cam


func _count_non_background(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - CLEAR.r) > 0.08 or absf(c.g - CLEAR.g) > 0.08 or absf(c.b - CLEAR.b) > 0.08:
				n += 1
	return n * 4


## Screen rectangle of a kit's AABB placed at `at`.
func _figure_rect(cam: Camera3D, aabb: AABB, at: Vector3) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := cam.unproject_position(aabb.get_endpoint(i) + at)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil()))


## Pixels in `r` with the hue of `paint`: the paint's channels visible and the other channel nearly absent (a pure
## paint keeps that channel at 0 under any shading, while the kit's own blue-grey armour keeps all three channels).
func _count_hue(img: Image, r: Rect2i, paint: Color) -> int:
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			var c := img.get_pixel(x, y)
			var on_min := 1.0
			var off_max := 0.0
			for ch in 3:
				if paint[ch] > 0.5:
					on_min = minf(on_min, c[ch])
				else:
					off_max = maxf(off_max, c[ch])
			if on_min > 0.2 and off_max < 0.35 * on_min:
				n += 1
	return n


## Pixels at the same offset inside two equally sized rectangles that differ noticeably.
func _count_differing(img: Image, a: Rect2i, b: Rect2i) -> int:
	var n := 0
	var w := mini(a.size.x, b.size.x)
	var h := mini(a.size.y, b.size.y)
	for y in h:
		for x in w:
			var pa := Vector2i(a.position.x + x, a.position.y + y)
			var pb := Vector2i(b.position.x + x, b.position.y + y)
			if pa.x < 0 or pb.x < 0 or pa.y < 0 or pb.y < 0 or pa.x >= img.get_width() or pb.x >= img.get_width() or pa.y >= img.get_height() or pb.y >= img.get_height():
				continue
			var ca := img.get_pixelv(pa)
			var cb := img.get_pixelv(pb)
			if absf(ca.r - cb.r) > 0.1 or absf(ca.g - cb.g) > 0.1 or absf(ca.b - cb.b) > 0.1:
				n += 1
	return n


## Mean colour of the pixels inside `r` (clipped to the image); robust to sub-pixel offsets between two figures.
func _mean_colour(img: Image, r: Rect2i) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			sum += img.get_pixel(x, y)
			n += 1
	return sum / maxi(n, 1)
