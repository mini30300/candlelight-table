extends "res://tests/testing.gd"
## The infantry soldier preview (scenes/arena/soldier_figure.gd, assets/figures/soldier/, Figures kind "builtin").
## Registry and i18n: one "soldier" entry after the egg and before the kits, Thai and English names (the Thai one in the
## dictionary), no schemes, never the default, a pack entry cannot take its id, the selection keeps the old format.
## Contract: Figures.DECK_API for the deck and ArenaActors.FIGURE_API (twelve methods) plus clip_event for the player,
## the optional hooks (deck_speeds, H6, H8, H9 false). Assets: the 23 game bones with their parents, every helper bone has
## a driver rule, every blend shape is known, one surface per level within the triangle budget, min skinned to game bones
## only, no blend shapes on lo/min, an unshaded body shader without TIME, every dependency inside the soldier folder.
## Clips: the soldier's copy keeps every mapped clip and its metadata, its wrists are eased (twist and bend within
## limits, hands still, no hand position tracks) and the shared humanoid.res is untouched. Behaviour (manual clock):
## walk/run rates, still on min within 10 frames, the deck figure still on lo and min, the arena player looping on lo,
## clip events, the aim pose and muzzle, backwards walk, helpers and correctives per level, flash, the hero light on the
## figure's own material only.

const STORE := "user://test_soldier.cfg"
const NONE := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DIR := "res://assets/figures/soldier/"
const LIB := "res://assets/anim/humanoid.res"
const DT := 1.0 / 30.0
const TMP_PACK := "user://test_soldier_pack/"
## SKRIG (assets/kits/CONTRACT.md §1): bone → parent
const PARENTS := {"pelvis": "", "spine": "pelvis", "chest": "spine", "neck": "chest", "head": "neck", "shoulderL": "chest",
	"elbowL": "shoulderL", "wristL": "elbowL", "handL": "wristL", "shoulderR": "chest", "elbowR": "shoulderR",
	"wristR": "elbowR", "handR": "wristR", "hipL": "pelvis", "kneeL": "hipL", "ankleL": "kneeL", "toeL": "ankleL",
	"heelL": "ankleL", "hipR": "pelvis", "kneeR": "hipR", "ankleR": "kneeR", "toeR": "ankleR", "heelR": "ankleR"}

var _shots := 0
var _thuds := 0


func setup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = STORE
	Figures.pack_list = NONE
	Figures.pack_manifest = NONE_PACK


func _reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = ""
	Figures.pack_list = Figures.PACK_LIST
	Figures.pack_manifest = ArenaActors.PACK_MANIFEST


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _new_fig(role: StringName, level: String, manual := true) -> Node3D:
	var f: Node3D = (load(SCRIPT) as GDScript).new()
	_tree().root.add_child(f)
	if manual:
		f.call("set_manual", true)
	f.call("setup", {"role": role, "level": level, "team_colour": Color.BLUE, "seed": 7})
	return f


func _steps(f: Node3D, n: int) -> void:
	for i in n:
		f.call("step", DT)


func test_registry() -> void:
	setup()
	var l := Figures.list()
	var ids: Array = l.map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_eq(ids.count("soldier"), 1, "the soldier is listed once")
	var e := Figures.entry("soldier")
	assert_eq(str(e.get("kind", "")), "builtin", "its kind is builtin")
	assert_false(bool(e.get("schemes", true)), "it keeps its own colours (no schemes)")
	assert_eq(e.get("name", {}), {"th": "ทหารราบ (ทดลอง)", "en": "Infantry (preview)"}, "Thai and English names")
	assert_eq(I18n.lookup("ทหารราบ (ทดลอง)"), "Infantry (preview)", "the Thai name translates in the dictionary")
	var first_kit := ids.find(ids.filter(func(i: String) -> bool: return i.begins_with("kit_"))[0]) if ids.any(func(i: String) -> bool: return i.begins_with("kit_")) else ids.size()
	assert_true(ids.find("egg") < ids.find("soldier") and ids.find("soldier") < first_kit, "after the egg, before the kits", str(ids))
	assert_eq(Figures.default_figure(), "egg", "not the default: the egg stays the default")
	assert_eq(Figures.selected()["figure"], "egg", "nothing chosen: the egg")
	Figures.select("soldier", "original")
	assert_eq(Figures.selected(), {"figure": "soldier", "scheme": "original"}, "the soldier can be selected")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(STORE), OK, "written to the settings file")
	assert_eq(str(cfg.get_value("figure", "figure", "")), "soldier", "the same [figure] format, only the new id")
	assert_eq(Figures.builtin_figure("soldier"), SCRIPT, "builtin_figure() names the script")
	assert_eq(Figures.builtin_figure("egg"), "", "the egg is not a built-in figure")
	var w := Figures.make(&"soldier", &"mid")
	assert_true(w != null and (w.get_script() as Script).resource_path == SCRIPT, "make() builds the soldier for the deck")
	if w != null:
		w.free()
	var sel := {"figure": "soldier", "scheme": "red"}
	var p := ArenaActors.player_figure(sel)
	assert_true(p != null and (p.get_script() as Script).resource_path == SCRIPT, "the arena and campaign player is the soldier")
	if p != null:
		p.free()
	assert_eq(ArenaActors.scheme_of(sel), "original", "no scheme reaches it (its own skin)")
	assert_eq(ArenaActors.player_preload(sel), SCRIPT, "the arena door preloads its script")
	_reset()


