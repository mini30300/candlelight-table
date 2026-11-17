extends "res://tests/testing.gd"
## Campaign texts (CAMPAIGN_SPEC §5.1, AGENTS rules 1 and 4): every Thai name in the campaign tables has an English entry
## without Thai and English planet names are unique. Banned franchise words are caught by the data lint
## (tools/validate_data.py, check "names"), which scans these tables like every other file.

var thai_re := RegEx.create_from_string("[฀-๿]")


func _thai_names() -> PackedStringArray:
	var out := PackedStringArray()
	for p in CampaignGalaxy.PLANETS:
		out.append(str(p["th"]))
	for f in CampaignGalaxy.FACTIONS:
		out.append(str(f["th"]))
	for m in CampaignGalaxy.MODIFIERS:
		out.append(str(m["th"]))
	for b in CampaignGalaxy.BIOMES:
		out.append(str(CampaignGalaxy.BIOMES[b]))
	for d in CampaignRules.DIFFICULTY:
		out.append(str(CampaignRules.DIFFICULTY[d]["th"]))
		out.append(str(CampaignRules.DIFFICULTY[d]["blurb"]))
	for k in CampaignRules.LINE_TH:
		out.append(str(CampaignRules.LINE_TH[k]))
	for t in MissionTypes.TYPES:
		out.append(MissionTypes.name_th(t))
		out.append(MissionTypes.goal_th(t))
		out.append(MissionTypes.secondary_th(t))
	return out


func test_every_name_translates() -> void:
	var missing := []
	var thai_en := []
	for th in _thai_names():
		var en := I18n.lookup(th)
		if en == "":
			missing.append(th)
		elif thai_re.search(en) != null:
			thai_en.append(th)
	assert_eq(missing, [], "every campaign name has an English entry")
	assert_eq(thai_en, [], "no English entry keeps Thai letters")
	var seen := {}
	var twice := []
	for p in CampaignGalaxy.PLANETS:
		var en := I18n.lookup(str(p["th"]))
		if seen.has(en):
			twice.append(en)
		seen[en] = true
	assert_eq(twice, [], "English planet names are unique")
	assert_eq(MissionTypes.TYPES.keys(), Array(CampaignGalaxy.TYPES), "MissionTypes covers the galaxy's mission types in order")
	for f in CampaignGalaxy.FACTIONS:
		assert_true(MissionRoster.FACTIONS.has(str(f["id"])), "MissionRoster has faction " + str(f["id"]))
	for m in CampaignGalaxy.MODIFIERS:
		assert_true(MissionTypes.MODIFIERS.has(str(m["id"])), "MissionTypes has modifier " + str(m["id"]))

