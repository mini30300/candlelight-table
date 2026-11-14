extends "res://tests/testing.gd"
## The lobby hall's text (LOBBY_SPEC §0.7, §7.3): every Thai literal of the hall screen and the touch stick is a whole
## key of the I18n dictionaries (I18n.t matches whole strings only), every station has a Thai name and sign with an
## English pair, the 3D hall scripts under scenes/hall/ carry no Thai strings (their signs get text from the screen),
## and ui/i18n/hall.json is a clean Thai -> English fragment whose keys the hall screen really uses.
## 0.3 (SHIP_LOBBY_SPEC §1, §9.2): the warship deck adds the vault station (treasure chest, coming soon), its one-line
## coming-soon text and the place name PLACE on the title plaque; each is a whole key with an English pair.
## 0.5 (NET_SPEC §7.1, §12.1): the docking airlock opens the play-with-friends screen, so it is no longer a coming-soon
## station (two remain: adventure, vault) and its sign reads "ประตูเทียบยาน · เล่นกับเพื่อน"; the friends on the deck
## (scenes/hall/hall_friends.gd) carry no Thai either.
## 0.7 (PACK_SPEC §9): the pack room's screen joins the hall screen files (its Thai keys live in hall.json; the room's own
## names come from room.json) and the pack-room scripts under scenes/hall/ carry no Thai.

const SCRIPTS := ["res://ui/screens/hall_screen.gd", "res://ui/screens/hall_screen.tscn", "res://ui/widgets/touch_stick.gd",
	"res://ui/screens/pack_room_screen.gd", "res://ui/screens/pack_room_screen.tscn"]
const WORLD_SCRIPTS := ["res://scenes/hall/hall_layout.gd", "res://scenes/hall/hall_builder.gd", "res://scenes/hall/hall_world.gd",
	"res://scenes/hall/hall_avatar.gd", "res://scenes/hall/hall_camera.gd", "res://scenes/hall/hall_world.tscn",
	"res://scenes/hall/hall_space.gd", "res://scenes/hall/hall_friends.gd", "res://scenes/hall/pack_rooms.gd",
	"res://scenes/hall/room_layout.gd", "res://scenes/hall/pack_room_world.gd", "res://scenes/hall/pack_room_world.tscn"]
const SCREEN := "res://ui/screens/hall_screen.gd"
const FRAGMENT := "res://ui/i18n/hall.json"

var thai_re := RegEx.create_from_string("[฀-๿]")
var lit_re := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")


