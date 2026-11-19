extends "res://tests/testing.gd"
## The infantry soldier preview (scenes/arena/soldier_figure.gd, assets/figures/soldier/, Figures kind "builtin").
## Registry and i18n: one "soldier" entry after the egg and before the kits, Thai and English names (the Thai one in the
## dictionary), no schemes, never the default, a pack entry cannot take its id, the selection keeps the old format.
## Contract: Figures.DECK_API for the deck and ArenaActors.FIGURE_API (twelve methods) plus clip_event for the player,
## the optional hooks (deck_speeds, H6, H8, H9 false). Assets, for the base body (assets/figures/soldier/) and each
## other body (assets/figures/soldier_<id>/, BODIES): the 23 game bones with their parents and every bone offset at the
## base offset × S / S(base), motion_scale = that body's S, every helper bone has a driver rule, one named bind per bone,
## every blend shape is known (the other bodies have none: helpers only), one surface per level within the triangle
## budget, min skinned to game bones only, no blend shapes on lo/min, an unshaded body shader without TIME, every
## dependency inside the body's own folder, and the folder sizes within BASE_CAP / VARIANT_CAP / ALL_CAP (the owner's
## 3 GB app target under GitHub's 2 GiB release-file limit, docs/ARCHITECTURE.md).
## Bodies: four more registry entries after "soldier" (Thai and English names, the English in the dictionary) whose
## figures carry their body id to the deck, the dressing room and the arena; each body plays at its own S (walk rate,
## deck speeds), stands its own height, drives helpers but no correctives, and two bodies side by side keep their own
## meshes and scales; a body chosen before setup (body_id, or setup's "body" after set_light / deck_speeds) gives that
## body's rig, S, skin, material and mesh, never a mix with the base body.
## Clips: every clip the request map names (SoldierFigure.clip_map: the soldier's own clips.res, else PLAYER_CLIPS /
## ENEMY_CLIPS) is in its library, every fallback name is in humanoid.res; the fallback copy keeps its metadata, its
## wrists are eased (twist and bend within limits, hands still, no hand position tracks) and the shared humanoid.res is
## untouched (the own library: tests/unit/test_soldier_clips.gd). Behaviour (manual clock): 3 m/s plays jog with the own
## clips (walk without them), 5 m/s run, deck speeds unchanged (humanoid walk/run speed × S × 1.4),
## still on min within 10 frames, the deck figure still on lo and min, the arena player looping on lo,
## clip events, the aim pose and muzzle, backwards walk, helpers and correctives per level, flash, the hero light on the
## figure's own material only.

const STORE := "user://test_soldier.cfg"
const NONE := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DIR := "res://assets/figures/soldier/"
## ขนาดโฟลเดอร์ (ไบต์): เป้าแอปของเจ้าของ 3 GB แต่ไฟล์ใน GitHub release ได้ไม่เกิน 2 GiB (ประตู APK ใน CI 1900 MB)
## ทหารทุกร่างรวมไม่เกิน ALL_CAP (~3 % ของเพดาน เหลือที่ให้ชุดอื่น) · ร่างหลัก (มี blend shape) ไม่เกิน BASE_CAP (ตอนนี้ 6.4 MB)
## · ร่างอื่นร่างละไม่เกิน VARIANT_CAP (ไม่มี blend shape ตอนนี้ ~1.2 MB) · ขึ้นเป้าแล้วแต่ร่างที่โตผิดปกติยังต้องลดก่อน
const BASE_CAP := 10000000
const VARIANT_CAP := 4000000
const ALL_CAP := 60000000
const FIGURES_DIR := "res://assets/figures/"
## ร่างอื่น (Figures.BUILTINS ที่มี body): id -> [body id, ชื่อไทย, ชื่ออังกฤษ, S = ส่วนสูง / 1.6]
## ชื่ออังกฤษย่อ (เดิม "Infantry man 2 / woman 1 ..." ยาวเกินปุ่มห้องแต่งตัว ถูกตัดกลางคำ)
const BODIES := {"soldier_m2": ["m2", "ทหารราบ ชาย 2 (ทดลอง)", "Infantry M2 (preview)", 1.1625],
	"soldier_m3": ["m3", "ทหารราบ ชาย 3 (ทดลอง)", "Infantry M3 (preview)", 1.0625],
	"soldier_f1": ["f1", "ทหารราบ หญิง 1 (ทดลอง)", "Infantry W1 (preview)", 1.0],
	"soldier_f2": ["f2", "ทหารราบ หญิง 2 (ทดลอง)", "Infantry W2 (preview)", 1.08125]}
