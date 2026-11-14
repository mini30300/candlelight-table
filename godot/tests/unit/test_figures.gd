extends "res://tests/testing.gd"
## The dressing room's registry (PACK_SPEC §10, app/figures.gd): the list (egg, the curated walkable kits, pack figures
## from figures.json with every broken entry skipped, the old pack.json "deck" entry as a fallback), the kit choice by data
## (skinned 23-bone foot figures, no mount, no creature, 1.5-2.3 m, one per army, the humanoid idle/walk/run clips), the
## schemes, the selection (default, persistence in the settings file next to App's own keys, unknown ids fall back,
## App.figure_changed), the three slots, make() for each kind (egg = null, kit = KitWalker, pack = the pack script,
## a half-contract pack figure = null) and KitWalker's paint table (H10: armour primary, cloth secondary, weapons, lenses,
## trim and natural slots fixed), its deck speeds and its still pose on lo and min.

const STORE := "user://test_figures.cfg"
const FIX_LIST := "res://tests/fixtures/figure_pack/figures.json"
const BAD_LIST := "res://tests/fixtures/figure_pack_bad/figures.json"
const FIX_PACK := "res://tests/fixtures/figure_pack/pack.json"
const NONE := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const LIB := "res://assets/anim/humanoid.res"

var _changed := 0


func setup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = STORE
	Figures.pack_list = NONE
	Figures.pack_manifest = NONE_PACK
	_changed = 0


func _reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = ""
	Figures.pack_list = Figures.PACK_LIST
	Figures.pack_manifest = ArenaActors.PACK_MANIFEST


func _ids() -> Array:
	return Figures.list().map(func(e: Dictionary) -> String: return str(e["id"]))


func test_list_without_a_pack() -> void:
	setup()
	var l := Figures.list()
	assert_eq(str(l[0]["id"]), "egg", "no pack: the egg comes first")
	assert_eq(str(l[0]["kind"]), "egg", "the egg's kind is egg")
	assert_eq(l.size(), 1 + Figures.KITS.size(), "the egg plus every curated kit (%d)" % Figures.KITS.size())
	assert_true(Figures.KITS.size() >= 12, "at least 12 walkable kits")
	var thai := RegEx.create_from_string("[฀-๿]")
	for e in l:
		var n: Dictionary = e["name"]
		assert_true(str(n["th"]) != "" and str(n["en"]) != "" and thai.search(str(n["en"])) == null,
			"%s has a Thai and an English name" % e["id"])
		assert_true(I18n.lookup(str(n["th"])) != "", "the Thai name %s is in the dictionary" % n["th"])
		if e["kind"] == "kit":
			assert_eq(str(e["id"]), "kit_" + str(e["kit"]), "a kit's id is kit_<key>")
			assert_true(bool(e["schemes"]), "a kit takes schemes")
	assert_eq(Figures.entry("kit_samurai")["kit"], "samurai", "entry() finds a kit")
	assert_true(Figures.entry("nope").is_empty(), "entry() of an unknown id is {}")
	_reset()


func test_kits_are_walkable_by_data() -> void:
	var man := KitLibrary.load_manifest()
	var lib := load(LIB) as AnimationLibrary
	assert_true(lib != null and lib.has_animation(&"idle") and lib.has_animation(&"walk") and lib.has_animation(&"run"),
		"humanoid.res has idle, walk and run")
	var armies := {}
	for k in Figures.KITS:
		var key := str(k["kit"])
		var e: Dictionary = man.get(key, {})
		assert_true(KitLibrary.has_kit(key), "kit %s is present" % key)
		var bb := KitLibrary.bounds(man, key)
		assert_true(bool(e.get("skinned", false)) and int(e.get("joints", 0)) == 23 and e.get("mount") == null
			and not bool(e.get("creature", false)) and not e.has("palette"),
			"%s: a skinned 23-bone foot figure with its own palette" % key)
		assert_true(bb.size.y >= 1.5 and bb.size.y <= 2.3, "%s stands %.2f m (1.5-2.3)" % [key, bb.size.y])
		var fac := str((e.get("type", {}) as Dictionary).get("fac", ""))
		assert_false(armies.has(fac), "%s: one kit per army (%s)" % [key, fac])
		armies[fac] = true
	assert_true(armies.size() >= 12, "the kits come from %d armies" % armies.size())


