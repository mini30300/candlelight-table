extends SceneTree
## Bakes the far-tier impostors of every kit (or `--only k1,k2`): 16 yaws x 2 pitches per kit, rendered from the
## imported kit scene with figure_material.tres into one strip per kit (see assets/kits/CONTRACT.md):
##   assets/impostors/<kit>.png       RGBA8, 16 columns x 2 rows of CELL px; alpha = coverage
##   assets/impostors/<kit>_m.png     RGB8 mask: R = paintable flag (255/0), G = 255 - 8 * palette index (slot =
##                                    round((255 - G) / 8); the high range survives the renderer's output curve), B = 0
##   assets/impostors/impostors.json  cell size, columns, rows, pitches; per kit the world size one cell covers and the
##                                    figure-local centre every cell is drawn around
## Needs GL (xvfb + Mesa is enough):
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --audio-driver Dummy \
##     -s tools/bake_impostors.gd -- [--only k1,k2] [--cell 64] [--out res://assets/impostors]
## Deterministic: the same kits on the same Mesa give the same bytes. The output is git-ignored.

const KITS_DIR := "res://assets/kits/"
const MANIFEST := KITS_DIR + "kits.json"
const MATERIAL_PATH := "res://assets/shaders/figure_material.tres"
const YAWS := 16
const PITCHES: Array[float] = [20.0, 50.0]   # degrees above the horizon, one strip row each (row 0 = first)
const DEFAULT_CELL := 64
const DEFAULT_OUT := "res://assets/impostors"

var _cell := DEFAULT_CELL
var _out := DEFAULT_OUT
var _only := PackedStringArray()
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _mask_mat: ShaderMaterial
var _failed := 0


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_vp = SubViewport.new()
	_vp.size = Vector2i(YAWS * _cell, PITCHES.size() * _cell)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.use_debanding = false
	root.add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(_cam)
	_cam.make_current()
	_stage = Node3D.new()
	_vp.add_child(_stage)
	var base: ShaderMaterial = load(MATERIAL_PATH)
	if base == null:
		print("FAIL  cannot load " + MATERIAL_PATH)
		quit(1)
		return
	_mask_mat = base.duplicate()
	_mask_mat.set_shader_parameter("mask_out", true)
	print("adapter: " + RenderingServer.get_video_adapter_name())
	_run()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--only":
				i += 1
				_only = args[i].split(",", false)
			"--cell":
				i += 1
				_cell = maxi(8, int(args[i]))
			"--out":
				i += 1
				_out = args[i].trim_suffix("/")
			_:
				print("unknown argument " + args[i])
		i += 1


func _list_kits() -> PackedStringArray:
	var out := PackedStringArray()
	if FileAccess.file_exists(MANIFEST):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary and data.get("kits") is Dictionary:
			for k in data["kits"].keys():
				out.append(String(k))
	else:
		var dir := DirAccess.open(KITS_DIR)
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".glb"):
					out.append(f.get_basename())
	out.sort()
	if not _only.is_empty():
		var picked := PackedStringArray()
		for k in _only:
			if out.has(k):
				picked.append(k)
			else:
				print("FAIL  unknown kit " + k)
				_failed += 1
		return picked
	return out


func _run() -> void:
	var kits := _list_kits()
	var json := {
		"cell": _cell, "columns": YAWS, "rows": PITCHES.size(), "yaw_step_deg": 360.0 / YAWS, "pitches_deg": PITCHES,
		"layout": "column i = the figure seen from azimuth i*yaw_step_deg, measured from its front (+Z) towards its left (+X); row j = seen from pitches_deg[j] above the horizon; lit from the viewer's upper left",
		"cell_world": "every cell shows a square of `size` world units centred on the figure-local point `centre` (bounding-sphere diameter of the kit's AABB)",
		"mask": "<kit>_m.png: R = paintable flag (255/0), G = 255 - 8 * palette index (slot = round((255 - G) / 8)), B = 0; alpha of <kit>.png = coverage",
		"kits": {},
	}
	var t0 := Time.get_ticks_msec()
	for n in kits.size():
		var kit := kits[n]
		var entry: Dictionary = await _bake_kit(kit)
		if entry.is_empty():
			_failed += 1
			print("FAIL  " + kit)
		else:
			json["kits"][kit] = entry
		if (n + 1) % 25 == 0 or n + 1 == kits.size():
			print("baked %d/%d kits (%.1f s)" % [n + 1, kits.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	var f := FileAccess.open(_out + "/impostors.json", FileAccess.WRITE)
	if f == null:
		print("FAIL  cannot write " + _out + "/impostors.json")
		_failed += 1
	else:
		f.store_string(JSON.stringify(json, "\t") + "\n")
		f.close()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("%s  %d kits baked in %.1f s (%.0f ms/kit), %d failed -> %s" % ["ok   " if _failed == 0 else "FAIL ",
		kits.size() - _failed, secs, 1000.0 * secs / maxf(1.0, kits.size()), _failed, ProjectSettings.globalize_path(_out)])
	quit(1 if _failed > 0 else 0)


## One kit: 32 copies on a grid (yaw about the figure's own axis, then pitch towards the camera), one orthographic
## camera over the whole grid, one frame for the colour strip and one for the mask strip.
func _bake_kit(kit: String) -> Dictionary:
	var ps: PackedScene = load(KITS_DIR + kit + ".glb")
	if ps == null:
		return {}
	var probe := ps.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect(probe, meshes)
	if meshes.size() != 1 or meshes[0].mesh == null:
		probe.free()
		return {}
	var aabb: AABB = _xform_to(meshes[0], probe) * meshes[0].mesh.get_aabb()
	probe.free()
	var centre := aabb.get_center()
	var size := aabb.size.length()
	if size <= 0.0:
		return {}
	_cam.size = PITCHES.size() * size
	_cam.position = Vector3(0.0, 0.0, size * 4.0)
	_cam.near = 0.01
	_cam.far = size * 8.0
	for j in PITCHES.size():
		for i in YAWS:
			var pitch := Node3D.new()
			pitch.position = Vector3((i - (YAWS - 1) * 0.5) * size, ((PITCHES.size() - 1) * 0.5 - j) * size, 0.0)
			pitch.rotation = Vector3(deg_to_rad(PITCHES[j]), 0.0, 0.0)
			var yaw := Node3D.new()
			yaw.rotation = Vector3(0.0, -deg_to_rad(i * 360.0 / YAWS), 0.0)
			var off := Node3D.new()
			off.position = -centre
			off.add_child(ps.instantiate())
			yaw.add_child(off)
			pitch.add_child(yaw)
			_stage.add_child(pitch)
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img.get_used_rect().size == Vector2i.ZERO:        # nothing drawn yet (first frame after a shader compile): once more
		await RenderingServer.frame_post_draw
		img = _vp.get_texture().get_image()
	var err := img.save_png(_out + "/" + kit + ".png")
	var mis: Array[MeshInstance3D] = []
	_collect(_stage, mis)
	for mi in mis:
		mi.material_override = _mask_mat
	await RenderingServer.frame_post_draw
	var mask := _vp.get_texture().get_image()
	mask.convert(Image.FORMAT_RGB8)
	var err2 := mask.save_png(_out + "/" + kit + "_m.png")
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.free()
	if err != OK or err2 != OK:
		return {}
	return {
		"size": size, "centre": [centre.x, centre.y, centre.z],
		"aabb": [aabb.position.x, aabb.position.y, aabb.position.z, aabb.end.x, aabb.end.y, aabb.end.z],
	}


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _xform_to(n: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
