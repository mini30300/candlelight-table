extends "res://tests/testing.gd"
## CampaignHeroes (CAMPAIGN_SPEC §3): the hero-scene contract, pack lookup order with the primitive fixture pack, the
## fallback to the built-in scenes and the catastrophe music lookup.

const FIX := "res://tests/fixtures/campaign_pack/campaign"
const FIX_ARENA := "res://tests/fixtures/campaign_pack/arena/campaign"


func test_builtin_scenes_keep_the_contract() -> void:
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	for id in CampaignHeroes.IDS:
		var h := CampaignHeroes.make(id)
		assert_true(h != null and CampaignHeroes.missing_api(h).is_empty(), "built-in hero %s has setup and set_active" % id)
		if h == null:
			continue
		assert_false(CampaignHeroes.is_pack(h), "built-in hero %s is not a pack scene" % id)
		var vp := SubViewport.new()
		vp.own_world_3d = true
		root.add_child(vp)
		vp.add_child(h)
		h.call("setup", {"level": "min", "sel": Figures.selected(), "aspect": 16.0 / 9.0})
		var cam := vp.get_camera_3d()
		assert_true(cam != null and h.is_ancestor_of(cam), "hero %s builds its own current camera" % id)
		h.call("set_active", true)
		h.call("set_active", false)
		assert_false(h.is_processing() or h.is_physics_processing(), "hero %s does no per-frame work while inactive" % id)
		vp.free()
	assert_eq(CampaignHeroes.make("easy"), null, "an unknown id gives null")
	CampaignHeroes.test_dirs = PackedStringArray()


func test_pack_lookup() -> void:
	CampaignHeroes.test_dirs = PackedStringArray([FIX, FIX_ARENA])
	assert_eq(CampaignHeroes.pack_path("normal"), FIX + "/hero_normal.gd", "the first folder wins")
	assert_eq(CampaignHeroes.pack_path("veryhard"), FIX_ARENA + "/hero_veryhard.gd", "the second folder is searched too")
	assert_eq(CampaignHeroes.pack_path("catastrophe"), "", "no pack scene for catastrophe")
	var n := CampaignHeroes.make("normal")
	assert_true(CampaignHeroes.is_pack(n), "a valid pack scene is used")
	n.free()
	var h := CampaignHeroes.make("hard")
	assert_false(CampaignHeroes.is_pack(h), "a pack scene without set_active falls back to the built-in one")
	h.free()
	assert_eq(CampaignHeroes.music_path(), FIX_ARENA + "/catastrophe.ogg" if ResourceLoader.exists(FIX_ARENA + "/catastrophe.ogg") else "",
		"music lookup follows the same folders")
	CampaignHeroes.test_dirs = PackedStringArray()
	assert_eq(Array(CampaignHeroes.PACK_DIRS), ["res://packs/campaign", "res://packs/arena/campaign"], "public lookup order")
	assert_eq(CampaignHeroes.pack_path("normal"), "", "the public tree has no pack hero")


# ---- track B: stage, light, built-in scenes, broken packs, music ----

const BROKEN := "res://tests/fixtures/campaign_pack/broken"
const FIG_LIST := "res://tests/fixtures/figure_pack/figures.json"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _stage(level: String) -> HeroStage:
	var st := HeroStage.new()
	st.size = Vector2(320.0, 240.0)
	_root().add_child(st)
	st.size = Vector2(320.0, 240.0)
	return st


func _in_vp(h: Node3D, level: String, aspect := 16.0 / 9.0, sel: Variant = null) -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(320, int(320.0 / aspect))
	_root().add_child(vp)
	vp.add_child(h)
	h.call("setup", {"level": level, "sel": sel if sel != null else {"figure": "egg", "scheme": "original"}, "aspect": aspect})
	return vp


