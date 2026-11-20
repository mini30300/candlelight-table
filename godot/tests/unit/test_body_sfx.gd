extends "res://tests/testing.gd"
## Body sounds (0.14, item 1b): footsteps and panting in assets/body_sfx/, made by tools/sound/make_body_sfx.py and
## committed (CI does not bake them). The manifest and its kinds, every take's import (mono QOA, rate, length; the
## hard breaths fit the fastest breathing slots), the source WAVs (16-bit mono, peaks, silent ends, the 1 MB cap),
## both export presets, the credits of the downloaded takes, and ArenaSound.body through the live Sfx (Dummy driver).

const DIR := "res://assets/body_sfx/"
const MANIFEST := "res://assets/body_sfx/body_sfx.json"
const STEP_RATE := 32000
const PANT_RATE := 22050
## หายใจเร็วสุด 56 ครั้ง/นาที หายใจเข้า 45 % ของรอบ: เทคแรงต้องสั้นกว่าช่องของมัน
const SLOT_IN := 0.45 * 60.0 / 56.0
const SLOT_OUT := 0.55 * 60.0 / 56.0
const PEAK_MAX := 29204           # -1 dBFS (16 บิต)
const CAP := 1048576


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return m if m is Dictionary else {}


func _want_kinds() -> Array:
	var out: Array = ["step_boot", "step_metal"]
	for voice: String in ["low", "high"]:
		for tier: String in ["soft", "hard"]:
			for part: String in ["in", "out"]:
				out.append("pant_%s_%s_%s" % [part, tier, voice])
	out.sort()
	return out


## [ต่ำสุด, สูงสุด] วินาทีของเทคในชนิดนี้
func _range(k: String) -> Array:
	if k.begins_with("step_"):
		return [0.08, 0.35]
	if k.contains("_soft_"):
		return [0.45, 0.70]
	return [0.25, SLOT_IN if k.contains("_in_") else SLOT_OUT]


func test_manifest_and_kinds() -> void:
	var m := _manifest()
	assert_false(m.is_empty(), "body_sfx.json is present and parses (python3 -I tools/sound/make_body_sfx.py makes it)")
	if m.is_empty():
		return
	assert_eq(int(m.get("format", 0)), 1, "manifest format 1, like sfx.json")
	var kinds: Dictionary = m.get("kinds", {})
	var got: Array = kinds.keys()
	got.sort()
	assert_eq(got, _want_kinds(), "step_boot, step_metal and the 8 panting kinds (in/out x soft/hard x low/high voice)")
	var bad: PackedStringArray = []
	for k: String in kinds:
		var d: Dictionary = kinds[k]
		var step := k.begins_with("step_")
		var n := (d.get("files", []) as Array).size()
		if not d.has("h") or d["h"] != null or int(d.get("gap", 0)) != (90 if step else 150) \
				or (n < 4 or n > 8 if step else n != 3) or (d.get("len", []) as Array).size() != n:
			bad.append(k)
	assert_eq(bad, PackedStringArray(), "every kind: h null (no music heat), gap 90 ms (steps) / 150 ms (panting), 4-8 or 3 takes, a length each")


func test_takes_import() -> void:
	var kinds: Dictionary = _manifest().get("kinds", {})
	var bad: PackedStringArray = []
	var n := {"step": 0, "pant": 0}
	for k: String in kinds:
		var d: Dictionary = kinds[k]
		var r := _range(k)
		for i: int in (d["files"] as Array).size():
			var f := str(d["files"][i])
			var st := load(DIR + f) as AudioStreamWAV
			var sec := st.get_length() if st != null else -1.0
			n["step" if k.begins_with("step_") else "pant"] += 1
			if st == null or st.format != AudioStreamWAV.FORMAT_QOA or st.stereo \
					or st.mix_rate != (STEP_RATE if k.begins_with("step_") else PANT_RATE) \
					or sec < float(r[0]) or sec > float(r[1]) or absf(sec - float(d["len"][i])) > 0.01:
				bad.append("%s (%.3f s)" % [f, sec])
	assert_true(int(n["step"]) >= 8 and int(n["step"]) <= 16 and int(n["pant"]) == 24, "8-16 step takes and 24 panting takes (8 kinds x 3)", n)
	assert_eq(bad, PackedStringArray(), "every take imports as mono QOA at 32 kHz (steps) / 22.05 kHz (panting) within its length range")


## ไฟล์ WAV ต้นฉบับ (ในแอปที่ส่งออกมีแต่ผลนำเข้า)
func test_source_wavs() -> void:
	if OS.has_feature("template"):
		print("skip  the source WAVs are not inside an exported app (only their imports)")
		return
	var kinds: Dictionary = _manifest().get("kinds", {})
	var bad: PackedStringArray = []
	var total := 0
	for k: String in kinds:
		for f: Variant in kinds[k]["files"]:
			var b := FileAccess.get_file_as_bytes(DIR + str(f))
			total += b.size()
			var why := _wav_problem(b, STEP_RATE if k.begins_with("step_") else PANT_RATE)
			if why != "":
				bad.append("%s: %s" % [f, why])
	assert_eq(bad, PackedStringArray(), "every source WAV: PCM 16-bit mono at its rate, peak <= -1 dBFS, starts and ends silent (no click at a seam)")
	assert_true(total > 0 and total <= CAP, "all body WAVs together <= 1 MB (%d bytes)" % total)


