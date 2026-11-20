extends "res://tests/testing.gd"
## The soldier's face (ใหม่ 0.14 item 2): scenes/arena/soldier_face.gd (SoldierFace) and face_speech.gd (FaceSpeech) on
## SoldierFigure, with the assets of tools/soldier (5 face bones, CUSTOM1, face.gdshaderinc). Checks:
##  - assets, every body: the 5 face bones under head at rest rotation identity; CUSTOM1 on hi/mid/lo and not on min;
##    the mouth seam rows (u + v = 24) on hi/mid only; face-bone weights on hi/mid only; triangles within the budget;
##  - levels: hi/mid move the face bones and write face_state; lo writes face_state only (the painted mouth) and keeps
##    the face bones at rest; min writes nothing at all (a line, a mood, a hit, death), its material has face_on off and
##    hi/mid/lo's on; at most 6 writes in a tick (5 bones + face_state) and writes only on change (a still face writes
##    nothing between blinks);
##  - blinks: 10-25 in 60 s for every seed tried, the same times for the same seed (through the figure's own clock),
##    different times for another seed, 12 % doubles in the long run, none once dead;
##  - dead eyes: closed for about 3 in 4 soldiers and open for the rest, by the seed (400 seeds within 0.18-0.32, the
##    same answer every time), the death face written once, blinking back after a revive;
##  - moods: the 10 moods, an unknown one refused, the ranges of the generator (brow, lip corners, jaw <= 8°, speech
##    jaw 1.5-5°), pain on a hit and anger on a punch that wear off, narrowed eyes while aiming;
##  - visemes: Thai (leading vowels after their consonant, tone marks and ็ silent, ์ silent, closing M/B/P shut the
##    lips, TextServer word breaks, ๆ repeats), English (letters, digraphs, silent final e), deterministic;
##  - the lines: every SpeechBubble line has its English in ui/i18n/face.json and the file has nothing else;
##  - wound draws untouched: the face makes no material copy and no draw; face_state survives the wound material and
##    the wound updates per frame are the same with the face talking.

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const BODIES: PackedStringArray = ["", "m2", "m3", "f1", "f2"]
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const DT := 1.0 / 30.0
const FACE_BONES: PackedStringArray = ["head_jaw", "head_lipL", "head_lipR", "head_browL", "head_browR"]


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _fig(level: String, seed := 7, body := "", manual := true) -> Node3D:
	var f: Node3D = (load(SCRIPT) as GDScript).new()
	_tree().root.add_child(f)
	if manual:
		f.call("set_manual", true)
	f.call("setup", {"role": &"player", "level": level, "seed": seed, "body": body})
	return f


func _steps(f: Node3D, n: int) -> void:
	for i in n:
		f.call("step", DT)


func _face_pose(f: Node3D) -> Array:
	var sk: Skeleton3D = f.call("skeleton")
	var out := []
	for b in FACE_BONES:
		var i := sk.find_bone(b)
		out.append(sk.get_bone_pose(i) if i >= 0 else Transform3D())
	return out


func _at_rest(f: Node3D) -> bool:
	var sk: Skeleton3D = f.call("skeleton")
	for b in FACE_BONES:
		var i := sk.find_bone(b)
		if i < 0 or not sk.get_bone_pose(i).is_equal_approx(sk.get_bone_rest(i)):
			return false
	return true