func test_stage_scale_and_stills_on_min() -> void:
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	assert_eq(HeroStage.SCALE, {"hi": 1.0, "mid": 0.75, "lo": 0.5, "min": 0.5}, "3D resolution per level (§3.4)")
	for lv in ["hi", "mid", "lo", "min"]:
		var st := _stage(lv)
		st.show_hero("veryhard", {"level": lv})
		assert_true(st.busy() and st.viewport() != null, "%s: a still starts by building the scene in its own viewport" % lv)
		if st.viewport() != null:
			assert_within(st.viewport().scaling_3d_scale, float(HeroStage.SCALE[lv]), 0.001, "%s: viewport 3D scale" % lv)
			assert_true(st.viewport().own_world_3d, "%s: the scene has its own world" % lv)
			assert_eq(st.viewport().render_target_update_mode, SubViewport.UPDATE_DISABLED, "%s: nothing renders until the still is shot" % lv)
		st.set_live(true)
		if lv == "min":
			assert_false(st.live, "min: set_live(true) keeps the stage still")
			assert_false(bool(st.counts()["live"]), "min: counts says not live")
		else:
			assert_true(st.live and st.hero() != null, "%s: set_live(true) builds a live scene" % lv)
			assert_true(bool(st.hero().get("active")), "%s: the live scene is active" % lv)
			var mode := st.viewport().render_target_update_mode
			if lv == "lo":
				assert_true(st.get_node_or_null("LoFrame") is Timer, "lo: a 33 ms timer paces the live hero (≤ 30 fps)")
				assert_ne(mode, SubViewport.UPDATE_ALWAYS, "lo: the live viewport is not drawn every frame")
			else:
				assert_eq(mode, SubViewport.UPDATE_WHEN_VISIBLE, "%s: the live viewport draws while visible" % lv)
			assert_true(int(st.counts()["draws_hint"]) > 0, "%s: counts reports the scene's meshes" % lv)
			st.set_live(false)
			assert_false(st.live, "%s: set_live(false) goes back to a still" % lv)
		st.free()
	CampaignHeroes.test_dirs = PackedStringArray()


func test_stage_falls_back_from_broken_packs() -> void:
	CampaignHeroes.test_dirs = PackedStringArray([BROKEN])
	assert_eq(CampaignHeroes.pack_path("normal"), BROKEN + "/hero_normal.gd", "the broken fixture is found first")
	var h := CampaignHeroes.make("hard")
	assert_false(CampaignHeroes.is_pack(h), "a pack scene that is not a Node3D is refused by the loader")
	h.free()
	var st := _stage("mid")
	st.show_hero("normal", {"level": "mid"})
	assert_true(st.fell_back and st.hero() != null and not CampaignHeroes.is_pack(st.hero()),
		"a pack scene that sets up no camera is replaced by the built-in one")
	assert_true(st.viewport().get_camera_3d() != null and st.hero().is_ancestor_of(st.viewport().get_camera_3d()),
		"the built-in replacement owns the viewport's camera")
	print("      (expected: the engine prints a script error from the broken veryhard fixture next)")
	st.show_hero("veryhard", {"level": "mid"})
	assert_true(st.fell_back and st.hero() != null and not CampaignHeroes.is_pack(st.hero()),
		"a pack scene whose setup fails half-way is replaced by the built-in one (the screen goes on)")
	assert_eq(st.viewport().get_child_count(), 1, "the broken scene is gone from the viewport")
	st.free()
	CampaignHeroes.test_dirs = PackedStringArray()
	assert_true(CampaignHeroes.make_builtin("easy") == null, "make_builtin: unknown id gives null")


func test_hero_light_sets_the_figure_uniforms() -> void:
	var file_mat := load(HeroLight.SHADER.replace(".gdshader", "_material.tres")) as ShaderMaterial
	var root := Node3D.new()
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	a.material_override = file_mat
	root.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.material_override = file_mat
	root.add_child(b)
	var c := MeshInstance3D.new()
	c.mesh = BoxMesh.new()
	c.material_override = StandardMaterial3D.new()
	root.add_child(c)
	var n := HeroLight.apply(root, Vector3(0, 1, 0), Color(1.0, 0.5, 0.25), Color(0.1, 0.2, 0.3))
	assert_eq(n, 1, "one shared file material → one copy set (meshes that shared it share the copy)")
	assert_true(a.material_override != file_mat and a.material_override == b.material_override, "the file material is not changed in place")
	var m := a.material_override as ShaderMaterial
	assert_eq(m.get_shader_parameter("sun_dir"), Vector3(0, 1, 0), "sun_dir")
	assert_eq(m.get_shader_parameter("sun_colour"), Vector3(1.0, 0.5, 0.25), "sun_colour")
	assert_eq(m.get_shader_parameter("ambient_colour"), Vector3(0.1, 0.2, 0.3), "ambient_colour")
	assert_eq(m.get_shader_parameter("per_vertex"), false, "per-pixel light in the show scenes")
	assert_true(file_mat.get_shader_parameter("sun_dir") != Vector3(0, 1, 0), "the shared file material keeps its light")
	assert_true(c.material_override is StandardMaterial3D, "other materials are left alone")
	assert_eq(HeroLight.apply(root, Vector3(0, 1, 0), Color.WHITE, Color.BLACK), 1, "a second call reuses the copy")
	assert_eq(HeroLight.apply(null, Vector3.UP, Color.WHITE, Color.BLACK), 0, "null root → 0")
	root.free()
	if KitLibrary.has_kit("knight"):
		var k := HeroKit.kit_figure(PackedStringArray(["knight"]), "walker")
		var vp := SubViewport.new()
		_root().add_child(vp)
		vp.add_child(k)
		HeroKit.setup_figure(k, 1)
		assert_true(HeroLight.apply(k, Vector3.UP, Color.WHITE, Color.BLACK) >= 1, "a kit figure's own material takes the light")
		vp.free()


