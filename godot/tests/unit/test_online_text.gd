extends "res://tests/testing.gd"
## The play-with-friends text (NET_SPEC §7.3, §12.2 DECK): every Thai literal of the airlock screen (lobby.gd / .tscn),
## FriendTags, OnlineText and the hall additions is a whole key of I18n; every gate key (NetGate.KEYS) and local failure
## key has a Thai template with an English pair carrying the same {placeholders}; the where line, the status line and
## the default name translate; ui/i18n/online.json is clean and every key is used by the deck track's files; no Thai
## under net/ (its text lives in OnlineText).

const SCRIPTS := ["res://ui/screens/lobby.gd", "res://ui/screens/lobby.tscn", "res://ui/widgets/friend_tags.gd",
	"res://ui/online_text.gd", "res://ui/screens/hall_screen.gd", "res://ui/screens/main_menu.gd",
	"res://scenes/hall/hall_friends.gd"]
const FRAGMENT := "res://ui/i18n/online.json"
const NET_DIR := "res://net"

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
	assert_true(n >= 60, "found %d Thai literals in the deck track's online files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


func test_every_reason_key_has_thai_and_english() -> void:
	var keys := PackedStringArray(OnlineText.GATE_KEYS) + PackedStringArray(OnlineText.LOCAL_KEYS)
	keys.append_array(PackedStringArray(NetGate.KEYS))
	keys.append_array(PackedStringArray(NetGate.LOCAL_KEYS))
	keys.append("reconnecting")
	var bad := []
	for key in keys:
		var th := str(OnlineText.REASONS.get(key, ""))
		var en := I18n.lookup(th)
		if th == "" or thai_re.search(th) == null or en == "" or thai_re.search(en) != null:
			bad.append("%s: %s -> %s" % [key, th, en])
			continue
		if _placeholders(th) != _placeholders(en):
			bad.append("%s: placeholders %s vs %s" % [key, str(_placeholders(th)), str(_placeholders(en))])
	assert_eq(bad, [], "every gate and local failure key has a Thai template and an English pair with the same placeholders")
	assert_eq(PackedStringArray(OnlineText.GATE_KEYS), PackedStringArray(NetGate.KEYS), "OnlineText knows exactly the gate's keys, in its order")
	var was := I18n.english
	I18n.english = true
	var wrong_app := OnlineText.reason("wrong_app", {"host": "ใหม่ 0.5", "mine": "ใหม่ 0.4"})
	assert_true(wrong_app.begins_with("App versions differ") and wrong_app.contains("host 0.5") and wrong_app.contains("you 0.4")
		and not wrong_app.contains("{") and thai_re.search(wrong_app) == null, "English wrong_app fills both version numbers, no Thai prefix: " + wrong_app)
	var full := OnlineText.reason("full", {"n": 6, "max": 6})
	assert_eq(full, "The room is full (6/6 players)", "English full fills n and max")
	assert_true(thai_re.search(OnlineText.reason("no_such_key")) == null, "an unknown key falls back to an English line")
	var row := OnlineText.row_reason({"why": "wrong_rules", "rules": 9})
	assert_true(row.contains("9") and row.contains(str(Version.RULES_V)), "a greyed room row names both rules versions: " + row)
	I18n.english = false
	assert_eq(OnlineText.reason("full", {"n": 3, "max": 6}), "ห้องเต็มแล้ว (3/6 คน)", "Thai full")
	I18n.english = was


func test_where_status_and_default_name() -> void:
	var was := I18n.english
	for where in ["deck", "setup", "battle", "arena", "army", "settings", "menu"]:
		I18n.english = false
		var th := OnlineText.where_text(where)
		I18n.english = true
		var en := OnlineText.where_text(where)
		assert_true(thai_re.search(th) != null and en != th and thai_re.search(en) == null, "where %s: %s / %s" % [where, th, en])
	I18n.english = true
	var status := OnlineText.status("เพื่อน", 3, 6)
	assert_eq(status, "Online · เพื่อน's room · 3/6 players", "the English status line keeps the player's name as typed")
	assert_true(OnlineText.default_name(123) == "Player 123", "the default name in English")
	I18n.english = false
	assert_eq(OnlineText.status("เพื่อน", 3, 6), "ออนไลน์ · ห้องของ เพื่อน · 3/6 คน", "the Thai status line")
	assert_eq(OnlineText.default_name(456), "ผู้เล่น 456", "the default name in Thai")
	I18n.english = was


func test_online_fragment_is_clean_and_used() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	assert_true(data is Dictionary and (data as Dictionary).size() >= 40, "online.json is an object with the airlock's strings")
	if not data is Dictionary:
		return
	var src := ""
	for path in SCRIPTS:
		src += "\n".join(_literals(path)) + "\n"
	var unused := []
	var bad := []
	for k in data:
		var en := str(data[k])
		if thai_re.search(str(k)) == null or thai_re.search(en) != null or en.strip_edges() == "" or _placeholders(str(k)) != _placeholders(en):
			bad.append(k)
		if not src.contains(str(k)):
			unused.append(k)
	assert_eq(bad, [], "every online.json key is Thai, every value English with the same placeholders")
	assert_eq(unused, [], "every online.json key is used by the deck track's files")


func test_no_thai_under_net() -> void:
	var found := []
	var n := 0
	for fn in DirAccess.get_files_at(NET_DIR):
		if not fn.ends_with(".gd"):
			continue
		n += 1
		for lit in _literals(NET_DIR + "/" + fn):
			if thai_re.search(lit) != null:
				found.append(fn + ": " + lit)
	assert_true(n >= 1, "read %d scripts under net/" % n)
	assert_eq(found, [], "no Thai string literal under net/ (OnlineText holds the text)")


func _placeholders(s: String) -> Array:
	var out := []
	for m in ph_re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


## String literals of a script (comment lines skipped) or every String property stored in a scene.
func _literals(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if path.ends_with(".tscn"):
		var ps := load(path) as PackedScene
		assert_true(ps != null, "load " + path)
		if ps == null:
			return out
		var st := ps.get_state()
		for i in st.get_node_count():
			for j in st.get_node_property_count(i):
				var v: Variant = st.get_node_property_value(i, j)
				if v is String:
					out.append(v)
		return out
	var src := FileAccess.get_file_as_string(path)
	assert_true(src != "", "read " + path)
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for m in lit_re.search_all(line):
			out.append(m.get_string(1).replace("\\\"", "\""))
	return out
