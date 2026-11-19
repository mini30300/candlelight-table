extends "res://tests/testing.gd"
## Names inside compressed Godot resources (header RSCC) under res://assets. The data lint (tools/validate_data.py)
## cannot read their zstd bytes, so it checks only their file names; this test loads each one and checks every
## string it carries (resource names, metadata, blend shape and surface names, bind names) against the same banned
## list (AGENTS.md rule 1), read from the lint itself. A planted name shows the scan has teeth. Where the lint is not
## packed (an exported build) there is nothing to compare with, and the test says so.

const LINT := "res://tools/validate_data.py"
const ROOT := "res://assets"
## generated, git-ignored (the lint skips them too)
const SKIP: PackedStringArray = ["res://assets/kits", "res://assets/impostors", "res://assets/anim"]


func test_names_inside_compressed_resources() -> void:
	if not FileAccess.file_exists(LINT):
		assert_true(true, "the data lint is not in this build: nothing to compare with")
		return
	var lint := FileAccess.get_file_as_string(LINT)
	var subs := _list(lint, "_SUB")
	var words := _list(lint, "_WORD")
	assert_true(subs.size() >= 5 and words.size() >= 5, "read the banned list from the lint", [subs.size(), words.size()])
	if subs.is_empty() or words.is_empty():
		return
	var rx := _regex(subs, words)
	var two_pi := _rot13("GNH")
	# teeth: a planted resource name and a planted blend shape name are caught
	var planted := ArrayMesh.new()
	planted.resource_name = "body " + words[0]
	assert_true(not _hits(rx, _strings_of(planted), two_pi).is_empty(), "a planted resource name is caught")
	var planted2 := ArrayMesh.new()
	planted2.add_blend_shape(StringName(words[0] + "-shape"))
	assert_true(not _hits(rx, _strings_of(planted2), two_pi).is_empty(), "a planted blend shape name is caught")
	var plain := ArrayMesh.new()
	plain.resource_name = two_pi + " body"
	assert_true(_hits(rx, _strings_of(plain), two_pi).is_empty(), "Godot's upper-case 2*pi constant passes, as in the lint")
	# every compressed resource that ships
	var files := _compressed(ROOT)
	assert_true(files.size() >= 1, "found compressed resources under " + ROOT, files.size())
	for path in files:
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_true(res != null, "loads " + path)
		if res == null:
			continue
		var strs := _strings_of(res)
		var bad := _hits(rx, strs, two_pi)
		# never echo the banned word itself: report the count only
		assert_true(bad.is_empty(), "%s: no banned name in its %d strings" % [path, strs.size()], "%d hit(s)" % bad.size())


# ---------------------------------------------------------------- the banned list, as the lint reads it

## the quoted ROT13 items of `NAME = [...]` in the lint's source
static func _list(src: String, name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var m := RegEx.create_from_string("(?m)^" + name + " = \\[([^\\]]*)\\]").search(src)
	if m == null:
		return out
	for q in RegEx.create_from_string("'([^']*)'|\"([^\"]*)\"").search_all(m.get_string(1)):
		out.append(_rot13(q.get_string(1) if q.get_string(1) != "" else q.get_string(2)))
	return out


static func _rot13(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 97 and c <= 122:
			c = (c - 97 + 13) % 26 + 97
		elif c >= 65 and c <= 90:
			c = (c - 65 + 13) % 26 + 65
		out += String.chr(c)
	return out


## the lint's pattern: phrases anywhere, short words only between non-word characters
static func _regex(subs: PackedStringArray, words: PackedStringArray) -> RegEx:
	return RegEx.create_from_string("(?<sub>%s)|(?<![a-z0-9_'])(?<word>%s)(?![a-z0-9_'])" % [_alt(subs), _alt(words)])


static func _alt(items: PackedStringArray) -> String:
	var a := Array(items)
	a.sort_custom(func(x: String, y: String) -> bool: return x.length() > y.length())
	var parts := PackedStringArray()
	for w in a:
		parts.append(_escape(w))
	return "|".join(parts)


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}-".contains(ch) else ch
	return out


static func _hits(rx: RegEx, strs: PackedStringArray, two_pi: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in strs:
		for m in rx.search_all(t.to_lower()):
			if m.get_string("word") == two_pi.to_lower() and t.substr(m.get_start(), m.get_end() - m.get_start()) == two_pi:
				continue
			out.append(t)
	return out


# ---------------------------------------------------------------- the strings a resource carries

static func _strings_of(res: Resource) -> PackedStringArray:
	var out := PackedStringArray()
	_strings(res, out, {}, 0)
	return out


static func _strings(v: Variant, out: PackedStringArray, seen: Dictionary, depth: int) -> void:
	if depth > 8:
		return
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			out.append(str(v))
		TYPE_PACKED_STRING_ARRAY:
			out.append_array(v)
		TYPE_ARRAY:
			for e in v:
				_strings(e, out, seen, depth + 1)
		TYPE_DICTIONARY:
			for k in v:
				_strings(k, out, seen, depth + 1)
				_strings(v[k], out, seen, depth + 1)
		TYPE_OBJECT:
			var r := v as Resource
			if r == null or seen.has(r.get_instance_id()):
				return
			seen[r.get_instance_id()] = true
			for p in r.get_property_list():
				if int(p["usage"]) & PROPERTY_USAGE_STORAGE:
					_strings(r.get(p["name"]), out, seen, depth + 1)
			if r is ArrayMesh:
				var am := r as ArrayMesh
				for i in am.get_blend_shape_count():
					out.append(str(am.get_blend_shape_name(i)))
				for i in am.get_surface_count():
					out.append(am.surface_get_name(i))
			if r is Skin:
				var sk := r as Skin
				for i in sk.get_bind_count():
					out.append(str(sk.get_bind_name(i)))
			for m in r.get_meta_list():
				out.append(str(m))
				_strings(r.get_meta(m), out, seen, depth + 1)


static func _compressed(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if SKIP.has(dir):
		return out
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	for f in files:
		var p: String = dir + "/" + f
		if p.ends_with(".res") and _is_rscc(p):
			out.append(p)
	var subs := Array(d.get_directories())
	subs.sort()
	for s in subs:
		out.append_array(_compressed(dir + "/" + s))
	return out


static func _is_rscc(path: String) -> bool:
	var fa := FileAccess.open(path, FileAccess.READ)
	return fa != null and fa.get_buffer(4).get_string_from_ascii() == "RSCC"