func test_builtin_scenes_stage_and_levels() -> void:
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	for id in CampaignHeroes.IDS:
		for lv in ["hi", "mid", "lo", "min"]:
			var h := CampaignHeroes.make(id)
			var vp := _in_vp(h, lv)
			assert_true(h.has_method("set_aspect") and h.has_method("animated"), "%s: optional set_aspect / animated" % id)
			var moves: bool = h.call("animated")
			var want: bool = lv == "hi" or lv == "mid" or (lv == "lo" and (id == "veryhard" or id == "catastrophe"))
			assert_eq(moves, want, "%s on %s: animated() = %s" % [id, lv, str(want)])
			h.call("set_active", true)
			assert_eq(h.is_processing(), want, "%s on %s: processes only when it moves" % [id, lv])
			h.call("set_active", false)
			assert_false(h.is_processing(), "%s on %s: inactive = no processing" % [id, lv])
			for f in h.get("figs"):
				var ap: AnimationPlayer = (f as Node).call("animation_player") if (f as Node).has_method("animation_player") else null
				if ap != null:
					assert_eq(ap.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
						"%s: figure animation is stepped by the scene (never runs on its own)" % id)
					break
			h.call("set_aspect", 9.0 / 16.0)
			assert_true(h.get("camera") is Camera3D and (h.get("camera") as Camera3D).keep_aspect == Camera3D.KEEP_WIDTH,
				"%s: a tall card keeps the width (§3.2)" % id)
			h.call("set_aspect", 16.0 / 9.0)
			assert_eq((h.get("camera") as Camera3D).keep_aspect, Camera3D.KEEP_HEIGHT, "%s: a wide card keeps the height" % id)
			vp.free()
	CampaignHeroes.test_dirs = PackedStringArray()


func test_builtin_scenes_are_repeatable() -> void:
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	for id in ["veryhard", "catastrophe"]:
		var h := CampaignHeroes.make(id)
		var vp := _in_vp(h, "hi")
		var snap := func() -> Array:
			var out := []
			for n in (h.get("aliens") if id == "veryhard" else h.get("row")):
				out.append([(n as Node3D).position.snapped(Vector3.ONE * 0.0001), (n as Node3D).visible])
			if id == "veryhard":
				out.append(snappedf((h.get("knight") as Node3D).rotation.y, 0.0001))
			return out
		h.call("seek", 1.62)
		var a: Array = snap.call()
		h.call("seek", 0.3)
		h.call("seek", 1.62)
		assert_eq(snap.call(), a, "%s: seek gives the same pose every time" % id)
		vp.free()
	var cat := CampaignHeroes.make("catastrophe")
	var vp2 := _in_vp(cat, "min")
	var row: Array = cat.get("row")
	assert_eq(row.size(), 7, "catastrophe: seven figures in the row")
	assert_true(row.all(func(n: Node3D) -> bool: return n.visible), "catastrophe poster: the whole row is visible")
	assert_true(not KitLibrary.has_kit("cxl") or str((row[3] as Node).name) == "Fig_cxl", "catastrophe: cxl stands in the centre")
	var mid: float = (row[3] as Node3D).position.z
	assert_true(row.all(func(n: Node3D) -> bool: return n.position.z <= mid + 0.001), "catastrophe: the centre stands forward")
	cat.call("seek", 0.0)
	assert_false(row.any(func(n: Node3D) -> bool: return n.visible), "catastrophe: at t = 0 nobody has appeared yet")
	cat.call("seek", 0.4)
	assert_eq(row.filter(func(n: Node3D) -> bool: return n.visible).size(), 2, "catastrophe: 0.35 s apart (two by 0.4 s)")
	vp2.free()
	var vh := CampaignHeroes.make("veryhard")
	var vp3 := _in_vp(vh, "lo")
	assert_eq((vh.get("aliens") as Array).size(), 3, "veryhard on lo: three aliens")
	vp3.free()
	vh = CampaignHeroes.make("veryhard")
	vp3 = _in_vp(vh, "hi")
	assert_eq((vh.get("aliens") as Array).size(), 4, "veryhard on hi: four aliens")
	var kn: Node3D = vh.get("knight")
	assert_true(not KitLibrary.has_kit("pike_halb") or str(kn.name) == "Fig_pike_halb", "veryhard: the halberd kit", kn.name)
	vh.call("seek", 1.3 + 0.45 + 0.05)
	var turn := fposmod(kn.rotation.y - 0.25, TAU)
	assert_within(minf(turn, TAU - turn), 0.0, 0.01, "veryhard: one full turn by the end of the spin")
	assert_within(kn.rotation.y, 0.25 - TAU, 0.01, "veryhard: the spin is a whole 360°")
	vp3.free()
	CampaignHeroes.test_dirs = PackedStringArray()


