extends "res://tests/testing.gd"
## The army picker's model and texts without a display (ui/screens/army_roster.gd, ui/widgets/datasheet_text.gd and
## the KitLibrary helpers it uses): every army lists its datasheets in TYPES order and never a hidden unit, squads and
## points add up, the random pick is fixed by its seed and fits the budget, every datasheet text has an English
## translation with no Thai left, the labels follow the page's wording, and every Thai literal of the new screen
## files is a whole I18n key (I18n translates whole strings only).

const SCRIPTS: PackedStringArray = ["res://ui/screens/army.gd", "res://ui/screens/army_roster.gd",
	"res://ui/widgets/datasheet_text.gd", "res://ui/widgets/kit_turntable.gd", "res://ui/screens/gpu_check.gd",
	"res://ui/screens/army.tscn"]
## Thai literals that are deliberately not translated: a language shown in its own script
const LANG_NAMES: PackedStringArray = ["ไทย"]

var thai_re := RegEx.create_from_string("[฀-๿]")
var _was_english := false


func setup() -> void:
	_was_english = I18n.english


func test_every_army_lists_its_units_in_types_order_without_hidden_ones() -> void:
	var hidden := PackedStringArray()
	for t: Dictionary in GameData.types():
		if GameData.is_hidden(str(t["k"])):
			hidden.append(str(t["k"]))
	assert_true(hidden.size() > 0, "the data has hidden units for the filter to keep out (%d)" % hidden.size())
	assert_eq(GameData.factions().size(), 15, "15 armies")
	var bad := []
	var total := 0
	for fac in GameData.factions():
		var units := ArmyRoster.units_of(fac)
		total += units.size()
		if units.is_empty():
			bad.append(fac + ": empty")
		var last := -1
		for k in units:
			var i := GameData.index_of(k)
			if i <= last:
				bad.append(fac + ": out of TYPES order at " + k)
			last = i
			if GameData.is_hidden(k):
				bad.append(fac + ": lists a hidden unit")
			var f := GameData.fac_of(k)
			if f != fac and f != "*":
				bad.append(fac + ": lists " + k + " of " + f)
		for t: Dictionary in GameData.types():
			var k := str(t["k"])
			if str(t["fac"]) == fac and not GameData.is_hidden(k) and not units.has(k):
				bad.append(fac + ": misses " + k)
	assert_eq(bad, [], "each army: its own datasheets, TYPES order, nothing hidden, nothing missing")
	assert_eq(total, GameData.count() - hidden.size(), "every visible datasheet is listed once over the 15 armies (%d)" % total)


func test_squads_points_budget_and_army_switch() -> void:
	var r := ArmyRoster.new()
	assert_eq(r.fac, "mod", "an empty roster starts on the soldiers, like the page's facOf")
	assert_eq(r.budget, 1000, "the default budget is 1000")
	var budgets := ArmyRoster.budgets()
	assert_eq(budgets.size(), 99, "99 budget steps from constants.json BUDGETS")
	assert_eq([budgets[0], budgets[budgets.size() - 1]], [200, 40000], "from 200 to 40000")
	var units := ArmyRoster.units_of("mod")
	var a := units[0]
	var b := units[1]
	var pa := int(GameData.ty(a)["pts"])
	var pb := int(GameData.ty(b)["pts"])
	assert_true(r.add(a, 1) and r.add(a, 1) and r.add(b, 1), "plus on two units")
	assert_eq(r.points(), 2 * pa + pb, "points: 2 x %d + %d" % [pa, pb])
	assert_eq(r.models(), 2 * int(GameData.ty(a)["n"]) + int(GameData.ty(b)["n"]), "models follow the squads")
	assert_eq(r.list()[GameData.index_of(a)], 2, "the wire list counts squads per TYPES slot")
	assert_true(r.add(a, -1), "minus")
	assert_false(r.add(b, -1) and r.add(b, -1), "a squad count never goes below zero")
	assert_eq(r.count_of(b), 0, "b back to zero")
	var other := ArmyRoster.units_of("gr")[0]
	assert_false(r.add(other, 1), "a unit of another army cannot be added")
	for t: Dictionary in GameData.types():
		if GameData.is_hidden(str(t["k"])):
			assert_false(r.add(str(t["k"]), 1), "a hidden unit cannot be added")
	for i in 120:
		r.add(a, 1)
	assert_eq(r.count_of(a), ArmyRoster.slot_max(), "a slot stops at SLOT_MAX (%d)" % ArmyRoster.slot_max())
	assert_true(r.is_over(), "99 squads are over a 1000 budget")
	assert_true(r.step_budget(1) and r.budget == 1050, "budget steps up to 1050")
	assert_true(r.step_budget(-1) and r.step_budget(-1) and r.budget == 950, "and down to 950")
	assert_false(r.set_budget(1234), "a budget not in BUDGETS is refused")
	assert_true(r.set_budget(200) and not r.step_budget(-1), "200 is the lowest step")
	assert_true(r.set_fac("gr"), "switch to the Greeks")
	assert_eq(r.squads(), 0, "switching army drops the other army's squads (one army per list)")
	assert_false(r.set_fac("gr"), "the same army again changes nothing")
	assert_false(r.set_fac("nope"), "an unknown army is refused")