func test_assets_per_body() -> void:
	var S: GDScript = load(SCRIPT)
	var budget: Dictionary = S.get("BUDGET")
	for body in BODIES:
		var tag := "base" if body == "" else body
		var d := str(S.call("folder", body))
		var rig := load(d + "rig.tscn") as PackedScene
		var root := rig.instantiate()
		var sk := root.get_node("Skeleton3D") as Skeleton3D
		for b in FACE_BONES:
			var i := sk.find_bone(b)
			assert_true(i >= 0 and sk.get_bone_name(sk.get_bone_parent(i)) == "head", "%s: %s under head" % [tag, b])
			if i >= 0:
				assert_true(sk.get_bone_rest(i).basis.is_equal_approx(Basis.IDENTITY), "%s: %s rests unrotated" % [tag, b])
		root.free()
		var skin := load(d + "skin.res") as Skin
		var face_binds := {}
		for i in skin.get_bind_count():
			if FACE_BONES.has(String(skin.get_bind_name(i))):
				face_binds[i] = true
		assert_eq(face_binds.size(), 5, "%s: one bind per face bone" % tag)
		# สีเปลือกตาปิดของร่างนี้ (meta ของวัสดุจาก import) ไม่ใช่ค่าเริ่มของเชดเดอร์
		var bm := load(d + "body_material.tres") as Material
		var lid: Variant = bm.get_meta("face_lid_colour") if bm.has_meta("face_lid_colour") else null
		assert_true(lid is Vector3 and not (lid as Vector3).is_equal_approx(Vector3(0.62, 0.45, 0.37)),
			"%s: own closed-eyelid colour in body_material.tres (%s)" % [tag, lid])
		# เกมส่งสีนี้ถึงวัสดุหน้า (hi/mid/lo) และวัสดุ pv
		var st: Dictionary = S.call("_load_static", d)
		for k in ["mat", "mat_pv"]:
			var got: Variant = (st[k] as ShaderMaterial).get_shader_parameter("face_lid_colour") if st[k] != null else null
			assert_true(lid is Vector3 and got is Vector3 and (got as Vector3).is_equal_approx(lid),
				"%s: the face material (%s) gets the body's eyelid colour (%s)" % [tag, k, got])
		for lv in LEVELS:
			var m: ArrayMesh = S.call("body_mesh", lv, d)
			var arr := m.surface_get_arrays(0)
			var fmt := m.surface_get_format(0)
			var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			assert_true(tris <= int(budget[lv]), "%s %s: %d triangles within %d" % [tag, lv, tris, int(budget[lv])])
			var has_c1 := (fmt & Mesh.ARRAY_FORMAT_CUSTOM1) != 0
			assert_eq(has_c1, lv != "min", "%s %s: CUSTOM1 %s" % [tag, lv, "present" if lv != "min" else "absent"])
			var seam := 0
			if has_c1:
				var c1: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM1]
				for v in c1.size() / 4:
					if absf(c1[4 * v] + c1[4 * v + 1] - 24.0) < 0.01:
						seam += 1
			assert_eq(seam > 0, lv == "hi" or lv == "mid", "%s %s: mouth seam rows %s (%d)" % [tag, lv,
				"present" if lv == "hi" or lv == "mid" else "absent", seam])
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var on_face := 0
			for k in bones.size():
				if wts[k] > 0.0001 and face_binds.has(bones[k]):
					on_face += 1
			assert_eq(on_face > 0, lv == "hi" or lv == "mid", "%s %s: face-bone weights %s (%d)" % [tag, lv,
				"present" if lv == "hi" or lv == "mid" else "absent", on_face])