func test_every_thai_literal_of_the_hall_is_a_whole_key() -> void:
	var missing := []
	var n := 0
	for path in SCRIPTS:
		for lit in _literals(path):
			if thai_re.search(lit) == null:
				continue
			n += 1
			if not I18n.has_key(lit):
				missing.append(path.get_file() + ": " + lit)
	assert_true(n >= 15, "found %d Thai literals in the hall screen files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


func test_the_3d_hall_has_no_thai_strings() -> void:
	var found := []
	for path in WORLD_SCRIPTS:
		assert_true(ResourceLoader.exists(path) or FileAccess.file_exists(path), "find " + path)
		var lits := _literals(path)
		for lit in lits:
			if thai_re.search(lit) != null:
				found.append(path.get_file() + ": " + lit)
	assert_eq(found, [], "scenes/hall/ holds no Thai strings (signs get their text from the hall screen)")


func test_every_station_has_thai_and_english() -> void:
	var consts: Dictionary = (load(SCREEN) as Script).get_script_constant_map()
	var names: Dictionary = consts["NAMES"]
	var signs: Dictionary = consts["SIGNS"]
	var soon: Dictionary = consts["SOON"]
	var was := I18n.english
	for id in HallLayout.IDS:
		for table in [names, signs]:
			var th := str(table.get(id, ""))
			assert_true(thai_re.search(th) != null, "station %s has a Thai text (%s)" % [id, th])
			var en := I18n.lookup(th)
			assert_true(en != "" and thai_re.search(en) == null, "and an English pair without Thai (%s -> %s)" % [th, en])
	# 0.3: the vault (treasure chest; the work desk since 0.8) is a coming-soon station too (SHIP_LOBBY_SPEC §5)
	# 0.5 (NET_SPEC §12.1): with the online flag the airlock opens the online screen, so online left the SOON table;
	# 0.6 (PACK_SPEC §5.1): without the flag (the public app) the airlock is coming soon again (sign_of / soon_of)
	for id in ["adventure", "vault"]:
		assert_true(soon.has(id) and I18n.has_key(str(soon[id])), "the coming-soon panel of %s is translated" % id)
	assert_eq(soon.size(), 2, "exactly two coming-soon stations: adventure, vault")
	assert_false(soon.has("online"), "the docking airlock is not coming soon any more")
	assert_eq(str(signs.get("online", "")), "ประตูเทียบยาน · เล่นกับเพื่อน", "the airlock's sign names play with friends")
	assert_eq(I18n.lookup(str(signs.get("online", ""))), "Docking Airlock · Play with friends", "and translates")
	var hall_script: GDScript = load("res://ui/screens/hall_screen.gd")
	Features.set_flag(&"online", false)
	var sign_off := str(hall_script.call("sign_of", "online"))
	var soon_off := str(hall_script.call("soon_of", "online"))
	assert_eq(sign_off, "ประตูเทียบยาน · เร็วๆ นี้", "public app: the airlock's sign is coming soon")
	assert_true(I18n.has_key(sign_off) and I18n.has_key(soon_off) and thai_re.search(I18n.lookup(soon_off)) == null,
		"and its sign and panel translate (%s)" % I18n.lookup(soon_off))
	assert_eq(str(hall_script.call("soon_of", "vault")), str(soon["vault"]), "other stations keep their panel")
	Features.set_flag(&"online", true)
	assert_eq(str(hall_script.call("sign_of", "online")), str(signs["online"]), "online flag: the sign names play with friends")
	assert_eq(str(hall_script.call("soon_of", "online")), "", "online flag: no coming-soon panel at the airlock")
	Features.reset()
	var vault_en := I18n.lookup(str(soon.get("vault", "")))
	assert_true(vault_en != "" and thai_re.search(vault_en) == null and not vault_en.contains("{"),
		"the vault line has a plain English pair (%s)" % vault_en)
	# 0.8: the treasure chest became the work desk / storage (station id kept): its line names the campaign items and
	# the random rewards it will keep, and its name and sign are the desk in Thai and English
	assert_true(str(soon.get("vault", "")).contains("แคมเปญ") and str(soon.get("vault", "")).contains("ของรางวัลสุ่ม")
		and vault_en.contains("campaign") and vault_en.contains("random rewards"),
		"the desk line names what it will keep (campaign items and random rewards): %s" % vault_en)
	assert_eq(str(names["vault"]), "โต๊ะทำงาน", "the vault station is named the work desk")
	assert_eq(I18n.lookup(str(names["vault"])), "Work Desk", "and translates")
	assert_eq(str(signs["vault"]), "โต๊ะทำงาน · คลังของ", "the desk's sign reads work desk · storage")
	assert_eq(I18n.lookup(str(signs["vault"])), "Work Desk · Storage", "and translates")
	for t in [names["vault"], signs["vault"], soon["vault"]]:
		assert_false(str(t).contains("หีบ") or I18n.lookup(str(t)).to_lower().contains("chest"), "no treasure chest left in %s" % str(t))
	var place := str(consts.get("PLACE", ""))
	var place_en := I18n.lookup(place)
	assert_true(thai_re.search(place) != null and place_en != "" and thai_re.search(place_en) == null,
		"the title plaque's place name is Thai with an English pair (%s -> %s)" % [place, place_en])
	assert_eq(place_en, "Warship Deck", "the place is the Warship Deck")
	I18n.english = true
	for key in [consts["PROMPT_KEYS"], consts["PROMPT_TOUCH"]]:
		for id in HallLayout.IDS:
			var text := I18n.t(str(key)).format({"name": I18n.t(str(names[id]))})
			assert_true(thai_re.search(text) == null and not text.contains("{name}"), "English prompt: " + text)
	I18n.english = false
	var th_prompt := I18n.t(str(consts["PROMPT_KEYS"])).format({"name": I18n.t(str(names["battle"]))})
	assert_eq(th_prompt, "โต๊ะรบ · กด E", "the Thai keyboard prompt of the war table")
	I18n.english = was


func test_hall_fragment_is_clean_and_used() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	assert_true(data is Dictionary and not (data as Dictionary).is_empty(), "hall.json is a non-empty object")
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
		assert_eq(I18n.lookup(str(k)), str(data[k]), "I18n finds the hall key " + str(k))
	assert_eq(bad, [], "every hall.json key is Thai and every value is English")
	assert_eq(unused, [], "every hall.json key is used by the hall screen")


## String literals of a script (comment lines skipped) or every String property stored in a scene (through its
## SceneState: an exported game keeps scenes in binary form).
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