const BASE_S := 1.1125
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


func _new_fig(role: StringName, level: String, manual := true, body := "") -> Node3D:
	var f: Node3D = (load(SCRIPT) as GDScript).new()
	_tree().root.add_child(f)
	if manual:
		f.call("set_manual", true)
	f.call("setup", {"role": role, "level": level, "team_colour": Color.BLUE, "seed": 7, "body": body})
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
	# ร่างอื่น: ต่อจากทหารราบตามลำดับ ก่อนชุดโมเดล · ชื่อไทย/อังกฤษ · ตัวที่ได้ถือ body_id ไปทุกที่ที่ร่างหลักไป
	var prev := ids.find("soldier")
	for id: String in BODIES:
		var b: Array = BODIES[id]
		var be := Figures.entry(id)
		assert_eq(str(be.get("kind", "")), "builtin", "%s: kind builtin" % id)
		assert_false(bool(be.get("schemes", true)), "%s: its own colours (no schemes)" % id)
		assert_eq(be.get("name", {}), {"th": b[1], "en": b[2]}, "%s: Thai and English names" % id)
		assert_eq(I18n.lookup(str(b[1])), str(b[2]), "%s: the Thai name translates in the dictionary" % id)
		assert_true(ids.find(id) == prev + 1, "%s: listed right after %s" % [id, ids[prev] if prev >= 0 else "?"], str(ids))
		prev = ids.find(id)
		assert_eq(Figures.builtin_figure(id), SCRIPT, "%s: the soldier script" % id)
		var bw := Figures.make(StringName(id), &"mid")
		assert_true(bw != null and str(bw.get("body_id")) == str(b[0]), "%s: make() builds the soldier with body %s" % [id, b[0]])
		if bw != null:
			bw.free()
		var bsel := {"figure": id, "scheme": "blue"}
		var bp := ArenaActors.player_figure(bsel)
		assert_true(bp != null and str(bp.get("body_id")) == str(b[0]), "%s: the arena and campaign player is that body" % id)
		if bp != null:
			bp.free()
		assert_eq(ArenaActors.scheme_of(bsel), "original", "%s: no scheme reaches it" % id)
		Figures.select(id, "original")
		assert_eq(Figures.selected(), {"figure": id, "scheme": "original"}, "%s: can be selected" % id)
	assert_true(prev < first_kit, "the other bodies come before the kits", str(ids))
	assert_eq(Figures.default_figure(), "egg", "still not the default: the egg stays the default")
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
	var base := _rest_origins(DIR)
	_body_assets(DIR, "", BASE_S, base)
	for id: String in BODIES:
		var b: Array = BODIES[id]
		_body_assets(SoldierFigure.folder(str(b[0])), str(b[0]), float(b[3]), base)
	# ขนาดที่ APK/exe โตขึ้น: ต่อโฟลเดอร์และรวมทุกโฟลเดอร์ทหาร (soldier, soldier_<id>)
	var all := 0
	var n := 0
	for sub in DirAccess.get_directories_at(FIGURES_DIR):
		if sub != "soldier" and not sub.begins_with("soldier_"):
			continue
		var bytes := _folder_bytes(FIGURES_DIR + sub + "/")
		var cap := BASE_CAP if sub == "soldier" else VARIANT_CAP
		assert_true(bytes > 0 and bytes <= cap, "%s: %.2f MB, at most %.1f MB" % [sub, bytes / 1e6, cap / 1e6])
		assert_true(DirAccess.get_directories_at(FIGURES_DIR + sub + "/").is_empty(), "%s: no sub-folders (one folder per body)" % sub)
		all += bytes
		n += 1
	assert_eq(n, 1 + BODIES.size(), "one folder per body (%d)" % n)
	assert_true(all <= ALL_CAP, "every soldier folder together: %.2f MB, at most %.0f MB" % [all / 1e6, ALL_CAP / 1e6])


