extends "res://tests/testing.gd"
## The i18n dictionary: every Thai string the HUD draws has an English entry, and no English entry
## still contains Thai (so English mode never shows Thai, like tests/battle/english.js for the old page).

const I18nScript := preload("res://scripts/i18n.gd")
const SCRIPTS := ["res://scripts/hud.gd", "res://scripts/probe.gd", "res://scripts/orbit_camera.gd", "res://scripts/kit_lineup.gd"]

var thai_re := RegEx.create_from_string("[฀-๿]")


func test_dictionary_values_are_english() -> void:
	var en: Dictionary = I18nScript.EN
	assert_true(en.size() >= 5, "dictionary has entries: " + str(en.size()))
	var bad := []
	for th in en:
		var v: String = en[th]
		if v.strip_edges().is_empty() or thai_re.search(v) != null:
			bad.append(th)
	assert_eq(bad, [], "every English entry is non-empty and free of Thai characters")
	var not_thai := []
	for th in en:
		if thai_re.search(th) == null:
			not_thai.append(th)
	assert_eq(not_thai, [], "every key is a Thai string")


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
	assert_eq(Array(I18nScript.missing(used)), [], "every string the HUD uses has an English entry")


func test_t_switches_language() -> void:
	I18nScript.english = false
	assert_eq(I18nScript.t("เฟรม/วิ"), "เฟรม/วิ", "Thai is the default")
	I18nScript.english = true
	assert_eq(I18nScript.t("เฟรม/วิ"), "FPS", "English mode translates")
	assert_eq(I18nScript.t("ไม่มีในพจนานุกรม"), "ไม่มีในพจนานุกรม", "an unknown key falls back to the Thai text")
	I18nScript.english = false
