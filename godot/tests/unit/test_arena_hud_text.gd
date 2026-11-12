extends "res://tests/testing.gd"
## The arena HUD's text (ARENA_SPEC §1, §5.5, §13.2): every Thai literal of ui/widgets/arena_hud.gd and arena_touch.gd is
## a whole key of the I18n dictionaries (I18n.t matches whole strings only), both hints, the reload line, the downed
## line and every touch button have an English pair without Thai, the HP template keeps its {hp}/{max} placeholders in
## English, ui/i18n/arena_hud.json is a clean Thai -> English fragment whose keys these two files really use, and the
## PLAYER scripts under scenes/arena/ carry no Thai strings.

const SCRIPTS := ["res://ui/widgets/arena_hud.gd", "res://ui/widgets/arena_touch.gd"]
const WORLD_SCRIPTS := ["res://scenes/arena/arena_player.gd", "res://scenes/arena/arena_camera.gd",
	"res://scenes/arena/arena_weapons.gd", "res://scenes/arena/arena_fx.gd", "res://scenes/arena/egg_gunner.gd"]
const FRAGMENT := "res://ui/i18n/arena_hud.json"

var thai_re := RegEx.create_from_string("[฀-๿]")
var lit_re := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")


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
	assert_true(n >= 9, "found %d Thai literals in the HUD files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


func test_hints_buttons_and_lines_have_english() -> void:
	var hud: Dictionary = (load(SCRIPTS[0]) as Script).get_script_constant_map()
	var tch: Dictionary = (load(SCRIPTS[1]) as Script).get_script_constant_map()
	var keys := [hud["HINT_WALK"], hud["HINT_KEYS"], hud["HINT_TOUCH"], hud["RELOADING"], hud["DOWNED"], hud["HP_TEXT"],
		tch["FIRE_TEXT"], tch["MELEE_TEXT"], tch["RELOAD_TEXT"]]
	for id in ["gun", "sword", "punch"]:
		keys.append(ArenaData.WEAPONS[id]["th"])
	keys.append(ArenaData.BEAST["th"])
	for k in keys:
		var th := str(k)
		var en := I18n.lookup(th)
		assert_true(thai_re.search(th) != null, "Thai text: " + th)
		assert_true(en != "" and thai_re.search(en) == null, "…with English and no Thai left: " + en)
	var was := I18n.english
	I18n.english = true
	var hp := I18n.t(str(hud["HP_TEXT"])).format({"hp": 72, "max": 100})
	assert_eq(hp, "HP 72/100", "the English HP line fills both placeholders")
	assert_true(I18n.t(str(hud["HINT_KEYS"])).contains("Esc"), "the keyboard hint names Esc to pause")
	I18n.english = false
	assert_eq(I18n.t(str(hud["HP_TEXT"])).format({"hp": 72, "max": 100}), "พลังชีวิต 72/100", "the Thai HP line")
	I18n.english = was


func test_fragment_is_clean_and_used() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	# seven since integration: + "ฟัน" / "Swing", the fire button's label while the saw sword is in hand (ARENA_SPEC §17)
	assert_true(data is Dictionary and (data as Dictionary).size() == 7, "arena_hud.json holds the seven PLAYER strings")
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
		assert_eq(I18n.lookup(str(k)), str(data[k]), "I18n finds " + str(k))
	assert_eq(bad, [], "every key is Thai and every value is English")
	assert_eq(unused, [], "every key is used by the HUD or the touch controls")


func test_player_scripts_have_no_thai() -> void:
	var found := []
	for path in WORLD_SCRIPTS:
		assert_true(FileAccess.file_exists(path), "find " + path)
		for lit in _literals(path):
			if thai_re.search(lit) != null:
				found.append(path.get_file() + ": " + lit)
	assert_eq(found, [], "scenes/arena/ PLAYER scripts hold no Thai strings")


## String literals of a script (comment lines skipped).
func _literals(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var src := FileAccess.get_file_as_string(path)
	assert_true(src != "", "read " + path)
	for line in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for m in lit_re.search_all(line):
			out.append(m.get_string(1).replace("\\\"", "\""))
	return out
