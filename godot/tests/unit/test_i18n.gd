extends "res://tests/testing.gd"
## The I18n autoload: every Thai string the HUD draws has an English entry, no English entry still
## contains Thai (so English mode never shows Thai, like tests/battle/english.js for the old page), and the
## lookup order is the built-in EN dict, then ui/i18n_extra.json, then data/i18n_en.json.

const I18nScript := preload("res://ui/i18n.gd")
const SCRIPTS := ["res://scenes/probe/hud.gd", "res://scenes/probe/probe.gd", "res://table/camera_rig.gd", "res://table/figures/kit_library.gd"]

var thai_re := RegEx.create_from_string("[฀-๿]")


func test_autoload_is_live() -> void:
	assert_true(I18n != null and I18n.is_inside_tree(), "the I18n autoload is in the tree under the runner")
	# the live autoload may carry a saved "en" from user://settings.cfg (the render probe toggles it), so the
	# default is checked on a fresh instance and on App's default setting
	var fresh: Node = I18nScript.new()
	assert_false(fresh.english, "Thai is the default language of a fresh I18n")
	fresh.free()
	assert_eq(App.DEFAULT_LANG, "th", "App's default language setting is Thai")
	assert_true(I18n.page.size() >= 1500, "data/i18n_en.json loaded: %d pairs" % I18n.page.size())
	assert_true(I18n.extra.size() >= I18nScript.EN.size(), "ui/i18n_extra.json loaded: %d pairs" % I18n.extra.size())


func test_dictionary_values_are_english() -> void:
	for pair in [["EN", I18nScript.EN], ["i18n_extra.json", I18n.extra]]:
		var label: String = pair[0]
		var en: Dictionary = pair[1]
		assert_true(en.size() >= 5, label + " has entries: " + str(en.size()))
		var bad := []
		for th in en:
			var v: String = str(en[th])
			if v.strip_edges().is_empty() or thai_re.search(v) != null:
				bad.append(th)
		assert_eq(bad, [], label + ": every English entry is non-empty and free of Thai characters")
		var not_thai := []
		for th in en:
			if thai_re.search(th) == null:
				not_thai.append(th)
		assert_eq(not_thai, [], label + ": every key is a Thai string")


## The built-in dict and ui/i18n_extra.json must agree, so either source gives the same English.
func test_extra_file_carries_the_builtin_entries() -> void:
	var differ := []
	for th in I18nScript.EN:
		if not I18n.extra.has(th) or str(I18n.extra[th]) != I18nScript.EN[th]:
			differ.append(th)
	assert_eq(differ, [], "every EN entry is in ui/i18n_extra.json with the same English")


## Every I18n.t("…") literal in the game scripts, and the HUD's TITLE/HINT constants, must be a key.
func test_every_string_used_by_the_hud_has_an_entry() -> void:
	var used := PackedStringArray()
	var call_re := RegEx.create_from_string("I18n\\.t\\(\"([^\"]+)\"\\)")
	var const_re := RegEx.create_from_string("const (?:TITLE|HINT) := \"([^\"]+)\"")
	for path in SCRIPTS:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src != "", "read " + path)
		for m in call_re.search_all(src):
			used.append(m.get_string(1))
		for m in const_re.search_all(src):
			used.append(m.get_string(1))
	assert_true(used.size() >= 6, "found %d translated strings in the scripts" % used.size())
	assert_eq(Array(I18n.missing(used)), [], "every string the HUD uses has an English entry")


func test_t_switches_language() -> void:
	I18n.english = false
	assert_eq(I18n.t("เฟรม/วิ"), "เฟรม/วิ", "Thai is the default")
	I18n.english = true
	assert_eq(I18n.t("เฟรม/วิ"), "FPS", "English mode translates")
	assert_eq(I18n.t("ถาดลูกเต๋า"), "Dice tray", "a page string comes from data/i18n_en.json")
	assert_eq(I18n.t("ไม่มีในพจนานุกรม"), "ไม่มีในพจนานุกรม", "an unknown key falls back to the Thai text")
	I18n.english = false


## A fresh instance with its file dicts replaced shows the order: EN, then extra, then page.
func test_lookup_order_en_extra_page() -> void:
	var i: Node = I18nScript.new()
	i.english = true
	assert_eq(i.t("ถาดลูกเต๋า"), "Dice tray", "fresh instance reads data/i18n_en.json too")
	i.extra = {"ข้อความใหม่": "a new-app string", "ถาดลูกเต๋า": "Extra tray", "เฟรม/วิ": "WRONG"}
	assert_eq(i.t("ข้อความใหม่"), "a new-app string", "a key only in i18n_extra.json is found")
	assert_eq(i.t("ถาดลูกเต๋า"), "Extra tray", "i18n_extra.json wins over data/i18n_en.json")
	assert_eq(i.t("เฟรม/วิ"), "FPS", "the built-in EN dict wins over i18n_extra.json")
	assert_eq(Array(i.missing(PackedStringArray(["ข้อความใหม่", "ไม่มีในพจนานุกรม"]))), ["ไม่มีในพจนานุกรม"], "missing() looks through every source")
	i.english = false
	assert_eq(i.t("ข้อความใหม่"), "ข้อความใหม่", "Thai mode returns the key untouched")
	i.free()