## ตำแหน่งพักของทุกกระดูก (ชื่อ -> origin) ของ rig ในโฟลเดอร์ d
func _rest_origins(d: String) -> Dictionary:
	var out := {}
	var ps := load(d + "rig.tscn") as PackedScene
	if ps == null:
		return out
	var root := ps.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk != null:
		for i in sk.get_bone_count():
			out[sk.get_bone_name(i)] = sk.get_bone_rest(i).origin
	root.free()
	return out


## ร่างในโฟลเดอร์ d (body = "" ร่างหลัก): สัญญาเดียวกันทุกร่าง ต่างกันที่ S และ blend shape (ร่างอื่นไม่มี)
func _body_assets(d: String, body: String, want_s: float, base: Dictionary) -> void:
	var tag := "base" if body == "" else body
	var ps := load(d + "rig.tscn") as PackedScene
	assert_true(ps != null, "%s: rig.tscn loads" % tag)
	if ps == null:
		return
	var root := ps.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	assert_true(sk != null, "%s: rig.tscn holds a Skeleton3D named Skeleton3D" % tag)
	if sk == null:
		root.free()
		return
	for b in PARENTS:
		var i := sk.find_bone(b)
		var want := str(PARENTS[b])
		var par := sk.get_bone_name(sk.get_bone_parent(i)) if i >= 0 and sk.get_bone_parent(i) >= 0 else ""
		assert_true(i >= 0 and par == want, "%s: game bone %s under %s" % [tag, b, want if want != "" else "the root"], par)
	assert_within(sk.motion_scale, want_s, 0.0001, "%s: motion_scale = S %.5f" % [tag, want_s])
	# ระยะของกระดูกทุกชิ้น = ของร่างหลัก × S / S(ร่างหลัก) (ท่าทุกท่าเล่นได้ เท้าไม่ไถล)
	var worst := 0.0
	var names := 0
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if base.has(nm):
			names += 1
			worst = maxf(worst, sk.get_bone_rest(i).origin.distance_to((base[nm] as Vector3) * (want_s / BASE_S)))
	assert_true(names == sk.get_bone_count() and names == base.size(), "%s: the same %d bones as the base" % [tag, base.size()], str(names))
	assert_true(worst < 0.0005, "%s: every bone offset is the base offset × S ratio (worst %.2f mm)" % [tag, worst * 1000.0])
	root.free()
	var S: GDScript = load(SCRIPT)
	var rules: Array = S.call("helper_rules", d)
	assert_true(rules.size() >= 10, "%s: %d helper bones" % [tag, rules.size()])
	for r: Dictionary in rules:
		assert_true(str(r["kind"]) != "", "%s: helper %s (under %s) has a driver rule" % [tag, r["bone"], r["parent"]], str(r))
	var skin := load(d + "skin.res") as Skin
	assert_true(skin != null and skin.get_bind_count() == base.size(), "%s: one named bind per bone" % tag)
	if skin == null:
		return
	for i in skin.get_bind_count():
		assert_true(base.has(String(skin.get_bind_name(i))), "%s: bind %d is named after a bone" % [tag, i], String(skin.get_bind_name(i)))
	var budget: Dictionary = S.get("BUDGET")
	var game: PackedStringArray = S.get("GAME_BONES")
	for lv in ["hi", "mid", "lo", "min", "crowd"]:
		var m: ArrayMesh = S.call("body_mesh", lv, d)
		if lv == "crowd" and m == null:
			continue
		assert_true(m != null, "%s: body_%s.res loads" % [tag, lv])
		if m == null:
			continue
		var arr := m.surface_get_arrays(0)
		var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_eq(m.get_surface_count(), 1, "%s %s: one surface (one draw)" % [tag, lv])
		assert_true(tris > 0 and tris <= int(budget[lv]), "%s %s: %d triangles within %d" % [tag, lv, tris, int(budget[lv])])
		for i in m.get_blend_shape_count():
			var nm := String(m.get_blend_shape_name(i))
			assert_true(bool(S.call("shape_known", nm)), "%s %s: blend shape %s has a driver" % [tag, lv, nm])
		if lv == "lo" or lv == "min" or lv == "crowd" or body != "":
			assert_eq(m.get_blend_shape_count(), 0, "%s %s: no blend shapes (%s)" % [tag, lv,
				"helpers only on this body" if body != "" else "no extra pass on weak levels"])
		var aabb := m.get_aabb()
		assert_true(absf(aabb.position.y) < 0.012, "%s %s: the soles stand on the floor (%.1f mm)" % [tag, lv, aabb.position.y * 1000.0])
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
			assert_true(extra.is_empty(), "%s %s: skinned to the 23 game bones only" % [tag, lv], str(extra.keys()))
	var hi: ArrayMesh = S.call("body_mesh", "hi", d)
	var mn: ArrayMesh = S.call("body_mesh", "min", d)
	if hi != null and mn != null:
		assert_true(absf(hi.get_aabb().end.y - mn.get_aabb().end.y) < 0.02, "%s: hi and min stand the same height (%.1f mm apart)"
			% [tag, absf(hi.get_aabb().end.y - mn.get_aabb().end.y) * 1000.0])
		# ส่วนสูง = 1.6 ม. × S (ผม/มวยผมเพิ่มได้ไม่เกิน 3 ซม.)
		assert_true(hi.get_aabb().end.y > 1.6 * want_s - 0.01 and hi.get_aabb().end.y < 1.6 * want_s + 0.03,
			"%s: stands %.3f m for S %.4f (1.6 m × S, hair up to 3 cm)" % [tag, hi.get_aabb().end.y, want_s])
	var code := FileAccess.get_file_as_string(d + "body.gdshader")
	var bare := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/").sub(code, "", true)
	assert_true(RegEx.create_from_string("render_mode[^;]*\\bunshaded\\b").search(bare) != null, "%s: the body shader is unshaded (computes its own light)" % tag)
	assert_true(RegEx.create_from_string("\\bTIME\\b").search(bare) == null, "%s: …and uses no TIME (comments aside)" % tag)
	var mat := load(d + "body_material.tres") as ShaderMaterial
	assert_true(mat != null and mat.shader != null and mat.shader.resource_path == d + "body.gdshader", "%s: the material uses that shader" % tag)
	for f in ["rig.tscn", "skin.res", "body_hi.res", "body_mid.res", "body_lo.res", "body_min.res", "body_material.tres",
			"inner_bone.res", "inner_flesh.res"]:
		# แอปที่ส่งออกแปลง .tscn/.tres เป็นไบนารี (มี .remap): ตรวจด้วย ResourceLoader.exists ไม่ใช่ FileAccess
		assert_true(ResourceLoader.exists(d + f), "%s: has %s" % [tag, f])
		for dep in ResourceLoader.get_dependencies(d + f):
			var path := dep.get_slice("::", dep.get_slice_count("::") - 1)
			assert_true(path.begins_with(d), "%s: %s depends only on its own folder" % [tag, f], dep)