func test_random_pick_is_fixed_by_its_seed_and_fits_the_budget() -> void:
	var bad := []
	var differs := 0
	var runs := 0
	for fac in GameData.factions():
		for budget in [200, 500, 1000, 2000, 5000]:
			var r := ArmyRoster.new(fac)
			r.set_budget(budget)
			r.random_fill(7)
			var first := r.list()
			r.random_fill(7)
			if r.list() != first:
				bad.append("%s/%d: seed 7 gave two lists" % [fac, budget])
			var r2 := ArmyRoster.new(fac)
			r2.set_budget(budget)
			r2.random_fill(8)
			runs += 1
			if r2.list() != first:
				differs += 1
			if r.points() > budget:
				bad.append("%s/%d: %d points" % [fac, budget, r.points()])
			if r.is_empty():
				bad.append("%s/%d: nothing picked" % [fac, budget])
			for i in first.size():
				if first[i] > 0:
					var k := GameData.key_at(i)
					if GameData.is_hidden(k) or not GameData.pool(fac).has(k):
						bad.append("%s/%d: %s is not in the army's bot pool" % [fac, budget, k])
	assert_eq(bad, [], "random pick: one list per seed, within budget, never empty, bot pool only, never hidden")
	assert_true(differs > runs * 3 / 4, "another seed gives another list (%d of %d differ)" % [differs, runs])
	var rng_check := Rng.make(ArmyRoster.RANDOM_STREAM, 7)
	assert_eq(rng_check.stream, "armies", "the pick draws from the armies stream")


func test_datasheet_texts_have_english_without_thai() -> void:
	I18n.english = true
	var left := []
	var chapters: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/chapters.json"))
	for t: Dictionary in GameData.types():
		var k := str(t["k"])
		if GameData.is_hidden(k):
			continue
		var texts := PackedStringArray([DatasheetText.name_of(t), DatasheetText.desc_of(t), DatasheetText.sub_of(t)])
		for pair in DatasheetText.stats(t):
			texts.append_array(pair)
		texts.append_array(DatasheetText.weapon_head())
		for melee in [false, true]:
			var w: Variant = t.get("mel" if melee else "gun")
			if w is Dictionary:
				texts.append_array(DatasheetText.weapon_row(w, melee))
				texts.append_array(DatasheetText.weapon_keywords(w))
		texts.append_array(DatasheetText.abilities(t))
		texts.append_array(DatasheetText.chapter_heading(str(t.get("ch", "")), chapters))
		for s in texts:
			if thai_re.search(s) != null:
				left.append(k + ": " + s)
	for fac in GameData.factions():
		for s in [str(GameData.faction(fac)["nm"]), str(GameData.faction(fac)["d"])]:
			if thai_re.search(I18n.t(s)) != null:
				left.append(fac + ": " + s)
	I18n.english = _was_english
	assert_eq(left, [], "English mode: every datasheet text, army name and blurb is translated")