func test_schemes() -> void:
	var s := Figures.schemes()
	var ids := s.map(func(x: Dictionary) -> String: return str(x["id"]))
	for want in ["original", "pink", "blue", "red", "green", "black", "white"]:
		assert_true(ids.has(want), "the %s scheme exists" % want)
	assert_eq(ids.size(), Figures.SCHEMES.size(), "schemes() lists every scheme")
	for x in s:
		assert_true(x["primary"] is Color and x["secondary"] is Color and x["primary"] != x["secondary"],
			"%s: two different colours" % x["id"])
		assert_true(I18n.lookup(str(x["name"]["th"])) == str(x["name"]["en"]), "%s: the Thai name translates to %s" % [x["id"], x["name"]["en"]])
	assert_eq(Figures.scheme("nope")["id"], "original", "an unknown scheme gives the default (original)")
	# round C: "original" = the figure's own colours (first, the default; no H10), every other scheme paints
	assert_eq(str(s[0]["id"]), Figures.DEFAULT_SCHEME, "the original scheme is first and the default")
	for x in s:
		assert_eq(bool(x["original"]), str(x["id"]) == "original", "%s: original flag" % x["id"])


func test_selection_persists() -> void:
	setup()
	assert_eq(Figures.selected(), {"figure": "egg", "scheme": "original"}, "no pack, nothing saved: the egg in its own colours")
	var app := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"App")
	assert_true(app != null and app.has_signal("figure_changed"), "App has figure_changed")
	var cb := func() -> void: _changed += 1
	app.connect("figure_changed", cb)
	Figures.select("kit_viking", "pink")
	assert_eq(_changed, 1, "select() emits App.figure_changed once")
	assert_eq(Figures.selected(), {"figure": "kit_viking", "scheme": "pink"}, "the choice is read back")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(STORE), OK, "it is written to the settings file")
	assert_eq(str(cfg.get_value("figure", "figure", "")), "kit_viking", "under [figure]")
	Figures.select("no_such", "no_such")
	assert_eq(Figures.selected(), {"figure": "egg", "scheme": "original"}, "unknown ids fall back to the defaults")
	app.disconnect("figure_changed", cb)
	# App.save_settings keeps the [figure] section, and Figures uses App.settings_file by default
	var old := str(app.get("settings_file"))
	Figures.store_path = ""
	app.set("settings_file", STORE)
	Figures.select("kit_samurai", "red")
	app.call("save_settings")
	assert_eq(Figures.selected(), {"figure": "kit_samurai", "scheme": "red"}, "App.save_settings keeps the dressing-room choice")
	cfg = ConfigFile.new()
	cfg.load(STORE)
	assert_eq(str(cfg.get_value("app", "gfx", "")), str(app.get("gfx")), "and App's own keys are in the same file")
	app.set("settings_file", old)
	_reset()


func test_slots() -> void:
	setup()
	assert_eq(Figures.slots(), [{}, {}, {}], "three empty slots")
	Figures.save_slot(0, "kit_spartan", "gold")
	Figures.save_slot(2, "egg", "white")
	Figures.save_slot(3, "kit_spartan", "gold")
	Figures.save_slot(1, "no_such", "red")
	assert_eq(Figures.slots(), [{"figure": "kit_spartan", "scheme": "gold"}, {}, {"figure": "egg", "scheme": "white"}],
		"slots 0 and 2 saved; slot 3 and an unknown figure are ignored")
	Figures.save_slot(0, "kit_rwar", "nope")
	assert_eq(Figures.slots()[0], {"figure": "kit_rwar", "scheme": "original"}, "a slot is overwritten; an unknown scheme becomes original")
	assert_eq(Figures.selected()["figure"], "egg", "saving a slot does not change the selection")
	_reset()


func test_pack_figures() -> void:
	setup()
	Figures.pack_list = FIX_LIST
	var ids := _ids()
	assert_eq(ids.slice(0, 3), ["prim", "prim_abs", "egg"], "the two valid pack figures come first, then the egg")
	for bad in ["Bad id", "thai_en", "escape", "missing", "not_figure"]:
		assert_false(ids.has(bad), "broken entry %s is skipped" % bad)
	assert_eq(ids.count("prim"), 1, "a repeated id is skipped")
	assert_eq(ids.count("egg"), 1, "a pack entry cannot take the egg's id")
	assert_true(bool(Figures.entry("prim")["schemes"]) and not bool(Figures.entry("prim_abs")["schemes"]), "schemes default to false")
	assert_eq(Figures.selected()["figure"], "prim", "with a pack the default is its first figure")
	var f := Figures.make(&"prim", &"lo")
	assert_true(f != null and (f.get_script() as Script).resource_path.ends_with("prim_figure.gd"), "make() builds the pack script")
	if f != null:
		f.free()
	Figures.pack_list = BAD_LIST
	assert_true(Figures.entry("half").size() > 0 and Figures.make(&"half") == null, "a half-contract pack figure makes null (egg)")
	# no figures.json: pack.json's deck entry is the one pack figure
	Figures.pack_list = NONE
	Figures.pack_manifest = FIX_PACK
	assert_eq(_ids()[0], "pack", "no figures.json: pack.json's deck figure is listed as pack")
	assert_eq(Figures.default_figure(), "pack", "and is the default")
	_reset()