func test_pack_cannot_take_the_id() -> void:
	setup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_PACK))
	var src := "extends Node3D\nfunc setup(_o: Dictionary) -> void:\n\tpass\nfunc set_weapon(_i: StringName) -> void:\n\tpass\n" \
		+ "func play(_l: StringName, _s: float = 1.0) -> float:\n\treturn 0.0\nfunc set_move(_s: float, _r: bool) -> void:\n\tpass\n" \
		+ "func apply_level(_l: String) -> void:\n\tpass\n"
	var f := FileAccess.open(TMP_PACK + "fig.gd", FileAccess.WRITE)
	f.store_string(src)
	f.close()
	f = FileAccess.open(TMP_PACK + "figures.json", FileAccess.WRITE)
	f.store_string(JSON.stringify([{"id": "soldier", "name": {"th": "ปลอม", "en": "Fake"}, "figure": "fig.gd"},
		{"id": "other", "name": {"th": "อีกตัว", "en": "Other"}, "figure": "fig.gd"}]))
	f.close()
	Figures.pack_list = TMP_PACK + "figures.json"
	var ids: Array = Figures.list().map(func(e: Dictionary) -> String: return str(e["id"]))
	assert_true(ids.has("other"), "a valid pack entry is listed", str(ids))
	assert_eq(ids.count("soldier"), 1, "a pack entry cannot take the built-in id")
	assert_eq(str(Figures.entry("soldier")["kind"]), "builtin", "…which stays the built-in figure")
	for n in ["fig.gd", "figures.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PACK + n))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PACK))
	_reset()


func test_contract() -> void:
	var f := _new_fig(&"player", "mid")
	assert_eq(ArenaActors.FIGURE_API.size(), 12, "FIGURE_API still has twelve methods")
	assert_eq(ArenaActors.missing_api(f), PackedStringArray(), "the soldier has all twelve FIGURE_API methods")
	assert_true(f.has_signal("clip_event"), "…and the clip_event signal")
	var miss := PackedStringArray()
	for m in Figures.DECK_API:
		if not f.has_method(m):
			miss.append(m)
	assert_eq(miss, PackedStringArray(), "the deck API (%s)" % ", ".join(Figures.DECK_API))
	for m in ["deck_speeds", "set_move_dir", "begin_dodge", "uses_strafe", "set_light"]:
		assert_true(f.has_method(m), "optional hook " + m)
	assert_false(bool(f.call("uses_strafe")), "H9 false: A/D turn it (no side-step clips)")
	assert_false(f.has_method("apply_scheme") or f.has_method("apply_palette"), "no H10/H11: it keeps its own colours")
	var m: Dictionary = f.call("metrics")
	assert_true(float(m["height"]) > 1.7 and float(m["height"]) < 1.85, "metrics: height %.3f m (1.78 m man)" % float(m["height"]))
	assert_within(float(m["radius"]), 0.35, 0.001, "metrics: the player's radius")
	assert_true(float(m["eye"]) > float(m["shoulder"]) and float(m["eye"]) < float(m["height"]), "metrics: eye above shoulder")
	var cn: Dictionary = f.call("clip_names")
	for k in ["idle", "walk", "run", "fire", "punch", "swing", "hit", "die"]:
		assert_true(cn.has(k) and (cn[k] as PackedStringArray).size() > 0, "player clip " + k)
	for k in ["head", "chest", "hand_r", "hand_l"]:
		assert_true(f.call("anchor", StringName(k)) is BoneAttachment3D, "anchor " + k)
	assert_true(f.call("anchor", &"tail") == null, "an unknown anchor is null")
	f.free()
	var en := _new_fig(&"enemy", "mid")
	assert_true((en.call("clip_names") as Dictionary).has("attack"), "enemy role: an attack clip")
	assert_true(en.call("muzzle") == null, "enemy role: no muzzle")
	en.free()


func test_assets() -> void:
	var ps := load(DIR + "rig.tscn") as PackedScene
	assert_true(ps != null, "rig.tscn loads")
	if ps == null:
		return
	var root := ps.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	assert_true(sk != null, "rig.tscn holds a Skeleton3D named Skeleton3D")
	if sk == null:
		root.free()
		return
	for b in PARENTS:
		var i := sk.find_bone(b)
		var want := str(PARENTS[b])
		var par := sk.get_bone_name(sk.get_bone_parent(i)) if i >= 0 and sk.get_bone_parent(i) >= 0 else ""
		assert_true(i >= 0 and par == want, "game bone %s under %s" % [b, want if want != "" else "the root"], par)
	assert_true(sk.motion_scale > 1.0 and sk.motion_scale < 1.3, "motion_scale = S %.4f (taller than the 1.6 m rig)" % sk.motion_scale)
	root.free()
	var S: GDScript = load(SCRIPT)
	var rules: Array = S.call("helper_rules")
	assert_true(rules.size() >= 10, "%d helper bones" % rules.size())
	for r: Dictionary in rules:
		assert_true(str(r["kind"]) != "", "helper %s (under %s) has a driver rule" % [r["bone"], r["parent"]], str(r))
	var skin := load(DIR + "skin.res") as Skin
	var budget: Dictionary = S.get("BUDGET")
	var game: PackedStringArray = S.get("GAME_BONES")
	for lv in ["hi", "mid", "lo", "min", "crowd"]:
		var m: ArrayMesh = S.call("body_mesh", lv)
		if lv == "crowd" and m == null:
			continue
		assert_true(m != null, "body_%s.res loads" % lv)
		if m == null:
			continue
		var arr := m.surface_get_arrays(0)
		var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_eq(m.get_surface_count(), 1, "%s: one surface (one draw)" % lv)
		assert_true(tris > 0 and tris <= int(budget[lv]), "%s: %d triangles within %d" % [lv, tris, int(budget[lv])])
		for i in m.get_blend_shape_count():
			var nm := String(m.get_blend_shape_name(i))
			assert_true(bool(S.call("shape_known", nm)), "%s: blend shape %s has a driver" % [lv, nm])
		if lv == "lo" or lv == "min" or lv == "crowd":
			assert_eq(m.get_blend_shape_count(), 0, "%s: no blend shapes (no extra pass on weak levels)" % lv)
		var aabb := m.get_aabb()
		assert_true(absf(aabb.position.y) < 0.012, "%s: the soles stand on the floor (%.1f mm)" % [lv, aabb.position.y * 1000.0])
		if lv == "min" or lv == "crowd":
			# ระดับต่ำสุดผูกกับกระดูกของเกมเท่านั้น: ไม่ต้องขับกระดูกช่วย (ไม่มีงานต่อเฟรม)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var extra := {}
			for k in bones.size():
				if wts[k] > 0.0001:
					var bn := String(skin.get_bind_name(bones[k]))
					if not game.has(bn):
						extra[bn] = true
			assert_true(extra.is_empty(), "%s: skinned to the 23 game bones only" % lv, str(extra.keys()))
	var hi: ArrayMesh = S.call("body_mesh", "hi")
	var mn: ArrayMesh = S.call("body_mesh", "min")
	if hi != null and mn != null:
		assert_true(absf(hi.get_aabb().end.y - mn.get_aabb().end.y) < 0.02, "hi and min stand the same height (%.1f mm apart)"
			% (absf(hi.get_aabb().end.y - mn.get_aabb().end.y) * 1000.0))
	var code := FileAccess.get_file_as_string(DIR + "body.gdshader")
	var bare := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/").sub(code, "", true)
	assert_true(RegEx.create_from_string("render_mode[^;]*\\bunshaded\\b").search(bare) != null, "the body shader is unshaded (computes its own light)")
	assert_true(RegEx.create_from_string("\\bTIME\\b").search(bare) == null, "…and uses no TIME (comments aside)")
	var mat := load(DIR + "body_material.tres") as ShaderMaterial
	assert_true(mat != null and mat.shader != null and mat.shader.resource_path == DIR + "body.gdshader", "the material uses that shader")
	for f in ["rig.tscn", "skin.res", "body_hi.res", "body_mid.res", "body_lo.res", "body_min.res", "body_material.tres"]:
		for d in ResourceLoader.get_dependencies(DIR + f):
			var path := d.get_slice("::", d.get_slice_count("::") - 1)
			assert_true(path.begins_with(DIR), "%s depends only on the soldier folder" % f, d)


func test_clips() -> void:
	var S: GDScript = load(SCRIPT)
	var src := load(LIB) as AnimationLibrary
	assert_true(src != null, "humanoid.res is there (run godot/tools/kits.sh)")
	var lib: AnimationLibrary = S.call("clip_library")
	assert_true(lib != null, "the soldier's clips build")
	if lib == null or src == null:
		return
	var names := {}
	for m in [S.get("PLAYER_CLIPS"), S.get("ENEMY_CLIPS")]:
		for k in m:
			for n in m[k]:
				names[n] = true
	for n in names:
		assert_true(lib.has_animation(n), "the soldier has clip " + n)
	if str(S.call("clip_source")) == LIB:
		for n in names:
			var a := lib.get_animation(n)
			var o := src.get_animation(n)
			assert_eq(a.get_meta("events", []), o.get_meta("events", []), n + ": events kept")
			assert_eq(float(a.get_meta("speed", 0.0)), float(o.get_meta("speed", 0.0)), n + ": speed kept")
			var worst_tw := 0.0
			var worst_sw := 0.0
			var hand := 0.0
			for sd in ["L", "R"]:
				var tw := a.find_track(NodePath("Skeleton3D:wrist" + sd), Animation.TYPE_ROTATION_3D)
				for k in a.track_get_key_count(tw):
					var q: Quaternion = a.track_get_key_value(tw, k)
					var t := absf(float(S.call("twist_deg", q)))
					var sw := q * Quaternion(Vector3.UP, deg_to_rad(float(S.call("twist_deg", q)))).inverse()
					worst_tw = maxf(worst_tw, t)
					worst_sw = maxf(worst_sw, float(S.call("turn_deg", sw)))
				var th := a.find_track(NodePath("Skeleton3D:hand" + sd), Animation.TYPE_ROTATION_3D)
				for k in a.track_get_key_count(th):
					hand = maxf(hand, float(S.call("turn_deg", a.track_get_key_value(th, k))))
				for b in ["wrist" + sd, "hand" + sd]:
					assert_eq(a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_POSITION_3D), -1, "%s: no %s position track" % [n, b])
			assert_true(worst_tw <= 45.5 and worst_sw <= 45.5 and hand < 0.01,
				"%s: wrists eased (twist %.0f°, bend %.0f°, hand %.1f°)" % [n, worst_tw, worst_sw, hand])
		# ชุดท่าที่ใช้ร่วม (ชุดโมเดลทุกตัว) ไม่ถูกแตะ: กำปั้นใน bash_0 ยังหมุนเกือบรอบ
		var b0 := src.get_animation(&"bash_0")
		var hr := b0.find_track(NodePath("Skeleton3D:handR"), Animation.TYPE_ROTATION_3D)
		var big := 0.0
		for k in b0.track_get_key_count(hr):
			big = maxf(big, float(S.call("turn_deg", b0.track_get_key_value(hr, k))))
		assert_true(big > 120.0, "humanoid.res itself is untouched (bash_0 hand still turns %.0f°)" % big)
	# limit_turn: inside the limits nothing changes, outside it is clamped
	var small := Quaternion(Vector3(1, 0.3, 0).normalized(), deg_to_rad(20.0))
	assert_true((S.call("limit_turn", small, 45.0, 45.0) as Quaternion).is_equal_approx(small), "limit_turn keeps a small turn")
	var twisted := Quaternion(Vector3.UP, deg_to_rad(150.0))
	assert_within(absf(float(S.call("twist_deg", S.call("limit_turn", twisted, 45.0, 45.0)))), 45.0, 0.01, "limit_turn clamps a 150° twist to 45°")


