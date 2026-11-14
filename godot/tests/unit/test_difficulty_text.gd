extends "res://tests/testing.gd"
## Difficulty screen text (CAMPAIGN_SPEC §1.4, track B): every Thai string of the screen has an English entry with no Thai
## left, the revives line (0 / 1 / n), the "what changes" line from CampaignRules.DIFFICULTY, the score badge, and the
## difficulty names and blurbs the cards read (they live in ui/i18n/campaign.json).

const DS := "res://ui/screens/difficulty_screen.gd"
const FRAG := "res://ui/i18n/campaign_hero.json"

var _thai := RegEx.create_from_string("[฀-๿]")


func _en(th: String) -> String:
	var was := I18n.english
	I18n.english = true
	var out := I18n.t(th)
	I18n.english = was
	return out


func test_every_screen_string_has_english() -> void:
	var consts: Dictionary = (load(DS) as GDScript).get_script_constant_map()
	var n := 0
	for k in consts:
		var v: Variant = consts[k]
		if v is String and _thai.search(v) != null:
			n += 1
			var en := _en(v)
			assert_true(en != v and _thai.search(en) == null, "%s has English: %s" % [k, en])
	assert_true(n >= 10, "the screen's Thai strings were found", n)
	var frag: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAG))
	assert_true(frag is Dictionary, "campaign_hero.json parses")
	for k in frag:
		assert_true(_thai.search(str(frag[k])) == null, "fragment value has no Thai: " + str(frag[k]))
		assert_true(consts.values().has(k), "fragment key is used by the screen: " + str(k))


func test_difficulty_names_and_blurbs() -> void:
	for id in CampaignGalaxy.DIFFICULTIES:
		var d := CampaignRules.difficulty(id)
		for key in ["th", "blurb"]:
			var th := str(d[key])
			var en := _en(th)
			assert_true(en != th and _thai.search(en) == null, "%s %s → %s" % [id, key, en])
	assert_eq(_en("ภัยพิบัติ"), "Catastrophe", "Catastrophe")
	assert_eq(_en("ยากมาก"), "Very hard", "Very hard")


func test_revives_line() -> void:
	var S: GDScript = load(DS)
	I18n.english = false
	assert_eq(S.revives_text(0), "ล้มแล้วจบ", "0 revives (Thai)")
	assert_eq(S.revives_text(1), "ลุกได้ 1 ครั้ง", "1 revive (Thai)")
	assert_eq(S.revives_text(2), "ลุกได้ 2 ครั้ง", "2 revives (Thai)")
	I18n.english = true
	assert_eq(S.revives_text(0), "Fall once and it is over", "0 revives (English)")
	assert_eq(S.revives_text(1), "Get back up once", "1 revive (English)")
	assert_eq(S.revives_text(2), "Get back up 2 times", "2 revives (English)")
	I18n.english = false
	for id in CampaignGalaxy.DIFFICULTIES:
		var r := int(CampaignRules.difficulty(id)["revives"])
		assert_eq(S.revives_text(r) == "ล้มแล้วจบ", r == 0, "%s: the no-revive line only for 0" % id)


func test_what_changes_line_and_score() -> void:
	var S: GDScript = load(DS)
	assert_eq(S.pct_text(100), "×1", "100 → ×1")
	assert_eq(S.pct_text(140), "×1.4", "140 → ×1.4")
	assert_eq(S.pct_text(200), "×2", "200 → ×2")
	assert_eq(S.pct_text(125), "×1.25", "125 → ×1.25")
	I18n.english = false
	assert_eq(S.stats_text("normal"), "ศัตรูค่าปกติ ไม่มีตัวคูณ", "normal: standard enemies")
	assert_eq(S.stats_text("hard"), "ศัตรู ×1.4 · ทน ×1.3 · แรง ×1.3 · เร็ว ×1.1", "hard: from the table")
	assert_eq(S.stats_text("catastrophe"), "ศัตรู ×2.4 · ทน ×2.2 · แรง ×2 · เร็ว ×1.3", "catastrophe: from the table")
	I18n.english = true
	assert_eq(S.stats_text("veryhard"), "Enemies ×1.8 · toughness ×1.7 · damage ×1.6 · speed ×1.2", "very hard in English")
	assert_eq(S.stats_text("normal"), "Standard enemies, no multipliers", "normal in English")
	assert_eq(I18n.t("คะแนน {x}").format({"x": CampaignRules.mult_text("veryhard")}), "Score ×2.5", "score badge in English")
	I18n.english = false
	assert_eq(I18n.t("คะแนน {x}").format({"x": CampaignRules.mult_text("hard")}), "คะแนน ×1.5", "score badge in Thai")
