extends "res://tests/testing.gd"
## The weapons arena's text (ARENA_SPEC §1, §13.2): every Thai literal of the arena screen and of the deck's arena
## additions is a whole key of the I18n dictionaries; each board template's English keeps the same {placeholders};
## the 3D arena scripts under scenes/arena/ carry no Thai; ui/i18n/arena.json is a clean fragment the screen uses.

const SCRIPTS := ["res://ui/screens/arena_screen.gd", "res://ui/screens/arena_screen.tscn"]
const SCREEN := "res://ui/screens/arena_screen.gd"
const HALL := "res://ui/screens/hall_screen.gd"
const FRAGMENT := "res://ui/i18n/arena.json"
const TEMPLATES := ["HP_LINE", "HITS_LINE", "PROMPT_KEYS", "PROMPT_TOUCH"]

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
	assert_true(n >= 20, "found %d Thai literals in the arena screen" % n)
	assert_eq(missing, [], "every Thai literal of the arena screen is a whole key")
	var hall: Dictionary = (load(HALL) as Script).get_script_constant_map()
	for table in ["NAMES", "SIGNS"]:
		var th := str((hall[table] as Dictionary).get("arena", ""))
		assert_eq(th, "อารีน่าทดสอบอาวุธ", "the deck's %s.arena is the Weapons Arena" % table)
		assert_eq(I18n.lookup(th), "Weapons Arena", "and its English pair")


func test_templates_keep_their_placeholders() -> void:
	var consts: Dictionary = (load(SCREEN) as Script).get_script_constant_map()
	for name in TEMPLATES:
		var th := str(consts[name])
		var en := I18n.lookup(th)
		assert_true(en != "" and thai_re.search(en) == null, "%s has an English pair (%s)" % [name, en])
		var a := []
		for m in ph_re.search_all(th):
			a.append(m.get_string())
		var b := []
		for m in ph_re.search_all(en):
			b.append(m.get_string())
		a.sort()
		b.sort()
		assert_eq(b, a, "%s: the English keeps the same placeholders" % name)
	var was := I18n.english
	I18n.english = true
	var body: String = (load(SCREEN) as Script).call(&"board_body", {"bot_on": true, "hp": 220, "hp_max": 300, "hits": 7, "damage": 80, "dead": false})
	assert_eq(body, "Bot: ON\nHP 220/300\n7 hits · 80 damage dealt", "the English board body")
	body = (load(SCREEN) as Script).call(&"board_body", {"bot_on": false, "hp": 0, "hp_max": 300, "hits": 25, "damage": 300, "dead": true})
	assert_true(thai_re.search(body) == null and body.contains("Down · press reset"), "the English board body while dead: " + body)
	I18n.english = false
	body = (load(SCREEN) as Script).call(&"board_body", {"bot_on": false, "hp": 300, "hp_max": 300, "hits": 0, "damage": 0, "dead": false})
	assert_eq(body, "บอท: ปิด\nพลังชีวิต 300/300\nโดน 0 ครั้ง · ความเสียหายรวม 0", "the Thai board body")
	I18n.english = was


func test_no_thai_under_scenes_arena() -> void:
	var found := []
	var n := 0
	for fn in DirAccess.get_files_at("res://scenes/arena"):
		if not (fn.ends_with(".gd") or fn.ends_with(".tscn") or fn.ends_with(".gdshader")):
			continue
		n += 1
		var path := "res://scenes/arena/" + fn
		for lit in _literals(path):
			if thai_re.search(lit) != null:
				found.append(fn + ": " + lit)
	assert_true(n >= 6, "scanned %d files under scenes/arena" % n)
	assert_eq(found, [], "scenes/arena/ holds no Thai strings (3D labels get their text from the arena screen)")


func test_arena_fragment_is_clean_and_used() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	assert_true(data is Dictionary and not (data as Dictionary).is_empty(), "arena.json is a non-empty object")
	if not data is Dictionary:
		return
	var src := ""
	for path in SCRIPTS:
		src += "\n".join(_literals(path)) + "\n"
	var unused := []
	var bad := []
	for k in data:
		if thai_re.search(str(k)) == null or thai_re.search(str(data[k])) != null or str(data[k]).strip_edges() == "":
			bad.append(k)
		if not src.contains(str(k)):
			unused.append(k)
		assert_eq(I18n.lookup(str(k)), str(data[k]), "I18n finds the arena key " + str(k))
	assert_eq(bad, [], "every arena.json key is Thai and every value is English")
	assert_eq(unused, [], "every arena.json key is used by the arena screen")


## String literals of a script (comment lines skipped) or every String property stored in a scene
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
		var t := line.strip_edges()
		if t.begins_with("#") or t.begins_with("//"):
			continue
		for m in lit_re.search_all(line):
			out.append(m.get_string(1).replace("\\\"", "\""))
	return out
