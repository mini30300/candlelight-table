extends "res://tests/testing.gd"
## The online battle text (NET_SPEC §7.3, §12.2 BATTLE): every Thai literal of the online parts (battle_setup.gd,
## battle_screen.gd, net_seats.gd, the net battle scripts) is a whole key of I18n; ui/i18n/online_battle.json has an
## English pair for each key with the same {placeholders}, no Thai on the English side, and every key is used by the
## battle track's files.

const SCRIPTS := ["res://ui/screens/battle_setup.gd", "res://ui/screens/battle_screen.gd", "res://ui/battle/net_seats.gd",
	"res://ui/battle/net_match_runner.gd", "res://ui/battle/lockstep.gd", "res://ui/battle/net_battle_link.gd"]
const FRAGMENT := "res://ui/i18n/online_battle.json"

var thai_re := RegEx.create_from_string("[฀-๿]")
var lit_re := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
var ph_re := RegEx.create_from_string("\\{[a-z_]+\\}")


func test_every_thai_literal_is_a_whole_key() -> void:
	var missing := []
	var n := 0
	for path in SCRIPTS:
		for lit in _literals(path):
			if thai_re.search(lit) == null:
				continue
			n += 1
			if not I18n.has_key(lit):
				missing.append(path.get_file() + ": " + lit)
	assert_true(n >= 50, "found %d Thai literals in the battle track's files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


func test_fragment_pairs() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	assert_true(d is Dictionary and not (d as Dictionary).is_empty(), "online_battle.json is a filled dictionary")
	if not d is Dictionary:
		return
	var bad := []
	var used := {}
	for path in SCRIPTS:
		for lit in _literals(path):
			used[lit] = true
	for th: String in d:
		var en := str(d[th])
		if thai_re.search(th) == null or en == "" or thai_re.search(en) != null:
			bad.append("%s -> %s" % [th, en])
		elif _placeholders(th) != _placeholders(en):
			bad.append("%s: placeholders %s vs %s" % [th, str(_placeholders(th)), str(_placeholders(en))])
		if not used.has(th):
			bad.append("unused: " + th)
		if I18n.lookup(th) != en:
			bad.append("not loaded: " + th)
	assert_eq(bad, [], "every key has an English pair with the same placeholders, is used and is loaded")


func test_english_mode_lines() -> void:
	var was := I18n.english
	I18n.english = true
	assert_eq(I18n.t("รอ {name}…").format({"name": "Somchai"}), "Waiting for Somchai…", "wait banner in English")
	assert_eq(I18n.t("เจ้าห้อง"), "Host", "the host's name in English")
	assert_eq(NetSeats.error_text("member_gone", {}), "That friend has left the room", "member_gone in English")
	I18n.english = was


func _placeholders(s: String) -> Array:
	var out := []
	for m in ph_re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


## String literals of a script (comment lines skipped).
func _literals(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var src := FileAccess.get_file_as_string(path)
	for line in src.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#"):
			continue
		for m in lit_re.search_all(line):
			out.append(m.get_string(1))
	return out
