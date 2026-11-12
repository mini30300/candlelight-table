extends "res://tests/testing.gd"
## The i18n fragment files ui/i18n/{menu,hall,battle,arena,arena_hud,arena_data}.json (LOBBY_SPEC §0.7, ARENA_SPEC §1): each is a flat Thai → English
## object with English-only values, no key is in two fragments or already in another source (reuse a key that
## exists instead), and the I18n autoload finds every fragment key without overwriting i18n_extra.json.

const I18nScript := preload("res://ui/i18n.gd")

var thai_re := RegEx.create_from_string("[฀-๿]")
var line_re := RegEx.create_from_string("^  \"(?:[^\"\\\\]|\\\\.)*\": \"(?:[^\"\\\\]|\\\\.)*\",?$")


func _raw(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_fragment_list() -> void:
	# the three arena fragments were added on purpose (ARENA_SPEC §12.1 R0), in the spec's order
	assert_eq(Array(I18nScript.FRAGMENTS), ["res://ui/i18n/menu.json", "res://ui/i18n/hall.json", "res://ui/i18n/battle.json", "res://ui/i18n/arena.json", "res://ui/i18n/arena_hud.json", "res://ui/i18n/arena_data.json"], "I18n loads the six fragments in this order")
	for path in I18nScript.FRAGMENTS:
		assert_true(FileAccess.file_exists(path), "fragment exists: " + path)
	# a file in the folder that FRAGMENTS does not list would never load (the data lint fails on it as well)
	var on_disk := []
	for fn in DirAccess.get_files_at("res://ui/i18n"):
		if fn.ends_with(".json"):
			on_disk.append("res://ui/i18n/" + fn)
	on_disk.sort()
	var listed := Array(I18nScript.FRAGMENTS)
	listed.sort()
	assert_eq(on_disk, listed, "res://ui/i18n holds exactly the fragments I18n loads")


func test_fragments_are_thai_to_english_objects() -> void:
	for path in I18nScript.FRAGMENTS:
		var data: Variant = _raw(path)
		assert_true(data is Dictionary, path + " parses as a JSON object")
		if not data is Dictionary:
			continue
		var bad := []
		for k in data:
			var v: Variant = data[k]
			if not v is String or str(v).strip_edges().is_empty() or thai_re.search(str(v)) != null or thai_re.search(str(k)) == null:
				bad.append(k)
		assert_eq(bad, [], path + ": every key is Thai and every value is non-empty English")
		var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
		var odd := []
		for i in range(1, lines.size() - 1):
			if line_re.search(lines[i]) == null:
				odd.append(lines[i])
		assert_eq(odd, [], path + ": two-space indent, one pair per line")


func test_no_key_twice() -> void:
	var page: Variant = _raw(I18nScript.PAGE_PATH)
	var extra: Variant = _raw(I18nScript.EXTRA_PATH)
	assert_true(page is Dictionary and extra is Dictionary, "data/i18n_en.json and ui/i18n_extra.json parse")
	var seen := {}
	var twice := []
	var elsewhere := []
	for path in I18nScript.FRAGMENTS:
		var data: Variant = _raw(path)
		if not data is Dictionary:
			continue
		for k in data:
			if seen.has(k):
				twice.append("%s (%s and %s)" % [k, seen[k], path.get_file()])
			seen[k] = path.get_file()
			if I18nScript.EN.has(k) or (extra as Dictionary).has(k) or (page as Dictionary).has(k):
				elsewhere.append("%s (%s)" % [k, path.get_file()])
	assert_eq(twice, [], "no key is in two fragments")
	assert_eq(elsewhere, [], "no fragment key is already in I18n.EN, ui/i18n_extra.json or data/i18n_en.json (reuse it)")
	assert_true(seen.size() >= 7, "the shared words are seeded: %d fragment keys" % seen.size())


func test_lookup_finds_fragment_keys() -> void:
	var i: Node = I18nScript.new()
	i.english = true
	var wrong := []
	for path in I18nScript.FRAGMENTS:
		var data: Variant = _raw(path)
		if not data is Dictionary:
			continue
		for k in data:
			if i.t(k) != str(data[k]):
				wrong.append(k)
	assert_eq(wrong, [], "I18n.t gives the fragment's English for every fragment key")
	assert_eq(i.t("ตั้งค่า"), "Settings", "a seeded shared word translates")
	assert_eq(i.t("ล็อบบี้"), "Lobby", "the lobby's on-screen name translates")
	var extra: Variant = _raw(I18nScript.EXTRA_PATH)
	var changed := []
	for k in extra:
		if str(i.extra.get(k, "")) != str(extra[k]):
			changed.append(k)
	assert_eq(changed, [], "merging the fragments never overwrites an i18n_extra.json entry")
	i.free()
	assert_true(I18n.has_key("เร็วๆ นี้"), "the live autoload knows the fragment keys")