func test_moves_and_still_rules() -> void:
	var S: GDScript = load(SCRIPT)
	var lib: AnimationLibrary = S.call("clip_library")
	if lib == null:
		assert_true(false, "the soldier's clips build")
		return
	var f := _new_fig(&"player", "mid")
	var ap: AnimationPlayer = f.call("animation_player")
	var sk: Skeleton3D = f.call("skeleton")
	_steps(f, 2)
	assert_true(ap.is_playing() and String(ap.current_animation) == "humanoid/idle", "set up: idle plays")
	var sc := sk.motion_scale
	f.call("set_move", 3.0, false)
	_steps(f, 2)
	var want := 3.0 / (float(lib.get_animation(&"walk").get_meta("speed")) * sc)
	assert_true(String(ap.current_animation) == "humanoid/walk" and absf(ap.speed_scale - want) < 0.001,
		"3 m/s: walk at rate %.3f (speed / clip speed × S)" % ap.speed_scale)
	f.call("set_move", 5.0, true)
	_steps(f, 2)
	want = 5.0 / (float(lib.get_animation(&"run").get_meta("speed")) * sc)
	assert_true(String(ap.current_animation) == "humanoid/run" and absf(ap.speed_scale - want) < 0.001,
		"5 m/s running: run at rate %.3f" % ap.speed_scale)
	f.call("set_move_dir", Vector2(0, -1), 2.0, false)
	_steps(f, 2)
	assert_true(bool(f.call("moving_back")) and String(ap.current_animation) == "humanoid/walk", "H6 backwards: walk played in reverse")
	f.call("set_move_dir", Vector2(0, 1), 0.0, false)
	_steps(f, 2)
	assert_eq(String(ap.current_animation), "humanoid/idle", "standing: idle")
	# arena player: lo keeps its idle loop, min holds a still pose within 10 frames
	f.call("apply_level", "lo")
	_steps(f, 12)
	assert_true(ap.is_playing() and not bool(f.call("is_still")), "player on lo: the idle loop may play (PACK_SPEC §3.2)")
	f.call("apply_level", "min")
	f.call("set_move", 1.5, false)
	_steps(f, 3)
	f.call("set_move", 0.0, false)
	var n := 0
	while n < 10 and not bool(f.call("is_still")):
		f.call("step", DT)
		n += 1
	assert_true(bool(f.call("is_still")) and not ap.is_playing(), "player on min: still within 10 frames of stopping (%d)" % n)
	assert_false(f.is_processing() or f.is_physics_processing(), "no _process / _physics_process on the figure")
	f.call("apply_level", "mid")
	assert_true(ap.is_playing() and not bool(f.call("is_still")), "back on mid: the idle loop plays again")
	f.free()
	# deck: still on lo and on min
	for lv in ["lo", "min"]:
		var d := _new_fig(&"deck", lv)
		var dap: AnimationPlayer = d.call("animation_player")
		d.call("set_weapon", &"none")
		d.call("play", &"idle", 1.0)
		d.call("set_move", 0.0, false)
		var k := 0
		while k < 10 and not bool(d.call("is_still")):
			d.call("step", DT)
			k += 1
		assert_true(bool(d.call("is_still")) and not dap.is_playing(), "deck on %s: still within 10 frames (%d)" % [lv, k])
		d.call("set_move", 1.8, false)
		d.call("step", DT)
		assert_true(dap.is_playing() and String(dap.current_animation) == "humanoid/walk", "deck on %s: walking plays walk" % lv)
		d.free()
	var dm := _new_fig(&"deck", "mid")
	_steps(dm, 12)
	assert_true((dm.call("animation_player") as AnimationPlayer).is_playing(), "deck on mid: the idle loop plays")
	var sp: Vector2 = dm.call("deck_speeds")
	var ws := float(lib.get_animation(&"walk").get_meta("speed")) * sc * 1.4
	assert_true(absf(sp.x - ws) < 0.001 and sp.x >= 0.5 and sp.y <= 6.0 and sp.y > sp.x, "deck speeds %s = clip speed × S × 1.4" % str(sp))
	dm.free()