## "" = ดี · ไม่งั้นบอกว่าผิดตรงไหน
func _wav_problem(b: PackedByteArray, rate: int) -> String:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		return "not a RIFF/WAVE file"
	var o := 12
	var fmt_ok := false
	while o + 8 <= b.size():
		var id := b.slice(o, o + 4).get_string_from_ascii()
		var size := b.decode_u32(o + 4)
		if id == "fmt ":
			fmt_ok = b.decode_u16(o + 8) == 1 and b.decode_u16(o + 10) == 1 and b.decode_u32(o + 12) == rate and b.decode_u16(o + 22) == 16
			if not fmt_ok:
				return "format %d, %d channel(s), %d Hz, %d bit" % [b.decode_u16(o + 8), b.decode_u16(o + 10), b.decode_u32(o + 12), b.decode_u16(o + 22)]
		elif id == "data" and fmt_ok:
			var a := o + 8
			var e := mini(b.size(), a + size) - 2
			var peak := 0
			for p in range(a, e + 1, 2):
				peak = maxi(peak, absi(b.decode_s16(p)))
			if peak > PEAK_MAX:
				return "peak %d over -1 dBFS" % peak
			if absi(b.decode_s16(a)) > 1 or absi(b.decode_s16(e)) > 1:
				return "the first or last sample is not silent"
			return ""
		o += 8 + size + (size & 1)
	return "no fmt/data chunk"


func test_export_presets() -> void:
	if OS.has_feature("template"):
		print("skip  export_presets.cfg is not inside an exported app")
		return
	var cf := ConfigFile.new()
	assert_eq(cf.load("res://export_presets.cfg"), OK, "export_presets.cfg loads")
	var names: PackedStringArray = []
	var missing: PackedStringArray = []
	for sec: String in cf.get_sections():
		if not cf.has_section_key(sec, "include_filter"):
			continue
		names.append(str(cf.get_value(sec, "name", sec)))
		var parts: PackedStringArray = []
		for p: String in str(cf.get_value(sec, "include_filter")).split(","):
			parts.append(p.strip_edges())
		if not parts.has("assets/body_sfx/body_sfx.json"):
			missing.append(names[-1])
	assert_eq(names.size(), 2, "two export presets (Windows Desktop, Android)")
	assert_eq(missing, PackedStringArray(), "both presets export body_sfx.json, or the apps would play no body sounds")


func test_credits() -> void:
	if OS.has_feature("template"):
		print("skip  CREDITS.md is not inside an exported app")
		return
	var src: Dictionary = _manifest().get("sources", {})
	var cr := FileAccess.get_file_as_string(DIR + "CREDITS.md")
	assert_true(cr.contains("pant_") and cr.contains("synthesized"), "CREDITS.md is present and says the panting is synthesized")
	if str(src.get("steps", "")) != "pack":
		assert_true(cr.contains("step_boot") and cr.contains("synthesized"), "synthesized footsteps are said so")
		return
	var p: Dictionary = src.get("pack", {})
	assert_eq(str(p.get("licence", "")), "CC0 1.0", "the downloaded footsteps are used under CC0")
	assert_true((p.get("page_licences", []) as Array).has("CC0"), "the pack's page lists CC0 (checked by the script)")
	var missing: PackedStringArray = []
	for s: String in [str(p.get("page", "?")), str(p.get("url", "?")), str(p.get("author", "?")), str(p.get("sha256", "?")), "CC0"]:
		if not cr.contains(s):
			missing.append(s)
	var files: Dictionary = src.get("files", {})
	for f: String in files:
		if not cr.contains(f) or not cr.contains(str((files[f] as Dictionary).get("from", "?"))):
			missing.append(f)
	assert_eq(files.size(), 8, "8 downloaded takes (4 boot, 4 metal) are recorded")
	assert_eq(missing, PackedStringArray(), "CREDITS.md names the URL, author and licence of every downloaded take")


func test_body_through_arena_sound() -> void:
	var lone := Node.new()
	assert_false(ArenaSound.body(lone, &"step_boot"), "no tree, no Sfx: body() is silent and does not crash")
	lone.free()
	var s := _root().get_node_or_null(^"Sfx")
	assert_true(s != null, "the Sfx autoload runs")
	if s == null:
		return
	var had := bool(s.call("has", &"step_boot"))
	var page := bool(s.call("has", &"stomp"))
	var holder := Node3D.new()
	_root().add_child(holder)
	assert_true(ArenaSound.ensure_body(holder), "ensure_body merges body_sfx.json into Sfx")
	assert_true(bool(s.call("has", &"step_metal")) and bool(s.call("has", &"pant_in_soft_low")), "the body kinds are there")
	assert_eq(bool(s.call("has", &"stomp")), page, "the page's kinds stay")
	assert_false(ArenaData.SOUNDS.has("step_boot"), "body kinds stay out of ArenaData.SOUNDS (page DEF kinds only)")
	var by: Dictionary = s.get("stats")["by"]
	var before := [int(by.get("step_boot", 0)), int(by.get("pant_in_soft_low", 0))]
	assert_true(ArenaSound.body(holder, &"step_boot", Vector3(0.1, 0.05, 0.0), 0.55, 1.02), "a footstep plays")
	assert_true(ArenaSound.body(holder, &"pant_in_soft_low", Vector3(0.0, 1.6, 0.0), 0.3), "a breath plays")
	by = s.get("stats")["by"]
	assert_eq([int(by.get("step_boot", 0)), int(by.get("pant_in_soft_low", 0))], [before[0] + 1, before[1] + 1], "Sfx counted both")
	assert_false(ArenaSound.body(holder, &"no_such_body_sound"), "an unknown body kind is silent")
	holder.free()
	if not had:
		s.call("load_manifest")       # คืนสภาพ autoload ให้เทสอื่น