## ไบต์ของไฟล์ในโฟลเดอร์ (ไม่รวมโฟลเดอร์ย่อย, .uid, .import, IMPORTED.txt)
func _folder_bytes(d: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(d):
		if not f.ends_with(".uid") and not f.ends_with(".import") and f != "IMPORTED.txt":
			var fa := FileAccess.open(d + f, FileAccess.READ)
			n += fa.get_length() if fa != null else 0
	return n


## เพดานไฟล์ release ใน CI (เป้า 3 GB ใต้ 2 GiB ของ GitHub): APK และ zip ของ Windows ไม่เกิน 1900 MB
## (อ่าน .github/workflows/godot.yml ของ repo ; ในแอปที่ส่งออกไม่มีไฟล์นี้)
func test_release_size_gates() -> void:
	if OS.has_feature("template"):
		print("skip  the CI workflow is not inside the exported self-test")
		return
	var p := ProjectSettings.globalize_path("res://").path_join("../.github/workflows/godot.yml").simplify_path()
	var yml := FileAccess.get_file_as_string(p)
	assert_true(yml != "", "the CI workflow is readable (%s)" % p)
	var gate := "test \"$size\" -le $((1900 * 1024 * 1024)) || { echo \"::error::%s over 1900 MB ($size bytes)\"; exit 1; }"
	var apk := yml.find(gate % "APK")
	var win := yml.find(gate % "Windows zip")
	assert_true(apk > yml.find("--export-release \"Android\""), "CI fails an APK over 1900 MB")
	var zip := yml.find("zip -j \"$GITHUB_WORKSPACE/dist-godot/candlelight-table-godot-windows.zip\"")
	var upload := yml.find("name: godot-windows")
	assert_true(zip > 0 and win > zip and win < upload, "CI fails a Windows zip over 1900 MB, after zipping and before the upload")
	var st := yml.find("stat -c %s \"$GITHUB_WORKSPACE/dist-godot/candlelight-table-godot-windows.zip\"", maxi(zip, 0))
	assert_true(st > zip and st < win, "the Windows gate measures the zip it uploads")


func test_clips() -> void:
	var S: GDScript = load(SCRIPT)
	var src := load(LIB) as AnimationLibrary
	assert_true(src != null, "humanoid.res is there (run godot/tools/kits.sh)")
	var lib: AnimationLibrary = S.call("clip_library")
	assert_true(lib != null, "the soldier's clips build")
	if lib == null or src == null:
		return
	# 0.14 (intended): the names come from the request map in use (clip_map: the own clips.res has no bash_* /
	# thrust_* / flinch*); the fallback map's names are checked against humanoid.res, its source
	var names := {}
	for enemy in [false, true]:
		var cm: Dictionary = S.call("clip_map", enemy)
		for k in cm:
			for n in cm[k]:
				names[n] = true
	for n in names:
		assert_true(lib.has_animation(n), "the soldier has clip " + n)
	for m in [S.get("PLAYER_CLIPS"), S.get("ENEMY_CLIPS")]:
		for k in m:
			for n in m[k]:
				assert_true(src.has_animation(n), "the fallback clip %s is in humanoid.res" % n)
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
	# 0.14 (intended): with the own clips 3 m/s (the arena W) is the jog (before: walk at about 2×); fallback: walk
	var w3 := "jog" if bool(S.call("own_clips")) else "walk"
	var want := 3.0 / (float(lib.get_animation(w3).get_meta("speed")) * sc)
	assert_true(String(ap.current_animation) == "humanoid/" + w3 and absf(ap.speed_scale - want) < 0.001,
		"3 m/s: %s at rate %.3f (speed / clip speed × S)" % [w3, ap.speed_scale])
	f.call("set_move", 5.0, true)
	_steps(f, 2)
	want = 5.0 / (float(lib.get_animation(&"run").get_meta("speed")) * sc)
	assert_true(String(ap.current_animation) == "humanoid/run" and absf(ap.speed_scale - want) < 0.001,
		"5 m/s running: run at rate %.3f" % ap.speed_scale)
	f.call("set_move_dir", Vector2(0, -1), 2.0, false)
	_steps(f, 2)
	assert_true(bool(f.call("moving_back")) and String(ap.current_animation) == "humanoid/walk", "H6 backwards: walk played in reverse")
	f.call("set_move", 2.0, false)
	_steps(f, 2)
	assert_true(not bool(f.call("moving_back")) and ap.speed_scale > 0.0, "plain set_move walks forward again (H6: direction back to (0, 1))")
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
	# 0.14 (intended): move speeds stay, so the deck keeps humanoid.res's walk speed × S × 1.4 (the own walk clip is
	# slower and plays faster instead); without clips.res that is the soldier's walk clip, as before
	var ws := float((load(LIB) as AnimationLibrary).get_animation(&"walk").get_meta("speed")) * sc * 1.4
	assert_true(absf(sp.x - ws) < 0.001 and sp.x >= 0.5 and sp.y <= 6.0 and sp.y > sp.x, "deck speeds %s = humanoid walk speed × S × 1.4" % str(sp))
	var rs := float((load(LIB) as AnimationLibrary).get_animation(&"run").get_meta("speed")) * sc * 1.4
	assert_within(sp.y, rs, 0.001, "deck run speed %.4f = humanoid run speed × S × 1.4 (a gameplay value)" % sp.y)
	dm.free()


func test_actions_and_aim() -> void:
	var f := _new_fig(&"player", "mid")
	f.connect("clip_event", _on_event)
	_shots = 0
	_thuds = 0
	var d := float(f.call("play", &"punch", 1.0))
	assert_true(d > 0.3 and d < 0.6, "punch: a %.2f s blow (under the 0.55 s repeat)" % d)
	_steps(f, int(ceil(d / DT)) + 2)
	assert_true(_shots >= 1, "the punch emits clip_event shot (%d)" % _shots)
	var s := float(f.call("play", &"swing", 1.0))
	assert_true(s > 0.3 and s < 0.8, "swing: a %.2f s thrust" % s)
	assert_within(float(f.call("play", &"fire", 1.0)), 0.16, 0.001, "fire: a 0.16 s kick (procedural recoil)")
	# 0.14 (intended): the own reload clip lasts the game's reload time (visual only: ArenaWeapons times the lockout and
	# nothing reads this value); without clips.res there is no reload clip (0)
	var want_rl := float(ArenaCombat.weapon("gun")["reload"]) if bool((load(SCRIPT) as GDScript).call("own_clips")) else 0.0
	assert_within(float(f.call("play", &"reload", 1.0)), want_rl, 0.001, "reload: %.2f s (the game's reload time; 0 = no clip)" % want_rl)
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
	# ตายแล้วมีแผล: แสงวาบผ่าน uniform ของวัสดุตัวเอง (ไม่ทับรูแผล) · ไม่มีแผล: ชั้นทับ (overlay) บนวัสดุร่วม
	f.call("set_flash", 1.0)
	var body := f.call("body") as MeshInstance3D
	assert_true(int(f.call("wound_count")) > 0 and body.material_overlay == null
		and is_equal_approx(float((body.material_override as ShaderMaterial).get_shader_parameter("flash")), 1.0),
		"hit flash on the wounded body: the skin's own flash uniform, no overlay over the wounds")
	f.call("clear_wounds")
	assert_true(body.material_overlay != null, "hit flash, unwounded: an overlay")
	f.call("set_flash", 0.0)
	assert_true(body.material_overlay == null, "flash off: no overlay (no extra pass)")
	f.free()


func test_drivers_per_level() -> void:
	var f := _new_fig(&"player", "hi")
	var sk: Skeleton3D = f.call("skeleton")
	_steps(f, 3)
	var clav := sk.find_bone("clavicleL")
	var half := sk.find_bone("elbow_halfL")
	assert_true(not sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY), "hi: helper bones follow the joints")
	assert_true(int(f.call("active_shapes")) > 0, "hi: correctives are active in idle (%d)" % int(f.call("active_shapes")))
	# ใหม่ 0.14 item 2 (face): hi moves the face bones while talking, lo paints the face only, min drives nothing
	var jaw := sk.find_bone("head_jaw")
	var face: SoldierFace = f.call("face")
	f.call("say", "สวัสดี")
	_steps(f, 6)
	assert_false(sk.get_bone_pose(jaw).is_equal_approx(sk.get_bone_rest(jaw)), "hi: the jaw moves while talking")
	f.call("apply_level", "lo")
	_steps(f, 3)
	assert_eq(int(f.call("active_shapes")), 0, "lo: no correctives")
	assert_true(not sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY), "lo: helpers still driven")
	var painted := 0.0
	f.call("say", "สวัสดี")
	for i in 8:
		f.call("step", DT)
		painted = maxf(painted, face.state().z)
	assert_true(sk.get_bone_pose(jaw).is_equal_approx(sk.get_bone_rest(jaw)) and painted > 0.0,
		"lo: the face bones rest, the shader paints the talking mouth (%.2f)" % painted)
	f.call("apply_level", "min")
	_steps(f, 3)
	assert_true(sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY)
		and sk.get_bone_pose_rotation(clav).is_equal_approx(Quaternion.IDENTITY), "min: helpers rest (nothing driven)")
	var fw := face.writes()
	f.call("say", "สวัสดี")
	_steps(f, 6)
	assert_true(sk.get_bone_pose(jaw).is_equal_approx(sk.get_bone_rest(jaw)) and face.writes() == fw,
		"min: the face bones rest, no face writes")
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


