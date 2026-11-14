extends "res://tests/testing.gd"
## Every Thai literal in the menu track's screens (main menu, settings, title art, candle style, GPU check) is a
## whole key of the I18n dictionaries, because I18n.t matches whole strings only (LOBBY_SPEC §7.1), and the
## version label never shows the Thai APP_VER raw.

const SCRIPTS := [
	"res://ui/screens/main_menu.gd", "res://ui/screens/main_menu.tscn",
	"res://ui/screens/settings.gd", "res://ui/screens/settings.tscn",
	"res://ui/widgets/title_art.gd", "res://ui/theme/candle_style.gd",
	"res://ui/screens/gpu_check.gd", "res://ui/screens/gpu_check.tscn",
]
const LANG_NAMES: PackedStringArray = ["ไทย"]

var thai_re := RegEx.create_from_string("[฀-๿]")


func test_every_thai_literal_of_the_menu_is_a_whole_key() -> void:
	var lit_re := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var missing := []
	var n := 0
	for path in SCRIPTS:
		var lits := PackedStringArray()
		if path.ends_with(".tscn"):
			lits = _scene_strings(path)
			assert_true(not lits.is_empty(), "read " + path)
		else:
			var src := FileAccess.get_file_as_string(path)
			assert_true(src != "", "read " + path)
			for line in src.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				for m in lit_re.search_all(line):
					lits.append(m.get_string(1).replace("\\\"", "\""))
		for lit in lits:
			if thai_re.search(lit) == null or LANG_NAMES.has(lit):
				continue
			n += 1
			if not I18n.has_key(lit):
				missing.append(path.get_file() + ": " + lit)
	assert_true(n >= 40, "found %d Thai literals in the menu track's files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


func test_version_label_never_shows_thai() -> void:
	var menu_script: GDScript = load("res://ui/screens/main_menu.gd")
	var was := I18n.english
	I18n.english = true
	var en: String = menu_script.call("version_text")
	I18n.english = false
	var th: String = menu_script.call("version_text")
	I18n.english = was
	assert_true(thai_re.search(en) == null, "English version label has no Thai: " + en)
	var v: String = menu_script.call("version_number")
	assert_true(thai_re.search(v) == null and v != "" and Version.APP_VER.ends_with(v), "the version number without its Thai prefix: " + v)
	# 0.4 (ARENA_SPEC §15): the weapons arena is a user-visible release, so APP_VER moved on purpose (0.3 -> 0.4)
	# 0.5 (NET_SPEC §15): play with friends on the local network is a user-visible release (0.4 -> 0.5)
	# 0.6: battle sounds and animations from the old game, the arena dodge, online only in the personal build (0.5 -> 0.6)
	# 0.7 (PACK_SPEC §9): pack rooms behind the docking airlock; room poses use the +30 m band, which both devices must
	# understand, so the wrong_app gate has to keep 0.6 and 0.7 apart (0.6 -> 0.7)
	# 0.8: the deck's work desk replaces the treasure chest and the public app's airlock loses its ring (0.7 -> 0.8)
	# 0.9: the body faces the camera in the arena, play with friends in every app (on the deck), the desk by the exit,
	# and a pack room can take over the arena door (0.8 -> 0.9)
	assert_eq(v, "0.9", "this release is ใหม่ 0.9")
	assert_true(en.contains(v) and th.contains(v), "both labels carry the version number %s (%s / %s)" % [v, th, en])


## Every String property stored in a scene, read through its SceneState (an exported game keeps scenes binary).
func _scene_strings(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var ps := load(path) as PackedScene
	if ps == null:
		return out
	var st := ps.get_state()
	for i in st.get_node_count():
		for j in st.get_node_property_count(i):
			var v: Variant = st.get_node_property_value(i, j)
			if v is String:
				out.append(v)
	return out