func test_make_and_paint() -> void:
	setup()
	assert_true(Figures.make(&"egg") == null and Figures.make(&"no_such") == null, "the egg and unknown ids make null")
	var w := Figures.make(&"kit_kblade", &"mid") as KitWalker
	assert_true(w != null and w.walk_kit == "kblade", "a kit makes a KitWalker of that kit")
	if w == null:
		return
	Figures.dress(w, "original")   # สีเดิม: H10 is not called
	assert_eq(w.scheme(), [], "the original scheme leaves the figure unpainted")
	Figures.dress(w, "pink")   # before setup: kept and applied in setup
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.setup({"role": &"deck", "level": "mid", "team_colour": Color.BLUE, "seed": 0})
	assert_eq(w.kit_key(), "kblade", "set up on its kit")
	var mi := w.find_children("*", "MeshInstance3D", true, false)
	assert_eq(mi.size(), 1, "one mesh (one draw call)")
	var mat := (mi[0] as MeshInstance3D).material_override as ShaderMaterial
	assert_true(mat != null and int(mat.get_shader_parameter("paint_row")) == 0, "the paint row is set")
	var tex := mat.get_shader_parameter("paint_tex") as Texture2D
	var img := tex.get_image() if tex != null else null
	var keys := KitWalker.palette_keys("kblade")
	assert_true(img != null and img.get_width() == keys.size(), "one paint column per palette slot (%d)" % keys.size())
	var pink := Figures.scheme("pink")
	var seen := {0: 0, 1: 0, 2: 0}
	for i in keys.size():
		var want := KitWalker.paint_slot("kblade", i)
		seen[want] += 1
		var px := img.get_pixel(i, 0)
		if want == 0:
			assert_true(px.a < 0.01, "slot %s keeps its own colour" % keys[i])
		else:
			var c: Color = pink["primary"] if want == 1 else pink["secondary"]
			assert_true(px.a > 0.99 and absf(px.r - c.r) < 0.01 and absf(px.g - c.g) < 0.01 and absf(px.b - c.b) < 0.01,
				"slot %s takes the %s colour" % [keys[i], "primary" if want == 1 else "secondary"])
	assert_true(seen[0] > 0 and seen[1] > 0, "kblade has fixed and primary slots %s" % str(seen))
	for k in ["gun", "visor", "trim", "steel", "gold", "skin"]:
		var i := keys.find(k)
		if i >= 0:
			assert_eq(KitWalker.paint_slot("kblade", i), 0, "%s is a fixed colour" % k)
	# H10 after setup changes the colours in place
	Figures.dress(w, "green")
	assert_eq(w.scheme(), [Figures.scheme("green")["primary"], Figures.scheme("green")["secondary"]], "apply_scheme after setup")
	# deck speeds: the clips' speeds x scale x DECK_RATE, within HallAvatar's clamp
	var sp := w.deck_speeds()
	assert_true(sp.x >= 0.5 and sp.y <= 6.0 and sp.y > sp.x, "deck speeds %s within [0.5, 6]" % str(sp))
	# lo and min hold a still pose once idle
	for l in ["lo", "min"]:
		w.apply_level("mid")
		w.set_move(0.0, false)
		w.apply_level(l)
		assert_true(w.is_still() and not w.animation_player().is_playing(), "%s: standing still, the AnimationPlayer is paused" % l)
		assert_eq(w.gfx, l, "%s: gfx keeps the app's level" % l)
	w.apply_level("mid")
	assert_true(w.animation_player().is_playing(), "mid: the idle loop plays again")
	w.set_move(1.5, false)
	assert_true(w.playing_clip().ends_with("/walk"), "set_move picks walk")
	w.free()
	_reset()
