extends SceneTree
## Turns assets/anim/clips.json (tools/bake_anim.js: the old page's rig sampled at 30 Hz) into ONE AnimationLibrary,
## assets/anim/humanoid.res, shared by every skinned kit (same 23 bones, same names, same rest convention: no
## retargeting). Headless, no display needed:
##   <godot> --headless --path godot -s tools/bake_anim.gd [-- --in res://assets/anim/clips.json --out res://assets/anim/humanoid.res]
## Track paths are "Skeleton3D:<bone>" (assets/kits/CONTRACT.md §2: <kit> Node3D > Skeleton3D > <kit>_mesh), so an
## AnimationPlayer added as a child of the kit's root node with root_node = ".." plays them as they are.
## Every clip: a rotation track per bone (local rotation, all 23 every frame), a position track for the pelvis (and
## for the chest and shoulders where the idle breathes), keys every 1/30 s. The rig's units are those of an unscaled
## figure: a kit of scale S sets Skeleton3D.motion_scale = S and travels at speed * S (kits.json `scale`).
## Each Animation carries the clip's data as metadata: speed (rig m/s while it plays in place), turn (radians the pelvis
## turns by the end), travel (per frame, starts and stops), contact_l / contact_r (heel, ball, flat or "" per frame),
## events ([{t, kind}]: shot, thud, raised, lower), alpha (the page's fade, falls), drives (the bones it moves),
## hold_mode (all: a kit's holds bend every bone they name · undriven: only bones the clip does not drive · none),
## kit (seats), from / kind / gun / hand / heavy (which of the page's attacks it is), set, note. The library carries
## holds (per kit: how its own pose bends the clip's bones, see tools/bake_anim.js), joints, proofs and source.

const DEFAULT_IN := "res://assets/anim/clips.json"
const DEFAULT_OUT := "res://assets/anim/humanoid.res"
const SKELETON := "Skeleton3D"
const FPS := 30
const JOINTS := 23

var _in := DEFAULT_IN
var _out := DEFAULT_OUT
var _errors := PackedStringArray()


func _initialize() -> void:
	_parse_args()
	var t0 := Time.get_ticks_msec()
	if not FileAccess.file_exists(_in):
		_fail("%s is missing: run node godot/tools/bake_anim.js first" % _in)
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(_in))
	if not (doc is Dictionary):
		_fail("%s does not parse" % _in)
		return
	var lib := build_library(doc, _errors)
	if not _errors.is_empty():
		for e in _errors.slice(0, 30):
			print("FAIL  " + e)
		_fail("%d problems in %s" % [_errors.size(), _in])
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	var err := ResourceSaver.save(lib, _out, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_fail("cannot save %s (error %d)" % [_out, err])
		return
	var names := lib.get_animation_list()
	var keys := 0
	for n in names:
		var a := lib.get_animation(n)
		for ti in a.get_track_count():
			keys += a.track_get_key_count(ti)
	var size := FileAccess.get_file_as_bytes(_out).size()
	print("bake_anim: %d clips, %d keys, holds for %d kits -> %s (%.2f MB, %d ms)" % [names.size(), keys,
		(lib.get_meta("holds", {}) as Dictionary).size(), _out, size / 1048576.0, Time.get_ticks_msec() - t0])
	quit(0)


func _fail(msg: String) -> void:
	print("FAIL  bake_anim: " + msg)
	quit(1)


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i] == "--in" and i + 1 < a.size():
			_in = a[i + 1]
			i += 1
		elif a[i] == "--out" and i + 1 < a.size():
			_out = a[i + 1]
			i += 1
		i += 1


## clips.json (parsed) -> AnimationLibrary; problems are appended to `errors` (the library is then incomplete).
static func build_library(doc: Dictionary, errors: PackedStringArray) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	if int(doc.get("format", 0)) != 1:
		errors.append("format %s (expected 1)" % str(doc.get("format")))
	if int(doc.get("fps", 0)) != FPS:
		errors.append("fps %s (expected %d)" % [str(doc.get("fps")), FPS])
	var joints := PackedStringArray()
	for j in doc.get("joints", []):
		joints.append(String(j))
	if joints.size() != JOINTS:
		errors.append("%d joints (expected %d)" % [joints.size(), JOINTS])
		return lib
	var clips: Variant = doc.get("clips")
	if not (clips is Dictionary) or (clips as Dictionary).is_empty():
		errors.append("no clips")
		return lib
	var names: Array = (clips as Dictionary).keys()
	names.sort()
	for name in names:
		var anim := clip_to_animation(String(name), clips[name], joints, errors)
		if anim != null:
			lib.add_animation(StringName(name), anim)
	lib.set_meta("joints", joints)
	lib.set_meta("source", String(doc.get("source", "")))
	lib.set_meta("proofs", doc.get("proofs", {}))
	lib.set_meta("holds", _holds(doc.get("holds", {})))
	return lib