func test_normal_shows_the_selected_figure() -> void:
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	var h := CampaignHeroes.make("normal")
	var vp := _in_vp(h, "mid", 16.0 / 9.0, {"figure": "egg", "scheme": "original"})
	assert_true(h.get("figure") is EggGunner, "egg selected → the egg gunner")
	vp.free()
	if KitLibrary.has_kit("kblade"):
		h = CampaignHeroes.make("normal")
		vp = _in_vp(h, "mid", 16.0 / 9.0, {"figure": "kit_kblade", "scheme": "blue"})
		var f: Node3D = h.get("figure")
		assert_true(f is KitFighter and str(f.get("walk_kit")) == "kblade", "a kit selected → that kit (the arena's factory)")
		var sc: Array = f.call("scheme")
		assert_eq(sc, [Figures.scheme("blue")["primary"], Figures.scheme("blue")["secondary"]], "…in the selected scheme")
		vp.free()
	Figures.pack_list = FIG_LIST
	h = CampaignHeroes.make("normal")
	vp = _in_vp(h, "mid", 16.0 / 9.0, {"figure": "prim", "scheme": "pink"})
	var p: Node3D = h.get("figure")
	assert_true(p != null and str((p.get_script() as Script).resource_path).ends_with("prim_figure.gd"), "a pack figure selected → that figure")
	h.call("set_active", true)
	h.call("set_active", false)
	assert_eq(p.process_mode, Node.PROCESS_MODE_DISABLED, "a figure the scene does not step is switched off while inactive")
	vp.free()
	Figures.pack_list = Figures.PACK_LIST
	CampaignHeroes.test_dirs = PackedStringArray()


func test_catastrophe_music() -> void:
	CampaignHeroes.test_dirs = PackedStringArray([FIX, FIX_ARENA])
	assert_eq(CampaignHeroes.music_path(), FIX_ARENA + "/catastrophe.ogg", "the fixture music stand-in is found")
	for lv in ["hi", "min"]:
		var h := CampaignHeroes.make("catastrophe")
		var vp := _in_vp(h, lv)
		var mp: AudioStreamPlayer = h.call("music")
		assert_true(mp != null and mp.stream != null, "%s: the music player has the pack's track" % lv)
		h.call("set_active", true)
		assert_eq(mp.playing, lv != "min", "%s: set_active(true) %s" % [lv, "plays it" if lv != "min" else "does not autoplay on min"])
		h.call("set_active", false)
		assert_false(mp.playing, "%s: set_active(false) stops it" % lv)
		vp.free()
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	var q := CampaignHeroes.make("catastrophe")
	var vq := _in_vp(q, "hi")
	assert_true((q.call("music") as AudioStreamPlayer).stream == null, "no track: silent")
	q.call("set_active", true)
	assert_false((q.call("music") as AudioStreamPlayer).playing, "no track: nothing plays")
	vq.free()
	CampaignHeroes.test_dirs = PackedStringArray()