## ร่างอื่น: S ของตัวเอง (อัตราเล่นท่า ความเร็วดาดฟ้า) ส่วนสูงของตัวเอง กระดูกช่วยแต่ไม่มีท่าแก้ ยืนนิ่งบน min
## สองร่างในฉากเดียวกันใช้เมชและ S ของตัวเอง (static ต่อโฟลเดอร์)
func test_bodies_behaviour() -> void:
	var S: GDScript = load(SCRIPT)
	var lib: AnimationLibrary = S.call("clip_library")
	if lib == null:
		assert_true(false, "the soldier's clips build")
		return
	var base := _new_fig(&"player", "hi")
	for id: String in BODIES:
		var b: Array = BODIES[id]
		var want_s := float(b[3])
		var f := _new_fig(&"player", "hi", true, str(b[0]))
		var sk: Skeleton3D = f.call("skeleton")
		assert_true(sk != null and is_equal_approx(sk.motion_scale, want_s), "%s: its own rig (S %.5f)" % [id, want_s])
		if sk == null:
			f.free()
			continue
		var m: Dictionary = f.call("metrics")
		assert_true(float(m["height"]) > 1.6 * want_s - 0.01 and float(m["height"]) < 1.6 * want_s + 0.03,
			"%s: metrics height %.3f m (1.6 m × S)" % [id, float(m["height"])])
		assert_true((f.call("body") as MeshInstance3D).mesh == S.call("body_mesh", "hi", SoldierFigure.folder(str(b[0]))),
			"%s: its own hi mesh" % id)
		assert_true((f.call("body") as MeshInstance3D).mesh != (base.call("body") as MeshInstance3D).mesh, "%s: not the base mesh" % id)
		assert_true((f.call("body") as MeshInstance3D).skin == load(SoldierFigure.folder(str(b[0])) + "skin.res"), "%s: its own skin binds" % id)
		var ap: AnimationPlayer = f.call("animation_player")
		_steps(f, 3)
		var half := sk.find_bone("elbow_halfL")
		assert_true(not sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY), "%s hi: helper bones follow the joints" % id)
		assert_eq(int(f.call("active_shapes")), 0, "%s hi: no correctives (no blend shapes)" % id)
		assert_eq((f.call("shape_names") as PackedStringArray).size(), 0, "%s hi: the mesh has no blend shapes" % id)
		f.call("set_move", 3.0, false)
		_steps(f, 2)
		# 0.14 (intended): 3 m/s plays the own jog (fallback: walk)
		var w3 := "jog" if bool(S.call("own_clips")) else "walk"
		var want := 3.0 / (float(lib.get_animation(w3).get_meta("speed")) * want_s)
		assert_true(String(ap.current_animation) == "humanoid/" + w3 and absf(ap.speed_scale - want) < 0.001,
			"%s: 3 m/s plays %s at rate %.3f (speed / clip speed × its S)" % [id, w3, ap.speed_scale])
		f.call("set_move", 5.0, true)
		_steps(f, 2)
		want = 5.0 / (float(lib.get_animation(&"run").get_meta("speed")) * want_s)
		assert_true(String(ap.current_animation) == "humanoid/run" and absf(ap.speed_scale - want) < 0.001,
			"%s: 5 m/s runs at rate %.3f" % [id, ap.speed_scale])
		var sp: Vector2 = f.call("deck_speeds")
		# 0.14 (intended): deck speeds unchanged = humanoid walk speed × its S × 1.4
		var ws := float((load(LIB) as AnimationLibrary).get_animation(&"walk").get_meta("speed")) * want_s * 1.4
		assert_true(absf(sp.x - ws) < 0.001 and sp.y > sp.x, "%s: deck speeds %s = humanoid walk speed × its S × 1.4" % [id, str(sp)])
		var rs := float((load(LIB) as AnimationLibrary).get_animation(&"run").get_meta("speed")) * want_s * 1.4
		assert_within(sp.y, rs, 0.001, "%s: deck run speed %.4f = humanoid run speed × its S × 1.4" % [id, sp.y])
		f.call("set_move", 0.0, false)
		f.call("apply_level", "min")
		var n := 0
		while n < 10 and not bool(f.call("is_still")):
			f.call("step", DT)
			n += 1
		assert_true(bool(f.call("is_still")) and sk.get_bone_pose_rotation(half).is_equal_approx(Quaternion.IDENTITY),
			"%s min: still within 10 frames, helpers rest (%d)" % [id, n])
		f.free()
	# the base next to them still has its own scale and correctives
	assert_true(is_equal_approx((base.call("skeleton") as Skeleton3D).motion_scale, BASE_S), "the base body keeps S %.4f" % BASE_S)
	_steps(base, 3)
	assert_true(int(base.call("active_shapes")) > 0, "the base body keeps its correctives on hi")
	base.free()
	# an unknown body falls back to the base body (a warning, not a broken figure)
	var bad := _new_fig(&"player", "mid", true, "zz9")
	assert_true(bad.call("skeleton") != null and is_equal_approx((bad.call("skeleton") as Skeleton3D).motion_scale, BASE_S),
		"an unknown body id gives the base body")
	bad.free()