static func clip_to_animation(name: String, c: Dictionary, joints: PackedStringArray, errors: PackedStringArray) -> Animation:
	var frames := int(c.get("frames", 0))
	var loop := bool(c.get("loop", false))
	if int(c.get("fps", 0)) != FPS or frames < 1 or not (c.get("q") is Dictionary) or not (c.get("t") is Dictionary):
		errors.append("%s: fps, frames, q or t missing" % name)
		return null
	var q: Dictionary = c["q"]
	var t: Dictionary = c["t"]
	var anim := Animation.new()
	var length := float(c.get("length", 0.0))
	anim.length = maxf(length, 1.0 / FPS) if frames == 1 else length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.step = 1.0 / FPS
	for j in joints:
		var keys: Variant = q.get(j)
		if not (keys is Array) or (keys as Array).size() != frames:
			errors.append("%s: bone %s has %s keys for %d frames" % [name, j, str((keys as Array).size()) if keys is Array else "no", frames])
			return null
		var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(ti, NodePath("%s:%s" % [SKELETON, j]))
		for k in frames:
			var v: Array = keys[k]
			var rq := Quaternion(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
			if not rq.is_normalized():
				errors.append("%s: bone %s frame %d is not a unit quaternion" % [name, j, k])
				return null
			anim.rotation_track_insert_key(ti, float(k) / FPS, rq)
	if not t.has("pelvis"):
		errors.append("%s: no pelvis translation" % name)
		return null
	for j in t.keys():
		if not joints.has(String(j)):
			errors.append("%s: translation of unknown bone %s" % [name, j])
			return null
		var keys: Array = t[j]
		if keys.size() != frames:
			errors.append("%s: bone %s has %d positions for %d frames" % [name, j, keys.size(), frames])
			return null
		var ti := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(ti, NodePath("%s:%s" % [SKELETON, j]))
		for k in frames:
			var v: Array = keys[k]
			anim.position_track_insert_key(ti, float(k) / FPS, Vector3(float(v[0]), float(v[1]), float(v[2])))
	anim.set_meta("speed", float(c.get("speed", 0.0)))
	anim.set_meta("turn", float(c.get("turn", 0.0)))
	anim.set_meta("set", String(c.get("set", "")))
	anim.set_meta("hold_mode", String(c.get("holds", "all")))
	for k in ["kit", "from", "kind", "gun", "hand"]:
		anim.set_meta(k, "" if c.get(k) == null else String(c.get(k)))
	anim.set_meta("heavy", bool(c.get("heavy", false)))
	anim.set_meta("note", String(c.get("note", "")))
	anim.set_meta("drives", PackedStringArray(c.get("drives", [])))
	if c.get("contact") is Dictionary:
		anim.set_meta("contact_l", _contacts(c["contact"].get("L", [])))
		anim.set_meta("contact_r", _contacts(c["contact"].get("R", [])))
	for k in ["travel", "alpha"]:
		if c.get(k) is Array:
			anim.set_meta(k, PackedFloat32Array(c[k]))
	if c.get("events") is Array:
		var ev: Array[Dictionary] = []
		for e in c["events"]:
			ev.append({"t": float(e.get("t", 0.0)), "kind": String(e.get("kind", ""))})
		anim.set_meta("events", ev)
	if c.get("seam") is Dictionary:
		anim.set_meta("seam", c["seam"])
	return anim


static func _contacts(a: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for v in a:
		out.append("" if v == null else String(v))
	return out


## holds[kit] = {joints: {bone: {C: Quaternion, w: float} | {mul: Quaternion} | {pre: Quaternion} | "ik", res: deg}, root, ik}
static func _holds(src: Variant) -> Dictionary:
	var out := {}
	if not (src is Dictionary):
		return out
	for kit in src.keys():
		var h: Variant = src[kit]
		if not (h is Dictionary) or not (h.get("joints") is Dictionary):
			continue
		var joints := {}
		for j in h["joints"].keys():
			var v: Variant = h["joints"][j]
			if v is String:
				joints[String(j)] = String(v)
				continue
			var o := {"res": float(v.get("res", 0.0))}
			for key in ["C", "mul", "pre"]:
				if v.get(key) is Array:
					var a: Array = v[key]
					o[key] = Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
			if v.has("w"):
				o["w"] = float(v["w"])
			joints[String(j)] = o
		var e := {"joints": joints, "ik": bool(h.get("ik", false))}
		if h.get("root") is Array:
			var r: Array = h["root"]
			e["root"] = Vector3(float(r[0]), float(r[1]), float(r[2]))
		out[String(kit)] = e
	return out