func test_actions_and_aim() -> void:
	var f := _new_fig(&"player", "mid")
	f.connect("clip_event", _on_event)
	_shots = 0
	_thuds = 0
	var d := float(f.call("play", &"punch", 1.0))
	assert_true(d > 0.3 and d < 0.6, "punch: a %.2f s blow (bash at 1.8×, under the 0.55 s repeat)" % d)
	_steps(f, int(ceil(d / DT)) + 2)
	assert_true(_shots >= 1, "the punch emits clip_event shot (%d)" % _shots)
	var s := float(f.call("play", &"swing", 1.0))
	assert_true(s > 0.3 and s < 0.8, "swing: a %.2f s thrust" % s)
	assert_within(float(f.call("play", &"fire", 1.0)), 0.16, 0.001, "fire: a 0.16 s kick (procedural recoil)")
	assert_eq(float(f.call("play", &"reload", 1.0)), 0.0, "no reload clip: the actor uses its timer")
	_steps(f, int(ceil(s / DT)) + 4)
	f.call("set_weapon", &"gun")
	f.call("set_aim", -0.2)
	_steps(f, 3)
	assert_true(bool(f.call("aiming")), "gun in hand: the upper body takes the aim pose")
	var mz: Node3D = f.call("muzzle")
	var chest: Node3D = f.call("anchor", &"chest")
	var rel := mz.global_position - chest.global_position
	assert_true(rel.length() < 1.3 and rel.length() > 0.05 and rel.z > 0.2, "the muzzle is in front of the hands (%.2f m from the chest)" % rel.length(), str(rel))
	var dl := float(f.call("play", &"die", 1.0))
	_steps(f, int(ceil(dl / DT)) + 3)
	assert_true(_thuds >= 1, "die emits clip_event thud")
	var ap: AnimationPlayer = f.call("animation_player")
	f.call("set_move", 3.0, false)
	_steps(f, 2)
	assert_true(not String(ap.current_animation).ends_with("/walk") and not String(ap.current_animation).ends_with("/idle"),
		"dead: set_move does not get it up again", String(ap.current_animation))
	f.call("set_flash", 1.0)
	assert_true((f.call("body") as MeshInstance3D).material_overlay != null, "hit flash: an overlay")
	f.call("set_flash", 0.0)
	assert_true((f.call("body") as MeshInstance3D).material_overlay == null, "flash off: no overlay (no extra pass)")
	f.free()