## ร่างเลือกก่อน setup: set_light / deck_speeds ก่อน setup ต้องได้ร่างนั้นทั้งตัว (rig, S, skin, วัสดุ, ผิว) ไม่ปนร่างหลัก
## (Figures.make_builtin ตั้ง body_id ก่อน setup ; HeroLight.apply ถึง set_light ได้ทุกเมื่อ)
func test_body_chosen_before_setup() -> void:
	var S: GDScript = load(SCRIPT)
	var d1 := SoldierFigure.folder("f1")
	var sun := Vector3(0, 1, 0.15)
	# 0.14 review (intended): the lit copy is made from the shared hi material, which runs the body's body_face.gdshader
	var f1_shader := load(d1 + "body_face.gdshader") as Shader
	var base_shader := load(DIR + "body_face.gdshader") as Shader
	# body_id ก่อน (แบบ make_builtin) แล้วไฟ + ความเร็วดาดฟ้า แล้ว setup ; ร่างหลัก แล้ว setup({"body": "f1"})
	for how in ["body_id first", "setup body"]:
		var f: Node3D = S.new()
		if how == "body_id first":
			f.set("body_id", "f1")
		_tree().root.add_child(f)
		f.call("set_light", sun, Color(0.98, 0.9, 0.78), Color(0.15, 0.15, 0.16))
		var early: Vector2 = f.call("deck_speeds")
		f.call("set_manual", true)
		f.call("setup", {"role": &"deck", "level": "hi", "seed": 7, "body": "f1"} if how == "setup body" else {"role": &"deck", "level": "hi", "seed": 7})
		var sk: Skeleton3D = f.call("skeleton")
		var mi: MeshInstance3D = f.call("body")
		assert_true(sk != null and is_equal_approx(sk.motion_scale, 1.0), "%s: f1's rig and S 1.0 (%s)" % [how, str(sk.motion_scale if sk else -1.0)])
		assert_true(mi != null and mi.skin == load(d1 + "skin.res"), "%s: f1's skin binds" % how)
		assert_true(mi != null and mi.mesh == S.call("body_mesh", "hi", d1), "%s: f1's hi mesh" % how)
		var m := mi.material_override as ShaderMaterial if mi != null else null
		assert_true(m != null and m.shader == f1_shader and m.shader != base_shader, "%s: its lit copy is f1's material" % how)
		assert_true(m != null and m.get_shader_parameter("sun_dir") is Vector3 and (m.get_shader_parameter("sun_dir") as Vector3).is_equal_approx(sun),
			"%s: the copy keeps the scene light" % how)
		var sp: Vector2 = f.call("deck_speeds")
		# 0.14 (intended): deck speeds unchanged = humanoid walk speed × S × 1.4 (not the own walk clip's speed)
		var ws := float((load(LIB) as AnimationLibrary).get_animation(&"walk").get_meta("speed")) * 1.0 * 1.4
		assert_true(absf(sp.x - ws) < 0.001, "%s: deck speeds from f1's S %s" % [how, str(sp)])
		var rs := float((load(LIB) as AnimationLibrary).get_animation(&"run").get_meta("speed")) * 1.0 * 1.4
		assert_within(sp.y, rs, 0.001, "%s: deck run speed from f1's S (%.4f)" % [how, sp.y])
		if how == "body_id first":
			assert_true(early.is_equal_approx(sp), "body_id first: deck speeds before setup are already f1's")
		else:
			assert_true(absf(early.x - ws * BASE_S) < 0.001, "setup body: before setup the base body's deck speeds")
		f.free()


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