func test_levels_and_writes() -> void:
	var line := "สวัสดี! พร้อมออกรบแล้ว"
	for lv in ["hi", "mid", "lo"]:
		var f := _fig(lv)
		var face: SoldierFace = f.call("face")
		var mat := (f.call("body") as MeshInstance3D).material_override as ShaderMaterial
		assert_true(bool(mat.get_shader_parameter("face_on")), "%s: the material draws the face" % lv)
		_steps(f, 3)
		var rest := _face_pose(f)
		var dur := float(f.call("say", line))
		assert_true(dur > 1.0 and face.speaking(), "%s: says the line (%.2f s)" % [lv, dur])
		var moved := false
		var mouth := 0.0
		var most := 0
		for i in int(dur / DT) + 10:
			var w0 := face.writes()
			f.call("step", DT)
			most = maxi(most, face.writes() - w0)
			moved = moved or _face_pose(f) != rest
			mouth = maxf(mouth, face.state().z)
		assert_false(face.speaking(), "%s: the line ends" % lv)
		if lv == "lo":
			assert_true(_at_rest(f) and not moved, "lo: the face bones stay at rest (no face weights on lo)")
			assert_true(mouth > 0.3, "lo: the painted mouth opens while talking (%.2f)" % mouth)
			assert_true(most <= 1, "lo: at most one write a tick (face_state) (%d)" % most)
		else:
			assert_true(moved, "%s: the jaw and lip bones move while talking" % lv)
			assert_eq(mouth, 0.0, "%s: no painted mouth (the jaw opens instead)" % lv)
			assert_true(most <= 6, "%s: at most 6 writes a tick (5 bones + face_state) (%d)" % [lv, most])
		f.free()
	# min: nothing at all
	var mn := _fig("min")
	var mface: SoldierFace = mn.call("face")
	var mmat := (mn.call("body") as MeshInstance3D).material_override as ShaderMaterial
	assert_false(bool(mmat.get_shader_parameter("face_on")), "min: the material draws no face")
	assert_eq(float(mn.call("say", line)), 0.0, "min: say does nothing")
	mn.call("set_mood", &"shout")
	_steps(mn, 60)
	mn.call("play", &"hit", 1.0)
	_steps(mn, 30)
	mn.call("play", &"die", 1.0)
	_steps(mn, 30)
	assert_eq(mface.writes(), 0, "min: zero face writes (line, mood, hit, death)")
	assert_eq(mface.blinks(), 0, "min: no blink timer runs")
	assert_true(_at_rest(mn), "min: the face bones rest")
	mn.free()
	# hi → min: the bones go back to rest once, then nothing; back to hi: the face is written again
	var f := _fig("hi")
	var face: SoldierFace = f.call("face")
	f.call("set_mood", &"shout")
	_steps(f, 20)
	assert_false(_at_rest(f), "hi: the shout opens the jaw")
	f.call("apply_level", "min")
	var w := face.writes()
	assert_true(_at_rest(f), "to min: the face bones back at rest")
	assert_true(((f.call("body") as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("face_on") == false,
		"to min: the shared min material (face_on off)")
	_steps(f, 60)
	assert_eq(face.writes(), w, "on min: no face writes")
	f.call("apply_level", "hi")
	_steps(f, 2)
	assert_true(face.writes() > w and not _at_rest(f), "back to hi: the shout is written again")
	f.free()


func test_writes_only_on_change() -> void:
	var f := _fig("hi", 11)
	var face: SoldierFace = f.call("face")
	_steps(f, 30)
	var bad := 0
	var quiet := 0
	for i in 600:
		var w0 := face.writes()
		var was := face.blinking()
		f.call("step", DT)
		if face.writes() != w0 and not (was or face.blinking()):
			bad += 1
		if face.writes() == w0:
			quiet += 1
	assert_eq(bad, 0, "a still face writes only while it blinks")
	assert_true(quiet > 450, "most ticks write nothing (%d of 600)" % quiet)
	f.free()


func test_blinks() -> void:
	var S: GDScript = load(SCRIPT)
	var host := _fig("lo", 1)
	var sk: Skeleton3D = host.call("skeleton")
	var mi: MeshInstance3D = host.call("body")
	var doubles := 0
	var total := 0
	for seed in range(1, 41):
		var face := SoldierFace.new()
		face.attach(sk, mi, 1.0)
		face.reseed(seed)
		face.set_level("lo")
		for i in 1800:
			face.tick(DT)
		var n := face.blinks()
		total += n
		var t := face.blink_times()
		for k in range(1, t.size()):
			if t[k] - t[k - 1] < 0.4:
				doubles += 1
		assert_true(n >= 10 and n <= 25, "seed %d: %d blinks in 60 s (10-25)" % [seed, n])
	var share := float(doubles) / float(total - doubles)
	assert_true(share > 0.06 and share < 0.2, "about 12 %% of blinks are doubles (%.3f)" % share)
	host.free()
	# the figure's own clock: the same seed blinks at the same times, another seed does not
	var a := _fig("mid", 5)
	var b := _fig("mid", 5)
	var c := _fig("mid", 6)
	for i in 900:
		for f: Node3D in [a, b, c]:
			f.call("step", DT)
	var ta: PackedFloat32Array = (a.call("face") as SoldierFace).blink_times()
	var tb: PackedFloat32Array = (b.call("face") as SoldierFace).blink_times()
	var tc: PackedFloat32Array = (c.call("face") as SoldierFace).blink_times()
	assert_true(ta.size() >= 4 and ta == tb, "seed 5 twice: the same %d blink times" % ta.size())
	assert_true(ta != tc, "seed 6: other blink times")
	# dead: no more blinks, nothing written after the death face
	a.call("play", &"die", 1.0)
	var fa: SoldierFace = a.call("face")
	_steps(a, 3)
	var n0 := fa.blinks()
	var w0 := fa.writes()
	_steps(a, 1800)
	assert_eq(fa.blinks(), n0, "dead: no blinks in 60 s")
	assert_eq(fa.writes(), w0, "dead: nothing written after the death face")
	for f: Node3D in [a, b, c]:
		f.free()


func test_dead_eyes() -> void:
	var open := 0
	var stable := true
	for seed in range(1, 401):
		var o := SoldierFace.eyes_stay_open(seed)
		if o:
			open += 1
		stable = stable and o == SoldierFace.eyes_stay_open(seed)
	var share := float(open) / 400.0
	assert_true(share >= 0.18 and share <= 0.32, "dead eyes stay open for about 1 in 4 seeds (%.3f)" % share)
	assert_true(stable, "the same seed always gives the same answer")
	var want_open := -1
	var want_shut := -1
	for seed in range(1, 60):
		if want_open < 0 and SoldierFace.eyes_stay_open(seed):
			want_open = seed
		if want_shut < 0 and not SoldierFace.eyes_stay_open(seed):
			want_shut = seed
	for seed in [want_open, want_shut]:
		for lv in ["hi", "lo"]:
			var f := _fig(lv, seed)
			var face: SoldierFace = f.call("face")
			_steps(f, 5)
			f.call("play", &"die", 1.0)
			var lid := face.state().x
			var exp := 0.0 if SoldierFace.eyes_stay_open(seed) else 1.0
			assert_true(face.dead() and is_equal_approx(lid, exp), "seed %d %s: dead eyes %s (lid %.2f)" % [seed, lv,
				"open" if exp == 0.0 else "closed", lid])
			_steps(f, 40)
			f.call("play", &"idle", 1.0)
			_steps(f, 300)
			assert_true(not face.dead() and face.blinks() > 0, "seed %d %s: revived, blinking again" % [seed, lv])
			f.free()


func test_moods() -> void:
	assert_eq(SoldierFace.MOODS.size(), 10, "ten moods")
	for m: String in SoldierFace.MOODS:
		var v: Array = SoldierFace.MOOD[m]
		assert_true(float(v[0]) >= -2.5 and float(v[0]) <= 4.0 and absf(float(v[1])) <= 1.5, "%s: brows within the rig's range" % m)
		assert_true(absf(float(v[2])) <= 3.0 and absf(float(v[3])) <= 3.0 and absf(float(v[4])) <= 2.0, "%s: lip corners within ±3 / ±2 mm" % m)
		assert_true(float(v[5]) >= 0.0 and float(v[5]) <= 8.0, "%s: jaw within 0-8° (G13)" % m)
		assert_true(float(v[6]) >= 0.0 and float(v[6]) <= 1.0 and float(v[7]) >= 0.0 and float(v[7]) <= 1.0, "%s: lids 0..1" % m)
		assert_true(v.size() == 9 and absf(float(v[8])) <= 10.0, "%s: brow tilt within ±10°" % m)
	for c: String in FaceSpeech.CODES:
		var v: Array = SoldierFace.VIS[c]
		assert_true(float(v[0]) <= 5.0 and (c == "rest" or float(v[0]) >= 1.0), "viseme %s: jaw within speech range" % c)
	var f := _fig("hi")
	var face: SoldierFace = f.call("face")
	assert_true(bool(f.call("set_mood", &"happy")), "set_mood takes a known mood")
	assert_false(bool(f.call("set_mood", &"sleepy")), "set_mood refuses an unknown mood")
	assert_eq(face.mood(), &"happy", "the base mood shows")
	_steps(f, 20)
	assert_true(face.values()[3] > 2.0, "happy: lip corners up (%.2f mm)" % face.values()[3])
	f.call("play", &"hit", 1.0)
	assert_eq(face.mood(), &"pain", "a hit: pain")
	_steps(f, 6)
	assert_true(face.values()[6] > 0.2, "pain: the lids squeeze (%.2f)" % face.values()[6])
	_steps(f, 40)
	assert_eq(face.mood(), &"happy", "the pain wears off")
	f.call("play", &"punch", 1.0)
	assert_eq(face.mood(), &"angry", "a punch: anger")
	_steps(f, 45)
	assert_eq(face.mood(), &"happy", "the anger wears off")
	f.call("set_mood", &"neutral")
	f.call("set_weapon", &"gun")
	_steps(f, 20)
	assert_true(bool(f.call("aiming")) and face.mood() == &"focus" and face.state().y > 0.3,
		"aiming: narrowed eyes (lower lid %.2f)" % face.state().y)
	f.call("set_weapon", &"none")
	_steps(f, 30)
	assert_eq(face.mood(), &"neutral", "no gun: the eyes relax")
	f.free()


func test_visemes_thai() -> void:
	var v := func(t: String) -> Array: return FaceSpeech.visemes(t, "th").map(func(x: Array) -> String: return str(x[0]))
	assert_eq(v.call("ไป"), ["rest", "A", "I", "rest"], "ไป: the leading vowel comes after its consonant")
	assert_eq(v.call("เขา"), ["C", "A", "U", "rest"], "เขา: เ-า after the consonant")
	assert_eq(v.call("เรียน"), ["C", "I", "A", "C", "rest"], "เรียน: เ-ีย then the final")
	assert_eq(v.call("ไม่"), v.call("ไม"), "tone marks have no mouth shape")
	assert_eq(v.call("เด็ก"), ["C", "E", "C", "rest"], "็ is silent")
	assert_eq(v.call("การ์ด"), v.call("กาด"), "a consonant under ์ is silent")
	assert_eq(v.call("ผม"), ["rest", "O", "rest"], "ผม: the inherent vowel, the final ม shuts the lips")
	assert_eq(v.call("ลาบ").back(), "rest", "a final บ ends shut")
	assert_eq((v.call("ลาบ") as Array).slice(0, 3), ["C", "A", "rest"], "ลาบ: lips close on the final")
	assert_eq(FaceSpeech.words("สวัสดีครับ"), PackedStringArray(["สวัสดี", "ครับ"]), "TextServer splits Thai words")
	var two: Array = FaceSpeech.visemes("สวัสดีครับ", "th")
	var gaps := two.filter(func(x: Array) -> bool: return str(x[0]) == "rest").size()
	assert_true(gaps >= 2, "a closed gap between the words and at the end (%d)" % gaps)
	assert_eq(v.call("ลึก ๆ").count("E"), 2, "ๆ says the word again")
	assert_eq(FaceSpeech.visemes("หายใจลึก ๆ แล้วเล็งให้ดี", "th"), FaceSpeech.visemes("หายใจลึก ๆ แล้วเล็งให้ดี", "th"), "deterministic")
	assert_eq(FaceSpeech.visemes("สวัสดี"), FaceSpeech.visemes("สวัสดี", "th"), "Thai letters pick Thai when no language is given")
	assert_eq(FaceSpeech.visemes("   ", "th"), [], "blank says nothing")


func test_visemes_english() -> void:
	var v := func(t: String) -> Array: return FaceSpeech.visemes(t, "en").map(func(x: Array) -> String: return str(x[0]))
	assert_eq(v.call("she")[0], "U", "sh rounds the lips")
	assert_eq((v.call("food") as Array).slice(0, 2), ["F", "U"], "f then oo")
	assert_eq(v.call("make"), ["rest", "A", "C", "rest"], "a silent final e")
	assert_eq(v.call("the"), ["C", "E", "rest"], "th, then a short word keeps its e")
	assert_eq(v.call("hello"), ["C", "E", "C", "O", "rest"], "a doubled letter counts once")
	assert_eq(v.call("boots")[0], "rest", "b starts shut")
	var track: Array = FaceSpeech.visemes("Hello! Ready for battle.", "en")
	var ok := true
	for x: Array in track:
		ok = ok and FaceSpeech.CODES.has(str(x[0])) and float(x[1]) > 0.0
	assert_true(ok and FaceSpeech.duration(track) > 1.0, "known codes with positive times (%.2f s)" % FaceSpeech.duration(track))
	assert_eq(FaceSpeech.code_at(track, 0.0), str(track[0][0]), "code_at starts at the first shape")
	assert_eq(FaceSpeech.code_at(track, 99.0), "", "and ends after the line")


func test_lines() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ui/i18n/face.json"))
	assert_true(data is Dictionary, "ui/i18n/face.json parses")
	if not data is Dictionary:
		return
	var lines := []
	for k: String in SpeechBubble.LINES:
		lines.append_array(SpeechBubble.LINES[k])
	assert_eq(lines.size(), 20, "twenty lines")
	var missing := lines.filter(func(l: String) -> bool: return not (data as Dictionary).has(l) or I18n.lookup(l) == "")
	assert_eq(missing, [], "every line has its English")
	var extra := (data as Dictionary).keys().filter(func(k: String) -> bool: return not lines.has(k))
	assert_eq(extra, [], "face.json holds only the lines")
	assert_eq(SpeechBubble.line("greet", 10), SpeechBubble.line("greet", 0), "line() wraps around")
	assert_eq(SpeechBubble.line("nothing", 0), "", "an unknown set has no line")


func test_wound_draws_untouched() -> void:
	var f := _fig("hi")
	var g := _fig("hi")
	var mi: MeshInstance3D = f.call("body")
	var shared := mi.material_override
	f.call("say", "สวัสดี! พร้อมออกรบแล้ว")
	_steps(f, 20)
	_steps(g, 20)
	assert_true(mi.material_override == shared, "talking: still the shared material (instance uniform, no copy)")
	assert_eq((f.call("inner_layers") as Array).size(), 0, "talking: no inner layer made")
	assert_eq(f.call("skeleton").get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D).size(), 1,
		"talking: one mesh (no extra draw)")
	var spot := Vector3(0.0, 0.0, 0.1)
	for x: Node3D in [f, g]:
		x.call("add_wound", &"chest", spot, 0.05)
	var st: Vector4 = (f.call("face") as SoldierFace).state()
	assert_true(mi.material_override != shared and mi.get_instance_shader_parameter("face_state") == st,
		"a wound: the wound material, face_state kept on the instance")
	f.call("say", "Hello! Ready for battle.")
	var u0 := [int(f.call("wound_updates")), int(g.call("wound_updates"))]
	_steps(f, 30)
	_steps(g, 30)
	assert_eq(int(f.call("wound_updates")) - u0[0], int(g.call("wound_updates")) - u0[1],
		"the wound updates per frame are the same with the face talking")
	f.free()
	g.free()