func test_drivers_per_level() -> void:
	var f := _new_fig(&"player", "hi")
	var sk: Skeleton3D = f.call("skeleton")
	_steps(f, 3)
	var clav := sk.find_bone("clavicleL")
	var half := sk.find_bone("elbow_halfL")
	assert_true(not sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY), "hi: helper bones follow the joints")
	assert_true(int(f.call("active_shapes")) > 0, "hi: correctives are active in idle (%d)" % int(f.call("active_shapes")))
	f.call("apply_level", "lo")
	_steps(f, 3)
	assert_eq(int(f.call("active_shapes")), 0, "lo: no correctives")
	assert_true(not sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY), "lo: helpers still driven")
	f.call("apply_level", "min")
	_steps(f, 3)
	assert_true(sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY)
		and sk.get_bone_pose_rotation(clav).is_equal_approx(Quaternion.IDENTITY), "min: helpers rest (nothing driven)")
	f.free()
	# shape_weights: identity arms hang down → shoulder_down is the strongest shoulder key, a bent knee flexes
	var S: GDScript = load(SCRIPT)
	var rot := {}
	for b in ["shoulderL", "shoulderR", "elbowL", "elbowR", "hipL", "hipR", "kneeL", "kneeR"]:
		rot[b] = Quaternion.IDENTITY
	rot["kneeL"] = Quaternion(Vector3.RIGHT, deg_to_rad(120.0))
	var w: Dictionary = S.call("shape_weights", rot)
	assert_within(float(w["knee_flexL"]), 1.0, 0.001, "a 120° knee gives knee_flex 1")
	assert_within(float(w["knee_flexR"]), 0.0, 0.001, "a straight knee gives 0")
	assert_true(float(w["shoulder_downL"]) > float(w["shoulder_upL"]), "hanging arms: shoulder_down over shoulder_up")


func test_hero_light_on_own_material() -> void:
	var a := _new_fig(&"player", "lo")
	var b := _new_fig(&"player", "lo")
	var shared := (b.call("body") as MeshInstance3D).material_override
	var n := HeroLight.apply(a, Vector3(0, 1, 0.15), Color(0.98, 0.9, 0.78), Color(0.15, 0.15, 0.16))
	var ma := (a.call("body") as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(n, 1, "HeroLight hands the scene light to the figure (set_light)")
	assert_true(ma != shared and (ma.get_shader_parameter("sun_dir") as Vector3).is_equal_approx(Vector3(0, 1, 0.15)), "the figure gets its own lit copy")
	assert_false(bool(ma.get_shader_parameter("per_vertex")), "per pixel in the card")
	assert_true((b.call("body") as MeshInstance3D).material_override == shared, "the other soldier keeps the shared material")
	a.free()
	b.free()


func _on_event(kind: StringName) -> void:
	if kind == &"shot":
		_shots += 1
	elif kind == &"thud":
		_thuds += 1