func test_labels_follow_the_page_wording() -> void:
	I18n.english = false
	var hop := GameData.ty("hoplite")
	assert_eq(DatasheetText.name_of(hop), str(hop["nm"]), "Thai mode: the unit name is the data's Thai")
	assert_eq(DatasheetText.sub_of(hop), "×5 · 65 แต้ม", "models and points")
	var st := DatasheetText.stats(GameData.ty("kblade"))
	assert_eq(Array(st[0]), ["เดิน", "6\""], "move in inches")
	assert_eq(Array(st[3]), ["เกราะพิเศษ", "5++"], "an invulnerable save gets its own box")
	assert_eq(Array(DatasheetText.stats(GameData.ty("grot"))[2]), ["เกราะ", "ไม่มี"], "a save above 6 reads none")
	assert_eq(Array(DatasheetText.weapon_row(GameData.ty("infantry")["gun"], false)), ["ปืนเล็กยาว", "24\"", "1", "4+", "3", "0", "1"], "a ranged weapon row")
	assert_eq(DatasheetText.weapon_row(GameData.ty("hoplite")["mel"], true)[1], "ประชิด", "melee range reads melee")
	assert_eq(DatasheetText.weapon_row(GameData.ty("flamer")["gun"], false)[3], "อัตโนมัติ", "a spray weapon hits automatically")
	assert_true(DatasheetText.weapon_keywords(GameData.ty("infantry")["gun"]).has("ใกล้ครึ่งระยะ +1"), "rapid fire")
	assert_true(DatasheetText.abilities(GameData.ty("herc")).has("ผู้นำ: พวกในระยะ 6\" เข้าเป้า +1"), "the hit aura names AURA_R")
	assert_true(DatasheetText.abilities(GameData.ty("troy")).has("ซ่อนโฮพไลต์ 5 ตัวในท้อง"), "the wooden horse names what it hides")
	assert_true(DatasheetText.abilities(GameData.ty("achil")).has("ส้นเท้า: โดนเจาะได้ 6 ตายทันที"), "the heel")
	assert_true(DatasheetText.abilities(GameData.ty("dewar")).has("ยิ่งรบยิ่งดุ: ตั้งแต่รอบ 3 ตีประชิดเข้า +1 และวิ่งแล้วบุกได้"), "the dark elves' army rule")
	assert_eq(DatasheetText.fmt_pts(1000), "1,000", "thousands get a comma")
	assert_eq(DatasheetText.fmt_pts(40000), "40,000", "and 40,000")
	assert_eq(DatasheetText.fmt_pts(995), "995", "below a thousand none")
	I18n.english = true
	assert_eq(DatasheetText.sub_of(hop), "×5 · 65 pts", "English: models and points")
	assert_eq(DatasheetText.stats(hop)[2][0], "Save", "English: the save caption")
	I18n.english = _was_english


func test_every_thai_literal_of_the_screen_is_a_whole_key() -> void:
	var lit_re := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var missing := []
	var n := 0
	for path in SCRIPTS:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src != "", "read " + path)
		for line in src.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m in lit_re.search_all(line):
				var lit := m.get_string(1).replace("\\\"", "\"")
				if thai_re.search(lit) == null or LANG_NAMES.has(lit):
					continue
				n += 1
				if not I18n.has_key(lit):
					missing.append(path.get_file() + ": " + lit)
	assert_true(n >= 60, "found %d Thai literals in the army screen files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


func test_kit_library_helpers() -> void:
	var m := {"a": {"bbox": [[-1.0, 0.0, -0.5], [1.0, 2.0, 0.5]],
		"materials": [{"key": "skin", "rgb": [10, 20, 30], "tint": false}, {"key": "trim", "rgb": [200, 100, 50], "tint": true},
			{"key": "plate", "rgb": [1, 2, 3], "tint": true}]}}
	var box := KitLibrary.bounds(m, "a")
	assert_true(box.position.is_equal_approx(Vector3(-1.0, 0.0, -0.5)) and box.size.is_equal_approx(Vector3(2.0, 2.0, 1.0)), "bounds from bbox " + str(box))
	assert_eq(KitLibrary.bounds(m, "none").size, Vector3.ZERO, "no bbox: an empty box")
	var cols := KitLibrary.kit_colours(m, "a")
	assert_eq(cols, [Color8(1, 2, 3), Color8(200, 100, 50)], "colours: plate first, then trim")
	assert_eq(KitLibrary.kit_colours(m, "none"), [], "no kit: no colours")
	assert_eq(KitLibrary.kit_path("heavy"), "res://assets/kits/heavy.glb", "kit path")
	assert_false(KitLibrary.has_kit(""), "an empty name is not a kit")
